#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

cd "$(
    cd "$(dirname "$0")" || exit
    pwd
)" || exit

# fonts color
Green="\033[32m"
Red="\033[31m"
# Yellow="\033[33m"
GreenBG="\033[42;37m"
RedBG="\033[41;37m"
Font="\033[0m"

# notification information
# Info="${Green}[信息]${Font}"
OK="${Green}[OK]${Font}"
Error="${Red}[错误]${Font}"

source '/etc/os-release'

if [[ "${ID}" == "debian" ]]; then

  cat > /etc/sysctl.d/99-sysctl.conf <<EOF
# 开启数据包转发功能
net.ipv4.ip_forward=1
# 开启BBR
net.core.default_qdisc=cake
net.ipv4.tcp_congestion_control=bbr

# 默认值为32768 60999，也就是说可以对同一个服务器的ip+port创建28233个连接
net.ipv4.ip_local_port_range=1024 65000

# 内核会为Tcp维护两个队列，Syn队列和Accept队列，Syn队列是指存放完成第一次握手的连接，
# Accept队列是存放完成整个Tcp三次握手的连接，修改net.ipv4.tcp_max_syn_backlog使之增大可以接受更多的网络连接，默认128
net.ipv4.tcp_max_syn_backlog = 11000
# 开启SYN洪水攻击保护
net.ipv4.tcp_syncookies = 1
# 对于一个新建连接，内核要发送多少个 SYN 连接请求才决定放弃。默认6
net.ipv4.tcp_syn_retries = 1
# 对于远端的连接请求SYN，内核会发送SYN＋ACK数据报，以确认收到上一个 SYN连接请求包。默认5
net.ipv4.tcp_synack_retries = 1

# 表示当keepalive起用的时候，TCP发送keepalive消息的频度。缺省是2小时，改为30分钟。
net.ipv4.tcp_keepalive_time = 1800
# 如果对方不予应答，探测包的发送次数
net.ipv4.tcp_keepalive_probes = 3
# keepalive探测包的发送间隔
net.ipv4.tcp_keepalive_intvl = 15

# 关闭TCP时间戳
# 如果有一个用户的时间戳大于这个链接发出的syn中的时间戳，服务器上就会忽略掉这个syn，
# 不返会syn-ack消息，表现为用户无法正常完成tcp3次握手，从而不能打开web页面
net.ipv4.tcp_timestamps = 0
# 表示开启重用。允许将TIME-WAIT sockets重新用于新的TCP连接，默认为0，表示关闭；
net.ipv4.tcp_tw_reuse = 1
# 表示开启TCP连接中TIME-WAIT sockets的快速回收，默认为0，表示关闭。 !!!新版内核已废弃该参数!!!
# net.ipv4.tcp_tw_recycle = 1
# 表示如果套接字由本端要求关闭，这个参数决定了它保持在FIN-WAIT-2状态的时间。
net.ipv4.tcp_fin_timeout = 10
# 表示系统同时保持TIME_WAIT套接字的最大数量。默认8192
net.ipv4.tcp_max_tw_buckets = 10000

# 该参数决定了，网络设备接收数据包的速率比内核处理这些包的速率快时，允许送到队列的数据包的最大数目。默认1000
net.core.netdev_max_backlog = 400000
# Linux kernel参数，表示socket监听的backlog(监听队列)上限。默认4096
net.core.somaxconn = 100000
# 路由缓存刷新频率，当一个路由失败后多长时间跳到另一个路由，默认是300。
net.ipv4.route.gc_timeout = 100
# 关闭tcp的连接传输的慢启动，即先休止一段时间，再初始化拥塞窗口。
# 可以避免tcp连接qps不高的情况下，每一个请求都经历慢启动过程，从而提高网络传输速度。
net.ipv4.tcp_slow_start_after_idle = 0
# 最大孤儿套接字(orphan sockets)数
net.ipv4.tcp_max_orphans = 32768

# 每次软中断处理的网络包个数
net.core.netdev_budget = 50000
net.core.netdev_budget_usecs = 5000
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 67108864
net.core.wmem_default = 67108864
net.core.optmem_max = 65536

net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
EOF
      echo
      sysctl -p
      echo -e "---------------------------------------------------------------"
      echo
      sysctl --system
fi