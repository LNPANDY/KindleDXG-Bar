#!/bin/sh
# ============================================================================
# 在 Kindle DXG 本机执行(通过 usbnet ssh 上去跑, 或存成 /mnt/us/dash/setup.sh
# 在 launchpad 里绑定一个热键执行)。做三件事:
#   1. 建目录 + 校时
#   2. 进入"信息亭模式": 停掉原生框架与 powerd, 让 eips 独占屏幕
#   3. 立刻刷一张图验证
#
# 前提: 已越狱 + 已装 usbnet(见 README 第 1 步)
# ============================================================================

DASH=/mnt/us/dash
MODE="${1:-kiosk}"        # kiosk | framework

echo "== Kindle DXG dashboard 初始化 =="

# --- 1. 目录与校时 ----------------------------------------------------------
mntroot rw
mkdir -p $DASH
# 证书 2025-04 已过期, 系统日期必须早于该时间点, 否则 KUAL 打不开
date -s "011212002025" 2>/dev/null || date 011212002025
echo "[ok] 日期设为 $(date)"

# --- 2. 决定屏幕由谁控制 ----------------------------------------------------
if [ "$MODE" = "kiosk" ]; then
  echo "[..] 停止原生框架 (kiosk 模式)"
  /etc/init.d/framework stop   2>/dev/null
  /etc/init.d/powerd stop      2>/dev/null     # 不让它自动休眠/盖屏保
  /etc/init.d/netwatchd stop   2>/dev/null     # 免得它把 usb0 收回去
  sleep 2
  echo "[ok] 框架已停, 现在屏幕完全由 eips 控制"
else
  echo "[..] 保留原生框架"
  echo "     注意: 进入屏保后 eips 的画面会被覆盖,"
  echo "     需要用 'screensaver -> wake -> screensaver' 强制重载(见 README)"
fi

# --- 3. 刷一张图验证 --------------------------------------------------------
if [ -f $DASH/dashboard.png ]; then
  /usr/sbin/eips -c            # 清屏
  /usr/sbin/eips -f -g $DASH/dashboard.png
  echo "[ok] 已刷新 $DASH/dashboard.png"
else
  /usr/sbin/eips -c
  echo "[..] 还没有图片, 先在电脑上跑: ./push.sh"
fi

# --- 4. 常用运维命令备忘 ----------------------------------------------------
cat > $DASH/HOWTO.txt <<'EOF'
刷图:        /usr/sbin/eips -f -g /mnt/us/dash/dashboard.png
局部刷新:    /usr/sbin/eips -g /mnt/us/dash/dashboard.png     (快, 但有残影)
清屏:        /usr/sbin/eips -c
写文字:      /usr/sbin/eips 10 10 "hello"
恢复原系统:  /etc/init.d/framework start ; /etc/init.d/powerd start
看电量:      gasgauge-info -s
设横屏:      echo 14 2 > /proc/eink_fb/update_display
手工刷屏:    echo 2 > /proc/eink_fb/update_display
EOF

mntroot ro
echo "[done] 备忘写在 $DASH/HOWTO.txt"
