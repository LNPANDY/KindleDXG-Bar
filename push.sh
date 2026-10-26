#!/bin/sh
# ============================================================================
# 把渲染好的 PNG 推到 Kindle DXG 上并刷新屏幕 (双端通用)
#   - Mac/服务器: ssh + scp + 密钥 (~/.ssh/kindle_dxg_id_rsa)
#   - 路由器(Entware): dbclient(梅林自带, 仅命令通道) + 临时 HTTP 服务,
#     Kindle 用自带 busybox wget 拉取 + 远端 md5 校验
#     (dbclient 管道直传有缺陷: 固定丢失一个 4096 缓冲块导致文件损坏, 已弃用)
# 用法:  ./push.sh [图片路径]
# ============================================================================
DIR=$(cd "$(dirname "$0")" && pwd)

IMG="${1:-$DIR/dashboard.png}"
KINDLE_IP="${KINDLE_IP:-192.168.2.2}"
KINDLE_USER="${KINDLE_USER:-root}"
REMOTE_DIR="${REMOTE_DIR:-/mnt/us/dash}"
REMOTE_IMG="$REMOTE_DIR/dashboard.png"
EIPS="${EIPS:-/usr/sbin/eips}"

# 路由器环境: PATH 里有 Entware; 静默认证 (usbnet dropbear 不校验密码)
export PATH="/opt/bin:/opt/sbin:$PATH"
export DROPBEAR_PASSWORD="${DROPBEAR_PASSWORD:-kindle-dash}"

if [ -x /usr/bin/dbclient ]; then
  # ---------- 路由器模式: dbclient 命令通道 + HTTP 拉取 ----------
  DC="/usr/bin/dbclient -y -K 5"
  run_k() { $DC "$KINDLE_USER@$KINDLE_IP" "$@" </dev/null; }

  [ -f "$IMG" ] || { echo "[err] 找不到图片: $IMG" >&2; exit 1; }
  run_k "mkdir -p $REMOTE_DIR" || { echo "[err] ssh 连不上 Kindle" >&2; exit 4; }

  # 起临时 HTTP 服务 (绑定路由器 usb0, 传完即关)
  ROUTER_USB_IP="${ROUTER_USB_IP:-192.168.2.1}"
  HTTP_PORT="${HTTP_PORT:-8123}"
  IMG_DIR=$(dirname "$IMG"); IMG_NAME=$(basename "$IMG")
  /opt/bin/python3 -m http.server "$HTTP_PORT" --bind "$ROUTER_USB_IP" \
      --directory "$IMG_DIR" >/dev/null 2>&1 &
  HTTP_PID=$!
  trap 'kill $HTTP_PID 2>/dev/null' EXIT INT TERM
  sleep 1

  TMP_IMG="$REMOTE_DIR/.dashboard.tmp.png"
  LOCAL_MD5=$(md5sum "$IMG" | awk '{print $1}')
  REMOTE_MD5=$(run_k "wget -q -O $TMP_IMG http://$ROUTER_USB_IP:$HTTP_PORT/$IMG_NAME \
      && md5sum $TMP_IMG" | awk '{print $1}')

  if [ -z "$REMOTE_MD5" ]; then
    echo "[err] 传输失败 (wget 拉取出错)" >&2; exit 2
  elif [ "$REMOTE_MD5" != "$LOCAL_MD5" ]; then
    echo "[err] 传输损坏: 本地 $LOCAL_MD5 / 远端 $REMOTE_MD5" >&2; exit 2
  fi

  run_k "mv $TMP_IMG $REMOTE_IMG && sync" || { echo "[err] 落盘失败" >&2; exit 2; }
  run_k "$EIPS -f -g $REMOTE_IMG" || { echo "[err] eips 失败" >&2; exit 3; }
  echo "[ok] 已推送 $(wc -c < "$IMG") 字节 -> $KINDLE_IP (md5 校验通过)"
else
  # ---------- Mac/服务器模式: OpenSSH + 密钥 ----------
  SSH_KEY="${SSH_KEY:-$HOME/.ssh/kindle_dxg_id_rsa}"
  SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
  SSH_OPTS="$SSH_OPTS -oKexAlgorithms=+diffie-hellman-group1-sha1"
  SSH_OPTS="$SSH_OPTS -oHostKeyAlgorithms=+ssh-rsa -oPubkeyAcceptedAlgorithms=+ssh-rsa"
  SSH_OPTS="$SSH_OPTS -oCiphers=+aes128-cbc,3des-cbc,aes256-cbc,aes128-ctr"
  SSH_OPTS="$SSH_OPTS -oMACs=+hmac-sha1"
  [ -f "$SSH_KEY" ] && SSH_OPTS="$SSH_OPTS -i $SSH_KEY"

  if [ ! -f "$IMG" ]; then echo "[err] 找不到图片: $IMG" >&2; exit 1; fi
  # shellcheck disable=SC2086
  ssh $SSH_OPTS "$KINDLE_USER@$KINDLE_IP" "mkdir -p $REMOTE_DIR" \
    || { echo "[err] ssh 预建目录失败" >&2; exit 4; }
  # shellcheck disable=SC2086
  scp -O $SSH_OPTS "$IMG" "$KINDLE_USER@$KINDLE_IP:$REMOTE_IMG" >/dev/null 2>&1 \
    || { echo "[err] scp 失败" >&2; exit 2; }
  # shellcheck disable=SC2086
  ssh $SSH_OPTS "$KINDLE_USER@$KINDLE_IP" "$EIPS -f -g $REMOTE_IMG" \
    || { echo "[err] eips 失败" >&2; exit 3; }
  echo "[ok] 已推送 $(wc -c < "$IMG") 字节 -> $KINDLE_IP"
fi
