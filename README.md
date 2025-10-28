<p align="center">
<img width="768" src="https://raw.githubusercontent.com/QiuSimons/Others/master/YAOF.png" >
</p>
<p align="center">
<img src="https://github.com/Tired-Fox/cargors/raw/aabd34c/assets/badges/built_with_love.svg">
<p>
<p align="center">
<img alt="GitHub All Releases" src="https://img.shields.io/github/downloads/QiuSimons/YAOF/total?style=for-the-badge">
<img alt="GitHub" src="https://img.shields.io/github/license/QiuSimons/YAOF?style=for-the-badge">
<p>
<p align="center">
<img src="https://github.com/QiuSimons/YAOF/workflows/R2C-OpenWrt/badge.svg">
<img src="https://github.com/QiuSimons/YAOF/workflows/R2S-OpenWrt/badge.svg">
<img src="https://github.com/QiuSimons/YAOF/workflows/R4S-OpenWrt/badge.svg">
<img src="https://github.com/QiuSimons/YAOF/workflows/X86-OpenWrt/badge.svg">
<p>


<h1 align="center">请勿用于商业用途!!!</h1>

### 特性

- 基于原生 OpenWrt 24.10 编译，默认管理地址 192.168.1.1
- 默认开启了 SFE（修正了 udp 入站以及 sqm 兼容性问题）
- 内置升级功能可用，物理 Reset 按键可用
- 预配置了部分插件<b>(注意，使用 MosDNS 同时作为广告过滤手段及 dns 分流措施。)</b>
- 可无脑 opkg kmod
- R2C/R2S 核心频率 1.6（交换了 LAN WAN），R4S 核心频率 2.2/1.8（建议使用带有线损补偿的电源，死机大多数情况下，都是因为<b>你用的电源过于垃圾</b>，另外，你也可以选择使用<b>自带的 app 限制最大频率</b>，茄子 🍆）
- O2 编译，CFLAG 优化
- 插件包含：SSRP，PassWall，OpenClash，Mihomo，DAED，微信推送，网易云解锁，SQM，DNSProxy，网络唤醒，DDNS，迅雷快鸟，UPNP，FullCone(防火墙中开启，默认开启)，流量分载，irq 优化，京东签到，Zerotier，FRPC，FRPS，无线打印，流量监控，过滤军刀，R2S-OLED
- ss 协议在 armv8 上实现了 aes 硬件加速（请<b>仅使用 aead 加密</b>的连接方式）
- 集成并默认启用了 BBRv3，LRNG
- 不再集成了 Docker，Docker刚需用户请停留在23.05，要使用 Docker，请先开启“Docker-配置-自动启动”选项，并保存应用设置
- 内置了一个一键格式化剩余空间并挂载的插件，方便 Docker 用户
- 如有任何问题，请先尝试 ssh 进入后台，输入 fuck 后回车，等待机器重启后确认问题是否已经解决

### 下载

- 选择自己<b>设备对应的固件</b>，并[下载](https://github.com/QiuSimons/R2S-R4S-OpenWrt/releases)

### 致敬

本仓库衍生于 [QiuSimons/YAOF](https://github.com/QiuSimons/YAOF)，感谢原作者的付出。

### 鸣谢

|               [ImmortalWrt](https://github.com/immortalwrt)               |              [coolsnowwolf](https://github.com/coolsnowwolf)              |                    [Lienol](https://github.com/Lienol)                    |
| :-----------------------------------------------------------------------: | :-----------------------------------------------------------------------: | :-----------------------------------------------------------------------: |
| <img width="60" src="https://avatars.githubusercontent.com/u/53193414"/>  | <img width="60" src="https://avatars.githubusercontent.com/u/31687149" /> | <img width="60" src="https://avatars.githubusercontent.com/u/23146169" /> |
|            [NoTengoBattery](https://github.com/NoTengoBattery)            |                    [tty228](https://github.com/tty228)                    |                  [destan19](https://github.com/destan19)                  |
| <img width="60" src="https://avatars.githubusercontent.com/u/11285513" /> | <img width="60" src="https://avatars.githubusercontent.com/u/33397881" /> | <img width="60" src="https://avatars.githubusercontent.com/u/3950091" />  |
|                 [jerrykuku](https://github.com/jerrykuku)                 |                    [lisaac](https://github.com/lisaac)                    |             [rufengsuixing](https://github.com/rufengsuixing)             |
| <img width="60" src="https://avatars.githubusercontent.com/u/9485680" />  | <img width="60" src="https://avatars.githubusercontent.com/u/3320969" />  | <img width="60" src="https://avatars.githubusercontent.com/u/22387141" /> |
|                     [ElonH](https://github.com/ElonH)                     |                   [NateLol](https://github.com/NateLol)                   |                   [kiddin9](https://github.com/kiddin9)                   |
| <img width="60" src="https://avatars.githubusercontent.com/u/32666230" /> | <img width="60" src="https://avatars.githubusercontent.com/u/5166306" />  | <img width="60" src="https://avatars.githubusercontent.com/u/48883331" /> |
|              [AmadeusGhost](https://github.com/AmadeusGhost)              |                [1715173329](https://github.com/1715173329)                |                 [vernesong](https://github.com/vernesong)                 |
| <img width="60" src="https://avatars.githubusercontent.com/u/42570690" /> | <img width="60" src="https://avatars.githubusercontent.com/u/22235437" /> | <img width="60" src="https://avatars.githubusercontent.com/u/42875168" /> |
