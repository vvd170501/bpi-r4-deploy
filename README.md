# OpenWrt on BPI-R4 with the production system on NVMe

This tree supports the original Banana Pi BPI-R4 family: 4 GB, 8 GB, and
the 2.5GE/PoE variants. Boot firmware lives in SPI-NAND; the kernel, root
filesystem and persistent writable overlay live on the SSD. Normal boot
does not require an SD card or eMMC.

BPI-R4 Pro 8X build definitions, workflow and original packages are retained.
**Pro 8X with split rootfs has not been tested and may not work.** The NVMe
layout and installation instructions below describe the original BPI-R4.

The SSD format uses a raw kernel/device-tree FIT, separate ZSTD SquashFS lower
root and ext4 overlay, without initramfs. It is not compatible
with the former combined-FIT NVMe installation. The original R4 wired images
build successfully; validation of the native PHY/LED changes is ongoing.

## Build

Run from this repository's root:

```sh
./build.sh bpi-r4 wired
# Or retain the MediaTek Wi-Fi stack:
./build.sh bpi-r4 standard
# Pro 8X split rootfs is untested and may not work:
./build.sh bpi-r4-pro-8x standard
```

The images end up in `openwrt/bin/targets/mediatek/filogic/`.

A normal build resets and cleans the source checkouts. Local changes in `openwrt` and `mtk-openwrt-feeds` are discarded.
Downloaded source archives in `openwrt/dl/` are kept and reused on subsequent runs.

Builds automatically enable compiler caching when `ccache` is installed,
using its configured cache directory (including a `CCACHE_DIR` override).

Set partition capacities in `boards/bpi-r4/configs/<variant>.config` (MiB).
For example, a 1 GiB read-only root and an 8 GiB writable overlay:

```ini
CONFIG_TARGET_ROOTFS_PARTSIZE=1024
CONFIG_BPI_R4_NVME_OVERLAY_PARTSIZE=8192
```

The defaults are `1024` MiB for p2 and `16384` MiB (16 GiB) for p3.
Normal, incremental and Docker builds use these config values. Image metadata
records both capacities for fresh installations; sysupgrade preserves installed sizes.

### Build using Docker

To build with Docker and its bundled build dependencies:

```sh
./docker-build.sh bpi-r4 wired
```

The wrapper builds the Docker image and runs `./build.sh` inside a temporary
container with all supplied arguments. The repository is bind-mounted, so
downloaded sources and images are saved in the same place as for a local build.
The compiler cache is bind-mounted from `cache/` and has a 10 GB limit.

### Incremental builds

**EXPERIMENTAL, use normal build for stable images.**

After the first normal build has prepared the checkouts, you can use incremental mode
to rebuild after changing patches, configs or the board's `files/` overlay:

```sh
./build.sh --incremental bpi-r4 wired
# Or invoke the incremental script directly:
./build-incremental.sh bpi-r4 wired
# With the Docker environment used for the initial build:
./docker-build.sh --incremental bpi-r4 wired
```

Incremental mode uses MediaTek's source cleanup and preparation stages to
reapply the current patches, including changed, removed and renamed patches.
It regenerates the configuration and synchronizes the board overlay, including
deleted files. Local edits made directly in `openwrt/` or its feeds are reset;
keep changes in this repository's patches, configs and `files/` instead.

Use the same host/container environment and build profile as the initial
build. Changes to the OpenWrt or MediaTek revisions require a normal build;
incremental mode checks both checkouts before resetting sources. A normal
build is also required to switch between `standard` and `wired`.

## Install

1. Build matching board/RAM images and verify their checksums.
2. Flash the matching `*-sdcard.img.gz` to an SD card. Set SW3 A=1, B=1
   and boot from SD.
3. Copy the matching `*-nvme-sysupgrade.tar` and
   `*-nand*-snand-img.bin` from that same build to `/tmp` on the router.
