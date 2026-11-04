#!/bin/sh
# ============================================================================
# kindle-dash U 盘健康守护
#
#   部署位置: /jffs/scripts/usb-guard.sh   (故意不放 U 盘: 盘崩了脚本还要能跑)
#   调用方式: cron 每 2 分钟 */2 * * * * sh /jffs/scripts/usb-guard.sh
#            或插件页『立即检测』(kindledash_config.sh usbguard)
#
# 检测三件事:
#   1) 块设备 /dev/sda1 是否存在      (掉盘: USB 枚举丢失)
#   2) /tmp/mnt/KINDLEDASH 是否挂着   (重启后 post-mount 没跑、被 umount)
#   3) 挂载点是否真的可写            (IO 错误 → ext4 自动 remount-ro, 只读)
#
# 恢复分级:
#   - 只读       → mount -o remount,rw
#   - 只读失败   → 停 cron → 卸载 → e2fsck -y → 重新挂载
#   - 未挂载     → 直接挂载, 失败则同上 fsck 流程
#   - 设备消失   → SCSI rescan → (必要时)USB 端口 authorized 0/1 复位 → 再挂载
#   恢复成功后统一收尾: bind /tmp/opt、补 crond、重注册 cron、推一屏
#
# 依赖全部来自固件自身 (busybox + /usr/sbin/e2fsck), 不碰 /opt —— U 盘挂掉时
# Entware 整棵树不可用, 任何依赖 /opt/bin 的修复手段都会一起失效。
#
# 日志: /jffs/kindle-dash-usb.log (超过 200KB 自动截尾)
# 状态: dbus kindledash_usbguard = "OK 03:12" / "FIXED:fsck 03:12" / "DOWN 03:12"
#       只在状态变化或发生动作时写, 避免每 2 分钟写一次 nvram
# 退出码: 0 正常 / 1 已自动修复 / 2 无法恢复
#
# 还原: cru d kindle-usbguard; rm /jffs/scripts/usb-guard.sh
# ============================================================================

MNT=${USBGUARD_MNT:-/tmp/mnt/KINDLEDASH}
DEV=${USBGUARD_DEV:-/dev/sda1}
LOCK=/tmp/.usbguard.lock
STATE=/tmp/.usbguard.state          # 上次状态 + 时间戳 (tmpfs, 重启失效无妨)
TRY=/tmp/.usbguard.try              # 上次"动手修复"的时间戳 (fsck 节流用)
LOG=/jffs/kindle-dash-usb.log
MAXLOG=204800
QUIET_SEC=1800                      # 同状态日志节流 (30 分钟)

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

rotate_log() {
  [ -f "$LOG" ] || return 0
  sz=$(wc -c < "$LOG" 2>/dev/null || echo 0)
  if [ "${sz:-0}" -gt "$MAXLOG" ]; then
    tail -c 60000 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
  fi
}

# 带超时执行 (busybox 没有 timeout): to <秒> <命令...>
to() {
  _s=$1; shift
  "$@" & _p=$!
  _i=0
  while kill -0 "$_p" 2>/dev/null; do
    _i=$((_i + 1))
    if [ "$_i" -ge "$_s" ]; then
      kill -9 "$_p" 2>/dev/null
      wait "$_p" 2>/dev/null
      return 124
    fi
    sleep 1
  done
  wait "$_p"
}

dev_ok()  { [ -b "$DEV" ]; }
mounted() { mount 2>/dev/null | grep -q " on $MNT "; }
RWTS=/tmp/.usbguard.rwts            # 上次真实写测时间
# 可写检测: 平时只看挂载选项(ext4 遇 IO 错误会 remount-ro, 选项立刻变 ro);
# 每 30 分钟才真写一次小文件 —— 墨水屏副屏是 7x24 长跑, 每 2 分钟写一次 U 盘
# 会白白消耗闪存寿命
rw_flag() { mount 2>/dev/null | grep " on $MNT " | grep -q "(ro," && return 1; return 0; }
rw_ok() {
  rw_flag || return 1
  _t=$(cat "$RWTS" 2>/dev/null)
  case "$_t" in ''|*[!0-9]*) _t=0;; esac
  if [ $(( $(date +%s) - _t )) -ge 1800 ]; then
    date +%s > "$RWTS" 2>/dev/null
    to 10 sh -c ": > '$MNT/.kd_rwtest'" 2>/dev/null || return 1
    to 10 rm -f "$MNT/.kd_rwtest" 2>/dev/null
  fi
  return 0
}

# 修复动作节流: 同一故障 15 分钟内不重复动手 (fsck 尤其不能连环跑)
in_throttle() {
  _t=$(cat "$TRY" 2>/dev/null)
  case "$_t" in ''|*[!0-9]*) return 1;; esac
  [ $(( $(date +%s) - _t )) -lt 900 ]
}
mark_try() { date +%s > "$TRY" 2>/dev/null; }

