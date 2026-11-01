# Shared NVMe SquashFS boot discovery, image validation and partition writes.
# Function definitions only; no device operations at source time.

nvme_squashfs_booted() {
	grep -qw 'owrt_nvme_squashfs=1' /proc/cmdline
}

nvme_squashfs_parts() {
	local arg uuid= found= node name candidate
	for arg in $(cat /proc/cmdline); do
		case "$arg" in root=PARTUUID=*) uuid=${arg#root=PARTUUID=} ;; esac
	done
	[ -n "$uuid" ] || return 1
	for node in /sys/class/block/nvme*n*p2/uevent; do
		[ -f "$node" ] || continue
		name=${node%/uevent}
		name=${name##*/}
		# Linux 6.12 uevents expose PARTNAME, not PARTUUID. Probe GPT via
		# the packaged util-linux blkid, including in the upgrade RAM stage.
		candidate=$(blkid -s PARTUUID -o value "/dev/$name") || continue
		[ "$candidate" = "$uuid" ] || continue
		[ -z "$found" ] || return 1
		found=$name
	done
	[ -n "$found" ] || return 1
	NVME_DISK=/dev/${found%p2}
	for arg in '1:boot' '2:rootfs' '3:rootfs_data'; do
		name=${arg#*:}
		grep -qx "PARTNAME=$name" "/sys/class/block/${found%p2}p${arg%:*}/uevent" || return 1
	done
}

nvme_squashfs_sd_booted() {
	local rootdev disk
	grep -qw 'root=/dev/fit0' /proc/cmdline || return 1
	rootdev=$(readlink -f /sys/class/block/fit0/device/../lower_dev) || return 1
	case "${rootdev##*/}" in
		mmcblk*p[0-9]*) disk=${rootdev##*/}; disk=${disk%p*} ;;
		*) return 1 ;;
	esac
	[ "$(cat "/sys/class/block/$disk/device/type")" = SD ]
}

nvme_squashfs_board_matches() {
	local board=$(cat /tmp/sysinfo/board_name)
	case "$1:$board" in
		bananapi_bpi-r4:bananapi,bpi-r4|bananapi_bpi-r4-8gb:bananapi,bpi-r4|\
		bananapi_bpi-r4-poe:bananapi,bpi-r4-2g5|bananapi_bpi-r4-poe-8gb:bananapi,bpi-r4-2g5|\
		bananapi_bpi-r4-poe:bananapi,bpi-r4-poe|bananapi_bpi-r4-poe-8gb:bananapi,bpi-r4-poe)
			return 0 ;;
	esac
	return 1
}

# Extract metadata and kernel to caller-owned paths, never tar -C arbitrary
# archive paths. Stream the rootfs for validation without staging a copy.
# fwtool validates the complete image before any extraction or device writes.
nvme_squashfs_unpack() {
	local image="$1" work="$2" prefix entry count=0 board layout rootsize uppersize
	fwtool -q -i "$work/metadata" "$image" || return 1
	layout=$(jsonfilter -i "$work/metadata" -e '@.nvme_layout') || return 1
	[ "$layout" = bpi-r4-nvme-squashfs-v1 ] || return 1
	rootsize=$(jsonfilter -i "$work/metadata" -e '@.nvme_rootfs_partsize') || return 1
	uppersize=$(jsonfilter -i "$work/metadata" -e '@.nvme_overlay_partsize') || return 1
	case "$rootsize:$uppersize" in *[!0-9:]*|:*|*:|0*|*:0*) return 1 ;; esac
	[ "$rootsize" -gt 0 ] && [ "$uppersize" -gt 0 ] || return 1
	NVME_ROOT_PART_BYTES=$((rootsize * 1048576))
	NVME_OVERLAY_PART_BYTES=$((uppersize * 1048576))
	tar tf "$image" > "$work/list" || return 1
	prefix=$(sed -n 's#^\(sysupgrade-bananapi_bpi-r4[^/]*\)/CONTROL$#\1#p' "$work/list")
	case "$prefix" in
		sysupgrade-bananapi_bpi-r4|sysupgrade-bananapi_bpi-r4-8gb|\
		sysupgrade-bananapi_bpi-r4-poe|sysupgrade-bananapi_bpi-r4-poe-8gb) ;;
		*) return 1 ;;
	esac
	while IFS= read -r entry; do
		case "$entry" in "$prefix/"|"$prefix/CONTROL"|"$prefix/kernel"|"$prefix/root") ;;
			*) return 1 ;; esac
		count=$((count + 1))
	done < "$work/list"
	[ "$count" = 4 ] || return 1
	for entry in '' CONTROL kernel root; do
		[ "$(grep -c -x "$prefix/$entry" "$work/list")" = 1 ] || return 1
	done
	board=${prefix#sysupgrade-}
	[ "$(tar xOf "$image" "$prefix/CONTROL")" = "BOARD=$board" ] || return 1
	nvme_squashfs_board_matches "$board" || return 1
	tar xOf "$image" "$prefix/kernel" > "$work/kernel" || return 1
	# Reject kernels that cannot fit fresh-install p1 before the installer
	# prompts for confirmation or changes the existing SSD partition table.
	nvme_squashfs_check_kernel "$work" 268435456 || return 1
	fit_check_sign -f "$work/kernel" >/dev/null || return 1
	nvme_squashfs_validate_root "$image" "$prefix/root" "$work" || return 1
	[ "$NVME_ROOT_BYTES" -le "$NVME_ROOT_PART_BYTES" ] && [ "$NVME_OVERLAY_PART_BYTES" -gt 0 ] || return 1
	NVME_IMAGE_BOARD=$board
	NVME_IMAGE=$image
	NVME_ROOT_MEMBER=$prefix/root
}

