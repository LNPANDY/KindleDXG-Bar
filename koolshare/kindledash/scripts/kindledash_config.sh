#!/bin/sh
# ============================================================================
# Kindle 仪表盘 - 软件中心后端
# _api 调用约定: $1=ajax id, $2=action (apply / render)
# 日志: /tmp/upload/kindledash_log.txt, 结束标记 XU6J03M6
# ============================================================================
source /koolshare/scripts/base.sh
# httpds 传下来的 LD_LIBRARY_PATH=/lib:/usr/lib:/lib/aarch64 会让 Entware
# python3 加载固件老 glibc 而崩溃 (GLIBC_2.26 not found), 必须清掉
unset LD_LIBRARY_PATH
LOG_FILE=/tmp/upload/kindledash_log.txt
ACTION=$2

# 用 dbus 当前值重生成 config.json
gen_conf() {
  local PY=/opt/bin/python3
  [ -x "${PY}" ] || PY=/usr/bin/python3
  ${PY} /koolshare/scripts/kindledash_genconf.py 2>&1 | tee -a ${LOG_FILE}
}

# 按配置的刷新频率重注册 cron
re_cron() {
  local REFRESH=$(dbus get kindledash_refresh)
  [ -z "${REFRESH}" ] && REFRESH=15
  cru d kindle-dash 2>/dev/null
  cru a kindle-dash "*/${REFRESH} * * * * /bin/sh /opt/kindle-dash/run.sh >> /opt/kindle-dash/run.log 2>&1"
  echo_date "定时任务已更新: 每 ${REFRESH} 分钟刷新一次" | tee -a ${LOG_FILE}
}

# 立即渲染+推送一轮
render_now() {
  if [ ! -d /opt/kindle-dash ] || [ ! -x /opt/bin/python3 ]; then
    echo_date "错误: /opt/kindle-dash 不存在或 Entware python3 未就绪 (U 盘没插?)" | tee -a ${LOG_FILE}
    return 1
  fi
  echo_date "开始渲染并推送到 Kindle ..." | tee -a ${LOG_FILE}
  /bin/sh /opt/kindle-dash/run.sh >> ${LOG_FILE} 2>&1
  local RC=$?
  if [ "${RC}" == "0" ]; then
    echo_date "本轮推送完成" | tee -a ${LOG_FILE}
  else
    echo_date "本轮推送失败 (exit=${RC}), 详见上方日志" | tee -a ${LOG_FILE}
  fi
  return ${RC}
}

# 一键检测交易对: check_coin <SYMBOL>, 结果写 dbus kindledash_coincheck(_ts)
check_coin() {
  local SYM=$(echo "${1}" | tr -cd 'A-Za-z0-9' | tr 'a-z' 'A-Z')
  if [ -z "${SYM}" ]; then
    dbus set kindledash_coincheck="EMPTY"
    dbus set kindledash_coincheck_ts=$(date +%s)
    return 1
  fi
  local C=/usr/sbin/curl
  [ -x "${C}" ] || C=$(which curl)
  local R="binance:no"
  # 1) Binance 官方镜像 (数据格式同 api.binance.com, 国内直连)
  local code=$($C -s -o /dev/null -w "%{http_code}" --max-time 8 \
    "https://data-api.binance.vision/api/v3/ticker/24hr?symbol=${SYM}USDT" 2>/dev/null)
  [ "${code}" == "200" ] && R="binance:yes"
  # 2) CoinGecko (search 接口按代码模糊匹配)
  local cg=$($C -sL --max-time 8 -H "User-Agent: Mozilla/5.0" \
    "https://api.coingecko.com/api/v3/search?query=${SYM}" 2>/dev/null | grep -c "\"id\"")
  R="${R}|coingecko:$([ "${cg:-0}" -ge 1 ] && echo yes || echo no)"
  # 3) Gate.io
  local gt=$($C -s --max-time 8 \
    "https://api.gateio.ws/api/v4/spot/tickers?currency_pair=${SYM}_USDT" 2>/dev/null | head -c 20)
  R="${R}|gate:$(echo "${gt}" | grep -q "currency_pair" && echo yes || echo no)"
  dbus set kindledash_coincheck="${SYM}|${R}"
  dbus set kindledash_coincheck_ts=$(date +%s)
  echo_date "检测 ${SYM}: ${R}" | tee -a ${LOG_FILE}
}

