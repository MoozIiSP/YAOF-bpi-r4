     1|#!/bin/bash
     2|
     3|# 这个脚本的作用是从不同的仓库中克隆openwrt相关的代码，并进行一些处理
     4|
     5|# 定义一个函数，用来克隆指定的仓库和分支
     6|clone_repo() {
     7|  # 参数1是仓库地址，参数2是分支名，参数3是目标目录
     8|  repo_url=$1
     9|  branch_name=$2
    10|  target_dir=$3
    11|  # 克隆仓库到目标目录，并指定分支名和深度为1
    12|  git clone -b $branch_name --depth 1 $repo_url $target_dir
    13|}
    14|
    15|# 定义一些变量，存储仓库地址和分支名
    16|latest_release="$(curl -s https://github.com/openwrt/openwrt/tags | grep -Eo "v[0-9\.]+\-*r*c*[0-9]*.tar.gz" | grep 'v24.10' | sed -n 1p | sed 's/.tar.gz//g')"
    17|lede_repo="https://github.com/coolsnowwolf/lede.git"
    18|lede_luci_repo="https://github.com/coolsnowwolf/luci.git"
    19|lede_pkg_repo="https://github.com/coolsnowwolf/packages.git"
    20|openwrt_repo="https://github.com/openwrt/openwrt.git"
    21|openwrt_pkg_repo="https://github.com/openwrt/packages.git"
    22|openwrt_luci_repo="https://github.com/openwrt/luci.git"
    23|lienol_repo="https://github.com/Lienol/openwrt.git"
    24|lienol_pkg_repo="https://github.com/Lienol/openwrt-package"
    25|openwrt_add_repo="https://github.com/QiuSimons/OpenWrt-Add.git"
    26|openwrt_node_repo="https://github.com/nxhack/openwrt-node-packages.git"
    27|passwall_pkg_repo="https://github.com/xiaorouji/openwrt-passwall-packages"
    28|passwall_luci_repo="https://github.com/xiaorouji/openwrt-passwall"
    29|openwrt_third_repo="https://github.com/jjm2473/openwrt-third"
    30|dockerman_repo="https://github.com/lisaac/luci-app-dockerman"
    31|diskman_repo="https://github.com/lisaac/luci-app-diskman"
    32|docker_lib_repo="https://github.com/lisaac/luci-lib-docker"
    33|mosdns_repo="https://github.com/QiuSimons/openwrt-mos"
    34|ssrp_repo="https://github.com/fw876/helloworld"
    35|zxlhhyccc_repo="https://github.com/zxlhhyccc/bf-package-master"
    36|linkease_repo="https://github.com/linkease/openwrt-app-actions"
    37|linkease_pkg_repo="https://github.com/jjm2473/packages"
    38|linkease_luci_repo="https://github.com/jjm2473/luci"
    39|sirpdboy_repo="https://github.com/sirpdboy/sirpdboy-package"
    40|sbwdaednext_repo="https://github.com/sbwml/luci-app-daed-next"
    41|lucidaednext_repo="https://github.com/QiuSimons/luci-app-daed-next"
    42|sbwfw876_repo="https://github.com/sbwml/openwrt_helloworld"
    43|sbw_pkg_repo="https://github.com/sbwml/openwrt_pkgs"
    44|natmap_repo="https://github.com/blueberry-pie-11/luci-app-natmap"
    45|xwrt_repo="https://github.com/QiuSimons/openwrt-natflow"
    46|tailscale_repo="https://github.com/asvow/luci-app-tailscale"
    47|luci_theme_design_repo="https://github.com/SAENE/luci-theme-design"
    48|
    49|# 开始克隆仓库，并行执行
    50|clone_repo $openwrt_repo $latest_release openwrt &
    51|#clone_repo $openwrt_repo openwrt-24.10 openwrt &
    52|clone_repo $openwrt_repo openwrt-24.10 openwrt_snap &
    53|
    54|clone_repo $lede_repo master lede &
    55|clone_repo $lede_pkg_repo master lede_pkg_ma &
    56|clone_repo $openwrt_repo main openwrt_ma &
    57|clone_repo $openwrt_pkg_repo master openwrt_pkg_ma &
    58|clone_repo $openwrt_add_repo master OpenWrt-Add &
    59|clone_repo $dockerman_repo master dockerman &
    60|clone_repo $docker_lib_repo master docker_lib &
    61|clone_repo $luci_theme_design_repo master luci_theme_design_repo &
    62|# 等待所有后台任务完成
    63|# MTK Official Feed
    64|clone_repo "https://git01.mediatek.com/openwrt/feeds/mtk-openwrt-feeds.git" "openwrt-24.10" "mtk-feed" &
    65|
    66|# Custom Bootloader with DHCPD/WebUI (Yuzhii0718)
    67|clone_repo "https://github.com/Yuzhii0718/bl-mt798x-dhcpd.git" "master" "bl-mt798x-dhcpd" &
    68|
    69|wait
    70|
    71|# 进行一些处理
    72|find openwrt/package/* -maxdepth 0 ! -name 'firmware' ! -name 'kernel' ! -name 'base-files' ! -name 'Makefile' -exec rm -rf {} +
    73|rm -rf ./openwrt_snap/package/firmware ./openwrt_snap/package/kernel ./openwrt_snap/package/base-files ./openwrt_snap/package/Makefile
    74|cp -rf ./openwrt_snap/package/* ./openwrt/package/
    75|cp -rf ./openwrt_snap/feeds.conf.default ./openwrt/feeds.conf.default
    76|# 修复缺失的 kmod-drm-lima
    77|
    78|# 退出脚本
    79|exit 0
    80|