#!/bin/sh
# install-nand.sh - Install boot firmware only to NAND (spi0.0)
# Run from SD card (or eMMC). Writes BL2 and a UBI FIP/environment image, without a kernel/rootfs.
# Prefer install-nvme.sh with both artifacts to prepare SSD before NAND.

GH_USER="woziwrt"
GH_REPO="bpi-r4-deploy"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

printf "\n"
printf "=================================================\n"
printf "  BPI-R4 NAND Installer\n"
printf "=================================================\n"
printf "\n"

# || 0. Board and RAM variant selection ||||||||||||||||||||||||||||||||||||||||
# The NAND image is a lean installer (no docker/UniFi). It differs by RAM
# (DRAM training in BL2) and by board: the PoE (2.5GE) board needs its own
# DTS and its own U-Boot, so it gets the PoE NAND image. The board is taken
# from the running system, which the user booted from the matching SD image.

case "$(cat /tmp/sysinfo/board_name 2>/dev/null)" in
    bananapi,bpi-r4-2g5|bananapi,bpi-r4-poe) POE=1; BOARD_LABEL="BPI-R4 2.5GE (PoE)" ;;
    *)                                       POE=0; BOARD_LABEL="BPI-R4" ;;
esac

printf "Board: %s\n\n" "$BOARD_LABEL"
printf "Select your board RAM variant:\n"
printf "\n"
printf "  1) 4GB\n"
printf "  2) 8GB  (required for UniFi stack)\n"
printf "\n"
printf "Enter choice [1-2]: "
read RAM_CHOICE

# The NAND system only installs eMMC/NVMe, so it always comes from the wired
# release: the standard (WiFi) NAND image is ~123 MB, which nearly fills the
# 128 MB NAND, and users saw it hang at boot while the wired one works (#43).
case "$RAM_CHOICE" in
    1) GH_TAG="release-4gb-wired"; SNAND_NAME="openwrt-mediatek-filogic-bananapi_bpi-r4-nand-snand-img.bin";     RAM_LABEL="4GB" ;;
    2) GH_TAG="release-8gb-wired"; SNAND_NAME="openwrt-mediatek-filogic-bananapi_bpi-r4-nand-8gb-snand-img.bin"; RAM_LABEL="8GB" ;;
    *)
        printf "\n${RED}ERROR: Invalid choice!${NC}\n\n"
        exit 1
        ;;
esac

if [ "$POE" = 1 ]; then
    case "$RAM_CHOICE" in
        1) GH_TAG="release-4gb-poe-wired"; SNAND_NAME="openwrt-mediatek-filogic-bananapi_bpi-r4-poe-nand-snand-img.bin" ;;
        2) GH_TAG="release-8gb-poe-wired"; SNAND_NAME="openwrt-mediatek-filogic-bananapi_bpi-r4-poe-nand-8gb-snand-img.bin" ;;
    esac
    RAM_LABEL="${RAM_LABEL} PoE"
fi

SNAND_IMG="/tmp/${SNAND_NAME}"
SOURCE_IS_LOCAL=0

printf "\n"
printf "  Selected: %s (%s)\n" "$RAM_LABEL" "$GH_TAG"
printf "\n"

# || 1. Check boot media ||||||||||||||||||||||||||||||||||||||||||||||||||||||
# Must NOT be booted from NAND itself (can't rewrite the running NAND).

printf "[ 1/6 ] Checking boot media...\n"

if grep -q "ubi" /proc/cmdline 2>/dev/null; then
    printf "\n"
    printf "${RED}ERROR: You are booted from NAND -- cannot overwrite the running NAND.${NC}\n"
    printf "       Boot from the SD card (DIP = SD) and run this again.\n"
    printf "\n"
    exit 1
fi

printf "        OK -- not running from NAND\n"
printf "\n"

# || 2. Check NAND device ||||||||||||||||||||||||||||||||||||||||||||||||||||||

printf "[ 2/6 ] Checking NAND device...\n"

if ! grep -q "spi0.0" /proc/mtd 2>/dev/null; then
    printf "\n"
    printf "${RED}ERROR: NAND device (spi0.0) not found in /proc/mtd!${NC}\n"
    printf "\n"
    exit 1
fi

printf "        OK -- NAND device (spi0.0) found\n"
printf "\n"

# || 3. File source ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||

printf "[ 3/6 ] File source...\n"
printf "\n"
printf "  [1] Download from GitHub (default)\n"
printf "  [2] Use local file from /tmp (development/testing)\n"
printf "\n"
printf "  Select [1/2]: "
read USE_LOCAL

