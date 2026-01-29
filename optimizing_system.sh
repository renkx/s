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

if [ "$MEM_MB" -le 600 ]; then
    # 针对 512MB 左右的小内存大带宽 VPS 优化
    echo_info "检测到内存为 ${MEM_MB}MB，采用 [小内存-高带宽] 激进策略..."
    CONNTRACK_MAX="524288"
    TARGET_HASHSIZE="65536"
    VM_SWAPPINESS="20"        # 稍微积极一点使用 swap，保护物理内存不崩
    VM_DIRTY_RATIO="10"       # 减少脏数据堆积，防止小内存写磁盘时卡死
    TCP_BUFFER_MAX="8388608"  # 8MB 封顶，兼顾 1Gbps 峰值
    VM_MIN_FREE="16384"       # 预留 16MB 紧急内存
elif [ "$MEM_MB" -le 2048 ]; then
    # 标准级 VPS (512MB - 2GB) - 通用模式
    # 策略：性能与稳定平衡，使用 16MB 黄金通用值
    echo_info "检测到内存为 ${MEM_MB}MB，使用 [标准性能型] 策略..."
    CONNTRACK_MAX="1048576"
    TARGET_HASHSIZE="131072"
    VM_SWAPPINESS="15"
    VM_DIRTY_RATIO="15"
    TCP_BUFFER_MAX="16777216" # 16MB 封顶（黄金值，跑满 1Gbps）
    VM_MIN_FREE="32768"       # 预留 32MB
else
    # 高性能服务器 (> 2GB) - 极速模式
    # 策略：释放性能，尽量多用物理内存
    echo_info "检测到内存为 ${MEM_MB}MB，使用 [极致性能型] 策略..."
    CONNTRACK_MAX="2621440"
    TARGET_HASHSIZE="327680"
    VM_SWAPPINESS="10"        # 尽量不用 swap
    VM_DIRTY_RATIO="20"       # 允许更多内存作为磁盘缓存
    TCP_BUFFER_MAX="33554432" # 32MB 封顶（适合 2.5G/10G 大带宽）
    VM_MIN_FREE="65536"       # 预留 64MB
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
# TCP/IP 核心优化 (BBR & 链路适配)
# =========================
# 禁止保存 TCP RTT/带宽指标，让 BBR 每次重新探测，适合网络环境变化大的情况
net.ipv4.tcp_no_metrics_save=1
# 禁用 ECN。虽然 ECN 是好技术，但在跨境链路上经常被运营商干扰，禁用可增加稳定性
net.ipv4.tcp_ecn=0
# 禁用 F-RTO，在 BBR 算法下通常不需要，减少干扰
net.ipv4.tcp_frto=0
# 开启 MTU 探测，这是 VPN/隧道 必须开启的，防止因 MTU 不匹配导致的“卡死”
net.ipv4.tcp_mtu_probing=1
# 防止 TIME_WAIT 状态下的连接被恶意重用
net.ipv4.tcp_rfc1337=1
# 开启选择性确认 (SACK)，丢包恢复的关键
net.ipv4.tcp_sack=1
# 开启窗口缩放，支持 64KB 以上的 TCP 窗口，跑满带宽必备
net.ipv4.tcp_window_scaling=1
# 接收窗口比例设定，-1 代表自动计算 (默认推荐)
net.ipv4.tcp_adv_win_scale=-1
# 自动调节接收缓冲，适应长距离传输
net.ipv4.tcp_moderate_rcvbuf=1

# 提高 TSO 自动调节灵敏度
# 改为 1 可以让 BBR 在发送小块数据时更连贯，减少延迟抖动
net.ipv4.tcp_min_tso_segs=1
# 开启 TCP RACK (RFC 8985)
# 6.x 内核的标配。它改变了丢包探测机制，不再只看序号，而是看时间戳。
# 在翻墙这种丢包、乱序严重的链路下，RACK 能让重传极其精准，不误降速
net.ipv4.tcp_recovery=1
# 乱序容忍度 (Reordering Threshold)
# 跨境链路设为 6-10 比较适合，减少误重传
net.ipv4.tcp_reordering=8
# 禁用 Autocorking，VPN 场景下希望包越快发出去越好，降低延迟
# 在高速传输时，内核会尝试合并小包。VPN 场景下，我们希望包越快发出去越好，禁用它可以降低延迟。
net.ipv4.tcp_autocorking=0
# 增加网卡处理数据包的预算。在高 PPS 流量下降低 CPU 占用
net.core.netdev_budget=600
net.core.netdev_budget_usecs=20000
# 开启 RPS 相关的流控制，有助于在多核 CPU 上均匀分发网络压力
net.core.rps_sock_flow_entries=65536
# 缩短重试次数，让死连接更快被释放
net.ipv4.tcp_orphan_retries=1

# =========================
# Google BBR 专属优化 (关键)
# =========================
# 选用 BBR 拥塞控制
net.ipv4.tcp_congestion_control=bbr
# 配合 BBR 必须使用 fq 调度算法
net.core.default_qdisc=fq
# BBR 慢启动阶段的起步倍数 (默认288/200)，330% 适合跨境激进抢占带宽
# 注：部分内核可能不直接支持通过 sysctl 修改此参数，若报错可忽略
net.ipv4.tcp_pacing_ss_ratio=330
# BBR 拥塞避免阶段的增益倍数 (默认125/112)，136% 适合对抗网络波动
net.ipv4.tcp_pacing_ca_ratio=136