4. Run the installer, for example for a 4 GB non-PoE board:

   ```sh
   /root/install-dir/install-nvme.sh \
     /tmp/openwrt-mediatek-filogic-bananapi_bpi-r4-nvme-sysupgrade.tar \
     /tmp/openwrt-mediatek-filogic-bananapi_bpi-r4-nand-snand-img.bin
   ```

   The installer requires SD boot and an unused SSD, validates its inputs,
   rejects oversized kernels before requesting erase confirmation, prepares
   the SSD and flashes NAND boot firmware. It erases the SSD and NAND.
5. Power off, remove SD, set SW3 A=0, B=1 for NAND boot, and power on.

The retained defaults use `192.168.1.1`, user `root`, with no initial
password. Set a password on first login.

## SSD layout and upgrades

| Partition | Contents |
| --- | --- |
| p1 boot, 256 MiB raw | Kernel/device-tree FIT at partition start |
| p2 rootfs, configurable (default 1 GiB) | Read-only ZSTD SquashFS lower root, selected by PARTUUID |
| p3 rootfs_data, configurable (default 16 GiB), ext4 | Persistent writable overlay |
| p4 data, remaining ext4 | `/data`, outside sysupgrade |

On the SSD system, validate with `sysupgrade -T <tar>` and install with
`sysupgrade <tar>`. Use the NVMe tar rather than a combined FIT image.
The standard OpenWrt tar contains `CONTROL`, kernel and raw SquashFS root.
Mandatory `fwtool` validation checks the whole-image CRC before extraction
and device writes. No separate hash manifest or rootfs gzip wrapper is used.
See [NVME-SQUASHFS.md](boards/bpi-r4/NVME-SQUASHFS.md) for format details,
settings preservation and validation limits.

Factory reset through `firstboot`, `factoryreset`, LuCI or the reset button is
not supported on the NVMe system: fstools cannot discover the separate p3
extroot overlay through its normal `rootfs_data` lookup. To reset settings,
run `sysupgrade -n <nvme-sysupgrade.tar>` with a matching NVMe image. This resets
the overlay while preserving p4 (`/data`).

## Retained local support

- U-Boot R4 board definitions and PCIe/NVMe enablement (`450`, `451`).
- U-Boot root-device setup and consolidated NVMe boot defaults (`452`, `454`).
- Host SquashFS ZSTD support and the MT7988 DDR4 4BG firmware variants for
  the 8 GB R4. The latter uses a focused patch rather than a full Makefile override.
- Exact-disk extroot discovery for `root=PARTUUID=...`, using unmodified fstools.
- SSD installation, root verification, sysupgrade and `/data` mount files.
- Native MediaTek switch-PHY and LED control, with the upstream Aeonsemi
  vendor-match guards and LED defaults matching the vendor DSA bus name.
  The PHY driver derives polarity from hardware boot straps. An empty LED
  overlay preserves compatibility with installed U-Boot environments.
  See [PHY-DEBUG.md](boards/bpi-r4/PHY-DEBUG.md).

R4 builds omit the Pro 8X SFP/PHY and Wi-Fi patches, custom application packages,
QMI and package-repository overrides, Wi-Fi LED and hostname overrides and
SD auto-expansion. Shared sources needed by Pro 8X are retained and applied
only to Pro 8X builds. Standalone NAND/eMMC installers and UniFi deployment
files are removed from R4; the Pro 8X board files remain available.
The NVMe installer writes NAND after
preparing the SSD, so a separate NAND installer is unnecessary. R4 uses
direct filesystem root mounting, so the legacy NVMe FIT-block discovery
patch is also unnecessary.
The old NVMe overlay only supplied a fitblk rootdisk phandle; the base board
tree already enables PCIe, so that overlay and its boot references are removed.

Shared build-tree patches live in `common/patches/build/`, with board-specific
patches in `boards/bpi-r4/patches/build/`. When updating `pins.conf`, rebase
these patches against the sources after MediaTek preparation.

The original R4 wired Docker build passes. The upstream-only PHY matching fix
and native LED cleanup await board validation; Standard/Wi-Fi and Pro 8X builds
remain unverified.