# ---------------------------------------------------------------------------
# 环境自检: 只读检查全部依赖, 结果写 dbus kindledash_envcheck(_ts)
# 格式: entware:yes|python:yes|pillow:yes|fonts:yes|app:yes|cron:yes|kindle:yes|net:yes
doctor() {
  local C=/usr/sbin/curl; [ -x "${C}" ] || C=$(which curl)
  local R=""
  # 1) Entware (opkg 可用)
  if [ -x /opt/bin/opkg ]; then R="entware:yes"; else R="entware:no"; fi
  # 2) Python3
  if [ -x /opt/bin/python3 ]; then R="${R}|python:yes"; else R="${R}|python:no"; fi
  # 3) Pillow
  local pil=no
  if [ -x /opt/bin/python3 ]; then
    /opt/bin/python3 -c "import PIL" >/dev/null 2>&1 && pil=yes
  fi
  R="${R}|pillow:${pil}"
  # 4) 中文字体
  local f=yes
  [ -s /opt/kindle-dash/fonts/NotoSansCJKsc-Regular.otf ] || f=no
  [ -s /opt/kindle-dash/fonts/NotoSansCJKsc-Bold.otf ] || f=no
  R="${R}|fonts:${f}"
  # 5) 程序文件
  local a=yes
  for x in dashboard.py run.sh push.sh config.json; do
    [ -s /opt/kindle-dash/${x} ] || a=no
  done
  R="${R}|app:${a}"
  # 6) 定时任务
  R="${R}|cron:$(cru l 2>/dev/null | grep -q kindle-dash && echo yes || echo no)"
  # 7) Kindle 连通
  local k=no
  ping -c 1 -W 2 192.168.2.2 >/dev/null 2>&1 && k=yes
  R="${R}|kindle:${k}"
  # 8) 外网数据源 (Binance 官方镜像, 国内直连)
  local code=$(${C} -s -o /dev/null -w "%{http_code}" --max-time 6 \
    "https://data-api.binance.vision/api/v3/ping" 2>/dev/null)
  R="${R}|net:$([ "${code}" == "200" ] && echo yes || echo no)"
  dbus set kindledash_envcheck="${R}"
  dbus set kindledash_envcheck_ts=$(date +%s)
  echo_date "环境自检: ${R}" | tee -a ${LOG_FILE}
}

