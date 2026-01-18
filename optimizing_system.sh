#!/usr/bin/env bash

# ==============================================================================
# Linux TCP/IP & Conntrack 高并发深度优化脚本
#
# 脚本功能：
# 1. 深度调优 TCP/IP 内核参数 (针对 Nginx 转发与高并发长连接)
# 2. 优化 nf_conntrack 哈希表性能，解决 Softirq 瓶颈
# 3. 突破 Systemd 与文件句柄限制，支持百万级并发
# 4. 自动配置持久化，确保重启不还原
# ==============================================================================

set -euo pipefail

# --- 颜色定义 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
echo_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
echo_err()  { echo -e "${RED}[ERROR]${NC} $1"; }

# 增加 99 权重，确保配置优先级最高
SYSCTL_CONF="/etc/sysctl.d/99-optimizing-sysctl.conf"

# --- 权限检查 ---
if [[ $(id -u) -ne 0 ]]; then
    echo_err "此脚本必须以 root 权限运行！"
    exit 1
fi

# 获取总物理内存 (MB)，精确匹配 Mem 行，不包含 Swap
MEM_MB=$(free -m | awk '/^Mem:/{print $2}')

if [ "$MEM_MB" -le 512 ]; then
    # 入门级 VPS (≤512MB)，防止内存溢出导致内核崩溃
    echo_info "检测到内存为 ${MEM_MB}MB，使用入门级优化策略..."
    CONNTRACK_MAX="524288"
    TARGET_HASHSIZE="65536"
else
    # 进阶/专业级 VPS (>512MB)
    echo_info "检测到内存为 ${MEM_MB}MB，使用高性能优化策略..."
    CONNTRACK_MAX="2621440"
    TARGET_HASHSIZE="327680"
fi

