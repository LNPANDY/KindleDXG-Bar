#!/bin/sh
# ============================================================================
# /jffs/scripts/post-mount  (梅林 U 盘挂载钩子, 记得 chmod +x)
# 作用: 把装着 Entware 的分区挂到 /tmp/opt (固件自带 /opt -> tmp/opt 软链),
#       并启动 Entware 自身服务; 最后交给 koolshare 软件中心的挂载处理。
#
# 为什么需要: 本机实测重启后 /tmp/opt 未创建也未挂载, /opt 全路径失效,
# /opt/kindle-dash 下的程序与 python 全部"消失", 定时任务静默失败。
# 判定依据: 分区根目录存在 etc/init.d/rc.unslung 即视为 Entware 根
#           (本项目 U 盘即如此: 盘根 = Entware 根, 没有 entware/ 子目录)。
# 还原: 删除本文件中的 Entware 段, 只保留 koolshare 那行。
# ============================================================================

if [ -x "$1/etc/init.d/rc.unslung" ]; then
  mkdir -p /tmp/opt
  mount | grep -q "on /tmp/opt " || mount -o bind "$1" /tmp/opt
  # Entware 服务放后台, 不拖慢挂载流程
  (sleep 1; /opt/etc/init.d/rc.unslung) >/dev/null 2>&1 &
fi

/koolshare/bin/ks-mount-start.sh start $1
