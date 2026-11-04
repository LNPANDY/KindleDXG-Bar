#!/bin/sh
# Kindle 仪表盘 - 软件中心卸载脚本 (只移除插件 UI 与 dbus, 不动 /opt/kindle-dash 项目本体)
source /koolshare/scripts/base.sh

rm -f /koolshare/scripts/kindledash_config.sh
rm -f /koolshare/scripts/kindledash_genconf.py
rm -f /koolshare/webs/Module_kindledash.asp
# U 盘守护: cron + jffs 上的脚本
cru d usb-guard 2>/dev/null
rm -f /jffs/scripts/usb-guard.sh
rm -f /jffs/kindle-dash-usb.log /jffs/.usbguard.port

for key in $(dbus | grep "^kindledash_" | sed 's/=.*//'); do
  dbus remove ${key}
done
dbus remove softcenter_module_kindledash_md5
dbus remove softcenter_module_kindledash_version
dbus remove softcenter_module_kindledash_install
dbus remove softcenter_module_kindledash_description
dbus remove softcenter_module_kindledash_name
dbus remove softcenter_module_kindledash_title
