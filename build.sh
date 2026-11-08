#!/bin/bash
# Build one board and variant:
#
#   ./build.sh [--incremental] <board> <variant>
#     board:   bpi-r4 | bpi-r4-pro-8x     (boards/<board>/board.sh)
#     variant: standard (Wi-Fi) | wired   (boards/<board>/configs/<variant>.config)
#
# Run from the repository root. Source checkouts in ./openwrt and
# ./mtk-openwrt-feeds are reset and cleaned first, keeping only ./openwrt/dl
# for downloaded sources. --incremental refreshes sources while retaining
# compiled output. Images end up in openwrt/bin/targets/mediatek/filogic.
#
# What is shared by both boards lives in common/, what is not in boards/.
# The upstream revisions are in pins.conf.
set -euo pipefail

usage() { echo "usage: $0 [--incremental] <bpi-r4|bpi-r4-pro-8x> <standard|wired>" >&2; exit 1; }

incremental=
args=()
for arg in "$@"; do
	case $arg in
	--incremental) incremental=1 ;;
	--*) usage ;;
	*) args+=("$arg") ;;
	esac
done

if [ -n "$incremental" ]; then
	exec bash ./build-incremental.sh "${args[@]}"
fi

REPO=$(pwd)
. "$REPO/scripts/common.sh"
init_build "${args[@]}"

fetch_sources

cd openwrt
prepare_build

bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh "$PROFILE" build
