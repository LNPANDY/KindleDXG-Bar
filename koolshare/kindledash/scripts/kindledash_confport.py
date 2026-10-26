#!/opt/bin/python3
# ============================================================================
# Kindle 仪表盘 - 配置导入导出 (dbus kindledash_* ↔ base64(JSON) 备份文本)
# 用法: kindledash_confport.py export | import
# ============================================================================
import base64
import json
import shlex
import subprocess
import sys
import time

# 不进备份的运行态/瞬态键
EXCLUDE = {
    "kindledash_version",
    "kindledash_envcheck", "kindledash_envcheck_ts",
    "kindledash_coincheck", "kindledash_coincheck_ts",
    "kindledash_confport", "kindledash_confport_ts", "kindledash_confport_in",
}


def dbus_env():
    """dbus export kindledash_ → dict (输出形如: export k="v";export k2="v2";)"""
    out = subprocess.run(["/usr/bin/dbus", "export", "kindledash_"],
                         capture_output=True, text=True, timeout=10).stdout
    d = {}
    for tok in out.split(";"):
        tok = tok.strip()
        if tok.startswith("export "):
            tok = tok[len("export "):]
        if not tok or "=" not in tok:
            continue
        k, _, v = tok.partition("=")
        try:
            v = shlex.split(v)[0] if v.strip() else ""
        except ValueError:
            v = v.strip("\"")
        d[k] = v
    return d


def dset(k, v):
    subprocess.run(["/usr/bin/dbus", "set", f"{k}={v}"], timeout=10)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "export"
    env = dbus_env()
    if mode == "export":
        cfg = {k: v for k, v in env.items() if k not in EXCLUDE}
        payload = base64.b64encode(
            json.dumps(cfg, ensure_ascii=False, sort_keys=True).encode()).decode()
        dset("kindledash_confport", payload)
        dset("kindledash_confport_ts", str(int(time.time())))
        print(f"[ok] 导出完成: {len(cfg)} 项配置已生成到备份文本框, 请全选复制保存")
    else:
        raw = env.get("kindledash_confport_in", "").strip()
        if not raw:
            print("[err] 导入失败: 备份文本为空")
            sys.exit(1)
        try:
            cfg = json.loads(base64.b64decode(raw + "=" * (-len(raw) % 4)))
        except Exception as e:                       # noqa: BLE001
            print(f"[err] 导入失败: 备份文本无法解析 ({e})")
            sys.exit(1)
        if not isinstance(cfg, dict):
            print("[err] 导入失败: 备份内容不是有效配置")
            sys.exit(1)
        n = 0
        for k, v in cfg.items():
            if not k.startswith("kindledash_") or k in EXCLUDE:
                continue
            dset(k, str(v))
            n += 1
        dset("kindledash_confport_in", "")
        print(f"[ok] 导入完成: 已写入 {n} 项配置, 正在重新生成 config.json 并推送...")


if __name__ == "__main__":
    main()
