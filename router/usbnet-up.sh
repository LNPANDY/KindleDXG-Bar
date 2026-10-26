#!/bin/sh
# ============================================================================
# Asuswrt-Merlin (RT-AC86U) 侧: 把插在 USB 口的 Kindle 识别成网卡 usb0
#
#  Kindle 在 usbnet 模式下是 USB Ethernet Gadget (g_ether / RNDIS),
#  路由器 USB 口是 Host, 加载 rndis_host + cdc_ether + usbnet 即可。
#
# 用法:
#   sh usbnet-up.sh            # 手动跑一次看效果
#   放到 /jffs/scripts/services-start 里开机自动执行(见 services-start.snippet.sh)
# ============================================================================

MODDIR="/lib/modules/$(uname -r)"

# 1) 加载内核模块(梅林固件自带这三个)
for M in usbnet cdc_ether rndis_host; do
  if ! lsmod | grep -q "^$M"; then
    if [ -f "$MODDIR/$M.ko" ]; then
      insmod "$MODDIR/$M.ko" 2>/dev/null && echo "[ok] insmod $M" \
        || echo "[warn] insmod $M 失败"
    else
      echo "[warn] 找不到 $MODDIR/$M.ko —— 这个固件没编该模块, usbnet 走不通"
    fi
  fi
done

# 2) 等一下让 usb0 出现
for i in 1 2 3 4 5 6 7 8 9 10; do
  ip link show usb0 >/dev/null 2>&1 && break
  sleep 1
done

if ! ip link show usb0 >/dev/null 2>&1; then
  echo "[err] 没有出现 usb0。插上去后先看 dmesg | tail -30"
  echo "      常见原因: Kindle 没进 usbnet 模式(进了 USB Drive Mode 就只会是 U 盘)"
  exit 1
fi

# 3) 配 IP(与 Kindle 的 HOST_IP 保持一致, 默认 192.168.2.1/24)
ip addr flush dev usb0 2>/dev/null
ip addr add 192.168.2.1/24 dev usb0
ip link set usb0 up
ip link set usb0 mtu 1500

# 4) 开启转发, 让 Kindle 也能上网(可选, 用于 Kindle 自己校时/取数据)
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
iptables -t nat -C POSTROUTING -o "$(nvram get wan0_ifname)" -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -o "$(nvram get wan0_ifname)" -j MASQUERADE 2>/dev/null
iptables -C FORWARD -i usb0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -i usb0 -j ACCEPT
iptables -C FORWARD -o usb0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -o usb0 -j ACCEPT

# 5) 可选: 把 usb0 桥进 LAN, 这样局域网里任何机器都能直接 ssh 192.168.2.2
if [ "$1" = "bridge" ]; then
  brctl addif br0 usb0 2>/dev/null && echo "[ok] usb0 已桥接进 br0, 局域网可直接访问 192.168.2.2"
fi

echo "[ok] usb0 ready, 测试: ping -c 2 192.168.2.2"
ping -c 2 -W 2 192.168.2.2
