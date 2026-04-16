<p align="center">
  <img width="768" src="https://raw.githubusercontent.com/QiuSimons/Others/master/YAOF.png" alt="YAOF">
</p>

<p align="center">
  <a href="https://github.com/MoozIiSP/YAOF-bpi-r4/releases">
    <img alt="Latest Release" src="https://img.shields.io/github/v/release/MoozIiSP/YAOF-bpi-r4?style=for-the-badge&label=Release">
  </a>
  <a href="https://github.com/MoozIiSP/YAOF-bpi-r4/blob/mt7988-24.10/LICENSE">
    <img alt="License" src="https://img.shields.io/github/license/MoozIiSP/YAOF-bpi-r4?style=for-the-badge">
  </a>
  <a href="https://github.com/MoozIiSP/YAOF-bpi-r4/actions/workflows/BPI-R4-OpenWrt.yml">
    <img alt="BPI-R4 Build" src="https://img.shields.io/github/actions/workflow/status/MoozIiSP/YAOF-bpi-r4/BPI-R4-OpenWrt.yml?branch=mt7988-24.10&style=for-the-badge&label=BPI-R4">
  </a>
  <a href="https://github.com/MoozIiSP/YAOF-bpi-r4/actions/workflows/BPI-R4-PRO-OpenWrt.yml">
    <img alt="BPI-R4-PRO Build" src="https://img.shields.io/github/actions/workflow/status/MoozIiSP/YAOF-bpi-r4/BPI-R4-PRO-OpenWrt.yml?branch=mt7988-24.10&style=for-the-badge&label=BPI-R4-PRO">
  </a>
</p>

<h1 align="center">YAOF for Banana Pi BPI-R4</h1>
<p align="center"><strong>OpenWrt 24.10 · MT7988 / Filogic 880 · WiFi 7 · 10G · VPN-friendly</strong></p>

> 本仓库是面向 **Banana Pi BPI-R4** 的 YAOF 分支，聚焦 **OpenWrt 24.10 + Kernel 6.6**，优先保证 MTK WiFi / 交换 / 10G 相关稳定性。

---

## ⚠️ 声明

