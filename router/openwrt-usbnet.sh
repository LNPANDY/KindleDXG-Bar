#!/bin/sh
# ============================================================================
# OpenWrt / GL.iNet 旅行路由器: 把插在 USB 口的 Kindle 变成 WiFi 上的一台设备
#
# 原理: Kindle 在 usbnet 模式下 = 一台"开 USB 网络共享的手机"(RNDIS/CDC-ECM)。
# OpenWrt 官方手机 tethering 用的就是同一套驱动, 直接复用即可。
#
# 用法(SSH 进旅行路由器):
#   opkg update
#   sh openwrt-usbnet.sh            # 装驱动 + 建接口 + 配防火墙
#   sh openwrt-usbnet.sh route      # 可选: 打印要在主路由(AC86U)上添加的静态路由
#
# 常见机型: GL-AR300M16 / GL-MT300N-V2 / GL-SFT1200(Opal) / GL-AXT1800(Slate AX)
# ============================================================================

KINDLE_IF="usb0"
KINDLE_IP="192.168.2.1"
KINDLE_NET="192.168.2.0/24"

# --- 1. 装驱动 --------------------------------------------------------------
opkg update
opkg install kmod-usb-core kmod-usb2 kmod-usb-net kmod-usb-net-cdc-ether \
             kmod-usb-net-rndis kmod-nls-base usbutils

# --- 2. 等 usb0 出现 --------------------------------------------------------
i=0
while [ $i -lt 15 ]; do
  ip link show "$KINDLE_IF" >/dev/null 2>&1 && break
  i=$((i + 1)); sleep 1
done
ip link show "$KINDLE_IF" >/dev/null 2>&1 || {
  echo "[err] 没有 $KINDLE_IF。先看 dmesg | tail -30 和 lsusb"
  echo "      Kindle 如果只被识别成 U 盘, 说明没进 usbnet 模式(建 /mnt/us/usbnet/auto)"
  exit 1
}
echo "[ok] $(lsusb | grep -i -E 'kindle|lab126|0525')"

# --- 3. 建网络接口(OpenWrt 21+ 用 device, 老版本用 ifname) ------------------
uci -q delete network.kindle
uci set network.kindle='interface'
uci set network.kindle.device="$KINDLE_IF"
uci set network.kindle.proto='static'
uci set network.kindle.ipaddr="$KINDLE_IP"
uci set network.kindle.netmask='255.255.255.0'
uci commit network

# --- 4. 防火墙: 放进 lan 区, 允许转发 ---------------------------------------
uci -q delete firewall.kindle_zone
uci set firewall.kindle_zone='zone'
uci set firewall.kindle_zone.name='kindle'
uci set firewall.kindle_zone.network='kindle'
uci set firewall.kindle_zone.input='ACCEPT'
uci set firewall.kindle_zone.output='ACCEPT'
uci set firewall.kindle_zone.forward='ACCEPT'
uci set firewall.kindle_zone.masq='1'          # 让 Kindle 能借 WiFi 上网
uci -q add_list firewall.@zone[0].network='kindle'   # 同时算作 lan 区, 简化访问
uci commit firewall

/etc/init.d/network restart
/etc/init.d/firewall restart
sleep 3

# --- 5. 自愈看门狗 ----------------------------------------------------------
mkdir -p /etc/kindle
cat > /etc/kindle/watchdog.sh <<'EOF'
#!/bin/sh
ping -c 1 -W 2 192.168.2.2 >/dev/null 2>&1 && exit 0
logger -t kindle "192.168.2.2 不通, 重启 usb0 接口"
ifdown kindle 2>/dev/null; ifup kindle 2>/dev/null
EOF
chmod +x /etc/kindle/watchdog.sh
( crontab -l 2>/dev/null | grep -v kindle/watchdog
  echo "*/5 * * * * /etc/kindle/watchdog.sh" ) | crontab -

echo "[ok] 本机测试: ping -c 2 192.168.2.2"

# --- 6. 告诉用户主路由怎么配 ------------------------------------------------
if [ "$1" = "route" ]; then
  LANIP=$(uci -q get network.lan.ipaddr)
  echo ""
  echo "== 让家里其他机器也能访问 Kindle =="
  echo "在主路由(AC86U)上加一条静态路由:"
  echo "    目标网段: $KINDLE_NET"
  echo "    网关:     $LANIP   (本旅行路由器的 LAN IP)"
  echo "梅林位置: 高级设置 → 路由 → 静态路由列表"
fi
