#!/bin/sh
# ============================================================================
# Raspberry Pi (Zero W / Zero 2 W / 3B / 4B): Kindle 走 USB, Pi 走 WiFi, 桥起来
#
# 接线(Pi Zero W 为例):
#   Pi 的 PWR 口  ──► 5V 电源(必需, OTG 口做 host 时不供电)
#   Pi 的 OTG 口  ──► micro-USB 公 转 USB-A 母 的 OTG 线
#                        └──► Kindle 原装 micro-USB 数据线 ──► Kindle DXG
#   注意: 不需要给 Kindle 用 OTG 线, Kindle 是 device, 普通数据线就行。
#         OTG 线只用在 Pi 那一端(Pi 要当 host)。
#
# 用法: sudo sh pi-usbnet.sh
# ============================================================================
set -e

KINDLE_IF="${KINDLE_IF:-usb0}"
OUT_IF="${OUT_IF:-wlan0}"       # Pi 上网用的口

# 1. 配 usb0 静态 IP(与 Kindle 的 HOST_IP 一致)
ip link show "$KINDLE_IF" >/dev/null 2>&1 || {
  echo "[err] 没有 $KINDLE_IF。检查: dmesg | tail -30 / lsusb"
  echo "      Pi Zero 必须用中间那个 OTG 口, 不能用 PWR 口"
  exit 1
}
ip addr flush dev "$KINDLE_IF" 2>/dev/null || true
ip addr add 192.168.2.1/24 dev "$KINDLE_IF"
ip link set "$KINDLE_IF" up

# 2. 开转发 + NAT, 让 Kindle 能借 Pi 的 WiFi 上网
sysctl -w net.ipv4.ip_forward=1 >/dev/null
grep -q '^net.ipv4.ip_forward' /etc/sysctl.conf \
  && sed -i 's/^#\?net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf \
  || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

iptables -t nat -C POSTROUTING -o "$OUT_IF" -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -o "$OUT_IF" -j MASQUERADE
iptables -C FORWARD -i "$KINDLE_IF" -o "$OUT_IF" -j ACCEPT 2>/dev/null \
  || iptables -A FORWARD -i "$KINDLE_IF" -o "$OUT_IF" -j ACCEPT
iptables -C FORWARD -i "$OUT_IF" -o "$KINDLE_IF" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null \
  || iptables -A FORWARD -i "$OUT_IF" -o "$KINDLE_IF" -m state --state ESTABLISHED,RELATED -j ACCEPT

# 持久化 iptables
if command -v netfilter-persistent >/dev/null 2>&1; then
  netfilter-persistent save
else
  apt-get install -y iptables-persistent >/dev/null 2>&1 && netfilter-persistent save || true
fi

# 3. 自愈看门狗
cat > /usr/local/bin/kindle-watchdog.sh <<'EOF'
#!/bin/sh
ping -c 1 -W 2 192.168.2.2 >/dev/null 2>&1 && exit 0
logger -t kindle "192.168.2.2 不通, 重配 usb0"
ip link set usb0 down 2>/dev/null; sleep 1
ip addr flush dev usb0 2>/dev/null
ip addr add 192.168.2.1/24 dev usb0
ip link set usb0 up
EOF
chmod +x /usr/local/bin/kindle-watchdog.sh
( crontab -l 2>/dev/null | grep -v kindle-watchdog
  echo "*/5 * * * * /usr/local/bin/kindle-watchdog.sh" ) | crontab -

# 4. 开机自动
cat > /etc/systemd/system/kindle-usbnet.service <<'EOF'
[Unit]
Description=Kindle usbnet bridge
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/kindle-watchdog.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable kindle-usbnet.service

echo "[ok] 本机测试: ping -c 2 192.168.2.2"
echo "[ok] 想让家里其他机器访问 Kindle, 在主路由加静态路由:"
echo "     192.168.2.0/24  ->  $(hostname -I | awk '{print $1}')"
ping -c 2 -W 2 192.168.2.2 || true