set_state() {                        # set_state <VERB> <detail>
  _v="$1"; _d=$2
  _now=$(date +%s)
  _old=$(cat "$STATE" 2>/dev/null)
  _olds=$(echo "$_old" | cut -d'|' -f1)
  _oldt=$(echo "$_old" | cut -d'|' -f2)
  case "$_oldt" in ''|*[!0-9]*) _oldt=0;; esac
  echo "${_v}|${_now}" > "$STATE" 2>/dev/null
  # 状态没变且未超节流窗口 → 不写 dbus、不记日志
  if [ "$_olds" = "$_v" ] && [ $((_now - _oldt)) -lt $QUIET_SEC ]; then
    return 0
  fi
  dbus set kindledash_usbguard="${_v} $(date '+%H:%M')" 2>/dev/null
  [ -n "$_d" ] && log "[$_v] $_d"
}

do_mount() {
  mkdir -p "$MNT" 2>/dev/null
  to 30 mount -t ext3 "$DEV" "$MNT" 2>>"$LOG" && return 0
  to 30 mount "$DEV" "$MNT" 2>>"$LOG" && return 0
  return 1
}

# 只读 / 挂载失败 → 停服务、卸载、fsck、重挂
do_fsck() {
  log "开始 fsck $DEV (先停 cron 与渲染进程)"
  sync
  cru d kindle-dash 2>/dev/null
  killall -q python3 dbclient 2>/dev/null
  sleep 1
  if mounted; then
    to 20 umount "$MNT" 2>>"$LOG" || to 20 umount -l "$MNT" 2>>"$LOG"
    sleep 1
  fi
  if mounted; then
    # 还有进程把 cwd 留在盘上 → 逐个清掉再试一次 (跳过自己)
    for _p in /proc/[0-9]*; do
      _pid=${_p#/proc/}
      [ "$_pid" = "$$" ] && continue
      _cwd=$(readlink "$_p/cwd" 2>/dev/null)
      case "$_cwd" in
        "$MNT"*|/opt/*) kill -9 "$_pid" 2>/dev/null;;
      esac
    done
    sleep 1
    to 20 umount "$MNT" 2>>"$LOG"
    sleep 1
  fi
  if mounted; then
    log "umount 失败(仍被占用), 放弃 fsck 以免损坏文件系统"
    return 1
  fi
  to 240 /usr/sbin/e2fsck -y "$DEV" >>"$LOG" 2>&1
  _rc=$?
  log "e2fsck 退出码 $_rc"
  [ "$_rc" -eq 124 ] && log "e2fsck 超时(240s), 可能盘体故障"
  do_mount || { log "fsck 后仍无法挂载 $DEV"; return 1; }
  log "fsck 完成并重新挂载成功"
  return 0
}

# 设备节点消失: 只做"软重扫"(scsi rescan + mdev), 不做硬件层复位。
# 重要教训: 曾用 authorized 0/1 复位 U 盘所在 USB 端口, 实测会让整机重启
# (路由器断网 20~40 秒), 代价远大于收益 —— 掉盘到需要硬件复位的程度时,
# 正确做法是提示用户重新插拔, 而不是拿整台路由器的网络去赌。
try_reattach() {
  for d in /sys/bus/scsi/devices/*; do
    [ -f "$d/rescan" ] && echo 1 > "$d/rescan" 2>/dev/null
  done
  command -v mdev >/dev/null 2>&1 && mdev -s 2>/dev/null
  sleep 3
  dev_ok && return 0
  sleep 2
  command -v mdev >/dev/null 2>&1 && mdev -s 2>/dev/null
  dev_ok
}

# 恢复成功后的统一收尾: /opt 绑定、crond、cron 注册、推一屏
post_recover() {
  if ! mount 2>/dev/null | grep -q " on /tmp/opt "; then
    mkdir -p /tmp/opt 2>/dev/null
    mount -o bind "$MNT" /tmp/opt 2>>"$LOG" && log "已重新 bind $MNT -> /tmp/opt"
  fi
  [ -x /opt/bin/python3 ] || log "[warn] /opt/bin/python3 仍不可用, Entware 可能不完整"

  ps w 2>/dev/null | grep -q '[c]rond' || { /usr/sbin/crond -b -l 8 2>/dev/null; log "crond 未运行, 已补启"; }

  _iv=$(dbus get kindledash_refresh 2>/dev/null)
  case "$_iv" in ''|*[!0-9]*) _iv=15;; esac
  [ "$_iv" -lt 3 ] && _iv=3
  cru d kindle-dash 2>/dev/null
  cru a kindle-dash "*/$_iv * * * * /bin/sh /opt/kindle-dash/run.sh >> /opt/kindle-dash/run.log 2>&1"

  # Kindle 网卡也顺手拉一下 (U 盘恢复过程常伴随整机重启)
  if ifconfig usb0 >/dev/null 2>&1; then
    ifconfig usb0 2>/dev/null | grep -q "inet addr:" || \
      ifconfig usb0 192.168.2.1 netmask 255.255.255.0 up
  fi

  # 立刻补一屏, 后台跑, 不阻塞下次检查
  if [ -x /opt/kindle-dash/run.sh ] || [ -f /opt/kindle-dash/run.sh ]; then
    ( sh /opt/kindle-dash/run.sh >> /opt/kindle-dash/run.log 2>&1 ) &
  fi
}

# ---------------------------------------------------------------------------
# 单实例锁: cron 每 2 分钟 + 插件页手动点, 可能撞车; fsck 更不能并发
if ! mkdir "$LOCK" 2>/dev/null; then
  _lp=$(cat "$LOCK/pid" 2>/dev/null)
  if [ -n "$_lp" ] && kill -0 "$_lp" 2>/dev/null; then
    exit 0                      # 上一轮还在跑, 本轮直接跳过
  fi
  rm -rf "$LOCK" 2>/dev/null    # 残留锁(进程已死)
  mkdir "$LOCK" 2>/dev/null || exit 0
fi
echo $$ > "$LOCK/pid"
trap 'rm -rf "$LOCK"' EXIT INT TERM

rotate_log

if dev_ok && mounted && rw_ok; then
  # 健康: 顺带体检"盘好但附属环境坏了"的情况 —— /opt 绑定丢失、crond 不在、
  # cron 任务丢失(重启后 crontab 在 tmpfs 里会没) 都曾实测踩过
  _need=0
  mount 2>/dev/null | grep -q " on /tmp/opt " || _need=1
  [ -d /opt/kindle-dash ] || _need=1
  [ -x /opt/bin/python3 ] || _need=1
  ps w 2>/dev/null | grep -q '[c]rond' || _need=1
  cru l 2>/dev/null | grep -q kindle-dash || _need=1
  if [ "$_need" = "1" ]; then
    in_throttle && exit 2          # 15 分钟内刚动过手, 不重复推屏
    mark_try
    log "盘正常但附属环境异常(/opt 绑定 / crond / cron 任务), 执行收尾修复"
    post_recover
    set_state "FIXED:env" "已自动修复: /opt 绑定 / crond / 定时任务"
    exit 1
  fi
  # 刚修复过的 30 分钟内保留 FIXED 提示, 让插件页看得到"刚刚自愈过"
  case "$(cat "$STATE" 2>/dev/null)" in
    FIXED:*)
      _ot=$(cut -d'|' -f2 "$STATE" 2>/dev/null)
      case "$_ot" in ''|*[!0-9]*) _ot=0;; esac
      [ $(( $(date +%s) - _ot )) -lt $QUIET_SEC ] && exit 0
      ;;
  esac
  set_state OK ""
  exit 0
