#!/bin/sh
# Fresh installation from SD. Both arguments are local, matching build outputs.
# Never execute this on a host: it intentionally erases the board SSD and NAND.
set -eu

[ "$#" = 2 ] || {
    echo "usage: $0 NVME_SYSUPGRADE_TAR MATCHING_SNAND_IMG" >&2
    exit 1
}
image=$1
nand=$2
[ -s "$image" ] && [ -s "$nand" ] || exit 1
. /lib/functions/nvme-squashfs.sh
nvme_squashfs_sd_booted || {
    echo "Installation must run from SD, not eMMC/NVMe" >&2; exit 1;
}
for tool in sfdisk partprobe blockdev mkfs.ext4 mtd fwtool jsonfilter hexdump fit_check_sign; do
    command -v "$tool" >/dev/null || { echo "Missing installer tool: $tool" >&2; exit 1; }
done

work=$(mktemp -d /tmp/nvme-squashfs-install.XXXXXX)
trap 'nvme_squashfs_cleanup "$work"' EXIT
trap 'exit 1' HUP INT TERM
nvme_squashfs_unpack "$image" "$work" || { echo "Invalid NVMe SquashFS image" >&2; exit 1; }
case "$NVME_IMAGE_BOARD" in
    bananapi_bpi-r4) expected=bananapi_bpi-r4-nand-snand-img.bin ;;
    bananapi_bpi-r4-8gb) expected=bananapi_bpi-r4-nand-8gb-snand-img.bin ;;
    bananapi_bpi-r4-poe) expected=bananapi_bpi-r4-poe-nand-snand-img.bin ;;
    bananapi_bpi-r4-poe-8gb) expected=bananapi_bpi-r4-poe-nand-8gb-snand-img.bin ;;
esac
[ "${nand##*/}" = "openwrt-mediatek-filogic-$expected" ] || {
    echo "Expected matching NAND firmware: openwrt-mediatek-filogic-$expected" >&2; exit 1;
}
# Require matching NAND defaults that load the raw FIT from p1.
grep -aq 'owrt_nvme_squashfs=1' "$nand" && grep -aq 'nvme_read_kernel=' "$nand" || {
    echo "NAND firmware does not contain the raw-FIT NVMe boot defaults" >&2; exit 1;
}
grep -q '"spi0.0"' /proc/mtd || { echo "Whole NAND device spi0.0 unavailable" >&2; exit 1; }
NVME_DISK=/dev/nvme0n1
[ -b "$NVME_DISK" ] || exit 1
[ "$(blockdev --getss "$NVME_DISK")" = 512 ] || {
    echo "This installer currently requires 512-byte NVMe logical sectors" >&2; exit 1;
}
root_start=526336
# Reserve the configured p2 capacity even though the SquashFS payload is
# unpadded, so later firmware images can grow without moving p3/p4.
root_sectors=$((NVME_ROOT_PART_BYTES / 512))
root_end=$((root_start + root_sectors - 1))
upper_start=$((root_end + 1))
upper_end=$((upper_start + NVME_OVERLAY_PART_BYTES / 512 - 1))
disk_bytes=$(blockdev --getsize64 "$NVME_DISK")
[ "$disk_bytes" -gt "$(((upper_end + 131072) * 512))" ] || {
    echo "SSD too small for boot, rootfs, configured overlay and data" >&2; exit 1;
}
printf 'ERASE all data on %s AND SPI-NAND spi0.0? Type YES: ' "$NVME_DISK"
read -r confirm
[ "$confirm" = YES ] || exit 1
mounted=$(mount | awk -v disk="$NVME_DISK" 'index($1, disk "p") == 1 { print $1 }')
for part in $mounted; do
    umount "$part" || { echo "Cannot unmount $part; installation stopped" >&2; exit 1; }
done
# Wipe signatures at the NEW partition locations before exposing the GPT.
# Defer both of sfdisk's kernel rereads to partprobe, after signatures are gone.
# The standard GPT reserves its final 33 sectors for the backup table/header.
sfdisk --no-reread --no-tell-kernel --wipe always --wipe-partitions always "$NVME_DISK" <<EOF
label: gpt
unit: sectors

start=2048, size=524288, type=L, name=boot
start=$root_start, size=$root_sectors, type=L, name=rootfs
start=$upper_start, size=$((NVME_OVERLAY_PART_BYTES / 512)), type=L, name=rootfs_data
start=$((upper_end + 1)), size=$((disk_bytes / 512 - 34 - upper_end)), type=L, name=data
EOF
sync
partprobe "$NVME_DISK"
tries=0
while [ ! -b "${NVME_DISK}p4" ]; do
    tries=$((tries + 1))
    [ "$tries" -lt 10 ] || { echo "Partition devices did not appear" >&2; exit 1; }
    sleep 1
done
mkfs.ext4 -F -L data "${NVME_DISK}p4"
nvme_squashfs_write "$work" "$NVME_DISK" "" || {
    echo "NVMe firmware installation failed; NAND has not been written. Remain on SD to repair." >&2
    exit 1
}
# Write only BL2 + UBI FIP/environment, after SSD preparation has succeeded.
# NVMe boot is a compiled NAND default; do not write the SD environment.
mtd -e spi0.0 write "$nand" spi0.0
sync
echo "Installation complete. Power off, remove SD, set SW3 A=0 B=1, power on."