case "$USE_LOCAL" in
    2)
        SOURCE_IS_LOCAL=1
        printf "\n"
        printf "        INFO: Using local file from /tmp\n"
        printf "        Expecting: %s\n" "$SNAND_IMG"
        if [ ! -f "$SNAND_IMG" ]; then
            printf "${RED}ERROR: %s not found!${NC}\n" "$SNAND_IMG"
            printf "       Copy the NAND image there first, e.g.:\n"
            printf "       scp %s root@<router>:/tmp/\n\n" "$SNAND_NAME"
            exit 1
        fi
        printf "        OK -- file present (%s)\n\n" "$(du -h "$SNAND_IMG" | cut -f1)"
        ;;
    *)
        printf "\n"
        printf "  Use default release or your own fork?\n"
        printf "  [1] Default (woziwrt/bpi-r4-deploy)\n"
        printf "  [2] My fork (same repo name, different username)\n"
        printf "\n"
        printf "  Select [1/2]: "
        read USE_FORK

        case "$USE_FORK" in
            2)
                printf "\n"
                printf "        INFO: Fork repo name must remain 'bpi-r4-deploy'\n"
                printf "        Enter your GitHub username: "
                read GH_USER
                ;;
            *)
                ;;
        esac

        SNAND_URL="https://github.com/${GH_USER}/${GH_REPO}/releases/download/${GH_TAG}/${SNAND_NAME}"
        printf "        URL: %s\n\n" "$SNAND_URL"

        # || 4. Network check ||||||||||||||||||||||||||||||||||||||||||||||||
        printf "[ 4/6 ] Network check...\n"
        printf "\n"
        printf "        INFO: Internet required (~30-60 MB download)\n"
        printf "        Is ethernet connected? [yes/no]: "
        read NET_CONFIRM

        if [ "$NET_CONFIRM" != "yes" ]; then
            printf "\n        Connect ethernet and run the script again.\n\n"
            exit 0
        fi

        if ! ping -c 1 -W 3 github.com > /dev/null 2>&1; then
            printf "\n"
            printf "${RED}ERROR: No network connectivity -- check ethernet and try again.${NC}\n"
            printf "\n"
            exit 1
        fi

        printf "        OK -- network available\n\n"

        printf "        Checking release availability...\n"
        HTTP_CODE=$(wget --server-response --spider "$SNAND_URL" 2>&1 | grep "HTTP/" | tail -1 | awk '{print $2}')
        if [ "$HTTP_CODE" != "200" ]; then
            printf "\n${RED}ERROR: Release not found on GitHub (tag: %s).\n" "$GH_TAG"
            printf "       The build has not been created yet.\n"
            printf "       Please run the GitHub Actions workflow first:\n"
            printf "       https://github.com/${GH_USER}/${GH_REPO}/actions\n\n${NC}"
            exit 1
        fi
        printf "        OK -- release available\n\n"

        # || 5. Download snand-img.bin |||||||||||||||||||||||||||||||||||||||
        printf "[ 5/6 ] Downloading %s...\n\n" "$SNAND_NAME"

        wget -O "$SNAND_IMG" "$SNAND_URL"

        if [ $? -ne 0 ] || [ ! -s "$SNAND_IMG" ]; then
            printf "\n${RED}ERROR: Download failed.${NC}\n"
            printf "       Check network or URL and try again.\n\n"
            rm -f "$SNAND_IMG"
            exit 1
        fi

        printf "\n        OK -- downloaded (%s)\n\n" "$(du -h "$SNAND_IMG" | cut -f1)"
        ;;
esac

# || 6. Confirm and write ||||||||||||||||||||||||||||||||||||||||||||||||||||||

printf "[ 6/6 ] Writing image to NAND...\n"
printf "\n"
printf "${RED}  WARNING: This will ERASE the entire NAND (spi0.0).${NC}\n"
printf "\n"
printf "  Are you sure? Type YES to confirm: "
read CONFIRM

if [ "$CONFIRM" != "YES" ]; then
    printf "\n  Installation cancelled.\n\n"
    [ "$SOURCE_IS_LOCAL" = "0" ] && rm -f "$SNAND_IMG"
    exit 1
fi

printf "\n"
printf "        Writing %s image to NAND...\n" "$RAM_LABEL"
mtd -e spi0.0 write "$SNAND_IMG" spi0.0
if [ $? -ne 0 ]; then
    printf "\n${RED}ERROR: mtd write failed.${NC}\n\n"
    [ "$SOURCE_IS_LOCAL" = "0" ] && rm -f "$SNAND_IMG"
    exit 1
fi
sync
printf "        OK -- image written to NAND\n\n"

# Keep local test files; only clean up downloaded ones.
if [ "$SOURCE_IS_LOCAL" = "0" ]; then
    rm -f "$SNAND_IMG"
    printf "        OK -- cleanup done\n"
else
    printf "        INFO: kept local file %s\n" "$SNAND_IMG"
fi
printf "\n"

printf "${GREEN}=================================================${NC}\n"
printf "${GREEN}  NAND installation complete!${NC}\n"
printf "${GREEN}=================================================${NC}\n"
printf "\n"
printf "  NAND contains boot firmware only; there is no NAND installer OS.\n"
printf "  Prepare the SSD from SD with install-nvme.sh before booting NAND.\n"