# ---------------------------------------------------------------------------
# 一键安装依赖: Entware → Python3+Pillow → 字体 → 程序文件 → cron
# 唯一前提: U 盘有 ext2/ext3/ext4 分区并已挂到 /tmp/opt (格式化属破坏性操作,
# 不代做, 日志里给出指引)。全部步骤幂等, 可反复执行。
provision() {
  local C=/usr/sbin/curl; [ -x "${C}" ] || C=$(which curl)
  echo_date "======================= 一键安装依赖 (可反复执行) =======================" | tee -a ${LOG_FILE}

  # ---- 1. Entware ----
  if [ ! -x /opt/bin/opkg ]; then
    echo_date "【1/4】未检测到 Entware, 尝试自动安装..." | tee -a ${LOG_FILE}
    if ! mount | grep -qE "on /tmp/opt type (ext2|ext3|ext4)"; then
      echo_date "✗ 没有 ext2/ext3/ext4 分区挂载在 /tmp/opt。" | tee -a ${LOG_FILE}
      echo_date "  请先做一次性准备 (二选一, 均会清空 U 盘数据):" | tee -a ${LOG_FILE}
      echo_date "  a) SSH 登录路由器执行 amtm → 选 Entware 安装;" | tee -a ${LOG_FILE}
      echo_date "  b) 软件中心安装『USB 应用』插件格式化 U 盘为 ext4。" | tee -a ${LOG_FILE}
      echo_date "  完成后重新点『一键安装依赖』即可继续。" | tee -a ${LOG_FILE}
      return 1
    fi
    local EW
    case "$(uname -m)" in
      aarch64) EW=aarch64-k3.10 ;;
      armv7l)  EW=armv7sf-k3.2 ;;
      x86_64)  EW=x64-k3.2 ;;
      mipsel)  EW=mipselsf-k3.4 ;;
      *) echo_date "✗ 不支持的架构: $(uname -m)" | tee -a ${LOG_FILE}; return 1 ;;
    esac
    ${C} -s --max-time 60 -o /tmp/kd_entware_install.sh \
      "http://bin.entware.net/${EW}/installer/entware_install.sh" || {
      echo_date "✗ 下载 Entware 安装脚本失败 (bin.entware.net 不可达)" | tee -a ${LOG_FILE}; return 1; }
    echo_date "  开始安装 Entware (${EW}), 视网络约 1~5 分钟..." | tee -a ${LOG_FILE}
    sh /tmp/kd_entware_install.sh >> ${LOG_FILE} 2>&1
    [ -x /opt/bin/opkg ] || { echo_date "✗ Entware 安装未成功, 详见日志" | tee -a ${LOG_FILE}; return 1; }
    echo_date "  ✓ Entware 就绪" | tee -a ${LOG_FILE}
  else
    echo_date "【1/4】Entware 已就绪, 跳过" | tee -a ${LOG_FILE}
  fi

  # ---- 2. Python3 + Pillow ----
  if [ ! -x /opt/bin/python3 ]; then
    echo_date "【2/4】安装 Python3 (opkg, 约 1~3 分钟)..." | tee -a ${LOG_FILE}
    /opt/bin/opkg update >> ${LOG_FILE} 2>&1
    /opt/bin/opkg install python3 python3-pip >> ${LOG_FILE} 2>&1
    [ -x /opt/bin/python3 ] || { echo_date "✗ Python3 安装失败, 详见日志" | tee -a ${LOG_FILE}; return 1; }
  else
    echo_date "【2/4】Python3 已就绪, 检查 Pillow..." | tee -a ${LOG_FILE}
  fi
  if ! /opt/bin/python3 -c "import PIL" >/dev/null 2>&1; then
    echo_date "  安装 Pillow (pip 二进制轮子, 约 1~3 分钟)..." | tee -a ${LOG_FILE}
    # 优先清华镜像(国内直连稳定), 失败再试官方源
    /opt/bin/pip3 install --no-cache-dir -i https://pypi.tuna.tsinghua.edu.cn/simple Pillow >> ${LOG_FILE} 2>&1 \
      || /opt/bin/pip3 install --no-cache-dir Pillow >> ${LOG_FILE} 2>&1
    /opt/bin/python3 -c "import PIL" >/dev/null 2>&1 \
      || { echo_date "✗ Pillow 安装失败, 详见日志" | tee -a ${LOG_FILE}; return 1; }
  fi
  echo_date "  ✓ Python3 + Pillow 就绪" | tee -a ${LOG_FILE}

  # ---- 3. 中文字体 (从项目 Release 下载, 共约 33MB) ----
  if [ ! -s /opt/kindle-dash/fonts/NotoSansCJKsc-Regular.otf ] || \
     [ ! -s /opt/kindle-dash/fonts/NotoSansCJKsc-Bold.otf ]; then
    echo_date "【3/4】下载中文字体 (约 33MB, 视带宽 1~5 分钟)..." | tee -a ${LOG_FILE}
    mkdir -p /opt/kindle-dash/fonts
    local FBASE="https://github.com/LNPANDY/KindleDXG-Bar/releases/download/v1.2.0"
    local F furl ok
    for F in NotoSansCJKsc-Regular.otf NotoSansCJKsc-Bold.otf; do
      ok=no
      for furl in "${FBASE}/${F}" "https://gh-proxy.com/${FBASE}/${F}" "https://ghproxy.net/${FBASE}/${F}"; do
        ${C} -fL --max-time 300 --retry 1 -o "/opt/kindle-dash/fonts/${F}" "${furl}" 2>/dev/null
        [ "$(wc -c < /opt/kindle-dash/fonts/${F} 2>/dev/null)" -gt 5000000 ] && { ok=yes; break; }
      done
      [ "${ok}" == "yes" ] || { echo_date "✗ 字体 ${F} 下载失败, 可手动下载后放到 /opt/kindle-dash/fonts/" | tee -a ${LOG_FILE}; return 1; }
      echo_date "  ✓ ${F}" | tee -a ${LOG_FILE}
    done
  else
    echo_date "【3/4】字体已就绪, 跳过" | tee -a ${LOG_FILE}
  fi

  # ---- 4. 程序文件 + 开机脚本 + cron (install.sh 已复制, 这里兜底) ----
  local APP=/koolshare/scripts/kindledash_app
  mkdir -p /opt/kindle-dash
  for x in dashboard.py run.sh push.sh; do
    [ -s /opt/kindle-dash/${x} ] || [ -s ${APP}/${x} ] && cp -f ${APP}/${x} /opt/kindle-dash/${x} 2>/dev/null
  done
  chmod +x /opt/kindle-dash/run.sh /opt/kindle-dash/push.sh 2>/dev/null
  [ -s /opt/kindle-dash/config.json ] || cp -f ${APP}/config.default.json /opt/kindle-dash/config.json
  echo_date "【4/4】注册开机自启与定时任务..." | tee -a ${LOG_FILE}
  [ -f /jffs/scripts/kindle-dash-start.sh ] || cp -f ${APP}/kindle-dash-start.sh /jffs/scripts/ 2>/dev/null
  chmod +x /jffs/scripts/kindle-dash-start.sh 2>/dev/null
  if [ -f /jffs/scripts/services-start ] && ! grep -q kindle-dash /jffs/scripts/services-start; then
    cat >> /jffs/scripts/services-start <<'APPEND'

