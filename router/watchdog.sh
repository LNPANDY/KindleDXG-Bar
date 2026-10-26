#!/bin/sh
# ============================================================================
# usb0 自愈看门狗: 每 5 分钟跑一次, Kindle 不通就重新拉 usbnet
# 长跑必配 —— USB gadget 侧偶尔会掉, 尤其是 Kindle 进过屏保之后
# ============================================================================
D=$(cd "$(dirname "$0")/.." && pwd)
KINDLE_IP="${KINDLE_IP:-192.168.2.2}"

if ping -c 1 -W 2 "$KINDLE_IP" >/dev/null 2>&1; then
  exit 0
fi

echo "[$(date '+%F %T')] $KINDLE_IP 不通, 重新拉起 usb0"
ip link set usb0 down 2>/dev/null
rmmod rndis_host 2>/dev/null
rmmod cdc_ether 2>/dev/null
rmmod usbnet 2>/dev/null
sleep 2
sh "$D/router/usbnet-up.sh"
