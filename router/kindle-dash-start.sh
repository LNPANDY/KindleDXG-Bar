#!/bin/sh
# ============================================================================
# kindle-dash 开机自启 (由 /jffs/scripts/services-start 末尾调用, 幂等可重复执行)
#   - 配置 usb0 (Kindle 网卡) 的 IP
#   - 注册 cron (刷新频率从软件中心插件 dbus 读取, 默认 15 分钟)
#   - 依赖: 梅林固件会自动把带 Entware 的 U 盘分区挂到 /tmp/opt (/opt -> tmp/opt)
# 还原: cru d kindle-dash; 删除本文件并移除 services-start 末尾的调用行
# ============================================================================
LOG=/opt/kindle-dash/run.log

# Entware 挂载自愈: 重启后 post-mount 未跑/未生效时 /opt 会整路径失效
# (实测: /tmp/opt 不存在 → /opt/kindle-dash 与 /opt/bin/python3 全部"消失",
#  定时任务静默失败)。这里兜底扫描 U 盘挂载点并 bind 到 /tmp/opt
if [ ! -d /opt/kindle-dash ]; then
  for m in /tmp/mnt/*; do
    if [ -x "$m/etc/init.d/rc.unslung" ]; then
      mkdir -p /tmp/opt
      mount | grep -q "on /tmp/opt " || mount -o bind "$m" /tmp/opt
      break
    fi
  done
fi

# usb0 若已枚举(开机时 Kindle 已插在 USB 口)则配置 IP; 没插也不要紧,
# run.sh 每次运行都会自愈
if ifconfig usb0 >/dev/null 2>&1; then
  ifconfig usb0 2>/dev/null | grep -q "inet addr:" || \
    ifconfig usb0 192.168.2.1 netmask 255.255.255.0 up
fi

# cron 注册 (先删再建, 保证幂等; 频率尊重软件中心插件里的设置)
INTERVAL=$(dbus get kindledash_refresh 2>/dev/null)
case "$INTERVAL" in ""|*[!0-9]*) INTERVAL=15;; esac
[ "$INTERVAL" -lt 3 ] && INTERVAL=3
cru d kindle-dash 2>/dev/null
cru a kindle-dash "*/$INTERVAL * * * * /bin/sh /opt/kindle-dash/run.sh >> $LOG 2>&1"

# crond 存活守护: 本机梅林固件开机后 crond 可能不在运行(实测: 任务已注册
# 却无进程消费, 定时刷新静默失效)。注册完检查并补启 busybox crond,
# 它启动后会自动加载 /var/spool/cron/crontabs 里的任务
ps w 2>/dev/null | grep -q '[c]rond' || /usr/sbin/crond -b -l 8 2>/dev/null

# U 盘守护: 每 2 分钟自检掉盘/只读/文件系统错误并自动恢复。
# 脚本常驻 /jffs (U 盘崩了照样能执行); 开机先跑一次 + 注册 cron
UG=/jffs/scripts/usb-guard.sh
if [ ! -s "$UG" ] && [ -s /opt/kindle-dash/usb-guard.sh ]; then
  cp -f /opt/kindle-dash/usb-guard.sh "$UG" 2>/dev/null && chmod +x "$UG" 2>/dev/null
fi
if [ -s "$UG" ]; then
  cru d usb-guard 2>/dev/null
  cru a usb-guard "*/2 * * * * /bin/sh $UG >/dev/null 2>&1"
  ( /bin/sh "$UG" >/dev/null 2>&1 ) &
fi

echo "$(date +%F_%T) [kindle-dash] 自启脚本完成, cron 已注册 (每 ${INTERVAL} 分钟)" >> $LOG
