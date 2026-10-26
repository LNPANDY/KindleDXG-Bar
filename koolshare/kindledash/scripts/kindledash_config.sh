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
*)
    http_response "$1"
    ;;
esac
