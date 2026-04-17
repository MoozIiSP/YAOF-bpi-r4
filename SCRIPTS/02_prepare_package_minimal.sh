#!/bin/bash
set -euo pipefail
clear

rewrite_feeds() {
  local pkg_src=$1
  local luci_src=$2
  local routing_src=$3
  local telephony_src=$4
  for feed_file in feeds.conf feeds.conf.default; do
    if [ -f "$feed_file" ]; then
      sed -i "s#https://git.openwrt.org/feed/packages.git[^ ]*#$pkg_src#g" "$feed_file"
      sed -i "s#https://git.openwrt.org/project/luci.git[^ ]*#$luci_src#g" "$feed_file"
      sed -i "s#https://git.openwrt.org/feed/routing.git[^ ]*#$routing_src#g" "$feed_file"
      sed -i "s#https://git.openwrt.org/feed/telephony.git[^ ]*#$telephony_src#g" "$feed_file"
    fi
  done
}

rewrite_feeds "https://github.com/openwrt/packages.git;openwrt-24.10" \
              "https://github.com/openwrt/luci.git;openwrt-24.10" \
              "https://github.com/openwrt/routing.git;openwrt-24.10" \
              "https://github.com/openwrt/telephony.git;openwrt-24.10"

MTK_FEED_URL=${MTK_FEED_URL:-https://git01.mediatek.com/openwrt/mtk-openwrt-feeds.git}
MTK_FEED_BRANCH=${MTK_FEED_BRANCH:-openwrt-24.10}
if ! grep -qE "^src-git mtk " feeds.conf.default; then
  echo "src-git mtk ${MTK_FEED_URL};${MTK_FEED_BRANCH}" >> feeds.conf.default
fi

if ! ./scripts/feeds update -a; then
  echo "GitHub 镜像更新失败，尝试切换回官方源..."
  rewrite_feeds "https://git.openwrt.org/feed/packages.git;openwrt-24.10" \
                "https://git.openwrt.org/project/luci.git;openwrt-24.10" \
                "https://git.openwrt.org/feed/routing.git;openwrt-24.10" \
                "https://git.openwrt.org/feed/telephony.git;openwrt-24.10"
  ./scripts/feeds update -a
fi

./scripts/feeds install -a
./scripts/feeds install -a -p mtk -f || true

if [ -d "../bl-mt798x-dhcpd" ]; then
  echo "[BOOT] Found custom bootloader repo: bl-mt798x-dhcpd"

  if [ -d "../bl-mt798x-dhcpd/atf-20260123" ]; then
    rm -rf ./package/boot/arm-trusted-firmware-mediatek
    cp -rf ../bl-mt798x-dhcpd/atf-20260123 ./package/boot/arm-trusted-firmware-mediatek
    echo "[BOOT] Replaced ATF with bl-mt798x-dhcpd version"
  fi

  if [ -d "../bl-mt798x-dhcpd/uboot-mtk-20250711" ]; then
    rm -rf ./package/boot/uboot-mediatek
    cp -rf ../bl-mt798x-dhcpd/uboot-mtk-20250711 ./package/boot/uboot-mediatek
    echo "[BOOT] Replaced U-Boot with bl-mt798x-dhcpd version"
  fi

  if [ -n "${BPI_R4_GPT_LAYOUT:-}" ] && [ -f "../PATCH/gpt/$BPI_R4_GPT_LAYOUT" ]; then
    mkdir -p ./package/boot/arm-trusted-firmware-mediatek/src/gpt
    cp "../PATCH/gpt/$BPI_R4_GPT_LAYOUT" ./package/boot/arm-trusted-firmware-mediatek/src/gpt/
    echo "[GPT] Injected GPT layout: $BPI_R4_GPT_LAYOUT"
  elif [ -n "${BPI_R4_GPT_LAYOUT:-}" ]; then
    echo "[GPT] Requested GPT layout '$BPI_R4_GPT_LAYOUT' not found, skipping"
  else
    echo "[GPT] No GPT layout requested"
  fi
else
  echo "[BOOT] Custom bootloader repo not found, using default OpenWrt sources"
fi

sed -i 's,-SNAPSHOT,,g' include/version.mk
sed -i 's,-SNAPSHOT,,g' package/base-files/image-config.in
sed -i '/CONFIG_BUILDBOT/d' include/feeds.mk
sed -i 's/;)\s*\\/; \\/' include/feeds.mk
sed -i 's,CONFIG_WERROR=y,# CONFIG_WERROR is not set,g' target/linux/generic/config-6.6 || true

echo "[MINIMAL] Minimal package preparation complete."