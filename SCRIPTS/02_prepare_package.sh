#!/bin/bash
clear

### feeds 优化 ###
# 先尝试 GitHub 镜像，失败后回退到 git.openwrt.org
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

if ! ./scripts/feeds update -a; then
  echo "GitHub 镜像更新失败，尝试切换回官方源..."
  rewrite_feeds "https://git.openwrt.org/feed/packages.git;openwrt-24.10" \
                "https://git.openwrt.org/project/luci.git;openwrt-24.10" \
                "https://git.openwrt.org/feed/routing.git;openwrt-24.10" \
                "https://git.openwrt.org/feed/telephony.git;openwrt-24.10"
  ./scripts/feeds update -a
fi

if ! ./scripts/feeds install -a; then
  echo "Feeds 安装部分失败，请检查上游仓库状态。" >&2
fi

### 基础部分 ###
# 可选：接入 MediaTek 的 OpenWrt feeds 或本地 SDK
# 通过环境变量控制，不默认启用，以免影响现有构建：
# - USE_MTK_FEED=1                 启用在线 mtk feeds
#   MTK_FEED_URL=...               feeds 仓库地址（可选，留空用默认）
#   MTK_FEED_BRANCH=...            分支（可选，默认尝试与底座版本匹配）
# - MTK_SDK_TARBALL=/path/to.tgz   使用离线 SDK 包（可选）
if [ "1" = "1" ]; then  # [MODIFIED] Force enable MTK Feed
  echo "[MTK] 启用 MediaTek feeds 集成"
  MTK_FEED_URL=${MTK_FEED_URL:-https://git01.mediatek.com/openwrt/feeds/mtk-openwrt-feeds.git}
  # MediaTek feed 当前仅提供 master 分支，24.10 内容位于仓库内的 24.10/ 子目录。
  MTK_FEED_BRANCH=${MTK_FEED_BRANCH:-master}
  if ! grep -qE "^src-git mtk " feeds.conf.default; then
    echo "src-git mtk ${MTK_FEED_URL};${MTK_FEED_BRANCH}" >> feeds.conf.default
  fi
fi

if [ -n "${MTK_SDK_TARBALL:-}" ]; then
  echo "[MTK] 使用本地 SDK 包：${MTK_SDK_TARBALL}"
  mkdir -p ../mtk-sdk
  tar -xf "${MTK_SDK_TARBALL}" -C ../mtk-sdk || {
    echo "[MTK] 解压 SDK 失败" >&2; exit 2;
  }
  # 如果离线 SDK 中提供了 feeds 目录，作为本地 feed 接入
  if [ -d ../mtk-sdk/feeds ]; then
    if ! grep -qE "^src-link mtk-sdk " feeds.conf.default; then
      echo "src-link mtk-sdk ../mtk-sdk/feeds" >> feeds.conf.default
    fi
  fi
fi

### Custom Bootloader (Yuzhii0718) & GPT for A/B Partition ###
if [ -d "../bl-mt798x-dhcpd" ]; then
  echo "[BOOT] Found custom bootloader repo: bl-mt798x-dhcpd"
  
  # 1. Replace Arm Trusted Firmware (ATF)
  if [ -d "../bl-mt798x-dhcpd/atf-20260123" ]; then
    rm -rf ./package/boot/arm-trusted-firmware-mediatek
    cp -rf ../bl-mt798x-dhcpd/atf-20260123 ./package/boot/arm-trusted-firmware-mediatek
    echo "[BOOT] Replaced ATF with bl-mt798x-dhcpd version"
  fi
  
  # 2. Replace U-Boot
  if [ -d "../bl-mt798x-dhcpd/uboot-mtk-20250711" ]; then
    rm -rf ./package/boot/uboot-mediatek
    cp -rf ../bl-mt798x-dhcpd/uboot-mtk-20250711 ./package/boot/uboot-mediatek
    echo "[BOOT] Replaced U-Boot with bl-mt798x-dhcpd version"
  fi
  
  # 3. Inject media-specific GPT definitions for block-device targets when requested
  if [ -n "$BPI_R4_GPT_LAYOUT" ] && [ -f "../PATCH/gpt/$BPI_R4_GPT_LAYOUT" ]; then
    mkdir -p ./package/boot/arm-trusted-firmware-mediatek/src/gpt
    cp "../PATCH/gpt/$BPI_R4_GPT_LAYOUT" ./package/boot/arm-trusted-firmware-mediatek/src/gpt/
    echo "[GPT] Injected GPT layout: $BPI_R4_GPT_LAYOUT"
  elif [ -n "$BPI_R4_GPT_LAYOUT" ]; then
    echo "[GPT] Requested GPT layout '$BPI_R4_GPT_LAYOUT' not found, skipping"
  else
    echo "[GPT] No block-device GPT layout requested (expected for NAND / non-GPT targets)"
  fi

  else
    echo "[BOOT] Custom bootloader repo not found, using default OpenWrt sources"
  fi


### MTK WiFi Optimization (TX Power & Region Unlock) ###
# Unlock WiFi region restrictions and maximize TX power
if [ -d "../mtk-feed" ]; then
  echo "[WIFI] Applying TX power and region unlock for MTK WiFi..."
  
  # 1. Replace wireless-regdb patches in OpenWrt source
  rm -rf ./package/firmware/wireless-regdb/patches/*
  cp ../PATCH/kernel/mtk_wifi/500-tx_power.patch ./package/firmware/wireless-regdb/patches/ 2>/dev/null || true
  if [ -f "../PATCH/kernel/mtk_wifi/regdb.Makefile" ]; then
    cp ../PATCH/kernel/mtk_wifi/regdb.Makefile ./package/firmware/wireless-regdb/Makefile
  fi

  # 2. Also apply to MTK feed structure (it has its own copy)
  # MTK feed puts wireless-regdb patches in a specific location
  MTK_REGDB_PATH="../mtk-feed/autobuild/unified/filogic/mac80211/24.10/files/package/firmware/wireless-regdb/patches"
  if [ -d "$MTK_REGDB_PATH" ]; then
    rm -rf $MTK_REGDB_PATH/*
    cp ../PATCH/kernel/mtk_wifi/500-tx_power.patch $MTK_REGDB_PATH/ 2>/dev/null || true
  fi
fi

# 使用 O2 级别的优化
sed -i 's/Os/O2/g' include/target.mk
# 移除 SNAPSHOT 标签
sed -i 's,-SNAPSHOT,,g' include/version.mk
sed -i 's,-SNAPSHOT,,g' package/base-files/image-config.in
sed -i '/CONFIG_BUILDBOT/d' include/feeds.mk
sed -i 's/;)\s*\\/; \\/' include/feeds.mk
# Nginx
sed -i "s/large_client_header_buffers 2 1k/large_client_header_buffers 4 32k/g" feeds/packages/net/nginx-util/files/uci.conf.template
sed -i "s/client_max_body_size 128M/client_max_body_size 2048M/g" feeds/packages/net/nginx-util/files/uci.conf.template
sed -i '/client_max_body_size/a\\tclient_body_buffer_size 8192M;' feeds/packages/net/nginx-util/files/uci.conf.template
sed -i '/client_max_body_size/a\\tserver_names_hash_bucket_size 128;' feeds/packages/net/nginx-util/files/uci.conf.template
sed -i '/ubus_parallel_req/a\        ubus_script_timeout 600;' feeds/packages/net/nginx/files-luci-support/60_nginx-luci-support
sed -ri "/luci-webui.socket/i\ \t\tuwsgi_send_timeout 600\;\n\t\tuwsgi_connect_timeout 600\;\n\t\tuwsgi_read_timeout 600\;" feeds/packages/net/nginx/files-luci-support/luci.locations
sed -ri "/luci-cgi_io.socket/i\ \t\tuwsgi_send_timeout 600\;\n\t\tuwsgi_connect_timeout 600\;\n\t\tuwsgi_read_timeout 600\;" feeds/packages/net/nginx/files-luci-support/luci.locations
# uwsgi
sed -i 's,procd_set_param stderr 1,procd_set_param stderr 0,g' feeds/packages/net/uwsgi/files/uwsgi.init
sed -i 's,buffer-size = 10000,buffer-size = 131072,g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed -i 's,logger = luci,#logger = luci,g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed -i '$a cgi-timeout = 600' feeds/packages/net/uwsgi/files-luci-support/luci-*.ini
sed -i 's/threads = 1/threads = 2/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed -i 's/processes = 3/processes = 4/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed -i 's/cheaper = 1/cheaper = 2/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
# rpcd
sed -i 's/option timeout 30/option timeout 60/g' package/system/rpcd/files/rpcd.config
sed -i 's#20) \* 1000#60) \* 1000#g' feeds/luci/modules/luci-base/htdocs/luci-static/resources/rpc.js

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
sed -i '/PKG_INSTALL:=/iPKG_FIXUP:=autoreconf' package/libs/libnftnl/Makefile
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