fi

# ---- 异常: 记清是哪一种 ----
_d="dev=$(dev_ok && echo yes || echo no) mount=$(mounted && echo yes || echo no)"
if dev_ok && mounted; then
  _d="$_d rw=no"
else
  _d="$_d rw=-"
fi
log "检测到异常: $_d"

_repaired=0
_allow_fsck=1
in_throttle && _allow_fsck=0        # 15 分钟内已经 fsck 过: 本轮只做轻量重试

if ! dev_ok; then
  log "块设备 $DEV 不存在, 尝试重新枚举 USB"
  try_reattach && log "USB 重新枚举成功, $DEV 已回来"
fi

if dev_ok; then
  if mounted; then
    if ! rw_ok; then
      log "挂载点不可写(多半是 IO 错误导致只读), 先试 remount rw"
      to 20 mount -o remount,rw "$MNT" 2>>"$LOG"
      if rw_ok; then
        _repaired=1
        _why="remount"
      elif [ "$_allow_fsck" = "1" ]; then
        mark_try
        do_fsck && { _repaired=1; _why="fsck"; }
      else
        log "只读且处于 fsck 节流窗口, 本轮跳过"
      fi
    fi
  else
    log "未挂载, 尝试挂载"
    if do_mount && rw_ok; then
      _repaired=1
      _why="mount"
    elif [ "$_allow_fsck" = "1" ]; then
      mark_try
      do_fsck && { _repaired=1; _why="fsck"; }
    else
      log "挂载失败且处于 fsck 节流窗口, 本轮跳过"
    fi
  fi
fi

if [ "$_repaired" = "1" ] && dev_ok && mounted && rw_ok; then
  post_recover
  set_state "FIXED:$_why" "已恢复 ($_why)"
  log "恢复完成: $_why"
  exit 1
fi

# 未能恢复: fsck 时删过 cron, 这里至少把状态说清楚
set_state DOWN "无法自动恢复 ($_d), 可能需要重新插拔 U 盘或更换盘"
exit 2
