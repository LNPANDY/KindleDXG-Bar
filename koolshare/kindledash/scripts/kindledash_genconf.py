#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
kindle-dash 软件中心插件: dbus 变量 → /opt/kindle-dash/config.json
由 kindledash_config.sh 调用, 环境里无需预置变量(自己从 dbus 读取)。
"""
import json
import os
import re
import shlex
import subprocess

CFG_PATH = "/opt/kindle-dash/config.json"
BASE_COINS = {"BTC", "ETH", "SOL", "BNB", "XRP", "DOGE", "ADA", "DOT", "LINK", "LTC", "AVAX"}
HOT_OK = {"weibo", "toutiao", "zhihu", "bilibili", "baidu", "douyin"}
MODULES_OK = {"crypto", "fastnews", "hot"}

# RSS 池: dbus 后缀 → (显示名, url)
FEEDS = [
    ("36kr", "36氪", "https://36kr.com/feed"),
    ("ithome", "IT之家", "https://www.ithome.com/rss/"),
    ("sspai", "少数派", "https://sspai.com/feed"),
    ("solidot", "Solidot", "https://www.solidot.org/index.rss"),
    ("sinafinance", "新浪财经", "https://rss.sina.com.cn/roll/finance/hot_roll.xml"),
    ("cointele", "Cointelegraph", "https://cointelegraph.com/rss"),
    ("foresight", "ForesightNews", "https://foresightnews.pro/rss"),
]


def read_dbus():
    """dbus export kindledash_ → dict (输出形如: export k="v";export k2="v2";)"""
    env = {}
    try:
        out = subprocess.run(["/usr/bin/dbus", "export", "kindledash_"],
                             capture_output=True, text=True, timeout=10).stdout
        for tok in out.split(";"):
            tok = tok.strip()
            if tok.startswith("export "):
                tok = tok[len("export "):]
            if not tok or "=" not in tok:
                continue
            k, _, val = tok.partition("=")
            try:
                env[k] = shlex.split(val)[0] if val.strip() else ""
            except ValueError:
                env[k] = val.strip("'\"")
    except Exception as e:                     # noqa: BLE001
        print(f"[warn] 读取 dbus 失败: {e}")
    return env


def ev(env, key, default):
    val = env.get("kindledash_" + key, "")
    return val if val not in ("", None) else default


def main():
    env = read_dbus()
    old = {}
    if os.path.exists(CFG_PATH):
        try:
            with open(CFG_PATH, encoding="utf-8") as f:
                old = json.load(f)
        except Exception:                      # noqa: BLE001
            old = {}

    modules = [m for m in str(ev(env, "modules", "crypto,fastnews,hot")).split(",")
               if m in MODULES_OK]
    # 币池 = 内置 + 用户手动添加 (dbus kindledash_coins_extra, 逗号分隔)
    extra = {s.strip().upper() for s in str(ev(env, "coins_extra", "")).split(",")
             if re.fullmatch(r"[A-Za-z0-9]{2,10}", s.strip() or "")}
    coin_pool = BASE_COINS | extra
    pairs, psrc = [], {}
    for i in range(1, 6):
        p = str(ev(env, f"pair_{i}", "")).upper()
        if p in coin_pool and p not in pairs:
            pairs.append(p)
        s = str(ev(env, f"pair_src_{i}", "")).lower()
        if p and s in ("binance", "coingecko", "gate"):
            psrc[p] = s                   # 按币覆盖行情源, 未覆盖走全局
    feeds = [{"name": n, "url": u} for k, n, u in FEEDS if ev(env, "feed_" + k, "") == "1"]
    hot = []
    for slot in ("hot1", "hot2"):
        s = str(ev(env, slot + "_source", "")).lower()
        if s in HOT_OK:
            hot.append({"source": s,
                        "count": max(2, min(6, int(ev(env, "hot_count", "4") or 4)))})

    cfg = {
        "title": old.get("title", "每日简报"),
        "orientation": "landscape" if ev(env, "orientation", "portrait") == "landscape" else "portrait",
        "refresh_minutes": max(3, min(720, int(ev(env, "refresh", "15") or 15))),
        "modules": modules or ["crypto", "fastnews", "hot"],
        "crypto": {
            "source": ev(env, "coin_source", "binance") if ev(env, "coin_source", "binance") in ("binance", "coingecko", "gate") else "binance",
            "vs_currency": "usd",
            "pairs": pairs or ["BTC", "ETH", "SOL", "BNB", "XRP"],
            "pair_sources": psrc,
        },
        "fastnews": {
            "source": ev(env, "fn_source", "sina7x24"),
            "count": max(2, min(8, int(ev(env, "fn_count", "4") or 4))),
            "feeds": feeds,
        },
        "hot": hot or [{"source": "weibo", "count": 4}],
        "gray_levels": old.get("gray_levels", 16),
        "dither": old.get("dither", True),
        "font_regular": old.get("font_regular", "fonts/NotoSansCJKsc-Regular.otf"),
        "font_bold": old.get("font_bold", "fonts/NotoSansCJKsc-Bold.otf"),
        "output": old.get("output", "dashboard.png"),
    }
    with open(CFG_PATH, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"[ok] config.json 已生成: 方向={cfg['orientation']} "
          f"频率={cfg['refresh_minutes']}min 模块={','.join(cfg['modules'])} "
          f"币={cfg['crypto']['source']}{','.join(cfg['crypto']['pairs'])} "
          f"快讯={cfg['fastnews']['source']}(feeds:{len(feeds)}) "
          f"热榜={'+'.join(h['source'] for h in cfg['hot'])}")


if __name__ == "__main__":
    main()
