# OpenWrt + UniFi Stack for Banana Pi BPI-R4 & BPI-R4 Pro 8X

Run **OpenWrt** on Banana Pi BPI-R4 and **BPI-R4 Pro 8X** (MT7988A, Wi-Fi 7) with an optional **UniFi Protect + UniFi Network Application** stack — a cost-effective alternative to the Ubiquiti UNVR + Cloud Gateway combo.

Ready-made images are in [Releases](https://github.com/woziwrt/bpi-r4-deploy/releases); the installer scripts download them for you. Everything is built on GitHub — no Linux machine needed, not even to build your own fork.

> **Tested hardware:** Banana Pi R4 rev 1.0 (4GB) · Banana Pi R4 rev 1.1 (8GB) · Banana Pi R4 Pro 8X · UniFi G5 Flex camera · UniFi U7-LR WiFi 7 AP

---

## Contents

- [Quick start: which image do I need?](#quick-start-which-image-do-i-need)
- [What is in the image](#what-is-in-the-image)
- [DIP switch reference](#dip-switch-reference)
- [Part A — BPI-R4: Install](#part-a--bpi-r4-install)
- [Part B — BPI-R4: UniFi stack](#part-b--bpi-r4-unifi-stack)
- [Part C — BPI-R4 Pro 8X: Install](#part-c--bpi-r4-pro-8x-install)
- [Part D — BPI-R4 Pro 8X: UniFi stack](#part-d--bpi-r4-pro-8x-unifi-stack)
- [Updating](#updating)
- [Part E — Fork and customize](#part-e--fork-and-customize)
- [NVMe partition layout](#nvme-partition-layout)
- [Hardware notes](#hardware-notes)
- [Known behaviors](#known-behaviors)
- [Reporting a problem](#reporting-a-problem)

---

## Quick start: which image do I need?

**Standard** = with the on-board/PCIe Wi-Fi 7 card. **Wired** = without Wi-Fi (smaller image, for a router or a UniFi server with a separate AP).

### BPI-R4

| Your board | Wi-Fi | Release |
|---|---|---|
| 4 GB | ✅ | `release-4gb-standard` |
| 4 GB | ❌ | `release-4gb-wired` |
| 4 GB with 2.5GE PoE port | ✅ | `release-4gb-poe` |
| 4 GB with 2.5GE PoE port | ❌ | `release-4gb-poe-wired` |
| 8 GB | ✅ | `release-8gb-standard` |
| 8 GB | ❌ | `release-8gb-wired` |
| 8 GB with 2.5GE PoE port | ✅ | `release-8gb-poe` |
| 8 GB with 2.5GE PoE port | ❌ | `release-8gb-poe-wired` |
| 8 GB, UniFi server | ❌ | `release-8gb-wired-unifi` (installed by `install-nvme-unifi.sh`, see [Part B](#part-b--bpi-r4-unifi-stack)) |
| 8 GB PoE, UniFi server | ❌ | `release-8gb-poe-wired-unifi` (same) |

> ⚠️ **The UniFi stack needs 8 GB RAM and an NVMe SSD.** UniFi Network + Protect exhaust 4 GB of RAM.

### BPI-R4 Pro 8X

| Wi-Fi | Release |
|---|---|
| ✅ | `release-pro-8x-standard` |
| ❌ | `release-pro-8x-wired` |

Pro 8X images do **not** work on the BPI-R4 and the other way round.

### What a release contains

| File | Used for |
|---|---|
| `…-sdcard.img.gz` | microSD card — flash with Etcher, boots on its own ([Step 1](#step-1--flash-the-sd-card)) |
| `…-snand-img.bin` | BPI-R4 NAND boot firmware only; Pro 8X keeps its installer OS |
| `…-emmc-img.bin` | eMMC, written by `install-emmc.sh` |
| `…-nvme-sysupgrade.tar` | BPI-R4 raw FIT + separate SquashFS installation and sysupgrade |
| `…-nvme-img.bin` + `bpi-r4-pro-8x.itb` | Pro 8X NVMe, unchanged |
| `bpi-r4*.itb` | firmware update with `sysupgrade` ([Updating](#updating)) |
| `sha256sums`, `config.buildinfo` | checksums and the exact build configuration |

For BPI-R4, download SD, NVMe tar and matching NAND firmware. Pro 8X installers retain their download prompts.

---

## What is in the image

- OpenWrt 25.12 with Linux 6.12, plus the MediaTek MT7988A feed (Ethernet, SFP, 10G PHYs).
- The MediaTek Wi-Fi 7 stack (mt76, mac80211, hostapd) in the standard variants.
- LuCI, Docker, modem tools (`sms-tool`, LuCI apps for modem data, SMS and a connection watchdog) and, in the standard variants, `luci-app-wifimgr`.

The exact upstream revisions are in [`pins.conf`](pins.conf); every image is built from those.

After installation the router is at **`192.168.1.1`**, user `root`, **no password** — set one first (LuCI → System → Administration, or `passwd`).

---

## DIP switch reference

| Boot medium | A | B |
|-------------|---|---|
| SD card     | 1 | 1 |
| NAND        | 0 | 1 |
| eMMC        | 1 | 0 |

> **NVMe boot:** BPI-R4 NAND firmware defaults to SSD boot. Keep DIP at **NAND** (A=0, B=1) after preparing SSD from SD. Pro 8X uses its saved environment selector.

The new BPI-R4 NAND artifact contains firmware only. Its production OS resides on NVMe; Pro 8X keeps its existing media options.

---

## Part A — BPI-R4: Install

BPI-R4 uses a raw kernel/device-tree FIT on NVMe p1, a separate read-only
ZSTD level 9 SquashFS rootfs on p2 and an ext4 writable overlay on p3. No
initramfs is used. This is a fresh-install format. Pro 8X keeps its separate existing flow.

1. Build/download matching board/RAM outputs: the SD image, the
   `*-nvme-sysupgrade.tar`, and the `*-nand*-snand-img.bin` from the same build.
   Check `sha256sums`. NAND now contains BL2 + FIP/environment only, no OS.
2. Flash the SD image, select SW3 **A=1, B=1**, boot and connect via SSH.
3. Copy the NVMe tar and matching NAND firmware to `/tmp` on the router.
4. While still running from SD, run (4 GB non-PoE example):

   ```sh
   /root/install-dir/install-nvme.sh \
     /tmp/openwrt-mediatek-filogic-bananapi_bpi-r4-nvme-sysupgrade.tar \
     /tmp/openwrt-mediatek-filogic-bananapi_bpi-r4-nand-snand-img.bin
   ```

   The installer validates the bundle, erases SSD, creates four partitions,
   installs SSD boot/root/overlay/data, then flashes the NAND firmware. It
   refuses to run on eMMC/NVMe or overwrite mounted NVMe filesystems.
5. Power off, remove SD, select SW3 **A=0, B=1**, and power on. NAND U-Boot
   selects SSD root by PARTUUID; preinit configures OpenWrt extroot to use
   p3 on that exact SSD and verifies the resulting mounts.

There is no intermediate NAND OpenWrt boot. NAND boot defaults already select
NVMe, so the installer does not use `fw_setenv` against the SD environment.
See [NVME-SQUASHFS.md](boards/bpi-r4/NVME-SQUASHFS.md) for layout, upgrades and limits.
The new path has not been built or boot-tested on a board.

---

## Part B — BPI-R4: UniFi stack

> The legacy BPI-R4 UniFi installer below is disabled for the ext4 layout.
> Its p3-data assumptions need porting; use Part A for the base SSD system.
> The Pro 8X instructions in Part D use a separate unchanged installer.

### What you need

- BPI-R4 **8 GB RAM** (rev 1.2+ recommended, see [Hardware notes](#hardware-notes))
- NVMe SSD, minimum 500 GB (1 TB recommended for continuous recording)
- UniFi camera (G5 Flex tested) · UniFi AP (U7-LR WiFi 7 tested)
- A [Ubiquiti account](https://account.ui.com) (optional — only for Remote Access)

When everything is set up:

| Service | Address |
|---------|---------|
| UniFi Protect | `https://192.168.1.1` |
| UniFi Network Application | `https://192.168.1.2:8443` |
| LuCI | `http://192.168.1.1:8081` |

---

### Step 1 — Install the UniFi NVMe system

Do [Part A](#part-a--bpi-r4-install) Steps 1–2, then from the NAND system, with the WAN cable connected:

```
/root/install-dir/install-nvme-unifi.sh
```

1. Select **1** (8 GB wired UniFi) or **2** (8 GB PoE wired UniFi).
2. Select the disk profile: **1** for a production disk (1 TB+, 30 GB data partition) or **2** for a small test disk (128 GB, 15 GB data partition). The rest of the disk is for recordings.

The script erases the whole NVMe, installs OpenWrt, puts the UniFi setup scripts on the data partition and reboots.

---

### Step 2 — Set up UniFi Protect

> ⚠️ **Run this from an SSH terminal, not from the LuCI terminal (ttyd).** The script changes the firewall and moves LuCI to another port, which cuts a ttyd session.

```
cd /mnt/nvme0n1p3
sh unifi-setup.sh
```

When asked, choose **[1] Download** — the script downloads the Protect Docker image (~660 MB) and loads it.

> ⚠️ When prompted, **disconnect the WAN cable** before pressing Enter.

---

### Step 3 — First-time Protect configuration

1. Open `https://192.168.1.1`.
2. Accept the SSL warning (self-signed certificate).
3. **Other Configuration Options → Local Network → Set Up Console Offline**.
4. Enter a console name, set a password, click **Finish**.

**Immediately disable auto-updates: Settings → Control Plane → Updates.** An automatic Protect update can break the stack.

---

### Step 4 — Set up the UniFi Network Application

Reconnect the WAN cable, then:

```
cd /mnt/nvme0n1p3
sh unifi-network-setup.sh
```

---

### Step 5 — First-time Network Application configuration

1. Open `https://192.168.1.2:8443`.
2. Complete the setup wizard.
3. **Settings → System** — disable auto-updates.

---

### Adding a camera

1. Connect the camera to a LAN port and power it on.
2. Hardware reset (hold the reset button until the LED changes).
3. Protect dashboard → **Devices** — the camera appears for adoption.

---

### Adopting an Access Point

After a factory reset the AP finds the Network Application through DNS (`unifi` → `192.168.1.2`). It appears as "Pending adoption" within a minute.

If auto-discovery fails (older AP firmware):

```
ssh ubnt@<AP_IP> "/usr/bin/syswrapper.sh set-inform http://192.168.1.2:8080/inform"
```

`<AP_IP>` is shown in LuCI (`http://192.168.1.1:8081`) → Network → DHCP Leases. Default AP credentials: `ubnt` / `ubnt`.

---

## Part C — BPI-R4 Pro 8X: Install

The BPI-R4 Pro 8X has a different NAND layout and device trees than the standard BPI-R4. **Pro 8X images are not compatible with the standard BPI-R4 and vice versa.**

### What you need

- BPI-R4 Pro 8X board
- **NVMe SSD in slot CN14 (M-key), minimum 512 GB** — tested with Patriot P300 512 GB. CN15 and CN18 are B-key slots for LTE modems, not for NVMe.
- microSD card (temporary, for the installation only)
- For WAN and LAN: SFP or SFP copper modules are recommended

---

### Step 1 — Flash the SD card

1. In [Releases](https://github.com/woziwrt/bpi-r4-deploy/releases) open **release-pro-8x-standard** (Wi-Fi) or **release-pro-8x-wired** and download
   `openwrt-mediatek-filogic-bananapi_bpi-r4-pro-8x-sdcard.img.gz`.
2. Flash it to a microSD card with [Balena Etcher](https://etcher.balena.io/).
3. Insert the SD card, set DIP **A=1, B=1** (SD boot) and power on.
4. Connect via SSH: `ssh root@192.168.1.1` (no password).

---

### Step 2 — Install the NAND system

Connect the WAN cable, then run:

```
/root/install-dir/install-nand.sh
```

Select **1** (standard, Wi-Fi 7) or **2** (wired). After the script finishes:

1. Power off.
2. Set DIP **A=0, B=1** (NAND boot) and power on.
3. Connect via SSH: `ssh root@192.168.1.1`.

---

### Step 3 — Optional: Install to eMMC

> ⚠️ **Run this before `install-nvme.sh`.** After the NVMe installation the board always boots from NVMe.

```
/root/install-dir/install-emmc.sh
```

Select **1** (Pro 8X Wi-Fi) or **2** (Pro 8X wired).

After the installation set DIP **A=1, B=0** (eMMC boot) to use eMMC, or keep DIP at A=0, B=1 and continue with the NVMe install.

---

### Step 4 — Install OpenWrt to NVMe

> For the **UniFi stack** use `install-nvme-unifi.sh` instead — see [Part D](#part-d--bpi-r4-pro-8x-unifi-stack).

From the NAND system, connect the WAN cable and run:

```
/root/install-dir/install-nvme.sh
```

Select **1** (Pro 8X Wi-Fi) or **2** (Pro 8X wired).

The script checks the NVMe health, downloads the images (~150 MB), **erases the whole NVMe**, writes OpenWrt and reboots.

**After the reboot the router runs from NVMe.** The DIP stays at A=0, B=1 for good — this is correct.

---

### Switching between NAND and NVMe

```
boot-nand    # switch to NAND on next reboot
boot-nvme    # switch back to NVMe on next reboot (run it on the NAND system)
```

---

## Part D — BPI-R4 Pro 8X: UniFi stack

The Pro 8X wired variant is well suited for the UniFi stack — 8 GB RAM, NVMe storage and no on-board Wi-Fi.

### What you need

- BPI-R4 Pro 8X (wired variant recommended)
- NVMe SSD in slot CN14, **minimum 512 GB** (1 TB recommended for continuous recording)
- UniFi camera (G5 Flex tested) · UniFi AP (U7-LR WiFi 7 tested)
- A [Ubiquiti account](https://account.ui.com) (optional — only for Remote Access)

When everything is set up:

| Service | Address |
|---------|---------|
| UniFi Protect | `https://192.168.1.1` |
| UniFi Network Application | `https://192.168.1.2:8443` |
| LuCI | `http://192.168.1.1:8081` |

### Steps

1. Do [Part C](#part-c--bpi-r4-pro-8x-install) Steps 1–2, then from the NAND system, with the WAN cable connected:
   ```
   /root/install-dir/install-nvme-unifi.sh
   ```
   Select **1** (Pro 8X Wi-Fi) or **2** (Pro 8X wired), then the disk profile (**1** production 1 TB+, **2** test 128 GB).
2. Set up Protect (SSH terminal only, not ttyd): `sh /mnt/nvme0n1p3/unifi-setup.sh` — choose **[1] Download**, and **disconnect the WAN cable** when prompted.
3. First-time Protect configuration — same as [Part B Step 3](#step-3--first-time-protect-configuration). Disable auto-updates in **Settings → General → Auto Update**.
4. Reconnect the WAN cable and set up the Network Application: `sh /mnt/nvme0n1p3/unifi-network-setup.sh`
5. Open `https://192.168.1.2:8443`, complete the wizard, disable auto-updates in **Settings → System**.

Cameras and access points are adopted as in Part B — see [Adding a camera](#adding-a-camera) and [Adopting an Access Point](#adopting-an-access-point).

---

## Updating

**BPI-R4 NVMe SquashFS:** use the matching `*-nvme-sysupgrade.tar`, not a `.itb`.
LuCI's firmware flash and `sysupgrade` use the same platform handler:

```sh
sysupgrade -T /tmp/openwrt-mediatek-filogic-bananapi_bpi-r4-nvme-sysupgrade.tar
sysupgrade /tmp/openwrt-mediatek-filogic-bananapi_bpi-r4-nvme-sysupgrade.tar
```

Keep settings enabled (the default) to save the selected configuration archive
onto a fresh p3 overlay. Early boot restores it. `sysupgrade -n` resets the
upper without restoring settings. p4 data and NAND firmware/environment are
not written. Installed packages not included in the new image must be
reinstalled. Keep an external backup until hardware tests have validated the
new path. There is no support for upgrading the old combined-FIT SSD layout.

The handler checks that the FIT and rootfs fit p1/p2 before writing them
directly to those partitions. p1 has no filesystem. Its final FIT sector
is zero-padded to 512 bytes. A partial raw write can require SD recovery;
there is no staged kernel file or A/B fallback.

The standard sysupgrade tar carries the raw SquashFS and kernel FIT. Mandatory
`fwtool` validation checks the whole-image CRC before extraction or device writes.
The rootfs is validated and written by streaming it from the archive. Only
the kernel FIT and metadata are extracted into `/tmp`, avoiding a second
rootfs copy in RAM. Validation finishes before partition writes.

**SD/eMMC and Pro 8X:** their existing FIT-based update paths still use the
matching `.itb`. Pro 8X NVMe settings still require manual backup and restore.

Do not rerun an installer to update: installers erase the disk, including data.
See [NVME-SQUASHFS.md](boards/bpi-r4/NVME-SQUASHFS.md) for implementation and test limits.

Factory reset through `firstboot`, `factoryreset`, LuCI or the reset button is
not supported on the NVMe system: fstools cannot discover the separate p3
extroot overlay through its normal `rootfs_data` lookup. To reset settings,
run `sysupgrade -n <nvme-sysupgrade.tar>` with a matching NVMe image. This resets
the overlay while preserving p4 (`/data`).

---

## Part E — Fork and customize

Fork this repository to build your own releases.

1. Fork on GitHub. **Keep the name `bpi-r4-deploy`** — the installers expect it.
2. **Settings → Actions → General** → set **Workflow permissions** to **Read and write**.
3. **Actions** → pick the workflow for your board → **Run workflow** from `main`:
   - **BPI-R4** — *Build BPI-R4 Deploy*, variant **standard** or **wired**
   - **BPI-R4 Pro 8X** — *Build BPI-R4 Pro 8X*, variant **Pro-8X-wifi** or **Pro-8X-wired**
   - Tick **publish** to turn the build into releases. Unticked, the images are only kept for 14 days as a workflow artifact (handy for testing).
4. After about 2–3 hours the releases appear in your fork.

To install from your fork, choose **"My fork"** when an installer asks where to download from and enter your GitHub username.
The Pro 8X `install-nand.sh`, `install-emmc.sh` and `install-nvme.sh` do not ask yet — change `GH_USER` at the top of those scripts in your fork.

### Repository layout

Both boards are built by one script:

```
./build.sh <bpi-r4|bpi-r4-pro-8x> <standard|wired>
```

| Path | What it holds |
|------|---------------|
| `pins.conf` | Every upstream revision: OpenWrt, MediaTek feed, mt76/mac80211/hostapd/iw/wifi-scripts |
| `build.sh` | The build, step by step |
| `scripts/common.sh` | Build steps shared by both boards |
| `common/` | Patches, packages and image files both boards use |
| `boards/<board>/board.sh` | What only that board does |
| `boards/<board>/` | Its source patches, image files (`files/`, installers in `files/root/install-dir/`), `configs/<variant>.config`, UniFi scripts (`unifi/`) |

To change what is in the image, edit `boards/<board>/configs/<variant>.config`; to add files to the image, put them under `common/files/` (both boards) or `boards/<board>/files/`.

### Building locally

`build.sh` clones OpenWrt and the MediaTek feed itself at the commits in `pins.conf`
(a variable set in the environment wins, e.g. `MTK_COMMIT=<sha>`). On Ubuntu 22.04
with the [OpenWrt build prerequisites](https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem):

```
git clone https://github.com/woziwrt/bpi-r4-deploy
cd bpi-r4-deploy
./build.sh bpi-r4-pro-8x standard
```

The images end up in `openwrt/bin/targets/mediatek/filogic/`.

A normal build resets and cleans the source checkouts. Local changes in `openwrt` and `mtk-openwrt-feeds` are discarded.
Downloaded source archives in `openwrt/dl/` are kept and reused on subsequent runs.

Builds automatically enable compiler caching when `ccache` is installed,
using its configured cache directory (including a `CCACHE_DIR` override).

For BPI-R4, configure NVMe partition capacities in
`boards/bpi-r4/configs/<variant>.config` (MiB):

```ini
CONFIG_TARGET_ROOTFS_PARTSIZE=1024
CONFIG_BPI_R4_NVME_OVERLAY_PARTSIZE=16384
```

The defaults reserve 1 GiB for the read-only root and 16 GiB for the writable
overlay. Normal, incremental and Docker builds use these values. They control
fresh installations; sysupgrade preserves existing partition sizes.

#### Building with Docker

If you don't have all build dependencies available or don't want to clutter the main system, you can use a docker container for building the images.

```
./docker-build.sh bpi-r4 wired
```

The wrapper builds the Docker image with required packages, then runs `./build.sh` inside a temporary container with all supplied arguments.
The repository is bind-mounted into the container, so downloaded sources and images are still saved in the same place as for non-Docker build.
The compiler cache is bind-mounted from `cache/` and has a 10 GB limit.

#### Incremental builds

**EXPERIMENTAL, use normal build for stable images.**

After the first normal build has prepared the checkouts, you can use incremental mode
to rebuild after changing patches, configs or the shared or board `files/` overlays:

```sh
./build.sh --incremental bpi-r4 wired
# Or invoke the incremental script directly:
./build-incremental.sh bpi-r4 wired
# With the Docker environment used for the initial build:
./docker-build.sh --incremental bpi-r4 wired
```

Incremental mode uses MediaTek's source cleanup and preparation stages to
reapply the current patches, including changed, removed and renamed patches.
It regenerates the configuration and synchronizes the file overlays, including
deleted files. Local edits made directly in `openwrt/` or its feeds are reset;
keep changes in this repository's patches, configs and `files/` instead.

Use the same host/container environment and build profile as the initial
build. Changes to the OpenWrt or MediaTek revisions require a normal build;
incremental mode checks both checkouts before resetting sources. A normal
build is also required to switch between `standard` and `wired`.


---

### Board source patches

Shared build-tree patches live in `common/patches/build/`, with board-specific
patches in `boards/<board>/patches/build/`. All are applied after MediaTek
preparation, before the final feed update and installation.
When updating `pins.conf`, rebase these patches against the sources after
MediaTek preparation.

## Architecture

| Component | Role |
|-----------|------|
| BPI-R4 / Pro 8X | Routing, firewall, Docker runtime, NVMe storage |
| UniFi Protect | Camera management ([dciancu](https://github.com/dciancu/unifi-protect-unvr-docker-arm64) Docker image) |
| UniFi Network Application | Wi-Fi management (linuxserver Docker image) |
| UniFi AP | Professional Wi-Fi (U7-LR WiFi 7 tested) |

---

## NVMe partition layout

BPI-R4 `install-nvme.sh`:

| Partition | Size | Purpose |
| --- | --- | --- |
| p1 `boot` | 256 MiB, raw | FIT at partition start: kernel + DT/overlays only |
| p2 `rootfs` | Configurable, default 1 GiB | ZSTD level 9 SquashFS read-only lower root |
| p3 `rootfs_data` | Configurable, default 16 GiB, ext4 | Persistent writable overlay |
| p4 `data` | Remaining SSD, ext4 | `/data` |

Set `CONFIG_TARGET_ROOTFS_PARTSIZE` in `boards/bpi-r4/configs/<variant>.config`
to p2 capacity in MiB (default `1024`); this also sizes the SD/eMMC image
partition. The SquashFS payload is rounded to 1 KiB in the standard tar, while
installation reserves the configured capacity for future larger images.
Sysupgrade preserves that capacity and rejects images that exceed it.
SD/eMMC rootfs images retain XZ.

Set overlay capacity in MiB when building, for example
`BPI_R4_NVME_OVERLAY_PARTSIZE=8192 ./build.sh bpi-r4 standard` for an 8 GiB p3.
The default is `16384`. Image metadata carries both capacities for fresh
installation; sysupgrade preserves the installed partition sizes.

Pro 8X and its UniFi installer retain their separate original layouts. The
legacy BPI-R4 UniFi installer is disabled rather than writing over the new
p3 overlay partition.

---

## Hardware notes

### BPI-R4 rev 1.0 known issues

| Issue | Details |
|-------|---------|
| NVMe + SFP conflict | Some NVMe disks pull down the I2C bus, disabling the SFP ports |
| Affected disks | Chinese OEM NVMe drives (e.g. generic 128 GB) |
| Not affected | Samsung EVO series |
| Fixed in | Rev 1.2+ |

For new builds, a **BPI-R4 8 GB RAM rev 1.2+** is recommended.

---

## Known behaviors

### Boot time

- ~1 min — router reachable via SSH and LuCI
- ~3 min — UniFi Protect available
- ~8–10 min — UniFi Network Application fully initialized

### WAN reconnect

When WAN goes down and comes back up, the hotplug handler (`99-docker-nft`) restores the Docker nftables rules automatically — no reboot needed.

### NAND first boot — UBI messages

On the very first boot into the NAND system, U-Boot may print messages like:

```
UBI: Bad EC magic in block XXXX
```

This is normal — U-Boot is initializing the NAND flash. The messages disappear on later boots.

### GitHub runner disk space

If a build fails with a disk-related error, re-run the workflow — runners with enough space are usually available shortly.

---

## Reporting a problem

Please open an [issue](https://github.com/woziwrt/bpi-r4-deploy/issues) with:

1. **Board:** BPI-R4 4 GB / 8 GB / PoE, revision, or BPI-R4 Pro 8X.
2. **Release** you installed (e.g. `release-8gb-standard`) and its date, or your fork and commit.
3. **Boot medium:** SD, NAND, eMMC or NVMe.
4. What you did, what you expected and what happened instead.
5. The output of `logread` and `dmesg`, or the serial console log if the board does not boot.

Problems with images built from a modified fork are hard for us to reproduce — please first check whether the same happens with our release.

---

<img width="1264" height="1080" alt="UniFi Protect dashboard" src="https://github.com/user-attachments/assets/1483d00f-839a-4ced-b899-6d688e0483a7" />

<img width="1264" height="1080" alt="UniFi Network Application" src="https://github.com/user-attachments/assets/f912c22e-a31c-42e6-8fc7-34e1632a8bc7" />

<img width="1264" height="1080" alt="LuCI dashboard" src="https://github.com/user-attachments/assets/ae709b45-ad2a-44ff-ab7b-73b9d5f1d6d9" />

<img width="1264" height="1080" alt="UniFi camera view" src="https://github.com/user-attachments/assets/b6ce49af-bd91-4a67-87b2-c77ee121f051" />

---

*This project is not affiliated with Ubiquiti Inc. in any way.*

*🍌 TEAM WOZIWRT+CLAUDE*