# =========================
# TCP 缓冲区与内存管理
# =========================
# 注意：根据内存动态计算，否则太大会有网络延迟，太小又跑不满带宽
net.ipv4.tcp_rmem=4096 87380 $TCP_BUFFER_MAX
net.ipv4.tcp_wmem=4096 65536 $TCP_BUFFER_MAX
# 内存合并限制，减少碎片
net.ipv4.tcp_collapse_max_bytes=6291456
# 降低缓冲区未发送数据阈值，减少 Bufferbloat (延迟优化关键)
# BBR 配合此项可以显著降低大流量时的网页访问延迟
net.ipv4.tcp_notsent_lowat=16384

# =========================
# 连接保持与超时优化
# =========================
# 开启 TCP Fast Open (TFO)，设为 3 支持客户端和服务器模式
net.ipv4.tcp_fastopen=3
# 缩短孤儿连接的 FIN 等待时间
net.ipv4.tcp_fin_timeout=15
# Keepalive 时间：300秒检测一次。防止防火墙或运营商剔除长连接
net.ipv4.tcp_keepalive_time=300
net.ipv4.tcp_keepalive_intvl=15
net.ipv4.tcp_keepalive_probes=5
# 优化重传次数：跨境链路丢包率高，8次(约25-30秒)既能容忍抖动，又不会死等太久
net.ipv4.tcp_retries2=8
# 空闲后不进入慢启动，保持高速状态 (VPN 保持吞吐的关键)
net.ipv4.tcp_slow_start_after_idle=0
# 开启 TIME_WAIT 复用，应对高并发短连接
net.ipv4.tcp_tw_reuse=1
# 开启时间戳，计算 RTT 和 防止序列号回绕 (PAWS)
net.ipv4.tcp_timestamps=1

# =========================
# 防御与高并发支持
# =========================
# 开启 SYN Cookies，轻量级防御 SYN Flood
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_syn_retries=3
net.ipv4.tcp_synack_retries=3
# 加大 SYN 队列，防止握手阶段丢包
net.ipv4.tcp_max_syn_backlog=65535
# 增加最大孤儿连接数，防止大量连接断开时报错
net.ipv4.tcp_max_orphans=65535
# 增加 TIME_WAIT 桶大小
net.ipv4.tcp_max_tw_buckets=262144
# 队列满时不要直接 Reset，而是丢弃包让客户端重试 (0)，增加鲁棒性
net.ipv4.tcp_abort_on_overflow=0

# =========================
# 路由与转发
# =========================
# 开启 IP 转发 (VPN/网关必备)
net.ipv4.ip_forward=1
net.ipv4.conf.all.forwarding=1
net.ipv4.conf.default.forwarding=1
# 允许本地路由环回 (部分透明代理需要)
net.ipv4.conf.all.route_localnet=1

# =========================
# UDP & Core 队列 (针对 QUIC/Hysteria)
# =========================
# 显著增加核心缓冲区上限，防止 Hysteria 等 UDP 协议在大流量下丢包
# 注意：根据内存动态计算，否则太大会有网络延迟，太小又跑不满带宽
net.core.rmem_max=$TCP_BUFFER_MAX
net.core.wmem_max=$TCP_BUFFER_MAX
# 网卡设备积压队列
net.core.netdev_max_backlog=65535
# 监听队列上限
net.core.somaxconn=65535
# UDP 缓冲区下限优化，提升极速传输稳定性
net.ipv4.udp_rmem_min=16384
net.ipv4.udp_wmem_min=16384

# =========================
# 连接跟踪 (Conntrack) 调优
# =========================
# 提高最大连接跟踪数，防止在高并发下出现 "table full" 错误
net.netfilter.nf_conntrack_max=${CONNTRACK_MAX:-1048576}
# 建立连接超时：建议 3600(1小时)，防止 SSH 等长连接空闲断开
net.netfilter.nf_conntrack_tcp_timeout_established=3600
# 缩短这些中间状态的超时，加快条目回收
net.netfilter.nf_conntrack_tcp_timeout_close_wait=60
net.netfilter.nf_conntrack_tcp_timeout_fin_wait=120
net.netfilter.nf_conntrack_tcp_timeout_time_wait=120

# 虚拟内存优化
vm.swappiness=$VM_SWAPPINESS
vm.dirty_ratio=$VM_DIRTY_RATIO
vm.dirty_background_ratio=5
vm.min_free_kbytes=$VM_MIN_FREE
vm.vfs_cache_pressure=50
vm.overcommit_memory=1

# =========================
# 文件句柄限制
# =========================
fs.file-max=10485760
fs.nr_open=1048576
fs.inotify.max_user_instances=8192
# 扩大本地端口范围
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
  echo_info "【重要】为了使所有修改（尤其是 Hashsize 和 Systemd 限制）彻底生效，请务必执行：reboot"
}

optimizing_system