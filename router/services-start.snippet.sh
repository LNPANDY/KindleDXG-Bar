# ============================================================================
# /jffs/scripts/services-start  (梅林开机钩子, 记得 chmod +x)
# 作用: 开机拉起 usb0, 并挂一个每 5 分钟的自愈检查
# ============================================================================

#!/bin/sh

D=/opt/kindle-dash

# 开机后延迟 20s 再拉(等 USB 子系统就绪)
(sleep 20; sh $D/router/usbnet-up.sh >> $D/router/usbnet.log 2>&1) &

# 自愈: usb0 掉了就重新拉起来
 cru a kindle_usbnet "*/5 * * * * sh $D/router/watchdog.sh >> $D/router/usbnet.log 2>&1"

# 每 15 分钟刷新一次仪表盘(若渲染跑在服务器上, 这行可以去掉)
 cru a kindle_dash "*/15 * * * * $D/run.sh >> $D/run.log 2>&1"
