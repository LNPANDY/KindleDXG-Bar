#!/bin/sh
# usbwatch.sh —— 实时监视 Kindle DXG 是否被 Mac 认到
#
# 用法：  ./tools/usbwatch.sh [秒数]
# 默认监视 120 秒，期间你随便插拔 / 换线 / 换口，终端会实时报告变化。
#
# Kindle DXG 可能出现的三种身份：
#   1. 大容量存储模式  -> VID 1949 PID 0002  "Amazon Kindle"
#   2. usbnet 网络模式 -> RNDIS/CDC-ECM 网卡，同时也会先枚举成 1949:0002
#   3. 完全没反应      -> 充电线 / 线坏 / DXG 的 micro-USB 座脱焊

DUR=${1:-120}
END=$(( $(date +%s) + DUR ))

say() { printf "\033[%sm%s\033[0m %s\n" "$1" "$2" "$3"; }

snapshot() {
    ioreg -p IOUSB -w 0 -l 2>/dev/null \
    | grep -E '"idVendor"|"idProduct"|"USB Product Name"|"USB Vendor Name"|"USB Serial Number"' \
    | tr -d ' ' | paste -sd' ' - 2>/dev/null
}

say 36 "[usbwatch]" "开始监视 ${DUR}s —— 现在可以插拔 Kindle / 换线 / 换 USB 口"
say 36 "[usbwatch]" "当前已连接的 USB 设备："

snap_now=$(snapshot)
printf '%s\n' "$snap_now" | tr ' ' '\n' | grep -E 'idVendor|idProduct' | paste - - 2>/dev/null | while read -r line; do
    printf '                %s\n' "$line"
done

echo
say 36 "[usbwatch]" "等待新设备接入..."

prev="$snap_now"
while [ "$(date +%s)" -lt "$END" ]; do
    cur=$(snapshot)
    if [ "$cur" != "$prev" ]; then
        echo
        if printf '%s' "$cur" | grep -qiE 'kindle|amazon'; then
            say 32 ">>> 找到 Kindle！" ""
            printf '%s\n' "$cur" | tr ' ' '\n' | grep -E 'idVendor|idProduct|USB' | paste - - 2>/dev/null | sed 's/^/    /'
        elif [ -n "$cur" ] && [ ${#cur} -gt ${#prev} ]; then
            say 33 ">>> USB 有变化（不是 Kindle）：" ""
            printf '%s\n' "$cur" | tr ' ' '\n' | grep -E 'idVendor|idProduct|USB' | paste - - 2>/dev/null | sed 's/^/    /'
        else
            say 90 ">>> 设备已拔出" ""
        fi
        prev="$cur"
    fi
    sleep 1
done

echo
say 36 "[usbwatch]" "监视结束。"
say 36 "[usbwatch]" "如果全程只看到充电图标、终端无变化 —— 那根线是充电线（无数据）。"