# kindle-dash: 等 USB/Entware 就绪后注册 cron 与 usb0 (延迟 30s 幂等执行)
(sleep 30; /jffs/scripts/kindle-dash-start.sh) &
APPEND
  fi
  /jffs/scripts/kindle-dash-start.sh >/dev/null 2>&1
  echo_date "✓ 全部依赖就绪! 点『保存并应用』即可渲染推送第一屏。" | tee -a ${LOG_FILE}
  doctor
}

case ${ACTION} in
apply)
    true > ${LOG_FILE}
    echo_date "======================= Kindle 仪表盘 - 应用配置 =======================" | tee -a ${LOG_FILE}
    gen_conf
    re_cron
    render_now
    echo_date "=============================== 完成 ==================================" | tee -a ${LOG_FILE}
    echo "XU6J03M6" >> ${LOG_FILE}
    http_response "$1"
    ;;
render)
    true > ${LOG_FILE}
    echo_date "======================= Kindle 仪表盘 - 手动刷新 =======================" | tee -a ${LOG_FILE}
    render_now
    echo "XU6J03M6" >> ${LOG_FILE}
    http_response "$1"
    ;;
check_coin)
    check_coin "$3"
    http_response "$1"
    ;;
doctor)
    true > ${LOG_FILE}
    echo_date "======================= Kindle 仪表盘 - 环境自检 =======================" | tee -a ${LOG_FILE}
    doctor
    echo "XU6J03M6" >> ${LOG_FILE}
    http_response "$1"
    ;;
provision)
    true > ${LOG_FILE}
    provision
    echo "XU6J03M6" >> ${LOG_FILE}
    http_response "$1"
    ;;
*)
    http_response "$1"
    ;;
esac