nvme_squashfs_validate_root() {
	local magic remaining
	# Consume the complete member to measure the payload without staging it.
	(
		set -o pipefail
		tar xOf "$1" "$2" | {
			dd bs=1 count=4 2>/dev/null | hexdump -v -e '1/1 "%02x"' || exit 1
			printf '\n'
			wc -c
		} > "$3/root.stats"
	) || return 1
	{ read -r magic && read -r remaining; } < "$3/root.stats" || return 1
	[ "$magic" = 68737173 ] || return 1
	case "$remaining" in ''|*[!0-9]*) return 1 ;; esac
	NVME_ROOT_BYTES=$((remaining + 4))
	[ "$NVME_ROOT_BYTES" -ge 96 ]
}

nvme_squashfs_cleanup() {
	local work="$1"
	umount "$work/mount" 2>/dev/null || :
	# A failed unmount must never turn rm -rf into deletion of p1/p3.
	awk -v stage="$work/mount" '$5 == stage { exit 1 }' /proc/self/mountinfo || return 1
	rm -rf "$work"
}

nvme_squashfs_check_kernel() {
	local kernelbytes
	# U-Boot's NVMe loader uses 512-byte sectors and caps its RAM load at
	# 256 MiB. Account for the last padded sector written by dd.
	kernelbytes=$(wc -c < "$1/kernel") || return 1
	[ "$kernelbytes" -gt 0 ] && [ "$kernelbytes" -le 268435456 ] && \
		[ "$(((kernelbytes + 511) / 512 * 512))" -le "$2" ]
}

nvme_squashfs_check_size() {
	local bootbytes
	[ "$(blockdev --getss "$2")" = 512 ] || return 1
	bootbytes=$(blockdev --getsize64 "${2}p1") || return 1
	nvme_squashfs_check_kernel "$1" "$bootbytes" && \
		[ "$NVME_ROOT_BYTES" -le "$(blockdev --getsize64 "${2}p2")" ]
}

nvme_squashfs_check_unmounted() {
	local part devno
	for part in 1 2 3; do
		devno=$(cat "/sys/class/block/${1##*/}p$part/dev") || return 1
		[ -n "$devno" ] || return 1
		# Linux mounts the initial root as /dev/root. Match the device
		# number, which also covers aliases and bind mounts.
		awk -v device="$devno" -v partition="${1}p$part" '
			$3 == device {
				printf "%s is mounted at %s; refusing to overwrite it\n", partition, $5
				mounted = 1
			}
			END { exit mounted }
		' /proc/self/mountinfo >&2 || return 1
	done
}

nvme_squashfs_write_root() (
	# OpenWrt's /bin/sh is BusyBox ash. Propagate tar and dd failures.
	set -o pipefail
	tar xOf "$1" "$2" | dd of="$3" bs=1M conv=fsync
)

nvme_squashfs_write() (
	local work="$1" disk="$2" backup="$3" stage="$1/mount"
	local rootdev=${disk}p2 upperdev=${disk}p3 bootdev=${disk}p1
	nvme_squashfs_check_size "$work" "$disk" || return 1
	[ -z "$backup" ] || [ -s "$backup" ] || return 1
	# All old root/overlay mounts must have been detached by sysupgrade's
	# RAM stage (or must be unused when called from the SD installer).
	nvme_squashfs_check_unmounted "$disk" || return 1
	mkdir -p "$stage" || return 1
	trap 'umount "$stage" 2>/dev/null || :' EXIT
	# The early boot guard made the lower block device read-only. Only lift
	# that protection here, after validation and detaching the old mounts.
	blockdev --setrw "$rootdev" || return 1
	nvme_squashfs_write_root "$NVME_IMAGE" "$NVME_ROOT_MEMBER" "$rootdev" || return 1
	# p1 contains the FIT itself. Pad only its final 512-byte sector.
	dd if="$work/kernel" of="$bootdev" bs=512 conv=sync,fsync || return 1
	# Reset the old upper so obsolete package files cannot mask the new
	# lower. Only the sysupgrade-selected archive is carried forward.
	mkfs.ext4 -F -L rootfs_data "$upperdev" || return 1
	mount -t ext4 "$upperdev" "$stage" || return 1
	[ -z "$backup" ] || cp "$backup" "$stage/sysupgrade.tgz" || return 1
	sync && umount "$stage" || return 1
	trap - EXIT
)