# --- 核心优化逻辑 ---
optimizing_system() {
  echo_info "正在开始系统环境检查与组件安装..."

  # 更新软件源
  apt update

  # 安装必要组件
  if ! [ -x "$(command -v ethtool)" ]; then
      apt -y install ethtool
  fi

  echo_info "正在配置 haveged 增强系统随机数性能..."
  apt install haveged -y
  systemctl disable --now haveged
  systemctl enable --now haveged
  echo_ok "haveged 配置完成"

  # 创建 sysctl 配置目录
  mkdir -p /etc/sysctl.d

  echo_info "正在写入 TCP/IP 核心优化参数到 $SYSCTL_CONF..."

  # 覆盖写入 sysctl 配置，保留所有原始注释
  cat >"$SYSCTL_CONF" <<EOF
# =========================
# TCP/IP 核心优化
# =========================
# 禁止保存 TCP RTT/带宽指标，避免旧连接影响新连接
net.ipv4.tcp_no_metrics_save=1
# 禁用 ECN 拥塞标记，保证兼容性
net.ipv4.tcp_ecn=0
# 禁用 F-RTO，减少误触发重传
net.ipv4.tcp_frto=0
# 开启 MTU 探测，防止跨国大包黑洞
net.ipv4.tcp_mtu_probing=1
# RFC1337 开启保护，防止 TIME_WAIT 重用
net.ipv4.tcp_rfc1337=1
# 开启选择性确认，提高丢包恢复能力
net.ipv4.tcp_sack=1
# 启用 FACK，减少网络拥塞时的重复确认
net.ipv4.tcp_fack=1
# 开启窗口缩放，支持高带宽延迟网络
net.ipv4.tcp_window_scaling=1
# 自动调节高级窗口缩放，兼顾性能与兼容
net.ipv4.tcp_adv_win_scale=-1
# 自动调节接收缓冲，提高大流量适应性
net.ipv4.tcp_moderate_rcvbuf=1

# =========================
# TCP 缓冲区设置
# =========================
# 接收缓冲：最小8KB，默认1MB，最大 128MB
net.ipv4.tcp_rmem=8192 1048576 134217728
# 发送缓冲：最小4KB，默认1MB，最大 128MB
net.ipv4.tcp_wmem=4096 1048576 134217728
# TCP 内存合并阈值，减少内存碎片
net.ipv4.tcp_collapse_max_bytes=6291456
# 降低缓冲区未发送数据阈值 (降低延迟)
net.ipv4.tcp_notsent_lowat=16384

# =========================
# TCP 连接参数优化
# =========================
# 开启 TFO
net.ipv4.tcp_fastopen=3
# 减少 TIME_WAIT 堆积
net.ipv4.tcp_fin_timeout=15
# TCP Keepalive 空闲时间 缩短存活时间，更快清理死连接
net.ipv4.tcp_keepalive_time=300
# Keepalive 探测间隔
net.ipv4.tcp_keepalive_intvl=3
# Keepalive 最大探测次数
net.ipv4.tcp_keepalive_probes=5
# TCP 初次重传次数
net.ipv4.tcp_retries1=3
# TCP 全重传次数 跨国链路建议不要太小，防止抖动断开
net.ipv4.tcp_retries2=8
# 空闲后不触发慢启动，保持速度
net.ipv4.tcp_slow_start_after_idle=0
# 开启 TIME_WAIT 复用 (关键优化)
net.ipv4.tcp_tw_reuse=1
# 开启时间戳，防止序列号回绕
net.ipv4.tcp_timestamps=1
# 开启 SYN Cookies，防止 SYN 洪泛攻击
net.ipv4.tcp_syncookies=1
# SYN 重试次数
net.ipv4.tcp_syn_retries=3
# SYN-ACK 重试次数
net.ipv4.tcp_synack_retries=3
# SYN 队列长度，支持高并发连接
net.ipv4.tcp_max_syn_backlog=819200
# 允许更多孤儿连接（防止突发流量报错）
net.ipv4.tcp_max_orphans = 32768
# TIME_WAIT 最大数量
net.ipv4.tcp_max_tw_buckets=131072
# 队列溢出直接拒绝新连接，防止内存崩溃
net.ipv4.tcp_abort_on_overflow=1

# =========================
# 内核转发 / 路由 / NAT
# =========================
# 开启 IP 转发，允许路由
net.ipv4.ip_forward=1
net.ipv4.conf.all.forwarding=1
net.ipv4.conf.default.forwarding=1
# 允许本地路由到 127.0.0.0/8，用于 NAT/代理
net.ipv4.conf.all.route_localnet=1

# =========================
# UDP & 网络队列优化
# =========================
# 接收缓冲区上限 128MB
net.core.rmem_max=134217728
# 发送缓冲区上限 128MB
net.core.wmem_max=134217728
# 接收队列最大长度，提高高并发处理能力
net.core.netdev_max_backlog=32768
# TCP 监听队列长度
net.core.somaxconn=32768
# UDP 最小接收缓冲 (优化QUIC)
net.ipv4.udp_rmem_min=16384
# UDP 最小发送缓冲 (优化QUIC)
net.ipv4.udp_wmem_min=16384

# =========================
# 拥塞控制算法
# =========================
# 使用 BBR 拥塞控制算法，提高吞吐和稳定性
net.ipv4.tcp_congestion_control=bbr
# 使用公平队列调度，避免网络抖动
net.core.default_qdisc=fq

# =========================
# 连接跟踪优化
# =========================
# 最大连接追踪数
# 每生成了12万连接会占用30M内存
# 默认通常是 65536，对于代理服务器太小，直接给到 200万+
net.netfilter.nf_conntrack_max=$CONNTRACK_MAX
# 已建立 TCP 连接超时
net.netfilter.nf_conntrack_tcp_timeout_established=600
net.netfilter.nf_conntrack_tcp_timeout_close_wait=60
net.netfilter.nf_conntrack_tcp_timeout_fin_wait=120
net.netfilter.nf_conntrack_tcp_timeout_time_wait=120

# =========================
# 系统资源 / 文件句柄
# =========================
# 系统最大文件句柄
fs.file-max=10485760
# 每进程最大文件数
fs.nr_open=1048576
# inotify 最大实例数
fs.inotify.max_user_instances=8192
# 本地端口范围
net.ipv4.ip_local_port_range=10000 65535
EOF

  echo_info "应用 sysctl 配置..."
  sysctl --system

  # ========================================================
  # 修正 nf_conntrack 哈希表性能瓶颈 这里的 hashsize 建议为 nf_conntrack_max 的 1/8 左右
  # ========================================================
  echo_info "优化 nf_conntrack 哈希桶大小 (hashsize)..."

  # 尝试立即修改当前环境
  modprobe nf_conntrack || true
  if [ -f "/sys/module/nf_conntrack/parameters/hashsize" ]; then
      echo $TARGET_HASHSIZE > /sys/module/nf_conntrack/parameters/hashsize
      echo_ok "当前 hashsize 已提升至 $TARGET_HASHSIZE"
  fi

  # 永久写入模块配置
  mkdir -p /etc/modprobe.d
  echo "options nf_conntrack hashsize=$TARGET_HASHSIZE" > /etc/modprobe.d/nf_conntrack.conf
  echo_ok "已将 hashsize 写入 modprobe 配置"

  # 参考：https://www.emqx.com/zh/blog/emqx-performance-tuning-linux-conntrack-and-mqtt-connections
  # Docker 等应用正在依赖 conntrack 提供服务，我们无法直接关闭它
  # 由于在 Linux 的启动过程中，sysctl 参数设置发生在 nf_conntrack 模块加载之前，
  # 所以仅仅将nf_conntrack_max 等参数的配置写入 /etc/sysctl.conf 中并不能直接令其生效。这也是 sysctl 的一个已知问题
  # 想要解决这个问题，我们可以在 /etc/udev/rules.d 中创建一个 50-nf_conntrack.rules 文件，
  # 然后添加以下 udev 规则，表示 一旦内核检测到 nf_conntrack 模块被添加（ACTION=="add"），立刻重新触发一次 sysctl 命令来刷新该模块相关的网络参数：
  cat >'/etc/udev/rules.d/50-nf_conntrack.rules' <<EOF
ACTION=="add", SUBSYSTEM=="module", KERNEL=="nf_conntrack", RUN+="/usr/lib/systemd/systemd-sysctl --prefix=/net/netfilter"
EOF
  echo_ok "udev 规则配置完成"

  echo_info "配置 Systemd 资源限制..."
  cat >'/etc/systemd/system.conf' <<EOF
[Manager]
#DefaultTimeoutStartSec=90s
DefaultTimeoutStopSec=30s
#DefaultRestartSec=100ms
DefaultLimitCORE=infinity
DefaultLimitNOFILE=infinity
DefaultLimitNPROC=infinity
DefaultTasksMax=infinity
EOF

  echo_info "配置用户级 limits.conf..."
  cat >'/etc/security/limits.conf' <<EOF
root     soft   nofile    1000000
root     hard   nofile    1000000
root     soft   nproc     unlimited
root     hard   nproc     unlimited
root     soft   core      unlimited
root     hard   core      unlimited
root     hard   memlock   unlimited
root     soft   memlock   unlimited
* soft   nofile    1000000
* hard   nofile    1000000
* soft   nproc     unlimited
* hard   nproc     unlimited
* soft   core      unlimited
* hard   core      unlimited
* hard   memlock   unlimited
* soft   memlock   unlimited
EOF

  echo_info "优化系统日志 Journald..."
  cat >'/etc/systemd/journald.conf' <<EOF
[Journal]
SystemMaxUse=300M
SystemMaxFileSize=50M
RuntimeMaxUse=30M
RuntimeMaxFileSize=5M
ForwardToSyslog=no
EOF
  systemctl restart systemd-journald

  # 写入 profile
  sed -i '/ulimit -SHn/d' /etc/profile
  sed -i '/ulimit -SHu/d' /etc/profile
  echo "ulimit -SHn 1000000" >>/etc/profile

  # 配置 PAM 模块
  if ! grep -q "pam_limits.so" /etc/pam.d/common-session; then
    echo "session required pam_limits.so" >>/etc/pam.d/common-session
  fi

  systemctl daemon-reload
  echo_ok "系统深度优化已全部应用完成！"
  echo_err "【重要】为了使所有修改（尤其是 Hashsize 和 Systemd 限制）彻底生效，请务必执行：reboot"
}

optimizing_system