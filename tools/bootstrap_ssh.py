#!/usr/bin/env python3
# ============================================================================
# Kindle DXG 首次 SSH 引导：
#   1) 用任意密码连进 192.168.2.2（usbnet 下 dropbear 不校验密码）
#   2) 探测 dropbear 的 authorized_keys 位置（根分区只读，必在 /mnt/us 下）
#   3) 写入本机公钥 -> 之后免密
# 用法: python3 bootstrap_ssh.py
# ============================================================================
import os, sys, paramiko

KINDLE_IP = "192.168.2.2"
USER = "root"
KEY = os.path.expanduser("~/.ssh/kindle_dxg_id_rsa")
PUB = KEY + ".pub"

# 放行老算法（dropbear 0.52）
ALGO = {
    "kex": [],          # 允许 diffie-hellman-group1-sha1 等
    "pubkeys": [],      # 允许 ssh-rsa
    "keys": [],
    "ciphers": [],
    "macs": [],
}

def connect(password):
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(KINDLE_IP, username=USER, password=password, timeout=20,
              look_for_keys=False, allow_agent=False,
              disabled_algorithms=ALGO)
    return c

def sh(c, cmd):
    _, out, err = c.exec_command(cmd)
    return out.read().decode("utf-8", "replace"), err.read().decode("utf-8", "replace")

def main():
    if not os.path.exists(PUB):
        print("[err] 没有公钥 %s，先生成密钥" % PUB); sys.exit(1)
    pub = open(PUB).read().strip()
    print("[*] 尝试用任意密码连接 %s ..." % KINDLE_IP)
    client = None
    for pw in ("kindle", "root", "", "password"):
        try:
            client = connect(pw)
            print("[ok] 登录成功 (password=%r)" % pw)
            break
        except Exception as e:
            print("  - 密码 %r 失败: %s" % (pw, str(e)[:80]))
    if client is None:
        print("[err] 无法登录，可能需要真实 root 密码（sven.de/kindle 用序列号算）")
        sys.exit(2)

    # 探测 authorized_keys 位置
    out, _ = sh(client,
        "grep -i authorizedkeys /mnt/us/usbnet/etc/sshd_config 2>/dev/null; "
        "echo '--- dot.ssh ---'; ls -la /mnt/us/usbnet/etc/dot.ssh/ 2>/dev/null; "
        "echo '--- HOME ---'; echo HOME=$HOME; "
        "echo '--- usbnet/etc ---'; ls -la /mnt/us/usbnet/etc/authorized_keys 2>/dev/null")
    print("[*] dropbear 配置探测:\n" + out)

    # 候选路径：优先 usbnet/etc/authorized_keys，其次 dot.ssh/authorized_keys
    candidates = [
        "/mnt/us/usbnet/etc/authorized_keys",
        "/mnt/us/usbnet/etc/dot.ssh/authorized_keys",
        "/mnt/us/usbnet/etc/.ssh/authorized_keys",
    ]
    target = candidates[0]
    cmd = (
        "mkdir -p /mnt/us/usbnet/etc/dot.ssh; "
        "f=%s; grep -qxF '%s' \"$f\" 2>/dev/null || echo '%s' >> \"$f\"; "
        "chmod 600 \"$f\"; chmod 700 /mnt/us/usbnet/etc/dot.ssh; "
        "echo WROTE_TO=$f; tail -1 \"$f\""
    ) % (target, pub, pub)
    out, err = sh(client, cmd)
    print("[*] 写入结果:\n" + out + err)

    client.close()

    # 验证免密
    print("[*] 验证免密登录 ...")
    try:
        c2 = paramiko.SSHClient()
        c2.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        c2.connect(KINDLE_IP, username=USER, key_filename=KEY, timeout=20,
                   look_for_keys=False, allow_agent=False, disabled_algorithms=ALGO)
        out, _ = sh(c2, "uname -a; echo '---'; /usr/sbin/eips -h 2>&1 | head -3")
        print("[ok] 免密登录成功!\n" + out)
        c2.close()
        print("\n✅ 引导完成。之后可用:")
        print("   KINDLE_IP=192.168.2.2 SSH_KEY=~/.ssh/kindle_dxg_id_rsa ./push.sh")
    except Exception as e:
        print("[warn] 免密验证失败: %s" % str(e)[:120])
        print("       请检查 authorized_keys 实际路径后手动修正。")

if __name__ == "__main__":
    main()
