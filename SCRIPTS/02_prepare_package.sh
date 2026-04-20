#!/bin/bash
clear

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

configure_package_use_source_dir() {
  local pkg_dir=$1
  local source_dir_rel=$2
  local label=$3
  local makefile="$pkg_dir/Makefile"
  local temp_file

  if [ ! -d "$source_dir_rel" ] || [ ! -f "$makefile" ]; then
    return 1
  fi

  temp_file="$(mktemp)"
  awk -v source_dir="$source_dir_rel" '
    /^USE_SOURCE_DIR:=/ { next }
    /^include \$\(INCLUDE_DIR\)\/package\.mk/ && !inserted {
      print "USE_SOURCE_DIR:=$(TOPDIR)/" source_dir
      inserted=1
    }
    { print }
    END {
      if (!inserted) {
        print "USE_SOURCE_DIR:=$(TOPDIR)/" source_dir
      }
    }
  ' "$makefile" > "$temp_file"
  mv "$temp_file" "$makefile"
  echo "[BOOT] Configured $label wrapper to use local source dir $source_dir_rel"
}

patch_custom_atf_sdmmc_flags() {
  local bl2_mk=$1

  [ -f "$bl2_mk" ] || return 1

  perl -0pi -e 's/ifeq \(\$\(BOOT_DEVICE\),sdmmc\)\n\$\(eval \$\(call BL2_BOOT_SD\)\)\nBL2_SOURCES\t\t\+=\t\+\$\(MTK_PLAT_SOC\)\/bl2\/bl2_dev_mmc\.c\nDEFINES\t\t\t\+=\t-DMSDC_INDEX=1\nDTS_NAME\t\t:=\tmt7988\nendif # END OF BOOTDEVICE = sdmmc/ifeq (\$(BOOT_DEVICE),sdmmc)\n\$(eval \$(call BL2_BOOT_SD))\nBL2_SOURCES\t\t+=\t\$(MTK_PLAT_SOC)\/bl2\/bl2_dev_mmc.c\nBL2_CPPFLAGS\t\t+=\t-DMSDC_INDEX=1\nDTS_NAME\t\t:=\tmt7988\nendif # END OF BOOTDEVICE = sdmmc/s' "$bl2_mk"
  echo "[BOOT] Patched custom ATF sdmmc flags in $(basename "$bl2_mk")"
}

ensure_file_has_line() {
  local file_path=$1
  local line=$2
  local label=$3

  [ -f "$file_path" ] || return 1
  grep -Fqx "$line" "$file_path" || printf '%s\n' "$line" >> "$file_path"
  echo "$label Ensured $(basename "$file_path") contains: $line"
}

fix_tfa_ldflags_compat() {
  local tfa_include=./include/trusted-firmware-a.mk

  [ -f "$tfa_include" ] || return 1

  perl -0pi -e 's/LDFLAGS="-no-warn-rwx-segments"/LDFLAGS="-Wl,--no-warn-rwx-segments"/g' "$tfa_include"
  echo "[BOOT] Patched trusted-firmware-a LDFLAGS compatibility in $(basename "$tfa_include")"
}

### feeds 优化 ###
# 先尝试 GitHub 镜像，失败后回退到 git.openwrt.org
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

disable_mtk_feed() {
  for feed_file in feeds.conf feeds.conf.default; do
    if [ -f "$feed_file" ]; then
      sed_in_place '/^src-\(git\|link\)\(-full\)\? mtk /d' "$feed_file"
    fi
  done

  rm -rf ./feeds/mtk ./feeds/mtk.index
}

