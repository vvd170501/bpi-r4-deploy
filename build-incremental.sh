#!/bin/bash
# Refresh the prepared source tree without removing compiled output.
# Run from the repository root, in the same environment as the initial build.
set -euo pipefail

usage() { echo "usage: $0 <bpi-r4|bpi-r4-pro-8x> <standard|wired>" >&2; exit 1; }
die() { echo "incremental build: $*" >&2; exit 1; }

REPO=$(pwd)
. "$REPO/scripts/common.sh"
init_build "$@"

# Updating either upstream base needs the normal source-setup path. Check
# before resetting any sources, including when an environment override is used.
require_revision() {
	local dir=$1 wanted=$2 actual resolved
	actual=$(git -C "$dir" rev-parse --verify HEAD) || die "$dir is not a checkout; run build.sh without --incremental first"
	resolved=$(git -C "$dir" rev-parse --verify "$wanted^{commit}") || die "$dir does not have revision $wanted; run build.sh without --incremental"
	[ "$actual" = "$resolved" ] || die "$dir revision changed; run build.sh without --incremental"
}

require_revision "$REPO/openwrt" "$OPENWRT_COMMIT"
require_revision "$REPO/mtk-openwrt-feeds" "$MTK_COMMIT"

cd "$REPO/openwrt"
[ -f .config ] || die "no prepared configuration; run build.sh without --incremental first"
if [ -f .ab/branch_name ] && [ "$(cat .ab/branch_name)" != "$PROFILE" ]; then
	die "build profile changed; run build.sh without --incremental"
fi

mkdir -p /tmp/agents
scratch=$(mktemp -d /tmp/agents/bpi-r4-incremental.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
cp -p .config "$scratch/config"

autobuild=$REPO/mtk-openwrt-feeds/autobuild/unified/autobuild.sh
echo "Refreshing sources; keeping build_dir, staging_dir, downloads and images."
# MTK's clean snapshots timestamps, resets tracked source changes and removes
# untracked source files. It leaves ignored build output and feeds in place.
# Re-preparing therefore also handles removed/renamed patches without needing
# to reverse an old patch using its previous contents.
bash "$autobuild" "$PROFILE" clean
prepare_build -i

# MTK restores timestamps at the end of its prepare stage, before our patches
# and config have been reapplied. Restore again against the final contents so
# unchanged local inputs do not make unrelated packages look out of date.
"${autobuild%/*}/tools/ftrestore" -b "$PWD" -f .ab/keep/ftsnap-cache.txt
if cmp -s .config "$scratch/config"; then
	touch -r "$scratch/config" .config
fi

bash "$autobuild" "$PROFILE" build
