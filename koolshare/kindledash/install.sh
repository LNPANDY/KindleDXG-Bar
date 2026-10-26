#!/bin/sh
# Kindle 仪表盘 - 软件中心安装脚本
source /koolshare/scripts/base.sh
cd $(dirname $0)

echo_date "复制插件文件..."
cp -rf scripts/kindledash_config.sh /koolshare/scripts/
cp -rf scripts/kindledash_genconf.py /koolshare/scripts/
cp -rf webs/Module_kindledash.asp /koolshare/webs/
# 软件中心图标 (约定: /koolshare/res/icon-<模块名>.png)
cp -rf icon.png /koolshare/res/icon-kindledash.png
chmod 755 /koolshare/scripts/kindledash_config.sh /koolshare/scripts/kindledash_genconf.py

echo_date "注册软件中心模块..."
dbus set softcenter_module_kindledash_install=1
dbus set softcenter_module_kindledash_title=Kindle仪表盘
dbus set softcenter_module_kindledash_description=Kindle_DXG墨水屏副屏仪表盘配置
dbus set softcenter_module_kindledash_version=1.1.0
dbus set kindledash_version=1.1.0

# 首次安装时的默认配置(不覆盖用户已有设置)
[ -z "$(dbus get kindledash_orientation)" ] && dbus set kindledash_orientation=portrait
[ -z "$(dbus get kindledash_refresh)" ] && dbus set kindledash_refresh=15
[ -z "$(dbus get kindledash_modules)" ] && dbus set kindledash_modules=crypto,fastnews,hot
[ -z "$(dbus get kindledash_coin_source)" ] && dbus set kindledash_coin_source=binance
[ -z "$(dbus get kindledash_pair_1)" ] && dbus set kindledash_pair_1=BTC
[ -z "$(dbus get kindledash_pair_2)" ] && dbus set kindledash_pair_2=ETH
[ -z "$(dbus get kindledash_pair_3)" ] && dbus set kindledash_pair_3=SOL
[ -z "$(dbus get kindledash_pair_4)" ] && dbus set kindledash_pair_4=BNB
[ -z "$(dbus get kindledash_pair_5)" ] && dbus set kindledash_pair_5=XRP
[ -z "$(dbus get kindledash_fn_source)" ] && dbus set kindledash_fn_source=sina7x24
[ -z "$(dbus get kindledash_fn_count)" ] && dbus set kindledash_fn_count=4
[ -z "$(dbus get kindledash_feed_36kr)" ] && dbus set kindledash_feed_36kr=1
[ -z "$(dbus get kindledash_feed_solidot)" ] && dbus set kindledash_feed_solidot=1
[ -z "$(dbus get kindledash_feed_cointele)" ] && dbus set kindledash_feed_cointele=1
[ -z "$(dbus get kindledash_feed_foresight)" ] && dbus set kindledash_feed_foresight=1
[ -z "$(dbus get kindledash_hot1_source)" ] && dbus set kindledash_hot1_source=weibo
[ -z "$(dbus get kindledash_hot2_source)" ] && dbus set kindledash_hot2_source=bilibili
[ -z "$(dbus get kindledash_hot_count)" ] && dbus set kindledash_hot_count=4

echo_date "安装完成! 前提: /opt/kindle-dash 已部署(U盘 Entware)且 Kindle 已插在路由器 USB 口。"
echo_date "卸载本插件不会停止已注册的定时刷新任务; 如需彻底停用请在系统 log 里执行: cru d kindle-dash"