mtk_feed_source_dir="./.mtk-feed-source"
mtk_feed_mode="${MTK_FEED_MODE:-auto}"
mtk_feed_branch="${MTK_FEED_BRANCH:-master}"
mtk_feed_version_dir="${MTK_FEED_VERSION_DIR:-24.10}"
mtk_feed_official_url="${MTK_FEED_OFFICIAL_URL:-https://git01.mediatek.com/openwrt/feeds/mtk-openwrt-feeds.git}"
mtk_feed_mirror_url="${MTK_FEED_MIRROR_URL:-https://tea.saymi-labs.top/Learning/mtk-openwrt-feeds}"
mtk_feed_mapping_url="${MTK_FEED_MAPPING_URL:-https://raw.githubusercontent.com/GainStrongService/mtk-openwrt-feeds/master/mtk-openwrt-feeds-commit-sha-mapping-table.md}"
mtk_feed_apply_patches="${MTK_FEED_APPLY_PATCHES:-0}"

configure_mtk_feed_link() {
  local abs_source_dir
  abs_source_dir="$(cd "$mtk_feed_source_dir" && pwd -P)"

  for feed_file in feeds.conf feeds.conf.default; do
    if [ -f "$feed_file" ]; then
      sed_in_place '/^src-\(git\|link\)\(-full\)\? mtk /d' "$feed_file"
      printf 'src-link mtk %s\n' "$abs_source_dir" >> "$feed_file"
    fi
  done
}

resolve_mtk_official_head() {
  git ls-remote "$mtk_feed_official_url" "refs/heads/$mtk_feed_branch" | awk 'NR==1 {print $1}'
}

resolve_mtk_mirror_full_sha() {
  local official_sha=$1
  local official_short mirror_short

  official_short="${official_sha:0:8}"
  mirror_short="$(
    curl -fsSL "$mtk_feed_mapping_url" | awk -F'|' -v sha="$official_short" '
      function trim(s) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
        return s
      }
      trim($2) == sha {
        print trim($3)
        exit
      }
    '
  )"

  if [ -z "$mirror_short" ]; then
    return 1
  fi

  curl -fsSL \
    -H 'Accept: application/vnd.github+json' \
    -H 'User-Agent: yaof-bpi-r4-ci' \
    "https://api.github.com/repos/GainStrongService/mtk-openwrt-feeds/commits/$mirror_short" \
    | jq -r '.sha // empty'
}

checkout_mtk_mirror_commit() {
  local target_sha=$1

  rm -rf "$mtk_feed_source_dir"
  git init "$mtk_feed_source_dir" >/dev/null 2>&1
  git -C "$mtk_feed_source_dir" remote add origin "$mtk_feed_mirror_url"
  git -C "$mtk_feed_source_dir" fetch --depth 1 origin "$target_sha" >/dev/null 2>&1
  git -C "$mtk_feed_source_dir" checkout --detach FETCH_HEAD >/dev/null 2>&1
}

prepare_mtk_feed_source() {
  local official_head mirror_sha

  case "$mtk_feed_mode" in
    disabled)
      echo "[MTK] Feed disabled"
      disable_mtk_feed
      return 0
      ;;
    official)
      echo "[MTK] Using official feed: $mtk_feed_official_url@$mtk_feed_branch"
      rm -rf "$mtk_feed_source_dir"
      git clone --depth 1 -b "$mtk_feed_branch" "$mtk_feed_official_url" "$mtk_feed_source_dir"
      ;;
    auto|mirror)
      if [ "$mtk_feed_mode" = "auto" ]; then
        echo "[MTK] Trying official feed: $mtk_feed_official_url@$mtk_feed_branch"
        rm -rf "$mtk_feed_source_dir"
        if git clone --depth 1 -b "$mtk_feed_branch" "$mtk_feed_official_url" "$mtk_feed_source_dir"; then
          echo "[MTK] Official feed clone succeeded"
          configure_mtk_feed_link
          return 0
        fi
        echo "[MTK] Official feed clone failed; falling back to mirror"
      else
        rm -rf "$mtk_feed_source_dir"
      fi

      official_head="$(resolve_mtk_official_head)"
      if [ -z "$official_head" ]; then
        echo "[MTK] Unable to resolve official head from $mtk_feed_official_url@$mtk_feed_branch" >&2
        return 1
      fi
      echo "[MTK] Official head is $official_head"

      if checkout_mtk_mirror_commit "$official_head"; then
        echo "[MTK] Mirror contains matching commit $official_head"
      else
        mirror_sha="$(resolve_mtk_mirror_full_sha "$official_head")"
        if [ -z "$mirror_sha" ]; then
          echo "[MTK] Unable to map official commit $official_head to mirror commit" >&2
          return 1
        fi
        checkout_mtk_mirror_commit "$mirror_sha"
        echo "[MTK] Mirror fallback commit is $mirror_sha"
      fi
      ;;
    *)
      echo "[MTK] Unsupported MTK_FEED_MODE: $mtk_feed_mode" >&2
      return 1
      ;;
  esac

  configure_mtk_feed_link
}

