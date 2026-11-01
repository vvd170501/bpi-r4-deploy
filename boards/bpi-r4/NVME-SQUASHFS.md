# BPI-R4 NVMe SquashFS format

This is a fresh-install format, without initramfs. Pro 8X is unchanged.
NAND contains only BL2, FIP and environment volumes. Normal boot loads
the raw kernel/DT FIT from NVMe p1 and mounts the p2 SquashFS root read-only
by PARTUUID. p1 has no filesystem. U-Boot obtains its start and size from
GPT, reads the fixed FIT header, then the complete FDT, and uses OpenWrt's
`imszb` to load the full FIT including external data. Every read is bounded
by p1 and a 256 MiB RAM-load limit. NVMe logical sectors must be 512 bytes.
Unmodified fstools mounts p3 through extroot. NVMe preinit resolves the root
SSD by its p2 PARTUUID and writes `/tmp/overlay/etc/config/fstab` with that
SSD's exact p3 device path.
`block extroot` reads this before the lower's fstab. No filesystem label or
UUID lookup is used, so matching labels on other disks cannot select their
overlays. Preinit removes the RAM config after verifying the mounts. SD/eMMC
boots never activate this config.
NVMe U-Boot defaults set `fstools_ignore_partname=1` to disable GPT-name scanning.
The kernel has PCIe/NVMe, SquashFS, ext4 and OverlayFS built in. An early preinit guard
makes p2 read-only at block level and stops before services if the expected
read-only lower or same-SSD persistent upper is missing.

| Partition | Contents |
| --- | --- |
| p1 boot, 256 MiB raw | Kernel/DT-only FIT at the partition start |
| p2 rootfs, configurable (default 1 GiB) | ZSTD level 9 compressed read-only SquashFS lower |
| p3 rootfs_data, configurable (default 16 GiB), ext4 | Persistent upper/work directories |
| p4 data, remaining ext4 | `/data`, outside sysupgrade |

Build with `./build.sh bpi-r4 standard` or `wired`. Set
`CONFIG_TARGET_ROOTFS_PARTSIZE` in `boards/bpi-r4/configs/<variant>.config`
to the desired p2 capacity in MiB (default `1024`). This also controls the
SD/eMMC image partition size. Set `CONFIG_BPI_R4_NVME_OVERLAY_PARTSIZE` in the
same variant config to choose p3 capacity in MiB, for example:

```ini
CONFIG_TARGET_ROOTFS_PARTSIZE=1024
CONFIG_BPI_R4_NVME_OVERLAY_PARTSIZE=8192
```

The overlay default is `16384` (16 GiB). The setting is a Kconfig integer
under Target Images and is retained by `make defconfig`. Normal, incremental
and Docker builds all read it from the variant config. Both capacities are recorded in standard
OpenWrt image metadata. These settings control fresh installs; sysupgrade
preserves existing partition sizes. The bundle records p2 capacity separately
from the SquashFS payload, so future images can grow within the reserved
space. The build rejects a payload larger than that capacity.
Preserve outputs before another build, since sources are recreated.

The SSD rootfs uses ZSTD at compression level 9; SD/eMMC FIT rootfs images
retain XZ. The board build enables ZSTD in the host SquashFS tools and builds
its kernel decompressor in, alongside XZ support. The standard sysupgrade tar
contains the raw SquashFS, rounded to 1 KiB rather than padded to p2 capacity,
keeping the upgrade archive and writes small.

From a matching SD boot (SW3 A=1, B=1), copy the board/RAM-specific
`*-nvme-sysupgrade.tar` and `*-nand*-snand-img.bin` from the same build to `/tmp`.
Verify release checksums. Run `/root/install-dir/install-nvme.sh <tar> <nand>`.
It validates inputs, requires an SSD with 512-byte sectors and enough
space, and rejects a kernel exceeding p1's 256 MiB capacity before asking for
erase confirmation. After confirmation, it unmounts SSD partitions, prepares
the SSD and flashes NAND firmware.
The installer uses `sfdisk` to clear old filesystem signatures at the new
partition locations before `partprobe` exposes the new GPT to the kernel.
This prevents stale filesystems from being automounted during repartitioning
without changing the SD system's automount settings.
An unmount or firmware-write failure stops installation with an error;
the final `Installation complete` message confirms that all stages finished.
Then power off, remove SD, set SW3 A=0, B=1 and power on. The installer does
not need a NAND OS or modify the SD U-Boot environment.

On the SSD system use `sysupgrade -T <tar>` then `sysupgrade <tar>`, or LuCI
with keep settings enabled. The standard tar contains `CONTROL`, kernel FIT
and raw SquashFS root. OpenWrt metadata records the NVMe layout and fresh-install
partition capacities. Mandatory `fwtool` validation checks the whole-image CRC
in both the SD installer and the upgrade RAM stage; there is no separate hash
manifest or gzip wrapper around the already compressed SquashFS.
The handler replaces p1/p2, reformats p3, and stages the selected backup
as `/sysupgrade.tgz` for normal preinit restoration. `sysupgrade -n` omits the
archive. p4 and NAND are not written. Package files outside the selected
backup are not retained. Images must fit the existing partitions;
`sysupgrade -T` checks p1/p2 capacity, including the FIT's final padded
512-byte sector. The actual upgrade repeats these checks, streams the rootfs
to p2, and writes the FIT directly to p1 using `dd` with `conv=sync,fsync`.
p1 is never formatted or mounted; ext4 is used only for the overlay and data.
Reformatting creates a new filesystem UUID; boot discovery does not depend
on that UUID. The overlay contents are reset so old package files and
whiteouts cannot mask the new SquashFS.
The overlay is reset only after both raw writes succeed. Mounted partitions
are detected by device number, including the automatic `/dev/root` alias.
A partial p1 write or power loss can destroy the previous kernel: there is
no staged-file rename or A/B slot. Recovery uses the SD installation path.

The archive remains in `/tmp`; only metadata and the small kernel FIT are
extracted alongside it. After `fwtool` validates the complete image, the rootfs
is streamed from the archive to check its magic and size, then streamed directly
to p2. No second rootfs copy is staged. All validation finishes
before partition writes, so validation failures leave the installed system
intact. The write pipeline propagates tar and disk-write errors before
kernel replacement or overlay reset. A failure after entering sysupgrade's RAM
stage may still require a manual reboot to restart normal services.

The old combined-FIT NVMe layout and BPI-R4 UniFi installer are not supported
by this format. No migration/rollback is implemented. Full image build and
board validation remain outstanding.
