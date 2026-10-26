# Changelog

## v1.2.0 (2026-10-27)

- 新增：插件页『运行环境』面板 —— **环境自检**（Entware / Python / Pillow / 字体 / 程序文件 / 定时任务 / Kindle 连通 / 外网数据源，8 项体检）+ **一键安装依赖**（Entware→Python3→Pillow→中文字体→开机脚本→cron 全自动，幂等可重复执行）
- 渲染程序、默认配置、开机自启脚本全部随插件打包：装完插件本体即就绪，无需 SSH 手工部署
- 中文字体（思源黑体简体）从项目 Release 自动下载（含 gh-proxy 镜像回退），33MB 不占插件包
- 唯一保留的手动步骤：U 盘一次性格式化为 ext2/3/4（破坏性操作，不代做；amtm 或 USB 应用插件均可完成），完成后点『一键安装依赖』即可
- koolshare 插件版本号 1.2.0

## v1.1.2 (2026-10-27)

- 修复：自定义币种被渲染器内置币池静默过滤（`_normalize_cfg` 遗留校验与配置生成层不一致），现只做格式清理

## v1.1.1 (2026-10-27)

- 新增：按币种指定行情来源 `crypto.pair_sources`（如 `{"PEPE": "gate"}`），渲染时按源分组批量拉取，某组失败自动换源兜底
- 24h 曲线按每个币自己的来源取 K 线（Binance klines / Gate candlesticks / CoinGecko market_chart）

## v1.1.0 (2026-10-26)

- 横版渲染（内容旋转 90° 适配竖屏 framebuffer）
- 模块显示顺序可配置（`modules` 数组）
- 行情三源：Binance（官方镜像 `data-api.binance.vision`，国内直连）/ CoinGecko / Gate.io，多域名自动探测
- 快讯五源：新浪 7×24 / 华尔街见闻 / 金十 / 东方财富 / RSS 聚合池
- 热榜六源：微博 / 头条 / 知乎(v2) / B站 / 百度 / 抖音，双栏并排
- koolshare 软件中心插件：网页配置全部参数，交易对一键检测（三源实测 ✓/✗），手动添加代币代码

## v1.0.0 (2026-10-26)

- 首个可用版本
- 路由器（Asuswrt-Merlin / OpenWrt / Raspberry Pi）全自主：抓数据 → Pillow 渲染 824×1200 灰度图 → `eips` 刷屏
- 传输方案：路由器临时 HTTP 服务 + Kindle busybox wget 拉取 + 远端 md5 校验（规避 dropbear dbclient 管道丢首个 4096 字节缓冲的缺陷）
- 三层自愈：usb0 重枚举 / Kindle 重启 kiosk 恢复 / 数据源故障换源 + 离线缓存兜底
- 内容逐字节去重，无变化跳过刷屏