apply_mtk_feed_overlay() {
  local overlay_dir="./feeds/mtk/$mtk_feed_version_dir"
  local patch_dir patch_file

  if [ ! -d "$overlay_dir" ]; then
    echo "[MTK] Overlay directory $overlay_dir not found" >&2
    return 1
  fi

  if [ -d "$overlay_dir/files" ]; then
    echo "[MTK] Applying files overlay from $overlay_dir/files"
    cp -af "$overlay_dir/files/." .
  fi

  if [ "$mtk_feed_apply_patches" != "1" ]; then
    echo "[MTK] Skipping overlay patches from $overlay_dir (set MTK_FEED_APPLY_PATCHES=1 to enable)"
    return 0
  fi

  for patch_dir in patches-base patches-feeds; do
    if [ ! -d "$overlay_dir/$patch_dir" ]; then
      continue
    fi

    while IFS= read -r patch_file; do
      [ -n "$patch_file" ] || continue
      echo "[MTK] Applying patch $patch_file"
      patch -f -p1 -i "$patch_file"
    done <<EOF
$(find "$overlay_dir/$patch_dir" -type f -name '*.patch' | sort)
EOF
  done
}

rewrite_feeds "https://github.com/openwrt/packages.git;openwrt-24.10" \
              "https://github.com/openwrt/luci.git;openwrt-24.10" \
              "https://github.com/openwrt/routing.git;openwrt-24.10" \
              "https://github.com/openwrt/telephony.git;openwrt-24.10"
disable_mtk_feed

if ! ./scripts/feeds update -a; then
  echo "GitHub 镜像更新失败，尝试切换回官方源..."
  rewrite_feeds "https://git.openwrt.org/feed/packages.git;openwrt-24.10" \
                "https://git.openwrt.org/project/luci.git;openwrt-24.10" \
                "https://git.openwrt.org/feed/routing.git;openwrt-24.10" \
                "https://git.openwrt.org/feed/telephony.git;openwrt-24.10"
  disable_mtk_feed
  ./scripts/feeds update -a
fi

### 基础部分 ###
prepare_mtk_feed_source

if [ "$mtk_feed_mode" != "disabled" ]; then
  ./scripts/feeds update mtk
  apply_mtk_feed_overlay
fi

ensure_file_has_line \
  "./target/linux/mediatek/filogic/config-6.6" \
  "# CONFIG_USB_XHCI_MTK_DEBUGFS is not set" \
  "[KERNEL]"

fix_tfa_ldflags_compat

if ! ./scripts/feeds install -a; then
  echo "Feeds 安装部分失败，请检查上游仓库状态。" >&2
fi

### Custom Bootloader (Yuzhii0718) & GPT for A/B Partition ###
restore_openwrt_boot_package arm-trusted-firmware-mediatek || true
restore_openwrt_boot_package uboot-mediatek || true

