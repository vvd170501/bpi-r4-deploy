# Build steps shared by both boards, sourced by build.sh.
# $REPO is the repository root; prepare_build runs inside $REPO/openwrt.

init_build() {
	[ "$#" -eq 2 ] || usage
	BOARD=$1
	VARIANT=$2
	case $BOARD in bpi-r4|bpi-r4-pro-8x) ;; *) usage ;; esac
	case $VARIANT in
	standard) PROFILE=filogic-mac80211-mt798x_rfb-wifi7_nic ;;
	wired)    PROFILE=filogic ;;
	*) usage ;;
	esac
	[ -f "$REPO/boards/$BOARD/configs/$VARIANT.config" ] || usage
	. "$REPO/boards/$BOARD/board.sh"
	load_pins "$REPO/pins.conf"
}

# Both build modes regenerate exactly the same local patches and config.
# Extra arguments select feeds-update options, e.g. -i to reindex locally.
prepare_build() {
	if [ "$BOARD" = bpi-r4-pro-8x ]; then
		add_kernel_patches
	fi
	bash "$REPO/mtk-openwrt-feeds/autobuild/unified/autobuild.sh" "$PROFILE" prepare

	if [ "$VARIANT" = standard ]; then
		if [ "$BOARD" = bpi-r4-pro-8x ]; then
			add_wifi_patches
		else
			pin_wifi_sources
		fi
	fi
	board_tree
	if [ "$BOARD" = bpi-r4-pro-8x ]; then
		add_packages
	fi
	add_files
	if [ "$BOARD" = bpi-r4-pro-8x ]; then
		board_packages
	fi

	./scripts/feeds update -a "$@"
	./scripts/feeds install -a
	if [ "$BOARD" = bpi-r4-pro-8x ]; then
		board_after_feeds
		add_after_feeds
	fi

	\cp "$REPO/boards/$BOARD/configs/$VARIANT.config" .config
	add_config
	board_config
	# Resolve defaults and dependencies after all shared and board settings.
	make defconfig
}

# Read pins.conf; a value already in the environment wins.
load_pins() {
	local key value
	while IFS='=' read -r key value; do
		case $key in ''|\#*) continue ;; esac
		[ -n "${!key:-}" ] || export "$key=$value"
	done < "$1"
}

fetch_source() {
	local dir=$1 url=$2 branch=$3 commit=$4 clean_exclude=${5:-}
	local -a clean_args=(-dffx)
	if [ -n "$clean_exclude" ]; then
		clean_args+=(-e "$clean_exclude")
	fi

	if [ ! -d "$dir/.git" ]; then
		rm -rf "$dir"
		git clone --single-branch --branch "$branch" "$url" "$dir"
	else
		git -C "$dir" reset --hard HEAD
		git -C "$dir" clean "${clean_args[@]}"
		# Fetch if the pinned commit is missing locally.
		git -C "$dir" cat-file -e "$commit^{commit}" 2>/dev/null || git -C "$dir" fetch origin "$branch"
	fi
	git -C "$dir" checkout "$commit"
}

fetch_sources() {
	# Keep downloaded sources; remove nested feed repositories and all build state.
	fetch_source openwrt https://github.com/openwrt/openwrt.git openwrt-25.12 "$OPENWRT_COMMIT" /dl
	fetch_source mtk-openwrt-feeds https://github.com/mediatek/mtk-openwrt-feeds main "$MTK_COMMIT"
}

# Legacy kernel patches are retained for Pro 8X only. The autobuild
# prepare step puts them next to MediaTek's own.
add_kernel_patches() {
	\cp "$REPO"/common/patches/kernel/*.patch \
		"$REPO/mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12/"
}

# R4 uses pinned Wi-Fi sources without the Pro 8X custom patches.
pin_wifi_sources() {
	sh "$REPO/common/softmac-pin.sh"
}

# Since MTK feed c21f3b36 mt76/mac80211/hostapd come from
# github.com/mediatek/softmac_* and the feed has no patch directories for
# them any more. Pin the sources, then add our patches straight into the
# packages. Each board lists the patches it takes in WIFI_PATCHES.
add_wifi_patches() {
	local p dir

	sh "$REPO/common/softmac-pin.sh"
	mkdir -p package/kernel/mt76/patches package/kernel/mac80211/patches/subsys \
		package/network/services/hostapd/patches
	for p in $WIFI_PATCHES; do
		case $p in
		mt76/*)     dir=package/kernel/mt76/patches ;;
		mac80211/*) dir=package/kernel/mac80211/patches/subsys ;;
		hostapd/*)  dir=package/network/services/hostapd/patches ;;
		esac
		\cp "$REPO/common/patches/wifi/$p" "$dir/"
	done
}

copy_patches() {
	local p
	for p in "$1"/*.patch; do
		[ -f "$p" ] || continue
		\cp "$p" "$2/"
	done
}

# Patches both boards take from common/patches: the U-Boot NVMe/NAND/MMC
# support and shared firmware build changes; the legacy NVMe overlay is
# included only for Pro 8X.
add_common_tree_patches() {
	local p
	for p in "$REPO"/common/patches/build/*.patch; do
		[ -f "$p" ] || continue
		patch --batch -p1 < "$p"
	done

	copy_patches "$REPO/common/patches/uboot" package/boot/uboot-mediatek/patches
	if [ "$BOARD" = bpi-r4-pro-8x ]; then
		copy_patches "$REPO/common/patches/target" target/linux/mediatek/patches-6.12
	fi
}

add_packages() {
	\cp -r "$REPO/common/packages/sms-tool/" feeds/packages/utils/sms-tool
	\cp -r "$REPO/common/packages/modemdata-main/" feeds/packages/utils/modemdata
	\cp -r "$REPO/common/packages/luci-app-modemdata-main/luci-app-modemdata/" feeds/luci/applications
	\cp -r "$REPO/common/packages/luci-app-lite-watchdog/" feeds/luci/applications
	\cp -r "$REPO/common/packages/luci-app-sms-tool-js-main/luci-app-sms-tool-js/" feeds/luci/applications
}

# Files baked into the image. Pro 8X also keeps the legacy shared overlay.
add_files() (
	local overlay
	mkdir -p /tmp/agents
	overlay=$(mktemp -d /tmp/agents/bpi-r4-files.XXXXXX)
	trap 'rm -rf "$overlay"' EXIT
	if [ "$BOARD" = bpi-r4-pro-8x ]; then
		rsync -a "$REPO/common/files/" "$overlay/"
	fi
	rsync -a "$REPO/boards/$BOARD/files/" "$overlay/"
	mkdir -p files
	rsync -a --delete "$overlay/" files/
)

add_after_feeds() {
	\cp -r "$REPO/common/qmi.sh" package/network/utils/uqmi/files/lib/netifd/proto/
	chmod -R 755 package/network/utils/uqmi/files/lib/netifd/proto
	chmod -R 755 feeds/luci/applications/luci-app-modemdata/root
	chmod -R 755 feeds/luci/applications/luci-app-sms-tool-js/root
	chmod -R 755 feeds/packages/utils/modemdata/files/usr/share
}

add_config() {
	# The hidden 4BG TF-A packages are selected by their Makefile defaults.
	# Assignments in .config would be discarded by make defconfig.
	if command -v ccache >/dev/null 2>&1; then
		echo "CONFIG_DEVEL=y" >> .config
		echo "CONFIG_CCACHE=y" >> .config
		printf 'CONFIG_CCACHE_DIR="%s"\n' "$(ccache --get-config cache_dir)" >> .config
	fi
}
