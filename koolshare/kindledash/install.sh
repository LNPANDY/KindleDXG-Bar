#!/bin/sh
# ============================================================================
# Kindle 仪表盘 - 软件中心安装脚本 (v1.2.0: 插件自带运行程序, 装完即可用)
# ============================================================================
source /koolshare/scripts/base.sh
cd $(dirname $0)
APP=/koolshare/scripts/kindledash_app

echo_date "复制插件文件..."
cp -rf scripts/kindledash_config.sh /koolshare/scripts/
cp -rf scripts/kindledash_genconf.py /koolshare/scripts/
cp -rf webs/Module_kindledash.asp /koolshare/webs/
# 软件中心图标 (约定: /koolshare/res/icon-<模块名>.png)
cp -rf icon.png /koolshare/res/icon-kindledash.png
chmod 755 /koolshare/scripts/kindledash_config.sh /koolshare/scripts/kindledash_genconf.py

echo_date "部署渲染程序到 /opt/kindle-dash (程序文件随插件自带)..."
mkdir -p /opt/kindle-dash
# 程序文件每次安装都更新为插件内置版本; 用户配置只在首次写入
for x in dashboard.py run.sh push.sh; do
  [ -s ${APP}/${x} ] && cp -f ${APP}/${x} /opt/kindle-dash/${x}
done
chmod +x /opt/kindle-dash/run.sh /opt/kindle-dash/push.sh 2>/dev/null
[ -s /opt/kindle-dash/config.json ] || cp -f ${APP}/config.default.json /opt/kindle-dash/config.json

echo_date "写入开机自启脚本 (/jffs)..."
[ -s ${APP}/kindle-dash-start.sh ] && cp -f ${APP}/kindle-dash-start.sh /jffs/scripts/kindle-dash-start.sh
chmod +x /jffs/scripts/kindle-dash-start.sh 2>/dev/null
if [ -f /jffs/scripts/services-start ] && ! grep -q kindle-dash /jffs/scripts/services-start; then
  cat >> /jffs/scripts/services-start <<'APPEND'

# kindle-dash: 等 USB/Entware 就绪后注册 cron 与 usb0 (延迟 30s 幂等执行)
(sleep 30; /jffs/scripts/kindle-dash-start.sh) &
APPEND
fi
/jffs/scripts/kindle-dash-start.sh >/dev/null 2>&1

echo_date "注册软件中心模块..."
dbus set softcenter_module_kindledash_install=1
dbus set softcenter_module_kindledash_title=Kindle仪表盘
dbus set softcenter_module_kindledash_description=Kindle_DXG墨水屏副屏仪表盘配置
dbus set softcenter_module_kindledash_version=1.2.0
dbus set kindledash_version=1.2.0

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

echo_date "安装完成! 打开插件页点『环境自检』查看依赖状态;"
echo_date "缺什么点『一键安装依赖』即可自动装好 (仅 U 盘格式化为 ext 分区需一次性手动完成)。"