if [ -d "../bl-mt798x-dhcpd" ]; then
  echo "[BOOT] Found custom bootloader repo: bl-mt798x-dhcpd"
  atf_custom_applied=0

  # 1. Replace Arm Trusted Firmware (ATF)
  if replace_with_custom_package_wrapper \
    "../bl-mt798x-dhcpd/atf-20260123" \
    "./package/boot/arm-trusted-firmware-mediatek" \
    "ATF"; then
    atf_custom_applied=1
  elif configure_package_use_source_dir \
    "./package/boot/arm-trusted-firmware-mediatek" \
    "../bl-mt798x-dhcpd/atf-20260123" \
    "ATF"; then
    atf_custom_applied=1
  fi

  # 2. Replace U-Boot
  replace_with_custom_package_wrapper \
    "../bl-mt798x-dhcpd/uboot-mtk-20250711" \
    "./package/boot/uboot-mediatek" \
    "U-Boot" || configure_package_use_source_dir \
    "./package/boot/uboot-mediatek" \
    "../bl-mt798x-dhcpd/uboot-mtk-20250711" \
    "U-Boot" || true

  # 3. Inject media-specific GPT definitions for block-device targets when requested
  if [ "$atf_custom_applied" -eq 1 ] && [ -n "$BPI_R4_GPT_LAYOUT" ] && [ -f "../PATCH/gpt/$BPI_R4_GPT_LAYOUT" ]; then
    mkdir -p ../bl-mt798x-dhcpd/atf-20260123/src/gpt
    cp "../PATCH/gpt/$BPI_R4_GPT_LAYOUT" ../bl-mt798x-dhcpd/atf-20260123/src/gpt/
    echo "[GPT] Injected GPT layout: $BPI_R4_GPT_LAYOUT"
  elif [ -n "$BPI_R4_GPT_LAYOUT" ] && [ "$atf_custom_applied" -ne 1 ]; then
    echo "[GPT] Skipping GPT layout injection because no custom ATF source was applied"
  elif [ -n "$BPI_R4_GPT_LAYOUT" ]; then
    echo "[GPT] Requested GPT layout '$BPI_R4_GPT_LAYOUT' not found, skipping"
  else
    echo "[GPT] No block-device GPT layout requested (expected for NAND / non-GPT targets)"
  fi

  if [ "$atf_custom_applied" -eq 1 ]; then
    patch_custom_atf_sdmmc_flags "../bl-mt798x-dhcpd/atf-20260123/plat/mediatek/mt7988/bl2/bl2.mk" || true
  fi

  else
    echo "[BOOT] Custom bootloader repo not found, using default OpenWrt sources"
  fi


