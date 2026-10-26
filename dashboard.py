#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Kindle DX / DXG 墨水屏仪表盘渲染器 v3
-------------------------------------
数据源全部可通过 config.json / 软件中心插件配置:
  行情: Binance(镜像优先) / CoinGecko / Gate.io
  快讯: 新浪7×24 / 华尔街见闻 / 金十 / 东方财富 / 自定义RSS
  热榜: 微博 / 头条 / 知乎 / B站 / 百度 / 抖音
  模块顺序可调, 支持竖版(824x1200)与横版(内容1200x824旋转后适配竖屏)。

只依赖 Pillow, 网络与解析全用标准库, 方便在路由器(Entware)上跑。

用法:
    python3 dashboard.py --config config.json            # 正常渲染
    python3 dashboard.py --demo -o preview.png           # 假数据预览版式
    python3 dashboard.py --offline -o dashboard.png      # 用上次的缓存渲染
    python3 dashboard.py --landscape -o dashboard.png    # 强制横版(本次)
"""

import argparse
import http.cookiejar
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("缺少 Pillow。路由器上: opkg install python3 python3-pillow\n"
             "电脑上: pip install pillow")

HERE = os.path.dirname(os.path.abspath(__file__))
UA = "Mozilla/5.0 (compatible; kindle-dash/3.0; +eink dashboard)"
UA_PHONE = ("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) "
            "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1")
CST = timezone(timedelta(hours=8))

# 常见 CJK 字体候选路径(按平台), 找不到就用 config 里的 font_regular
FONT_CANDIDATES = [
    "fonts/NotoSansSC-Regular.ttf",
    "/opt/share/fonts/NotoSansSC-Regular.ttf",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/noto/NotoSansCJKsc-Regular.otf",
    "/System/Library/Fonts/PingFang.ttc",
    "/System/Library/Fonts/STHeiti Medium.ttc",
    "/Library/Fonts/Arial Unicode.ttf",
    "C:\\Windows\\Fonts\\msyh.ttc",
]

# 交易对固定池(软件中心 UI 从这里选), CoinGecko 需要 coin id 映射
COIN_POOL = ["BTC", "ETH", "SOL", "BNB", "XRP", "DOGE", "ADA", "DOT", "LINK", "LTC", "AVAX"]
SYMBOL2CGID = {
    "BTC": "bitcoin", "ETH": "ethereum", "SOL": "solana", "BNB": "binancecoin",
    "XRP": "ripple", "DOGE": "dogecoin", "ADA": "cardano", "DOT": "polkadot",
    "LINK": "chainlink", "LTC": "litecoin", "AVAX": "avalanche-2",
}

# 快讯源与热榜源的展示名
FASTNEWS_SOURCES = ["sina7x24", "wallstcn", "jin10", "eastmoney", "rss"]
FASTNEWS_NAMES = {"sina7x24": "新浪7×24", "wallstcn": "华尔街见闻", "jin10": "金十数据",
                  "eastmoney": "东方财富", "rss": "RSS订阅"}
HOT_SOURCES = ["weibo", "toutiao", "zhihu", "bilibili", "baidu", "douyin"]
HOT_NAMES = {"weibo": "微博", "toutiao": "头条", "zhihu": "知乎",
             "bilibili": "B站", "baidu": "百度", "douyin": "抖音"}
COIN_SOURCE_NAMES = {"binance": "Binance", "coingecko": "CoinGecko", "gate": "Gate.io"}

DEMO_COINS = [
    {"id": "bitcoin", "symbol": "BTC", "name": "Bitcoin",
     "price": 71234.5, "change": 2.31, "spark": [66000 + 800 * (i % 17) - 400 * (i % 7) for i in range(120)]},
    {"id": "ethereum", "symbol": "ETH", "name": "Ethereum",
     "price": 3512.88, "change": -1.42, "spark": [3600 - 12 * (i % 23) + 8 * (i % 5) for i in range(120)]},
    {"id": "solana", "symbol": "SOL", "name": "Solana",
     "price": 168.42, "change": 5.07, "spark": [140 + i * 0.35 - 3 * (i % 9) for i in range(120)]},
    {"id": "binancecoin", "symbol": "BNB", "name": "BNB",
     "price": 592.10, "change": 0.44, "spark": [585 + 2 * (i % 11) - (i % 4) for i in range(120)]},
    {"id": "ripple", "symbol": "XRP", "name": "XRP",
     "price": 0.5218, "change": -3.16, "spark": [0.55 - 0.0008 * i + 0.01 * (i % 6) for i in range(120)]},
]

DEMO_FASTNEWS = [
    {"time": "09:12", "title": "国产大模型价格战再升级, 多厂商宣布下调推理成本"},
    {"time": "10:45", "title": "半导体设备国产化率突破四成, 先进制程设备开始批量交付"},
    {"time": "11:30", "title": "英特尔发布新一代低功耗处理器, 主打边缘计算场景"},
    {"time": "13:05", "title": "研究显示电子墨水屏长时间显示静态内容仍存在残影风险"},
]
DEMO_HOT = {
    "weibo": [{"title": t, "extra": e} for t, e in [
        ("国产大模型价格战再升级", "312万"), ("Kindle DXG 改造意外爆火", "268万"),
        ("新能源车渗透率再创新高", "201万"), ("卫星互联网建设提速", "189万")]],
    "toutiao": [{"title": t, "extra": e} for t, e in [
        ("长鑫存储硬气拒绝苹果", "890万"), ("美联储降息预期升温", "663万"),
        ("iPhone 18 或采用屏下 Face ID", "512万"), ("养老金迎来新调整", "433万")]],
    "zhihu": [{"title": t, "extra": e} for t, e in [
        ("如何看待新一代载人飞船试验成功", "热"), (" ereader 市场为何逆势增长", "沸"),
        ("墨水屏刷新技术突破意味着什么", "热"), ("副屏会成为桌面标配吗", "")]],
    "bilibili": [{"title": t, "extra": e} for t, e in [
        ("电子墨水屏改造实录", "96万"), ("开源固件刷机指南", "87万"),
        ("DIY 副屏的正确姿势", "76万"), ("墨水屏极简主义桌面", "65万")]],
    "baidu": [{"title": t, "extra": e} for t, e in [
        ("新征程上推进全面从严治党", "498万"), ("神舟舰队新进展", "422万"),
        ("国内外金价再创新高", "398万"), ("医保新政策解读", "351万")]],
    "douyin": [{"title": t, "extra": e} for t, e in [
        ("Kimi致歉并公布补偿方案", "1211万"), ("墨水屏改造视频爆火", "986万"),
        ("电子纸概念股大涨", "842万"), ("极简桌面改造挑战", "733万")]],
}


# --------------------------------------------------------------------------
# 工具
# --------------------------------------------------------------------------
def http_get(url, timeout=12, retries=2, ua=None):
    last = None
    for attempt in range(retries + 1):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": ua or UA, "Accept": "*/*"})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read()
        except Exception as e:          # noqa: BLE001
            last = e
            time.sleep(1.5 * (attempt + 1))
    raise last


def strip_html(s):
    if not s:
        return ""
    s = re.sub(r"<[^>]+>", "", s)
    s = (s.replace("&nbsp;", " ").replace("&amp;", "&")
          .replace("&lt;", "<").replace("&gt;", ">")
          .replace("&quot;", '"').replace("&#39;", "'"))
    return re.sub(r"\s+", " ", s).strip()


def find_font(cfg_key, cfg):
    if cfg.get(cfg_key):
        p = cfg[cfg_key] if os.path.isabs(cfg[cfg_key]) else os.path.join(HERE, cfg[cfg_key])
        if os.path.exists(p):
            return p
        print(f"[warn] config 里的 {cfg_key} 不存在: {p}", file=sys.stderr)
    for rel in FONT_CANDIDATES:
        p = rel if os.path.isabs(rel) else os.path.join(HERE, rel)
        if os.path.exists(p):
            return p
    return None


def load_font(path, size):
    if path is None:
        return ImageFont.load_default()
    try:
        return ImageFont.truetype(path, size)
    except Exception:                   # noqa: BLE001
        return ImageFont.load_default()


# --------------------------------------------------------------------------
# 数据抓取: 加密货币 (binance / coingecko / gate)
# --------------------------------------------------------------------------
# Binance 官方公共行情镜像 data-api.binance.vision 与 api.binance.com 数据格式
# 完全一致, 但国内网络环境通常只有前者直连可达, 因此镜像优先、原站兜底
BINANCE_HOSTS = ("https://data-api.binance.vision", "https://api.binance.com")
GATE_BASE = "https://api.gateio.ws/api/v4"


def _binance_get(path):
    """依次尝试多个 Binance 域名, 返回第一个成功的响应体, 全挂则抛最后异常"""
    last = None
    for host in BINANCE_HOSTS:
        try:
            return http_get(host + path, timeout=10, retries=1)
        except Exception as e:             # noqa: BLE001
            print(f"[warn] {host} 失败: {e}", file=sys.stderr)
            last = e
    raise last


def _mk_coin(symbol, name, price, change):
    return {"id": SYMBOL2CGID.get(symbol, symbol.lower()),
            "symbol": symbol, "name": name or symbol,
            "price": price, "change": change, "spark": []}


def fetch_crypto_binance(pairs, vs="usd"):
    url = "/api/v3/ticker/24hr?symbols=" + urllib.parse.quote(
        "[" + ",".join(f'"{s}USDT"' for s in pairs) + "]")
    data = json.loads(_binance_get(url).decode("utf-8"))
    by_sym = {d["symbol"].replace("USDT", ""): d for d in data}
    return [_mk_coin(s, s, float(by_sym[s]["lastPrice"]),
                     float(by_sym[s]["priceChangePercent"]))
            for s in pairs if s in by_sym]


def fetch_crypto_gate(pairs, vs="usd"):
    data = json.loads(http_get(f"{GATE_BASE}/spot/tickers", timeout=10,
                               retries=1, ua=UA).decode("utf-8"))
    by_sym = {}
    for d in data:
        cp = d.get("currency_pair") or ""
        if cp.endswith("_USDT"):
            base = cp[:-5]
            if base in pairs and base not in by_sym:
                chg = d.get("change_percentage")
                by_sym[base] = (d.get("last"), float(chg) if chg else None)
    out = []
    for s in pairs:
        if s in by_sym:
            price, chg = by_sym[s]
            out.append(_mk_coin(s, s, float(price) if price else None, chg))
    return out


def fetch_crypto_cg(pairs, vs="usd"):
    ids = ",".join(SYMBOL2CGID[s] for s in pairs if s in SYMBOL2CGID)
    url = ("https://api.coingecko.com/api/v3/coins/markets"
           f"?vs_currency={vs}&ids={ids}&sparkline=false"
           "&price_change_percentage=24h")
    data = json.loads(http_get(url).decode("utf-8"))
    id2sym = {v: k for k, v in SYMBOL2CGID.items()}
    order = {s: i for i, s in enumerate(pairs)}
    out = []
    for c in data:
        sym = id2sym.get(c.get("id"), (c.get("symbol") or "").upper())
        out.append({"id": c.get("id"), "symbol": sym,
                    "name": c.get("name") or sym,
                    "price": c.get("current_price"),
                    "change": c.get("price_change_percentage_24h"),
                    "spark": []})
    out.sort(key=lambda x: order.get(x["symbol"], 999))
    return out


COIN_FETCHERS = {"binance": fetch_crypto_binance,
                 "coingecko": fetch_crypto_cg,
                 "gate": fetch_crypto_gate}


def fetch_crypto_mixed(cfg):
    """按币分源拉行情: crypto.pair_sources 指定某币走某源, 未指定走全局 source"""
    cr = cfg["crypto"]
    pairs = cr["pairs"]
    default_src = cr.get("source", "binance")
    overrides = cr.get("pair_sources") or {}

    groups = {}                            # src -> [sym...] 保持显示顺序
    for s in pairs:
        src = overrides.get(s) if overrides.get(s) in COIN_FETCHERS else default_src
        groups.setdefault(src, []).append(s)

    by_sym = {}
    for src, syms in groups.items():
        got = []
        try:
            got = COIN_FETCHERS[src](syms, cr["vs_currency"])
        except Exception as e:             # noqa: BLE001
            print(f"[warn] {src} 行情失败({','.join(syms)}): {e}", file=sys.stderr)
        if not got:                        # 该组整体换源兜底
            for alt in COIN_FETCHERS:
                if alt == src:
                    continue
                try:
                    got = COIN_FETCHERS[alt](syms, cr["vs_currency"])
                    break
                except Exception as e2:    # noqa: BLE001
                    print(f"[warn] {alt} 兜底失败: {e2}", file=sys.stderr)
        for c in got:
            by_sym[c["symbol"]] = c
    return [by_sym[s] for s in pairs if s in by_sym]


def fetch_curves(cfg, coins):
    """24h 曲线, 按每个币自己的行情源取 K 线(源失败依次回退其它源)"""
    cr = cfg.get("crypto", {})
    default_src = cr.get("source", "binance")
    overrides = cr.get("pair_sources") or {}
    vs = cr.get("vs_currency", "usd")
    for c in coins:
        sym = (c.get("symbol") or "").upper()
        first = overrides.get(sym) if overrides.get(sym) in ("binance", "gate", "coingecko") \
            else default_src
        chain = [first] + [s for s in ("binance", "gate", "coingecko") if s != first]
        vals = []
        for src in chain:
            try:
                if src == "binance":
                    raw = _binance_get(f"/api/v3/klines?symbol={sym}USDT&interval=15m&limit=96")
                    vals = [float(r[4]) for r in json.loads(raw.decode("utf-8"))]
                elif src == "gate":
                    raw = http_get(f"{GATE_BASE}/spot/candlesticks"
                                   f"?currency_pair={sym}_USDT&interval=15m&limit=96",
                                   timeout=10, retries=1)
                    vals = [float(r[2]) for r in json.loads(raw.decode("utf-8"))]
                else:
                    cid = c.get("id") or SYMBOL2CGID.get(sym)
                    raw = http_get(f"https://api.coingecko.com/api/v3/coins/"
                                   f"{cid}/market_chart?vs_currency={vs}&days=1",
                                   timeout=10, retries=1)
                    vals = [p[1] for p in
                            json.loads(raw.decode("utf-8")).get("prices") or []]
                if vals:
                    break
            except Exception as e:         # noqa: BLE001
                print(f"[warn] {src} 曲线失败 {sym}: {e}", file=sys.stderr)
        if len(vals) > 48:                     # 抽稀到 ~48 点
            vals = vals[:: len(vals) // 48 + 1]
        c["curve"] = vals


# --------------------------------------------------------------------------
# 数据抓取: 快讯 (sina7x24 / wallstcn / jin10 / eastmoney / rss)
# --------------------------------------------------------------------------
def fetch_sina_7x24(cfg):
    raw = http_get("https://zhibo.sina.com.cn/api/zhibo/feed"
                   "?page=1&page_size=12&zhibo_id=152&tag_id=0",
                   timeout=10, retries=1)
    d = json.loads(raw.decode("utf-8"))
    lst = (((d.get("result") or {}).get("data") or {}).get("feed") or {}) \
        .get("list") or []
    out = []
    for it in lst:
        txt = strip_html(it.get("rich_text") or "")
        if not txt:
            continue
        ct = it.get("create_time")
        if isinstance(ct, (int, float)) and ct > 1e9:
            tm = datetime.fromtimestamp(ct, CST).strftime("%H:%M")
        else:
            m = re.search(r"(\d{1,2}:\d{2})", str(ct or ""))
            tm = m.group(1) if m else ""
        out.append({"title": txt, "time": tm})
    return out


def fetch_wallstcn(cfg):
    d = json.loads(http_get(
        "https://api-one.wallstcn.com/apiv1/content/lives"
        "?channel=global-channel&limit=12", timeout=10, retries=1,
        ua=UA).decode("utf-8"))
    out = []
    for it in (d.get("data") or {}).get("items") or []:
        txt = strip_html(it.get("title") or it.get("content_text") or "")
        if not txt:
            continue
        dt = it.get("display_time")
        tm = datetime.fromtimestamp(dt, CST).strftime("%H:%M") \
            if isinstance(dt, (int, float)) and dt else ""
        out.append({"title": txt, "time": tm})
    return out


def fetch_jin10(cfg):
    raw = http_get("https://www.jin10.com/flash_newest.js",
                   timeout=10, retries=1, ua=UA).decode("utf-8", "ignore")
    m = re.search(r"= (\[.*\]);?\s*$", raw, re.S)
    arr = json.loads(m.group(1)) if m else []
    out = []
    for it in arr:
        data = it.get("data") or {}
        txt = strip_html(data.get("title") or data.get("content") or "")
        if not txt:
            continue
        m2 = re.search(r"(\d{1,2}:\d{2})", str(it.get("time") or ""))
        out.append({"title": txt, "time": m2.group(1) if m2 else ""})
    return out


def fetch_eastmoney(cfg):
    d = json.loads(http_get(
        "https://np-listapi.eastmoney.com/comm/web/getFastNewsList"
        "?client=web&biz=web_724&fastColumn=102&sortEnd=&pageSize=12"
        f"&req_trace={int(time.time() * 1000)}",
        timeout=10, retries=1, ua=UA).decode("utf-8"))
    out = []
    for it in (d.get("data") or {}).get("fastNewsList") or []:
        txt = strip_html(it.get("summary") or it.get("title") or "")
        if not txt:
            continue
        m = re.search(r"(\d{1,2}:\d{2})", str(it.get("showTime") or ""))
        out.append({"title": txt, "time": m.group(1) if m else ""})
    return out


def _rss_titles(url):
    """拉一个 RSS 源的标题列表 (兼容各种残破 XML)"""
    raw = http_get(url, timeout=10, retries=1)
    try:
        root = ET.fromstring(raw)
        titles = []
        for node in root.iter():
            if node.tag.split("}")[-1] != "item":
                continue
            for ch in node:
                if ch.tag.split("}")[-1] == "title":
                    titles.append(strip_html(ch.text))
                    break
    except ET.ParseError:
        # 不少中文站点的 RSS 有未转义的 & 或裸 <, XML 解析会炸,
        # 退回正则抓 <item><title> 就够用了
        titles = [strip_html(t.decode("utf-8", "ignore")) for t in
                  re.findall(rb"<item[\s\S]*?<title[^>]*>([\s\S]*?)</title>",
                             raw, re.IGNORECASE)]
        titles = [t for t in titles if t]
    return titles


def fetch_news(cfg):
    """RSS 池。fastnews.rotate=true 时启用渠道轮播:
    - 每次刷新从「上次消费完的下一个渠道」开始 (各渠道轮流上屏)
    - 某渠道的新词条 (近期未展示过) 不足以凑满条数 → 自动轮到下一个渠道
    - 凑满即停; 全部轮完仍不足, 用抓到的最新词条兜底补齐 (避免开天窗)
    - 轮播进度与已展示历史 (防重复) 存 cfg['_fn_state'], 由 main 写回缓存
    """
    feeds = cfg.get("fastnews", {}).get("feeds") or cfg.get("feeds") or []
    if not feeds:
        return []
    need = max(1, int(cfg.get("fastnews", {}).get("count", 4)))
    st = cfg.get("_fn_state") or {}
    rotate = bool(cfg.get("fastnews", {}).get("rotate"))
    history = list(st.get("history") or [])
    hist = set(history)
    start = int(st.get("idx", 0)) % len(feeds) if (rotate and feeds) else 0
    order = list(range(len(feeds)))
    order = order[start:] + order[:start]

    items, seen = [], set()
    pool_recent = []                       # 本轮抓到的全部 (title, source), 兜底用
    consumed = 0                           # 本轮消费的渠道数 → 下次轮播起点
    for fi in order:
        f = feeds[fi]
        name = f.get("name", "RSS")
        try:
            titles = [t for t in _rss_titles(f["url"]) if t]
        except Exception as e:             # noqa: BLE001
            print(f"[warn] RSS 失败 {name}: {e}", file=sys.stderr)
            consumed += 1
            continue
        pool_recent.extend((t, name) for t in titles)
        consumed += 1
        if rotate:
            fresh = [t for t in titles if t not in hist and t not in seen]
            for t in fresh:
                if len(items) >= need:
                    break
                seen.add(t)
                items.append({"source": name, "title": t, "link": ""})
            if len(items) >= need:
                break                      # 凑满, 停止轮播
            # 该渠道新词条不够 → 继续轮到下一个渠道
        else:
            for t in titles:
                if t not in seen:
                    seen.add(t)
                    items.append({"source": name, "title": t, "link": ""})

    if rotate and len(items) < need:
        for t, name in pool_recent:        # 兜底补齐: 宁可重复也不开天窗
            if len(items) >= need:
                break
            if t not in seen:
                seen.add(t)
                items.append({"source": name, "title": t, "link": ""})

    if rotate:
        history.extend(it["title"] for it in items)
        st["history"] = history[-80:]
        st["idx"] = (start + consumed) % len(feeds)
        cfg["_fn_state"] = st
    return items


FASTNEWS_FETCHERS = {"sina7x24": fetch_sina_7x24, "wallstcn": fetch_wallstcn,
                     "jin10": fetch_jin10, "eastmoney": fetch_eastmoney,
                     "rss": fetch_news}


# --------------------------------------------------------------------------
# 数据抓取: 热榜 (weibo / toutiao / zhihu / bilibili / baidu / douyin)
# --------------------------------------------------------------------------
def fetch_weibo_hot(cfg):
    """微博热搜: 两步走, 先访问首页拿 Cookie 再调侧栏接口 (无登录可用)"""
    jar = http.cookiejar.CookieJar()
    op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    ua = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
          "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36")
    op.open(urllib.request.Request("https://weibo.com/",
                                   headers={"User-Agent": ua}), timeout=10)
    req = urllib.request.Request(
        "https://weibo.com/ajax/side/hotSearch",
        headers={"User-Agent": ua, "Referer": "https://s.weibo.com/",
                 "Accept": "application/json"})
    d = json.loads(op.open(req, timeout=10).read().decode("utf-8"))
    real = (d.get("data") or {}).get("realtime") or []
    out = []
    for it in real:
        if it.get("is_ad"):
            continue
        word = strip_html(it.get("word") or "").strip("#").strip()
        if not word:
            continue
        num = it.get("num")
        heat = (f"{num / 10000:.0f}万"
                if isinstance(num, (int, float)) and num else "")
        out.append({"title": word, "extra": it.get("label_name") or ""})
    return out


def fetch_toutiao_hot(cfg):
    raw = http_get("https://www.toutiao.com/hot-event/hot-board/"
                   "?origin=toutiao_pc", timeout=10, retries=1)
    d = json.loads(raw.decode("utf-8"))
    out = []
    for it in (d.get("data") or []):
        t = strip_html(it.get("Title") or "")
        if not t:
            continue
        out.append({"title": t})
    return out


_ZHIHU_LABEL = {"boiling": "热", "explosion": "爆", "fire": "沸", "recommand": "荐"}


def fetch_zhihu_hot(cfg):
    d = json.loads(http_get("https://api.zhihu.com/topstory/hot-list?limit=50",
                            timeout=10, retries=1, ua=UA_PHONE).decode("utf-8"))
    out = []
    for it in d.get("data") or []:
        t = strip_html((it.get("target") or {}).get("title") or "")
        if not t:
            continue
        label = (it.get("card_label") or {}).get("type") or ""
        extra = _ZHIHU_LABEL.get(label, "")
        out.append({"title": t, "extra": extra})
    return out


def fetch_bilibili_hot(cfg):
    d = json.loads(http_get(
        "https://api.bilibili.com/x/web-interface/search/square?limit=50"
        "&open_super=0", timeout=10, retries=1, ua=UA_PHONE).decode("utf-8"))
    lst = ((d.get("data") or {}).get("trending") or {}).get("list") or []
    return [{"title": strip_html(it.get("show_name") or it.get("keyword") or "")}
            for it in lst
            if strip_html(it.get("show_name") or it.get("keyword") or "")]


def fetch_baidu_hot(cfg):
    d = json.loads(http_get("https://top.baidu.com/api/board?platform=wise&tab=realtime",
                            timeout=10, retries=1, ua=UA_PHONE).decode("utf-8"))
    out = []
    for card in (d.get("data") or {}).get("cards") or []:
        for comp in card.get("content") or []:
            for it in comp.get("content") or []:
                t = strip_html(it.get("word") or "")
                if not t:
                    continue
                out.append({"title": t, "extra": "置顶" if it.get("isTop") else ""})
    return out


def fetch_douyin_hot(cfg):
    d = json.loads(http_get(
        "https://www.iesdouyin.com/web/api/v2/hotsearch/billboard/word/",
        timeout=10, retries=1, ua=UA_PHONE).decode("utf-8"))
    out = []
    for it in d.get("word_list") or []:
        t = strip_html(it.get("word") or "")
        if t:
            out.append({"title": t})
    return out


HOT_FETCHERS = {"weibo": fetch_weibo_hot, "toutiao": fetch_toutiao_hot,
                "zhihu": fetch_zhihu_hot, "bilibili": fetch_bilibili_hot,
                "baidu": fetch_baidu_hot, "douyin": fetch_douyin_hot}


def fmt_price(p, vs="usd"):
    if p is None:
        return "--"
    sym = {"usd": "$", "cny": "¥", "eur": "€"}.get(vs, "")
    if p >= 1000:
        return f"{sym}{p:,.0f}"
    if p >= 1:
        return f"{sym}{p:,.2f}"
    return f"{sym}{p:.4f}"


# --------------------------------------------------------------------------
# 渲染
# --------------------------------------------------------------------------
_TOKEN_RE = re.compile(r"[A-Za-z0-9$%,.]+|\s+|.")
_NO_LINE_START = set("，。、；：？！）】》…%")


def wrap(draw, text, font, max_w):
    """贪心换行: 英文/数字整词不断行, 标点不落行首(悬挂), 中文逐字"""
    lines, cur = [], ""
    for tk in _TOKEN_RE.findall(text):
        t = cur + tk
        if not cur or draw.textlength(t, font=font) <= max_w:
            cur = t
        elif tk.isspace() or tk in _NO_LINE_START:
            cur = t                      # 允许轻微超宽, 避免丑陋断点
        else:
            lines.append(cur)
            cur = tk.lstrip()
    if cur:
        lines.append(cur)
    return lines


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.img = Image.new("L", (w, h), 255)
        self.d = ImageDraw.Draw(self.img)
        self.pad = int(w * 0.045)

    def text(self, xy, s, font, fill=0, anchor=None):
        self.d.text(xy, s, font=font, fill=fill, anchor=anchor)

    def hline(self, y, x0=None, x1=None, fill=0, width=2):
        x0 = self.pad if x0 is None else x0
        x1 = self.w - self.pad if x1 is None else x1
        self.d.line([(x0, y), (x1, y)], fill=fill, width=width)

    def finish(self, levels=16, dither=True):
        if levels >= 256:
            return self.img
        q = self.img.quantize(colors=levels,
                              dither=Image.FLOYDSTEINBERG if dither else Image.NONE)
        return q.convert("L")


# ---- 各模块渲染: 都画进给定矩形 (x, y, w, h), 自己控制标题与内容 ----

def draw_crypto(c, rect, coins, cfg, F):
    x, y, w, h = rect
    c.text((x, y), cfg.get("crypto_label", "加密货币"), F(28, True), 60)
    y += 44
    n = max(1, len(coins))
    row_h = max(56, min(116, (h - (y - rect[1])) // n))
    pad = x + 2
    right = x + w - 4
    f_sym, f_price = F(30, True), F(36, True)
    f_name, f_chg = F(17), F(19, True)

    # 先统一量宽: 价格列取所有行的最大宽度, 曲线右边界固定 → 各行严格对齐
    rows = []
    max_pw = 0
    for coin in coins:
        price_s = fmt_price(coin.get("price"), cfg.get("crypto", {}).get("vs_currency", "usd"))
        chg = coin.get("change")
        chg_s = "--" if chg is None else ("▲" if chg >= 0 else "▼") + f"{abs(chg):.2f}%"
        try:
            pw = c.d.textlength(price_s, font=f_price)
        except Exception:                    # noqa: BLE001
            pw = 120
        max_pw = max(max_pw, pw)
        rows.append((coin, price_s, chg_s))
    curve_x1 = right - int(max_pw) - 16     # 曲线统一终点, 不再逐行变化

    for idx, (coin, price_s, chg_s) in enumerate(rows):
        row_top = y
        l1 = row_top + 2
        l2 = row_top + row_h - 26
        c.text((pad, l1), coin.get("symbol", "?"), f_sym, 0)
        c.text((right, l1), price_s, f_price, 0, anchor="ra")
        c.text((pad, l2), coin.get("name", ""), f_name, 135)
        c.text((right, l2), chg_s, f_chg, 60, anchor="ra")

        curve = coin.get("curve") or coin.get("spark") or []
        if len(curve) > 3:
            x0 = pad + 110                  # 曲线统一起点
            x1 = curve_x1
            x1 = curve_x1
            if x1 - x0 > 60:
                lo, hi = min(curve), max(curve)
                rng = (hi - lo) or 1.0
                mid_y = row_top + row_h / 2
                sh = min(48, row_h - 30)
                pts = [(x0 + (x1 - x0) * i / (len(curve) - 1),
                        mid_y + sh / 2 - (v - lo) / rng * sh)
                       for i, v in enumerate(curve)]
                c.d.line(pts, fill=95, width=2, joint="curve")
                c.d.ellipse([pts[-1][0] - 3, pts[-1][1] - 3,
                             pts[-1][0] + 3, pts[-1][1] + 3], fill=0)
        y = row_top + row_h
        if idx < n - 1:
            c.hline(y - 5, x0=x, x1=x + w - 4, fill=215, width=1)


def draw_fastnews(c, rect, items, cfg, F):
    x, y, w, h = rect
    c.text((x, y), cfg.get("fastnews_label", "财经 7×24"), F(28, True), 60)
    y += 44
    n = max(1, len(items))
    it_h = max(44, min(72, (h - (y - rect[1])) // n))
    f_fn = F(min(27, it_h // 2 - 2))
    for item in items:
        tm = item.get("time") or ""
        txt = (tm + "  " + item["title"]) if tm else item.get("title", "")
        lines = wrap(c.d, txt, f_fn, w - 8)[:2]
        if len(lines) == 2 and len(lines[1]) > 2:
            lines[1] = lines[1][:-1] + "…"
        for i, ln in enumerate(lines):
            c.text((x + 2, y + i * (it_h // 2)), ln, f_fn, 10)
        y += it_h


def draw_hot(c, rect, cols, cfg, F):
    """cols: [{'name':源名, 'items':[...]}...] 1~2 列, 单列自动通栏。
    词条不显示热度数值, 标题全宽显示; 行高足够时折两行, 尽量多显示文字。"""
    x, y, w, h = rect
    if not cols:
        return
    bottom = rect[1] + h
    c.text((x, y), cfg.get("hot_label", "热榜"), F(28, True), 60)
    y += 40
    n_rows = max(len(col["items"]) for col in cols)
    col_w = (w - 8 - 24 * (len(cols) - 1)) // len(cols)
    area = bottom - y - 30                          # 扣掉源名行
    hot_h = max(26, min(62, area // max(1, n_rows)))
    two = hot_h >= 50                               # 行高足够 → 词条折两行
    f_hot = F(min(24, (hot_h // 2 - 4) if two else hot_h - 6))
    line_h = f_hot.size + 6
    for ci, col in enumerate(cols):
        cx = x + ci * (col_w + 24)
        # 源名画在矩形内部(紧贴标题下), 不再越界与上方模块重叠
        c.text((cx, y), col.get("name", ""), F(19), 130)
        iy = y + 30
        for ri, it in enumerate(col["items"]):
            if iy + hot_h > bottom:
                break
            t = f"{ri + 1}. {it.get('title', '')}"
            lines = wrap(c.d, t, f_hot, col_w)[: 2 if two else 1]
            if len(lines) == 2 and len(lines[1]) > 2:
                lines[1] = lines[1][:-1] + "…"
            for li, ln in enumerate(lines):
                c.text((cx, iy + li * line_h), ln, f_hot, 10)
            iy += hot_h


def render(cfg, data, stale=False, demo=False):
    """data: {coins, fastnews, hot_cols}"""
    land = cfg.get("orientation", "portrait") == "landscape"
    dw, dh = int(cfg.get("width", 824)), int(cfg.get("height", 1200))
    if land:
        cw, ch = max(dw, dh), min(dw, dh)      # 内容画成 1200x824
    else:
        cw, ch = min(dw, dh), max(dw, dh)      # 竖版 824x1200

    f_reg, f_bold = cfg.get("_font_reg"), cfg.get("_font_bold")
    F = lambda size, bold=False: load_font(f_bold if bold else f_reg, size)  # noqa: E731

    c = Canvas(cw, ch)
    pad = c.pad
    right = cw - pad
    now = datetime.now(CST)
    weekday_cn = "一二三四五六日"[now.weekday()]

    # ---- 页眉 ----
    top = int(ch * 0.030)
    c.text((pad, top), cfg.get("title", "每日简报"), F(46, True), 0)
    c.text((right, top + 2), now.strftime("%H:%M"), F(34, True), 0, anchor="ra")
    c.text((right, top + 46), now.strftime("%Y-%m-%d") + f"  星期{weekday_cn}",
           F(20), 90, anchor="ra")
    y = top + 88
    c.hline(y, fill=0, width=3)
    y += 16

    footer_top = ch - int(ch * 0.045)
    avail = footer_top - y
    modules = [m for m in cfg.get("modules", ["crypto", "fastnews", "hot"])
               if m in ("crypto", "fastnews", "hot")]

    # ---- 各模块需要的高度 → 按比例分 ----
    coins = data.get("coins") or []
    fastnews = data.get("fastnews") or []
    hot_cols = data.get("hot_cols") or []
    need = {}
    if "crypto" in modules:
        need["crypto"] = 44 + max(1, len(coins)) * 78
    if "fastnews" in modules:
        need["fastnews"] = 44 + max(1, len(fastnews)) * 56
    if "hot" in modules and hot_cols:
        n_hot = max(len(col["items"]) for col in hot_cols)
        need["hot"] = 42 + 30 + n_hot * 40
    if not need:
        need = {"fastnews": 200}
        modules = ["fastnews"]
    scale = min(1.6, avail / sum(need.values()))
    gaps = 18 * (len(need) - 1)
    scale = min(1.6, (avail - gaps) / sum(need.values()))

    # ---- 版式: 竖版纵向堆叠; 横版第一模块占左半列, 其余堆右半列 ----
    if land:
        left_w = int(cw * 0.44)
        rects = {}
        rest = [m for m in modules if m in need]
        first = rest[0] if rest else None
        if first:
            # 左列模块撑满整列高度(行情行会自动拉高填满)
            rects[first] = (pad, y, left_w, avail)
        if len(rest) > 1:
            rx = pad + left_w + int(cw * 0.035)
            rw = right - rx
            ry = y
            rh_total = footer_top - y
            tot = sum(need[m] for m in rest[1:])
            for m in rest[1:]:
                rh = int((need[m] / tot) * rh_total) if tot else 0
                rects[m] = (rx, ry, rw, rh)
                ry += rh + 14
        for m in modules:
            if m in rects:
                _draw_module(c, m, rects[m], data, cfg, F, land)
    else:
        ry = y
        for m in modules:
            if m not in need:
                continue
            rh = int(need[m] * scale)
            rh = min(rh, footer_top - ry)
            if rh < 60:
                break
            _draw_module(c, m, (pad, ry, cw - 2 * pad, rh), data, cfg, F, land)
            ry += rh + 18

    # ---- 页脚 ----
    fy = ch - int(ch * 0.026)
    c.hline(fy - int(ch * 0.017), fill=205, width=1)
    src_parts = []
    if coins:
        src_parts.append("行情 " + COIN_SOURCE_NAMES.get(cfg.get("crypto", {}).get("source"), "Binance"))
    if fastnews:
        if fastnews[0].get("source"):       # RSS 轮播: 显示实际用到的渠道
            used = list(dict.fromkeys(it["source"] for it in fastnews))
            src_parts.append("快讯 " + "+".join(used[:2]) + ("等" if len(used) > 2 else ""))
        else:
            src_parts.append("快讯 " + FASTNEWS_NAMES.get(cfg.get("fastnews", {}).get("source"), ""))
    if hot_cols:
        src_parts.append("热榜 " + "/".join(col.get("name", "") for col in hot_cols))
    if demo:
        src_parts = ["DEMO"]
    foot = f"更新 {now.strftime('%H:%M')} · " + " · ".join(src_parts)
    if stale:
        foot += " · 数据可能过期"
    c.text((pad, fy), foot, F(18), 110)

    img = c.finish(levels=int(cfg.get("gray_levels", 16)),
                   dither=bool(cfg.get("dither", True)))
    if land:
        # 横版内容旋转 90° 适配竖屏 framebuffer, 阅读时将 Kindle 顺时针横持
        rot = getattr(Image, "Transpose", Image).ROTATE_90
        img = img.transpose(rot)
    return img


def _draw_module(c, m, rect, data, cfg, F, land):
    if m == "crypto":
        draw_crypto(c, rect, data.get("coins") or [], cfg, F)
    elif m == "fastnews":
        draw_fastnews(c, rect, data.get("fastnews") or [], cfg, F)
    elif m == "hot":
        cols = [dict(col) for col in (data.get("hot_cols") or [])]
        # 热榜列数: 竖版最多 2 列; 横版右半列窄, 也最多 2 列
        draw_hot(c, rect, cols[:2], cfg, F)


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------
def _normalize_cfg(cfg):
    """旧字段 → v3 结构迁移 (不写回, 仅内存)"""
    crypto = cfg.get("crypto") if isinstance(cfg.get("crypto"), dict) else {}
    crypto = dict(crypto)
    if "pairs" not in crypto:
        legacy = cfg.get("binance_symbols") or [c.get("symbol") for c in cfg.get("coins", [])]
        crypto["pairs"] = [s for s in legacy if s][:5] or ["BTC", "ETH", "SOL", "BNB", "XRP"]
    if "source" not in crypto:
        crypto["source"] = "binance"
    # 只做格式清理, 不按内置币池过滤 (支持 genconf 下发的自定义币, 如 0G/ATH)
    seen = []
    for s in crypto.get("pairs") or []:
        s = str(s).strip().upper()
        if re.fullmatch(r"[A-Za-z0-9]{2,10}", s) and s not in seen:
            seen.append(s)
    crypto["pairs"] = seen[:5]
    crypto.setdefault("vs_currency", cfg.get("vs_currency", "usd"))
    cfg["crypto"] = crypto

    fn = cfg.get("fastnews") if isinstance(cfg.get("fastnews"), dict) else {}
    fn = dict(fn)
    fn.setdefault("source", "sina7x24")
    fn.setdefault("count", int(cfg.get("sina7x24_count", 4)))
    if "feeds" not in fn:
        fn["feeds"] = cfg.get("feeds") or []
    cfg["fastnews"] = fn

    hot = cfg.get("hot") if isinstance(cfg.get("hot"), list) else None
    if not hot:
        hot = [{"source": "weibo", "count": int(cfg.get("weibo_count", 4))},
               {"source": "toutiao", "count": int(cfg.get("toutiao_count", 4))}]
    cfg["hot"] = [h for h in hot if h.get("source") in HOT_FETCHERS][:2]

    if "orientation" not in cfg:
        cfg["orientation"] = "landscape" if cfg.get("landscape") else "portrait"
    if not cfg.get("modules"):
        cfg["modules"] = ["crypto", "fastnews", "hot"]
    return cfg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default=os.path.join(HERE, "config.json"))
    ap.add_argument("-o", "--output", default=None)
    ap.add_argument("--demo", action="store_true", help="用假数据渲染, 不联网")
    ap.add_argument("--offline", action="store_true", help="用上次缓存渲染")
    ap.add_argument("--landscape", action="store_true", help="强制横版输出")
    args = ap.parse_args()

    cfg = {}
    if os.path.exists(args.config):
        with open(args.config, encoding="utf-8") as f:
            cfg = json.load(f)
    if args.landscape:
        cfg["orientation"] = "landscape"
    cfg = _normalize_cfg(cfg)

    cfg["_font_reg"] = find_font("font_regular", cfg)
    cfg["_font_bold"] = find_font("font_bold", cfg) or cfg["_font_reg"]
    if cfg["_font_reg"] is None:
        print("[warn] 没找到中文字体, 中文会变成方块。请把 NotoSans CJK 字体 "
              "放到 fonts/ 并在 config.json 里指定。", file=sys.stderr)

    cache_path = os.path.join(HERE, "cache.json")
    cache = {}
    if os.path.exists(cache_path):
        try:
            with open(cache_path, encoding="utf-8") as f:
                cache = json.load(f)
        except Exception:                  # noqa: BLE001
            cache = {}
    cfg["_fn_state"] = cache.get("fn_state") or {}   # 快讯轮播进度/历史

    stale = False
    if args.demo:
        data = {
            "coins": DEMO_COINS,
            "fastnews": DEMO_FASTNEWS,
            "hot_cols": [{"source": h["source"], "name": HOT_NAMES[h["source"]],
                          "items": DEMO_HOT[h["source"]][:h.get("count", 4)]}
                         for h in cfg["hot"]],
        }
    elif args.offline:
        data = {"coins": cache.get("coins") or DEMO_COINS,
                "fastnews": cache.get("fastnews") or [],
                "hot_cols": cache.get("hot_cols") or []}
        stale = True
    else:
        # ---- 行情 (支持按币分源) ----
        coins = []
        try:
            coins = fetch_crypto_mixed(cfg)
        except Exception as e:             # noqa: BLE001
            print(f"[warn] 行情获取失败: {e}", file=sys.stderr)
        if coins:
            fetch_curves(cfg, coins)
        # ---- 快讯 ----
        fastnews = []
        fsrc = cfg["fastnews"]["source"]
        try:
            fastnews = FASTNEWS_FETCHERS[fsrc](cfg)
        except Exception as e:             # noqa: BLE001
            print(f"[warn] 快讯 {fsrc} 失败: {e}", file=sys.stderr)
        if fsrc != "rss" and not fastnews:  # 主源挂了退回 RSS
            try:
                fastnews = FASTNEWS_FETCHERS["rss"](cfg)
            except Exception as e:         # noqa: BLE001
                print(f"[warn] RSS 兜底失败: {e}", file=sys.stderr)
        # ---- 热榜 ----
        hot_cols = []
        for slot in cfg["hot"]:
            s = slot["source"]
            try:
                items = HOT_FETCHERS[s](cfg)[: max(3, int(slot.get("count", 4)))]
                hot_cols.append({"source": s, "name": HOT_NAMES[s], "items": items})
            except Exception as e:         # noqa: BLE001
                print(f"[warn] 热榜 {s} 失败: {e}", file=sys.stderr)
        # ---- 全挂兜底缓存 ----
        if not (coins or fastnews or hot_cols):
            data = {"coins": cache.get("coins") or [],
                    "fastnews": cache.get("fastnews") or [],
                    "hot_cols": cache.get("hot_cols") or []}
            stale = bool(data["coins"] or data["fastnews"] or data["hot_cols"])
        else:
            data = {"coins": coins, "fastnews": fastnews, "hot_cols": hot_cols}
            try:
                with open(cache_path, "w", encoding="utf-8") as f:
                    json.dump({**data, "fn_state": cfg.get("_fn_state") or {}},
                              f, ensure_ascii=False)
            except Exception:              # noqa: BLE001
                pass
        if not data["coins"]:
            data["coins"] = cache.get("coins") or []
            if data["coins"]:
                stale = True

    data["fastnews"] = (data.get("fastnews") or [])[: max(1, int(cfg["fastnews"]["count"]))]
    data["hot_cols"] = [{"name": col["name"], "source": col["source"],
                         "items": col["items"][: max(1, int(
                             next((h.get("count", 4) for h in cfg["hot"]
                                   if h["source"] == col["source"]), 4)))]}
                        for col in (data.get("hot_cols") or [])]
    img = render(cfg, data, stale=stale, demo=args.demo)

    out = args.output or cfg.get("output", "dashboard.png")
    if not os.path.isabs(out):
        out = os.path.join(HERE, out)
    img.save(out, "PNG", optimize=True)
    print(f"[ok] {out}  {img.size[0]}x{img.size[1]}  "
          f"{os.path.getsize(out) // 1024}KB  coins={len(data['coins'])} "
          f"fn={len(data['fastnews'])} "
          f"hot={'+'.join(col['source'] for col in data['hot_cols'])}"
          + ("  (stale)" if stale else ""))


if __name__ == "__main__":
    main()
