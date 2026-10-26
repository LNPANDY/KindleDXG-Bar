#!/bin/sh
# ============================================================================
# 一轮完整流程: 渲染 -> 与上一张比对 -> 有变化才推送刷屏 (Mac/路由器通用)
# cron 建议: */15 * * * * /opt/kindle-dash/run.sh >> /opt/kindle-dash/run.log 2>&1
# ============================================================================
DIR=$(cd "$(dirname "$0")" && pwd)
cd "$DIR" || exit 1

# 路由器环境: Entware 路径 + python3 定位
export PATH="/opt/bin:/opt/sbin:$PATH"
if [ -x /opt/bin/python3 ]; then PY="/opt/bin/python3"; else PY="${PY:-python3}"; fi

# 路由器模式静默认证 (usbnet 的 dropbear 不校验密码, 随便给一个避免 tty 提示)
export DROPBEAR_PASSWORD="${DROPBEAR_PASSWORD:-kindle-dash}"

# usb0 自愈: 路由器重启或 Kindle 重新插拔后接口在但没有 IP
if ifconfig usb0 >/dev/null 2>&1 && ! ifconfig usb0 2>/dev/null | grep -q "inet addr:"; then
  ifconfig usb0 192.168.2.1 netmask 255.255.255.0 up
  echo "[info] 已自动配置 usb0 192.168.2.1"
fi

OUT="$DIR/dashboard.png"
LAST="$DIR/.last.png"

$PY dashboard.py --config config.json -o "$OUT" || {
  echo "[warn] 渲染失败, 尝试离线缓存"; $PY dashboard.py --offline -o "$OUT"
} || exit 1

# kiosk 自愈: Kindle 万一重启过, 屏保/框架会回来, 每轮推送前顺手停掉(幂等)
/usr/bin/dbclient -y root@192.168.2.2 \
  "/etc/init.d/framework stop 2>/dev/null; /etc/init.d/powerd stop 2>/dev/null; /etc/init.d/netwatchd stop 2>/dev/null" \
  </dev/null >/dev/null 2>&1

# 内容没变就不刷屏(省墨水屏寿命 + 省残影)
if [ -f "$LAST" ] && cmp -s "$OUT" "$LAST"; then
  echo "[skip] $(date '+%F %T') 内容无变化, 不刷新"
  exit 0
fi

./push.sh "$OUT" && cp "$OUT" "$LAST"
