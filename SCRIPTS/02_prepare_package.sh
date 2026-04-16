     1|#!/bin/bash
     2|clear
     3|
     4|### feeds 优化 ###
     5|# 先尝试 GitHub 镜像，失败后回退到 git.openwrt.org
     6|rewrite_feeds() {
     7|  local pkg_src=$1
     8|  local luci_src=$2
     9|  local routing_src=$3
    10|  local telephony_src=$4
    11|  for feed_file in feeds.conf feeds.conf.default; do
    12|    if [ -f "$feed_file" ]; then
    13|      sed -i "s#https://git.openwrt.org/feed/packages.git[^ ]*#$pkg_src#g" "$feed_file"
    14|      sed -i "s#https://git.openwrt.org/project/luci.git[^ ]*#$luci_src#g" "$feed_file"
    15|      sed -i "s#https://git.openwrt.org/feed/routing.git[^ ]*#$routing_src#g" "$feed_file"
    16|      sed -i "s#https://git.openwrt.org/feed/telephony.git[^ ]*#$telephony_src#g" "$feed_file"
    17|    fi
    18|  done
    19|}
    20|
    21|rewrite_feeds "https://github.com/openwrt/packages.git;openwrt-24.10" \
    22|              "https://github.com/openwrt/luci.git;openwrt-24.10" \
    23|              "https://github.com/openwrt/routing.git;openwrt-24.10" \
    24|              "https://github.com/openwrt/telephony.git;openwrt-24.10"
    25|
    26|if ! ./scripts/feeds update -a; then
    27|  echo "GitHub 镜像更新失败，尝试切换回官方源..."
    28|  rewrite_feeds "https://git.openwrt.org/feed/packages.git;openwrt-24.10" \
    29|                "https://git.openwrt.org/project/luci.git;openwrt-24.10" \
    30|                "https://git.openwrt.org/feed/routing.git;openwrt-24.10" \
    31|                "https://git.openwrt.org/feed/telephony.git;openwrt-24.10"
    32|  ./scripts/feeds update -a
    33|fi
    34|
    35|if ! ./scripts/feeds install -a; then
    36|  echo "Feeds 安装部分失败，请检查上游仓库状态。" >&2
    37|fi
    38|
    39|### 基础部分 ###
    40|# 可选：接入 MediaTek 的 OpenWrt feeds 或本地 SDK
    41|# 通过环境变量控制，不默认启用，以免影响现有构建：
    42|# - USE_MTK_FEED=1                 启用在线 mtk feeds
    43|#   MTK_FEED_URL=...               feeds 仓库地址（可选，留空用默认）
    44|#   MTK_FEED_BRANCH=...            分支（可选，默认尝试与底座版本匹配）
    45|# - MTK_SDK_TARBALL=/path/to.tgz   使用离线 SDK 包（可选）
    46|if [ "1" = "1" ]; then  # [MODIFIED] Force enable MTK Feed
    47|  echo "[MTK] 启用 MediaTek feeds 集成"
    48|  MTK_FEED_URL=${MTK_FEED_URL:-https://git01.mediatek.com/openwrt/mtk-openwrt-feeds.git}
    49|  # 优先尝试与 openwrt-24.10 对齐；如需其他版本，请在 CI 变量中覆盖
    50|  MTK_FEED_BRANCH=${MTK_FEED_BRANCH:-openwrt-24.10}
    51|  if ! grep -qE "^src-git mtk " feeds.conf.default; then
    52|    echo "src-git mtk ${MTK_FEED_URL};${MTK_FEED_BRANCH}" >> feeds.conf.default
    53|  fi
    54|fi
    55|
    56|if [ -n "${MTK_SDK_TARBALL:-}" ]; then
    57|  echo "[MTK] 使用本地 SDK 包：${MTK_SDK_TARBALL}"
    58|  mkdir -p ../mtk-sdk
    59|  tar -xf "${MTK_SDK_TARBALL}" -C ../mtk-sdk || {
    60|    echo "[MTK] 解压 SDK 失败" >&2; exit 2;
    61|  }
    62|  # 如果离线 SDK 中提供了 feeds 目录，作为本地 feed 接入
    63|  if [ -d ../mtk-sdk/feeds ]; then
    64|    if ! grep -qE "^src-link mtk-sdk " feeds.conf.default; then
    65|      echo "src-link mtk-sdk ../mtk-sdk/feeds" >> feeds.conf.default
    66|    fi
    67|  fi
    68|fi
    69|
    70|### Custom Bootloader (Yuzhii0718) & GPT for A/B Partition ###
    71|if [ -d "../bl-mt798x-dhcpd" ]; then
    72|  echo "[BOOT] Found custom bootloader repo: bl-mt798x-dhcpd"
    73|  
    74|  # 1. Replace Arm Trusted Firmware (ATF)
    75|  if [ -d "../bl-mt798x-dhcpd/atf-20260123" ]; then
    76|    rm -rf ./package/boot/arm-trusted-firmware-mediatek
    77|    cp -rf ../bl-mt798x-dhcpd/atf-20260123 ./package/boot/arm-trusted-firmware-mediatek
    78|    echo "[BOOT] Replaced ATF with bl-mt798x-dhcpd version"
    79|  fi
    80|  
    81|  # 2. Replace U-Boot
    82|  if [ -d "../bl-mt798x-dhcpd/uboot-mtk-20250711" ]; then
    83|    rm -rf ./package/boot/uboot-mediatek
    84|    cp -rf ../bl-mt798x-dhcpd/uboot-mtk-20250711 ./package/boot/uboot-mediatek
    85|    echo "[BOOT] Replaced U-Boot with bl-mt798x-dhcpd version"
    86|  fi
    87|  
  # 3. Inject media-specific GPT definitions for A/B testing on block devices
  if [ -d "../PATCH/gpt" ]; then
    mkdir -p ./package/boot/arm-trusted-firmware-mediatek/src/gpt
    cp ../PATCH/gpt/*.json ./package/boot/arm-trusted-firmware-mediatek/src/gpt/ 2>/dev/null || true
    echo "[GPT] Injected media-specific GPT layouts from PATCH/gpt"
  fi

  else
    echo "[BOOT] Custom bootloader repo not found, using default OpenWrt sources"
  fi
    97|
    98|
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
    99|sed -i 's/Os/O2/g' include/target.mk
   100|# 移除 SNAPSHOT 标签
   101|sed -i 's,-SNAPSHOT,,g' include/version.mk
   102|sed -i 's,-SNAPSHOT,,g' package/base-files/image-config.in
   103|sed -i '/CONFIG_BUILDBOT/d' include/feeds.mk
   104|sed -i 's/;)\s*\\/; \\/' include/feeds.mk
   105|# Nginx
   106|sed -i "s/large_client_header_buffers 2 1k/large_client_header_buffers 4 32k/g" feeds/packages/net/nginx-util/files/uci.conf.template
   107|sed -i "s/client_max_body_size 128M/client_max_body_size 2048M/g" feeds/packages/net/nginx-util/files/uci.conf.template
   108|sed -i '/client_max_body_size/a\\tclient_body_buffer_size 8192M;' feeds/packages/net/nginx-util/files/uci.conf.template
   109|sed -i '/client_max_body_size/a\\tserver_names_hash_bucket_size 128;' feeds/packages/net/nginx-util/files/uci.conf.template
   110|sed -i '/ubus_parallel_req/a\        ubus_script_timeout 600;' feeds/packages/net/nginx/files-luci-support/60_nginx-luci-support
   111|sed -ri "/luci-webui.socket/i\ \t\tuwsgi_send_timeout 600\;\n\t\tuwsgi_connect_timeout 600\;\n\t\tuwsgi_read_timeout 600\;" feeds/packages/net/nginx/files-luci-support/luci.locations
   112|sed -ri "/luci-cgi_io.socket/i\ \t\tuwsgi_send_timeout 600\;\n\t\tuwsgi_connect_timeout 600\;\n\t\tuwsgi_read_timeout 600\;" feeds/packages/net/nginx/files-luci-support/luci.locations
   113|# uwsgi
   114|sed -i 's,procd_set_param stderr 1,procd_set_param stderr 0,g' feeds/packages/net/uwsgi/files/uwsgi.init
   115|sed -i 's,buffer-size = 10000,buffer-size = 131072,g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
   116|sed -i 's,logger = luci,#logger = luci,g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
   117|sed -i '$a cgi-timeout = 600' feeds/packages/net/uwsgi/files-luci-support/luci-*.ini
   118|sed -i 's/threads = 1/threads = 2/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
   119|sed -i 's/processes = 3/processes = 4/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
   120|sed -i 's/cheaper = 1/cheaper = 2/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
   121|# rpcd
   122|sed -i 's/option timeout 30/option timeout 60/g' package/system/rpcd/files/rpcd.config
   123|sed -i 's#20) \* 1000#60) \* 1000#g' feeds/luci/modules/luci-base/htdocs/luci-static/resources/rpc.js
   124|
   125|### FW4 ###
   126|rm -rf ./package/network/config/firewall4
   127|cp -rf ../openwrt_ma/package/network/config/firewall4 ./package/network/config/firewall4
   128|
   129|### 必要的 Patches ###
   130|# TCP optimizations
   131|cp -rf ../PATCH/kernel/6.7_Boost_For_Single_TCP_Flow/* ./target/linux/generic/backport-6.6/
   132|cp -rf ../PATCH/kernel/6.8_Boost_TCP_Performance_For_Many_Concurrent_Connections-bp_but_put_in_hack/* ./target/linux/generic/hack-6.6/
   133|cp -rf ../PATCH/kernel/6.8_Better_data_locality_in_networking_fast_paths-bp_but_put_in_hack/* ./target/linux/generic/hack-6.6/
   134|# UDP optimizations
   135|cp -rf ../PATCH/kernel/6.7_FQ_packet_scheduling/* ./target/linux/generic/backport-6.6/
   136|# Patch arm64 型号名称
   137|cp -rf ../PATCH/kernel/arm/* ./target/linux/generic/hack-6.6/
   138|# BBRv3
   139|cp -rf ../PATCH/kernel/bbr3/* ./target/linux/generic/backport-6.6/
   140|# LRNG
   141|cp -rf ../PATCH/kernel/lrng/* ./target/linux/generic/hack-6.6/
   142|echo '
   143|# CONFIG_RANDOM_DEFAULT_IMPL is not set
   144|CONFIG_LRNG=y
   145|CONFIG_LRNG_DEV_IF=y
   146|# CONFIG_LRNG_IRQ is not set
   147|CONFIG_LRNG_JENT=y
   148|CONFIG_LRNG_CPU=y
   149|# CONFIG_LRNG_SCHED is not set
   150|CONFIG_LRNG_SELFTEST=y
   151|# CONFIG_LRNG_SELFTEST_PANIC is not set
   152|' >>./target/linux/generic/config-6.6
   153|# wg
   154|cp -rf ../PATCH/kernel/wg/* ./target/linux/generic/hack-6.6/
   155|# dont wrongly interpret first-time data
   156|echo "net.netfilter.nf_conntrack_tcp_max_retrans=5" >>./package/kernel/linux/files/sysctl-nf-conntrack.conf
   157|# OTHERS
   158|cp -rf ../PATCH/kernel/others/* ./target/linux/generic/pending-6.6/
   159|# 6.17_ppp_performance
   160|wget https://github.com/torvalds/linux/commit/95d0d094.patch -O target/linux/generic/pending-6.6/999-1-95d0d09.patch
   161|wget https://github.com/torvalds/linux/commit/1a3e9b7a.patch -O target/linux/generic/pending-6.6/999-2-1a3e9b7.patch
   162|wget https://github.com/torvalds/linux/commit/7eebd219.patch -O target/linux/generic/pending-6.6/999-3-7eebd21.patch
   163|# ppp_fix
   164|wget -qO - https://github.com/immortalwrt/immortalwrt/commit/9d852a0.patch | patch -p1
   165|
   166|### Fullcone-NAT 部分 ###
   167|# bcmfullcone
   168|cp -rf ../PATCH/kernel/bcmfullcone/* ./target/linux/generic/hack-6.6/
   169|# set nf_conntrack_expect_max for fullcone
   170|wget -qO - https://github.com/openwrt/openwrt/commit/bbf39d07.patch | patch -p1
   171|echo "net.netfilter.nf_conntrack_helper = 1" >>./package/kernel/linux/files/sysctl-nf-conntrack.conf
   172|# FW4
   173|mkdir -p package/network/config/firewall4/patches
   174|#cp -f ../PATCH/pkgs/firewall/firewall4_patches/*.patch ./package/network/config/firewall4/patches/
   175|mkdir -p package/libs/libnftnl/patches
   176|cp -f ../PATCH/pkgs/firewall/libnftnl/*.patch ./package/libs/libnftnl/patches/
   177|sed -i '/PKG_INSTALL:=/iPKG_FIXUP:=autoreconf' package/libs/libnftnl/Makefile
   178|mkdir -p package/network/utils/nftables/patches
   179|cp -f ../PATCH/pkgs/firewall/nftables/*.patch ./package/network/utils/nftables/patches/
   180|# Patch LuCI 以增添 FullCone 开关
   181|pushd feeds/luci
   182|patch -p1 <../../../PATCH/pkgs/firewall/luci/0001-luci-app-firewall-add-nft-fullcone-and-bcm-fullcone-.patch
   183|popd
   184|
   185|### Shortcut-FE 部分 ###
   186|# Patch Kernel 以支持 Shortcut-FE
   187|cp -rf ../PATCH/kernel/sfe/* ./target/linux/generic/hack-6.6/
   188|cp -rf ../lede/target/linux/generic/pending-6.6/613-netfilter_optional_tcp_window_check.patch ./target/linux/generic/pending-6.6/613-netfilter_optional_tcp_window_check.patch
   189|# Patch LuCI 以增添 Shortcut-FE 开关
   190|pushd feeds/luci
   191|patch -p1 <../../../PATCH/pkgs/firewall/luci/0002-luci-app-firewall-add-shortcut-fe-option.patch
   192|popd
   193|
   194|### NAT6 部分 ###
   195|# custom nft command
   196|patch -p1 < ../PATCH/pkgs/firewall/100-openwrt-firewall4-add-custom-nft-command-support.patch
   197|cp -f ../PATCH/pkgs/firewall/firewall4_patches/*.patch ./package/network/config/firewall4/patches/
   198|# Patch LuCI 以增添 NAT6 开关
   199|pushd feeds/luci
   200|patch -p1 <../../../PATCH/pkgs/firewall/luci/0003-luci-app-firewall-add-ipv6-nat-option.patch
   201|popd
   202|# Patch LuCI 以支持自定义 nft 规则
   203|pushd feeds/luci
   204|patch -p1 <../../../PATCH/pkgs/firewall/luci/0004-luci-add-firewall-add-custom-nft-rule-support.patch
   205|popd
   206|
   207|### natflow 部分 ###
   208|pushd feeds/luci
   209|patch -p1 <../../../PATCH/pkgs/firewall/luci/0005-luci-app-firewall-add-natflow-offload-support.patch
   210|popd
   211|
   212|### fullcone6 ###
   213|pushd feeds/luci
   214|patch -p1 <../../../PATCH/pkgs/firewall/luci/0007-luci-app-firewall-add-fullcone6-option-for-nftables-.patch
   215|popd
   216|
   217|### Other Kernel Hack 部分 ###
   218|# make olddefconfig
   219|wget -qO - https://github.com/openwrt/openwrt/commit/c21a3570.patch | patch -p1
   220|# igc-fix
   221|cp -rf ../lede/target/linux/x86/patches-6.6/996-intel-igc-i225-i226-disable-eee.patch ./target/linux/x86/patches-6.6/996-intel-igc-i225-i226-disable-eee.patch
   222|# btf
   223|cp -rf ../PATCH/kernel/btf/* ./target/linux/generic/hack-6.6/
   224|
   225|### ADD PKG 部分 ###
   226|cp -rf ../OpenWrt-Add ./package/new
   227|rm -rf feeds/packages/net/{xray-core,v2ray-core,v2ray-geodata,sing-box,frp,microsocks,shadowsocks-libev,zerotier,daed}
   228|rm -rf feeds/luci/applications/{luci-app-frps,luci-app-frpc,luci-app-zerotier,luci-app-filemanager}
   229|rm -rf feeds/packages/utils/coremark
   230|
   231|### 获取额外的 LuCI 应用、主题和依赖 ###
   232|# 更换 Nodejs 版本
   233|rm -rf ./feeds/packages/lang/node
   234|rm -rf ./package/new/feeds_packages_lang_node-prebuilt
   235|cp -rf ../OpenWrt-Add/feeds_packages_lang_node-prebuilt ./feeds/packages/lang/node
   236|# 更换 golang 版本
   237|rm -rf ./feeds/packages/lang/golang
   238|cp -rf ../lede_pkg_ma/lang/golang ./feeds/packages/lang/golang
   239|# rust
   240|wget https://github.com/rust-lang/rust/commit/e8d97f0.patch -O feeds/packages/lang/rust/patches/e8d97f0.patch
   241|# mount cgroupv2
   242|pushd feeds/packages
   243|patch -p1 <../../../PATCH/pkgs/cgroupfs-mount/0001-fix-cgroupfs-mount.patch
   244|popd
   245|mkdir -p feeds/packages/utils/cgroupfs-mount/patches
   246|cp -rf ../PATCH/pkgs/cgroupfs-mount/900-mount-cgroup-v2-hierarchy-to-sys-fs-cgroup-cgroup2.patch ./feeds/packages/utils/cgroupfs-mount/patches/
   247|cp -rf ../PATCH/pkgs/cgroupfs-mount/901-fix-cgroupfs-umount.patch ./feeds/packages/utils/cgroupfs-mount/patches/
   248|cp -rf ../PATCH/pkgs/cgroupfs-mount/902-mount-sys-fs-cgroup-systemd-for-docker-systemd-suppo.patch ./feeds/packages/utils/cgroupfs-mount/patches/
   249|# fstool
   250|wget -qO - https://github.com/coolsnowwolf/lede/commit/8a4db76.patch | patch -p1
   251|# Boost 通用即插即用
   252|rm -rf ./feeds/packages/net/miniupnpd
   253|cp -rf ../openwrt_pkg_ma/net/miniupnpd ./feeds/packages/net/miniupnpd
   254|wget https://github.com/miniupnp/miniupnp/commit/0e8c68d.patch -O feeds/packages/net/miniupnpd/patches/0e8c68d.patch
   255|sed -i 's,/miniupnpd/,/,g' ./feeds/packages/net/miniupnpd/patches/0e8c68d.patch
   256|wget https://github.com/miniupnp/miniupnp/commit/21541fc.patch -O feeds/packages/net/miniupnpd/patches/21541fc.patch
   257|sed -i 's,/miniupnpd/,/,g' ./feeds/packages/net/miniupnpd/patches/21541fc.patch
   258|wget https://github.com/miniupnp/miniupnp/commit/b78a363.patch -O feeds/packages/net/miniupnpd/patches/b78a363.patch
   259|sed -i 's,/miniupnpd/,/,g' ./feeds/packages/net/miniupnpd/patches/b78a363.patch
   260|wget https://github.com/miniupnp/miniupnp/commit/8f2f392.patch -O feeds/packages/net/miniupnpd/patches/8f2f392.patch
   261|sed -i 's,/miniupnpd/,/,g' ./feeds/packages/net/miniupnpd/patches/8f2f392.patch
   262|wget https://github.com/miniupnp/miniupnp/commit/60f5705.patch -O feeds/packages/net/miniupnpd/patches/60f5705.patch
   263|sed -i 's,/miniupnpd/,/,g' ./feeds/packages/net/miniupnpd/patches/60f5705.patch
   264|wget https://github.com/miniupnp/miniupnp/commit/3f3582b.patch -O feeds/packages/net/miniupnpd/patches/3f3582b.patch
   265|sed -i 's,/miniupnpd/,/,g' ./feeds/packages/net/miniupnpd/patches/3f3582b.patch
   266|cp -rf ../PATCH/pkgs/miniupnpd/301-options-force_forwarding-support.patch ./feeds/packages/net/miniupnpd/patches/
   267|pushd feeds/packages
   268|patch -p1 <../../../PATCH/pkgs/miniupnpd/01-set-presentation_url.patch
   269|patch -p1 <../../../PATCH/pkgs/miniupnpd/02-force_forwarding.patch
   270|popd
   271|pushd feeds/luci
   272|patch -p1 <../../../PATCH/pkgs/miniupnpd/luci-upnp-support-force_forwarding-flag.patch
   273|popd
   274|# 动态DNS
   275|sed -i '/boot()/,+2d' feeds/packages/net/ddns-scripts/files/etc/init.d/ddns
   276|# Docker 容器
   277|rm -rf ./feeds/luci/applications/luci-app-dockerman
   278|cp -rf ../dockerman/applications/luci-app-dockerman ./feeds/luci/applications/luci-app-dockerman
   279|sed -i '/auto_start/d' feeds/luci/applications/luci-app-dockerman/root/etc/uci-defaults/luci-app-dockerman
   280|pushd feeds/packages
   281|wget -qO- https://github.com/openwrt/packages/commit/e2e5ee69.patch | patch -p1
   282|wget -qO- https://github.com/openwrt/packages/pull/20054.patch | patch -p1
   283|popd
   284|sed -i '/sysctl.d/d' feeds/packages/utils/dockerd/Makefile
   285|rm -rf ./feeds/luci/collections/luci-lib-docker
   286|cp -rf ../docker_lib/collections/luci-lib-docker ./feeds/luci/collections/luci-lib-docker
   287|# IPv6 兼容助手
   288|patch -p1 <../PATCH/pkgs/odhcp6c/1002-odhcp6c-support-dhcpv6-hotplug.patch
   289|# ODHCPD
   290|rm -rf ./package/network/services/odhcpd
   291|cp -rf ../openwrt_ma/package/network/services/odhcpd ./package/network/services/odhcpd
   292|rm -rf ./package/network/ipv6/odhcp6c
   293|cp -rf ../openwrt_ma/package/network/ipv6/odhcp6c ./package/network/ipv6/odhcp6c
   294|# watchcat
   295|echo > ./feeds/packages/utils/watchcat/files/watchcat.config
   296|# 默认开启 Irqbalance
   297|#sed -i "s/enabled '0'/enabled '1'/g" feeds/packages/utils/irqbalance/files/irqbalance.config
   298|
   299|# 使用 TEO CPU 空闲调度器
   300|KERNEL_VERSION="6.6"
   301|CONFIG_CONTENT='
   302|CONFIG_CPU_IDLE_GOV_MENU=n
   303|CONFIG_CPU_IDLE_GOV_TEO=y
   304|'
   305|# 查找所有与内核 6.6 相关的配置文件并将这些配置项追加到文件末尾
   306|find ./target/linux/ -name "config-${KERNEL_VERSION}" | xargs -I{} sh -c "echo '$CONFIG_CONTENT' | tee -a {} > /dev/null"
   307|
   308|### 最后的收尾工作 ###
   309|# Lets Fuck
   310|mkdir -p package/base-files/files/usr/bin
   311|cp -rf ../OpenWrt-Add/fuck ./package/base-files/files/usr/bin/fuck
   312|# 生成默认配置及缓存
   313|rm -rf .config
   314|sed -i 's,CONFIG_WERROR=y,# CONFIG_WERROR is not set,g' target/linux/generic/config-6.6
   315|
   316|#exit 0
   317|