### WiFi regdb Optimization (OpenWrt tree only) ###
# MTK feed preparation is handled earlier; keep the remaining tree tweaks local here.
rm -rf ./package/firmware/wireless-regdb/patches/*
cp ../PATCH/kernel/mtk_wifi/500-tx_power.patch ./package/firmware/wireless-regdb/patches/ 2>/dev/null || true
if [ -f "../PATCH/kernel/mtk_wifi/regdb.Makefile" ]; then
  cp ../PATCH/kernel/mtk_wifi/regdb.Makefile ./package/firmware/wireless-regdb/Makefile
fi

# 使用 O2 级别的优化
sed_in_place 's/Os/O2/g' include/target.mk
# 移除 SNAPSHOT 标签
sed_in_place 's,-SNAPSHOT,,g' include/version.mk
sed_in_place 's,-SNAPSHOT,,g' package/base-files/image-config.in
sed_in_place '/CONFIG_BUILDBOT/d' include/feeds.mk
sed_in_place 's/;)\s*\\/; \\/' include/feeds.mk
# Nginx
sed_in_place "s/large_client_header_buffers 2 1k/large_client_header_buffers 4 32k/g" feeds/packages/net/nginx-util/files/uci.conf.template
sed_in_place "s/client_max_body_size 128M/client_max_body_size 2048M/g" feeds/packages/net/nginx-util/files/uci.conf.template
sed_in_place '/client_max_body_size/a\\tclient_body_buffer_size 8192M;' feeds/packages/net/nginx-util/files/uci.conf.template
sed_in_place '/client_max_body_size/a\\tserver_names_hash_bucket_size 128;' feeds/packages/net/nginx-util/files/uci.conf.template
sed_in_place '/ubus_parallel_req/a\        ubus_script_timeout 600;' feeds/packages/net/nginx/files-luci-support/60_nginx-luci-support
sed_in_place -E "/luci-webui.socket/i\\
\t\tuwsgi_send_timeout 600;\\
\t\tuwsgi_connect_timeout 600;\\
\t\tuwsgi_read_timeout 600;" feeds/packages/net/nginx/files-luci-support/luci.locations
sed_in_place -E "/luci-cgi_io.socket/i\\
\t\tuwsgi_send_timeout 600;\\
\t\tuwsgi_connect_timeout 600;\\
\t\tuwsgi_read_timeout 600;" feeds/packages/net/nginx/files-luci-support/luci.locations
# uwsgi
sed_in_place 's,procd_set_param stderr 1,procd_set_param stderr 0,g' feeds/packages/net/uwsgi/files/uwsgi.init
sed_in_place 's,buffer-size = 10000,buffer-size = 131072,g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed_in_place 's,logger = luci,#logger = luci,g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed_in_place '$a cgi-timeout = 600' feeds/packages/net/uwsgi/files-luci-support/luci-*.ini
sed_in_place 's/threads = 1/threads = 2/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed_in_place 's/processes = 3/processes = 4/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed_in_place 's/cheaper = 1/cheaper = 2/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
# rpcd
sed_in_place 's/option timeout 30/option timeout 60/g' package/system/rpcd/files/rpcd.config
sed_in_place 's#20) \* 1000#60) \* 1000#g' feeds/luci/modules/luci-base/htdocs/luci-static/resources/rpc.js

### FW4 ###
rm -rf ./package/network/config/firewall4
cp -rf ../openwrt_ma/package/network/config/firewall4 ./package/network/config/firewall4

### 必要的 Patches ###
# TCP optimizations
cp -rf ../PATCH/kernel/6.7_Boost_For_Single_TCP_Flow/* ./target/linux/generic/backport-6.6/
cp -rf ../PATCH/kernel/6.8_Boost_TCP_Performance_For_Many_Concurrent_Connections-bp_but_put_in_hack/* ./target/linux/generic/hack-6.6/
cp -rf ../PATCH/kernel/6.8_Better_data_locality_in_networking_fast_paths-bp_but_put_in_hack/* ./target/linux/generic/hack-6.6/
# UDP optimizations
cp -rf ../PATCH/kernel/6.7_FQ_packet_scheduling/* ./target/linux/generic/backport-6.6/
# Patch arm64 型号名称
cp -rf ../PATCH/kernel/arm/* ./target/linux/generic/hack-6.6/
# BBRv3
cp -rf ../PATCH/kernel/bbr3/* ./target/linux/generic/backport-6.6/
# LRNG
cp -rf ../PATCH/kernel/lrng/* ./target/linux/generic/hack-6.6/
echo '
# CONFIG_RANDOM_DEFAULT_IMPL is not set
CONFIG_LRNG=y
CONFIG_LRNG_DEV_IF=y
# CONFIG_LRNG_IRQ is not set
CONFIG_LRNG_JENT=y
CONFIG_LRNG_CPU=y
# CONFIG_LRNG_SCHED is not set
CONFIG_LRNG_SELFTEST=y
# CONFIG_LRNG_SELFTEST_PANIC is not set
' >>./target/linux/generic/config-6.6
# wg
cp -rf ../PATCH/kernel/wg/* ./target/linux/generic/hack-6.6/
# dont wrongly interpret first-time data
echo "net.netfilter.nf_conntrack_tcp_max_retrans=5" >>./package/kernel/linux/files/sysctl-nf-conntrack.conf
# OTHERS
cp -rf ../PATCH/kernel/others/* ./target/linux/generic/pending-6.6/
rm -f ./target/linux/generic/pending-6.6/1007-wozi-arch-arm64-dts-mt7988a-add-thermal-zone.patch
python3 - <<'PY'
from pathlib import Path
path = Path('./target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek/mt7988a.dtsi')
text = path.read_text()
old = '\t\t\tstatus = "disabled";\n'
if old not in text:
    raise SystemExit(f'mt7988a thermal status line not found in {path}')
path.write_text(text.replace(old, '', 1))
PY
# 6.17_ppp_performance
wget https://github.com/torvalds/linux/commit/95d0d094.patch -O target/linux/generic/pending-6.6/999-1-95d0d09.patch
wget https://github.com/torvalds/linux/commit/1a3e9b7a.patch -O target/linux/generic/pending-6.6/999-2-1a3e9b7.patch
wget https://github.com/torvalds/linux/commit/7eebd219.patch -O target/linux/generic/pending-6.6/999-3-7eebd21.patch
# ppp_fix
wget -qO - https://github.com/immortalwrt/immortalwrt/commit/9d852a0.patch | patch -p1

### Fullcone-NAT 部分 ###
# bcmfullcone
cp -rf ../PATCH/kernel/bcmfullcone/* ./target/linux/generic/hack-6.6/
# set nf_conntrack_expect_max for fullcone
wget -qO - https://github.com/openwrt/openwrt/commit/bbf39d07.patch | patch -p1
echo "net.netfilter.nf_conntrack_helper = 1" >>./package/kernel/linux/files/sysctl-nf-conntrack.conf
# FW4
mkdir -p package/network/config/firewall4/patches
#cp -f ../PATCH/pkgs/firewall/firewall4_patches/*.patch ./package/network/config/firewall4/patches/
mkdir -p package/libs/libnftnl/patches
cp -f ../PATCH/pkgs/firewall/libnftnl/*.patch ./package/libs/libnftnl/patches/
sed_in_place '/PKG_INSTALL:=/iPKG_FIXUP:=autoreconf' package/libs/libnftnl/Makefile
mkdir -p package/network/utils/nftables/patches
cp -f ../PATCH/pkgs/firewall/nftables/*.patch ./package/network/utils/nftables/patches/
# Patch LuCI 以增添 FullCone 开关
pushd feeds/luci
patch -p1 <../../../PATCH/pkgs/firewall/luci/0001-luci-app-firewall-add-nft-fullcone-and-bcm-fullcone-.patch
popd

### Shortcut-FE 部分 ###
# Patch Kernel 以支持 Shortcut-FE
cp -rf ../PATCH/kernel/sfe/* ./target/linux/generic/hack-6.6/
cp -rf ../lede/target/linux/generic/pending-6.6/613-netfilter_optional_tcp_window_check.patch ./target/linux/generic/pending-6.6/613-netfilter_optional_tcp_window_check.patch
# Patch LuCI 以增添 Shortcut-FE 开关
pushd feeds/luci
patch -p1 <../../../PATCH/pkgs/firewall/luci/0002-luci-app-firewall-add-shortcut-fe-option.patch
popd

### NAT6 部分 ###
# custom nft command
patch -p1 < ../PATCH/pkgs/firewall/100-openwrt-firewall4-add-custom-nft-command-support.patch
cp -f ../PATCH/pkgs/firewall/firewall4_patches/*.patch ./package/network/config/firewall4/patches/
# Patch LuCI 以增添 NAT6 开关
pushd feeds/luci
patch -p1 <../../../PATCH/pkgs/firewall/luci/0003-luci-app-firewall-add-ipv6-nat-option.patch
popd
# Patch LuCI 以支持自定义 nft 规则
pushd feeds/luci
patch -p1 <../../../PATCH/pkgs/firewall/luci/0004-luci-add-firewall-add-custom-nft-rule-support.patch
popd

### natflow 部分 ###
pushd feeds/luci
patch -p1 <../../../PATCH/pkgs/firewall/luci/0005-luci-app-firewall-add-natflow-offload-support.patch
popd

### fullcone6 ###
pushd feeds/luci
patch -p1 <../../../PATCH/pkgs/firewall/luci/0007-luci-app-firewall-add-fullcone6-option-for-nftables-.patch
popd

### Other Kernel Hack 部分 ###
# make olddefconfig
wget -qO - https://github.com/openwrt/openwrt/commit/c21a3570.patch | patch -p1
# igc-fix
cp -rf ../lede/target/linux/x86/patches-6.6/996-intel-igc-i225-i226-disable-eee.patch ./target/linux/x86/patches-6.6/996-intel-igc-i225-i226-disable-eee.patch
# btf
cp -rf ../PATCH/kernel/btf/* ./target/linux/generic/hack-6.6/

### ADD PKG 部分 ###
cp -rf ../OpenWrt-Add ./package/new
rm -rf feeds/packages/net/{xray-core,v2ray-core,v2ray-geodata,sing-box,frp,microsocks,shadowsocks-libev,zerotier,daed}
rm -rf feeds/luci/applications/{luci-app-frps,luci-app-frpc,luci-app-zerotier,luci-app-filemanager}
rm -rf feeds/packages/utils/coremark

### 获取额外的 LuCI 应用、主题和依赖 ###
# 更换 Nodejs 版本
rm -rf ./feeds/packages/lang/node
rm -rf ./package/new/feeds_packages_lang_node-prebuilt
cp -rf ../OpenWrt-Add/feeds_packages_lang_node-prebuilt ./feeds/packages/lang/node
# 更换 golang 版本
rm -rf ./feeds/packages/lang/golang
cp -rf ../lede_pkg_ma/lang/golang ./feeds/packages/lang/golang
# rust
wget https://github.com/rust-lang/rust/commit/e8d97f0.patch -O feeds/packages/lang/rust/patches/e8d97f0.patch
# mount cgroupv2
pushd feeds/packages
patch -p1 <../../../PATCH/pkgs/cgroupfs-mount/0001-fix-cgroupfs-mount.patch
popd
mkdir -p feeds/packages/utils/cgroupfs-mount/patches
cp -rf ../PATCH/pkgs/cgroupfs-mount/900-mount-cgroup-v2-hierarchy-to-sys-fs-cgroup-cgroup2.patch ./feeds/packages/utils/cgroupfs-mount/patches/
cp -rf ../PATCH/pkgs/cgroupfs-mount/901-fix-cgroupfs-umount.patch ./feeds/packages/utils/cgroupfs-mount/patches/
cp -rf ../PATCH/pkgs/cgroupfs-mount/902-mount-sys-fs-cgroup-systemd-for-docker-systemd-suppo.patch ./feeds/packages/utils/cgroupfs-mount/patches/
# fstool
wget -qO - https://github.com/coolsnowwolf/lede/commit/8a4db76.patch | patch -p1
# Boost 通用即插即用
rm -rf ./feeds/packages/net/miniupnpd
cp -rf ../openwrt_pkg_ma/net/miniupnpd ./feeds/packages/net/miniupnpd
wget https://github.com/miniupnp/miniupnp/commit/0e8c68d.patch -O feeds/packages/net/miniupnpd/patches/0e8c68d.patch
sed -i 's,/miniupnpd/,/,g' ./feeds/packages/net/miniupnpd/patches/0e8c68d.patch
wget https://github.com/miniupnp/miniupnp/commit/21541fc.patch -O feeds/packages/net/miniupnpd/patches/21541fc.patch
sed -i 's,/miniupnpd/,/,g' ./feeds/packages/net/miniupnpd/patches/21541fc.patch
wget https://github.com/miniupnp/miniupnp/commit/b78a363.patch -O feeds/packages/net/miniupnpd/patches/b78a363.patch
sed -i 's,/miniupnpd/,/,g' ./feeds/packages/net/miniupnpd/patches/b78a363.patch
wget https://github.com/miniupnp/miniupnp/commit/8f2f392.patch -O feeds/packages/net/miniupnpd/patches/8f2f392.patch
sed -i 's,/miniupnpd/,/,g' ./feeds/packages/net/miniupnpd/patches/8f2f392.patch
wget https://github.com/miniupnp/miniupnp/commit/60f5705.patch -O feeds/packages/net/miniupnpd/patches/60f5705.patch
sed -i 's,/miniupnpd/,/,g' ./feeds/packages/net/miniupnpd/patches/60f5705.patch
wget https://github.com/miniupnp/miniupnp/commit/3f3582b.patch -O feeds/packages/net/miniupnpd/patches/3f3582b.patch
sed -i 's,/miniupnpd/,/,g' ./feeds/packages/net/miniupnpd/patches/3f3582b.patch
cp -rf ../PATCH/pkgs/miniupnpd/301-options-force_forwarding-support.patch ./feeds/packages/net/miniupnpd/patches/
pushd feeds/packages
patch -p1 <../../../PATCH/pkgs/miniupnpd/01-set-presentation_url.patch
patch -p1 <../../../PATCH/pkgs/miniupnpd/02-force_forwarding.patch
popd
pushd feeds/luci
patch -p1 <../../../PATCH/pkgs/miniupnpd/luci-upnp-support-force_forwarding-flag.patch
popd
# 动态DNS
sed -i '/boot()/,+2d' feeds/packages/net/ddns-scripts/files/etc/init.d/ddns
# Docker 容器
rm -rf ./feeds/luci/applications/luci-app-dockerman
cp -rf ../dockerman/applications/luci-app-dockerman ./feeds/luci/applications/luci-app-dockerman
sed -i '/auto_start/d' feeds/luci/applications/luci-app-dockerman/root/etc/uci-defaults/luci-app-dockerman
pushd feeds/packages
wget -qO- https://github.com/openwrt/packages/commit/e2e5ee69.patch | patch -p1
wget -qO- https://github.com/openwrt/packages/pull/20054.patch | patch -p1
popd
sed -i '/sysctl.d/d' feeds/packages/utils/dockerd/Makefile
rm -rf ./feeds/luci/collections/luci-lib-docker
cp -rf ../docker_lib/collections/luci-lib-docker ./feeds/luci/collections/luci-lib-docker
# IPv6 兼容助手
patch -p1 <../PATCH/pkgs/odhcp6c/1002-odhcp6c-support-dhcpv6-hotplug.patch
# ODHCPD
rm -rf ./package/network/services/odhcpd
cp -rf ../openwrt_ma/package/network/services/odhcpd ./package/network/services/odhcpd
rm -rf ./package/network/ipv6/odhcp6c
cp -rf ../openwrt_ma/package/network/ipv6/odhcp6c ./package/network/ipv6/odhcp6c
# watchcat
echo > ./feeds/packages/utils/watchcat/files/watchcat.config
# 默认开启 Irqbalance
#sed -i "s/enabled '0'/enabled '1'/g" feeds/packages/utils/irqbalance/files/irqbalance.config

# 使用 TEO CPU 空闲调度器
KERNEL_VERSION="6.6"
CONFIG_CONTENT='
CONFIG_CPU_IDLE_GOV_MENU=n
CONFIG_CPU_IDLE_GOV_TEO=y
'
# 查找所有与内核 6.6 相关的配置文件并将这些配置项追加到文件末尾
find ./target/linux/ -name "config-${KERNEL_VERSION}" | xargs -I{} sh -c "echo '$CONFIG_CONTENT' | tee -a {} > /dev/null"

### 最后的收尾工作 ###
# Lets Fuck
mkdir -p package/base-files/files/usr/bin
cp -rf ../OpenWrt-Add/fuck ./package/base-files/files/usr/bin/fuck
# 生成默认配置及缓存
rm -rf .config
sed -i 's,CONFIG_WERROR=y,# CONFIG_WERROR is not set,g' target/linux/generic/config-6.6

#exit 0
