#!/bin/bash
set -euo pipefail

sed_in_place() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

is_openwrt_package_wrapper() {
  local pkg_dir=$1
  local makefile="$pkg_dir/Makefile"

  [ -f "$makefile" ] || return 1
  grep -qE 'include \$\(TOPDIR\)/rules\.mk|BuildPackage|PKG_SOURCE_(PROTO|URL|DATE|VERSION)' "$makefile"
}

restore_openwrt_boot_package() {
  local pkg_name=$1
  local src_dir="../openwrt_snap/package/boot/$pkg_name"
  local dst_dir="./package/boot/$pkg_name"

  if is_openwrt_package_wrapper "$dst_dir"; then
    return 0
  fi

  if [ ! -d "$src_dir" ]; then
    echo "[BOOT] Unable to restore $pkg_name: $src_dir not found"
    return 1
  fi

  rm -rf "$dst_dir"
  cp -rf "$src_dir" "$dst_dir"
  echo "[BOOT] Restored $pkg_name package wrapper from openwrt_snap"
}

replace_with_custom_package_wrapper() {
  local src_dir=$1
  local dst_dir=$2
  local label=$3

  if [ ! -d "$src_dir" ]; then
    return 1
  fi

  if ! is_openwrt_package_wrapper "$src_dir"; then
    echo "[BOOT] Skipping $label replacement: $src_dir is a source tree, not an OpenWrt package wrapper"
    return 1
  fi

  rm -rf "$dst_dir"
  cp -rf "$src_dir" "$dst_dir"
  echo "[BOOT] Replaced $label with custom OpenWrt package wrapper"
}

disable_mtk_feed() {
  for feed_file in feeds.conf feeds.conf.default; do
    if [ -f "$feed_file" ]; then
      sed_in_place '/^src-git\(-full\)\? mtk /d' "$feed_file"
    fi
  done

  rm -rf ./feeds/mtk ./feeds/mtk.index
}

rewrite_feeds() {
  local pkg_src=$1
  local luci_src=$2
  local routing_src=$3
  local telephony_src=$4
  for feed_file in feeds.conf feeds.conf.default; do
    if [ -f "$feed_file" ]; then
      sed_in_place "s#https://git.openwrt.org/feed/packages.git[^ ]*#$pkg_src#g" "$feed_file"
      sed_in_place "s#https://git.openwrt.org/project/luci.git[^ ]*#$luci_src#g" "$feed_file"
      sed_in_place "s#https://git.openwrt.org/feed/routing.git[^ ]*#$routing_src#g" "$feed_file"
      sed_in_place "s#https://git.openwrt.org/feed/telephony.git[^ ]*#$telephony_src#g" "$feed_file"
    fi
  done
}

rewrite_feeds "https://github.com/openwrt/packages.git;openwrt-24.10" \
              "https://github.com/openwrt/luci.git;openwrt-24.10" \
              "https://github.com/openwrt/routing.git;openwrt-24.10" \
              "https://github.com/openwrt/telephony.git;openwrt-24.10"
disable_mtk_feed

# MTK feed integration intentionally disabled for now because the upstream URL currently returns 404.
# MTK_FEED_URL=${MTK_FEED_URL:-https://git01.mediatek.com/openwrt/feeds/mtk-openwrt-feeds.git}
# MTK_FEED_BRANCH=${MTK_FEED_BRANCH:-master}
# if ! grep -qE "^src-git mtk " feeds.conf.default; then
#   echo "src-git mtk ${MTK_FEED_URL};${MTK_FEED_BRANCH}" >> feeds.conf.default
# fi

if ! ./scripts/feeds update -a; then
  echo "GitHub 镜像更新失败，尝试切换回官方源..."
  rewrite_feeds "https://git.openwrt.org/feed/packages.git;openwrt-24.10" \
                "https://git.openwrt.org/project/luci.git;openwrt-24.10" \
                "https://git.openwrt.org/feed/routing.git;openwrt-24.10" \
                "https://git.openwrt.org/feed/telephony.git;openwrt-24.10"
  disable_mtk_feed
  ./scripts/feeds update -a
fi

./scripts/feeds install -a
# ./scripts/feeds install -a -p mtk -f || true

restore_openwrt_boot_package arm-trusted-firmware-mediatek || true
restore_openwrt_boot_package uboot-mediatek || true

if [ -d "../bl-mt798x-dhcpd" ]; then
  echo "[BOOT] Found custom bootloader repo: bl-mt798x-dhcpd"
  atf_wrapper_replaced=0

  if replace_with_custom_package_wrapper \
    "../bl-mt798x-dhcpd/atf-20260123" \
    "./package/boot/arm-trusted-firmware-mediatek" \
    "ATF"; then
    atf_wrapper_replaced=1
  fi

  replace_with_custom_package_wrapper \
    "../bl-mt798x-dhcpd/uboot-mtk-20250711" \
    "./package/boot/uboot-mediatek" \
    "U-Boot" || true

  if [ "$atf_wrapper_replaced" -eq 1 ] && [ -n "${BPI_R4_GPT_LAYOUT:-}" ] && [ -f "../PATCH/gpt/$BPI_R4_GPT_LAYOUT" ]; then
    mkdir -p ./package/boot/arm-trusted-firmware-mediatek/src/gpt
    cp "../PATCH/gpt/$BPI_R4_GPT_LAYOUT" ./package/boot/arm-trusted-firmware-mediatek/src/gpt/
    echo "[GPT] Injected GPT layout: $BPI_R4_GPT_LAYOUT"
  elif [ -n "${BPI_R4_GPT_LAYOUT:-}" ] && [ "$atf_wrapper_replaced" -ne 1 ]; then
    echo "[GPT] Skipping GPT layout injection because no custom ATF package wrapper was applied"
  elif [ -n "${BPI_R4_GPT_LAYOUT:-}" ]; then
    echo "[GPT] Requested GPT layout '$BPI_R4_GPT_LAYOUT' not found, skipping"
  else
    echo "[GPT] No GPT layout requested"
  fi
else
  echo "[BOOT] Custom bootloader repo not found, using default OpenWrt sources"
fi

sed_in_place 's,-SNAPSHOT,,g' include/version.mk
sed_in_place 's,-SNAPSHOT,,g' package/base-files/image-config.in
sed_in_place '/CONFIG_BUILDBOT/d' include/feeds.mk
sed_in_place 's/;)\s*\\/; \\/' include/feeds.mk
sed_in_place 's,CONFIG_WERROR=y,# CONFIG_WERROR is not set,g' target/linux/generic/config-6.6 || true

echo "[MINIMAL] Minimal package preparation complete."
