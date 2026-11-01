# NVMe sysupgrade entry points and tools for the temporary upgrade root.
# The zz prefix appends tools after platform.sh sets its list.
. /lib/functions/nvme-squashfs.sh

RAMFS_COPY_BIN="${RAMFS_COPY_BIN:-} blkid blockdev fwtool jsonfilter mktemp"

nvme_squashfs_check_image() (
	local work
	work=$(mktemp -d /tmp/nvme-squashfs-check.XXXXXX) || return 1
	trap 'nvme_squashfs_cleanup "$work"' EXIT
	nvme_squashfs_parts && nvme_squashfs_unpack "$1" "$work" && \
		nvme_squashfs_check_size "$work" "$NVME_DISK"
)

nvme_do_upgrade() (
	local work
	nvme_squashfs_parts || { echo "Cannot resolve NVMe SquashFS root partitions"; return 1; }
	work=$(mktemp -d /tmp/nvme-squashfs-upgrade.XXXXXX) || return 1
	trap 'nvme_squashfs_cleanup "$work"' EXIT
	nvme_squashfs_unpack "$1" "$work" && \
		nvme_squashfs_write "$work" "$NVME_DISK" "$UPGRADE_BACKUP"
)