- **请勿用于商业用途**。
- 本仓库衍生于 [QiuSimons/YAOF](https://github.com/QiuSimons/YAOF)，感谢原作者与 OpenWrt / ImmortalWrt / 社区维护者的工作。
- 这里的取舍是 **BPI-R4 定向优化**，不是全平台通用仓库。

---

## 🎯 项目定位

这个仓库当前主要服务于以下目标：

- **设备**：Banana Pi **BPI-R4**
- **分支路线**：`24.10` / `mt7988-24.10`
- **内核策略**：锁定 **6.6**，优先 MTK 驱动稳定性，不盲目追新内核
- **网络场景**：WiFi 7、10G SFP+、多 WAN、VPN、旁路/分流、家宽路由强化
- **构建方式**：GitHub Actions

如果你在找的是 R2S / R4S / x86 的通用版本，这里不是那个仓库；这里已经明显偏向 **BPI-R4 专用**。

---

## ✨ 特性

### 基础

- 基于原生 **OpenWrt 24.10** 编译
- 默认管理地址：`192.168.1.1`
- 内置升级能力可用，物理 Reset 可用
- 保留较强的可扩展性，适合继续装包与二次定制

### 性能 / 网络

- 默认启用 **SFE**，兼顾 UDP 入站与 SQM 兼容性
- 集成 **BBRv3**、**LRNG**
- 面向 MT7988/Filogic 880 做了定向优化
- 对 10G / 高并发 / VPN 使用场景更友好

### 常用预置

- **MosDNS**（广告过滤 + DNS 分流）
- **PassWall / OpenClash / HomeProxy / Nikki / Dae**
- **SQM / UPNP / DDNS / Zerotier / Tailscale / FRP**
- **Watchcat / Filemanager / Argon / 微信推送 / WOL / NATMapT**

### 其他

- 支持直接 `opkg` 安装大量 `kmod-*`
- 保留 Docker 相关辅助思路，但当前主线重点不是 Docker 场景
- 如遇奇怪问题，可 SSH 后执行：

```bash
fuck
```

等待机器重启后再确认问题是否消失。

---

## 🧩 硬件侧重点

BPI-R4 典型关注点包括：

- **MT7988A / Filogic 880**
- **WiFi 7 / MT7996**
- **10G SFP+**
- **多千兆口交换 / VLAN / 路由混合场景**
- **Cloudflare / Tailscale / ZeroTier / 代理栈**

本仓库的策略更偏向：

- 先把 **能稳定跑** 放在第一位
- 再追求无线与网络吞吐
- 最后才考虑激进升级内核/驱动

---

## 📦 固件下载

请前往 Releases 页面下载与你设备匹配的固件：

- [Releases / 发布页](https://github.com/MoozIiSP/YAOF-bpi-r4/releases)

建议优先关注：

- `BPI-R4`
- `24.10.x`
- `sysupgrade`
- `factory`（如果某次发布有提供）

> 如果某个发布同时出现多个镜像，优先按发布说明选择，不要盲刷不匹配的产物。

---

## 🏗️ 仓库结构

```text
.
├── PATCH/                  # 内核/系统/网络相关补丁
├── SCRIPTS/                # 构建脚本
│   ├── 01_get_ready.sh
│   ├── 02_prepare_package.sh
│   └── BPI-R4/02_target_only.sh
├── SEED/                   # 目标机型 seed 配置
│   ├── BPI-R4/config.seed
│   └── BPI-R4-PRO/config.seed
├── .github/workflows/      # GitHub Actions
├── docs/                   # 介质策略、布局说明
```

其中：

- `SEED/BPI-R4/config.seed` 是当前主力配置
- `SCRIPTS/BPI-R4/02_target_only.sh` 包含 BPI-R4 定向处理
- `BPI-R4-PRO` 工作流已存在，但是否完整可用请以当前分支内容与发布结果为准
- `docs/bpi-r4-storage-layout.md` 记录 NAND / eMMC / SD 的介质分工与分区策略

---

## 🔨 本地构建

推荐环境：

- Ubuntu 24.04 / 22.04
- 8 GB+ 内存
- 50 GB+ 可用磁盘

基础流程：

```bash
git clone -b mt7988-24.10 https://github.com/MoozIiSP/YAOF-bpi-r4.git
cd YAOF-bpi-r4

bash SCRIPTS/01_get_ready.sh
bash SCRIPTS/02_prepare_package.sh
bash SCRIPTS/BPI-R4/02_target_only.sh

cd openwrt
make defconfig
make -j"$(nproc)"
```

### 构建说明

- 当前路线偏向 **OpenWrt 24.10 / Kernel 6.6**
- 不建议随手切到 6.12+ 再期待 MTK WiFi 仍然稳定
- 如果你想继续魔改，请优先理解 `PATCH/` 与 `SEED/` 的关系

---

## 🚀 CI / 自动构建

当前仓库已包含：

- `BPI-R4-OpenWrt.yml`
- `BPI-R4-PRO-OpenWrt.yml`
- `OpenWrt-Matrix.yml`

可通过 GitHub Actions 手动触发构建。

对于 `BPI-R4`，发布产物应按介质拆分为：

- `sd` 构建包
- `emmc` 构建包
- `snand` 构建包

---

## 🛠️ 使用建议

适合以下用户：

- 已经明确自己在玩 **BPI-R4**
- 想要一套更偏实战的 OpenWrt 固件
- 看重 **WiFi 7 / 10G / VPN / 分流**
- 能接受这个仓库是“面向单板定制”而不是“通用发行版”

不太适合：

- 需要全平台统一维护的人
- 追求最新内核、最新驱动、最新一切的人
- 想要完全零维护、零折腾体验的人

---

## 🙏 鸣谢

- [QiuSimons/YAOF](https://github.com/QiuSimons/YAOF)
- [OpenWrt](https://github.com/openwrt/openwrt)
- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)
- [frank-w](https://github.com/frank-w)
- MediaTek / Filogic 相关社区维护者
- 各类 LuCI 插件与第三方包维护者

---

## 📝 后续建议

如果你要继续把仓库往“更像一个可长期维护的固件项目”推进，优先建议做这几件事：

1. 给仓库补上 GitHub Topics：`bpi-r4`, `openwrt`, `mt7988`, `filogic`, `wifi7`
2. 给每个正式 tag 补 Release Notes
3. 在发布页注明：适用机型、刷写方式、已知问题、回退方式
4. 后续如果 `BPI-R4-PRO` 真开始维护，再把 README 里的支持矩阵单独展开

<p align="center"><strong>为 BPI-R4 做定向优化，而不是做一份什么都想兼顾的固件。</strong></p>
