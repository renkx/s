#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#fonts color
Green="\033[32m"
Red="\033[31m"
# Yellow="\033[33m"
# 有背景的绿色
GreenBG="\033[42;37m"
# 有背景的红色
RedBG="\033[41;37m"
Font="\033[0m"

#notification information
Info="${Green}[信息]${Font}"
OK="${Green}[OK]${Font}"
Error="${Red}[错误]${Font}"

echo_info() {
  # shellcheck disable=SC2145
  echo -e "${Info} ${GreenBG} $@ ${Font}"
}

echo_ok() {
  # shellcheck disable=SC2145
  echo -e "${OK} ${GreenBG} $@ ${Font}"
}

echo_error() {
  # shellcheck disable=SC2145
  echo -e "${Error} ${RedBG} $@ ${Font}" >&2
}

# 依据上个命令是否成功，判断是否继续执行
judge() {
  if [[ 0 -eq $? ]]; then
    echo_ok "$1 完成"
    sleep 1
  else
    echo_error "$1 失败"
    exit 1
  fi
}

# 检测执行结果，并输出相应的提示信息
check_result() {
  if [[ 0 -eq $? ]]; then
    echo_ok "$1 [成功]"
  else
    echo_error "$1 [失败]"
  fi
}

# 检查当前用户是否为 root 用户
if [ "$EUID" -ne 0 ]; then
  echo_error "请使用 root 用户身份运行此脚本"
  exit
fi

# 获取系统相关参数
source '/etc/os-release'

# 从VERSION中提取发行版系统的英文名称，为了在debian/ubuntu下添加相对应的Nginx apt源
VERSION=$(echo "${VERSION}" | awk -F "[()]" '{print $2}')

echo_info "检测是否能ping谷歌"
IsGlobal="0"
delay="$(ping -4 -c 2 -w 2 www.google.com | grep rtt | cut -d'/' -f4 | awk '{ print $3 }' | sed -n '/^[0-9]\+\(\.[0-9]\+\)\?$/p')";
if [ "$delay" != "" ] ; then
	IsGlobal="1"
	echo_info "延迟：$delay ms , ping yes"
else
  echo_info "延迟：$delay ms , ping no"
fi

judge() {
    if [[ 0 -eq $? ]]; then
        echo -e "${OK} ${GreenBG} $1 完成 ${Font}"
        sleep 1
    else
        echo -e "${Error} ${RedBG} $1 失败${Font}"
        exit 1
    fi
}

install_docker() {
  if [[ "$IsGlobal" == "1" ]];then
    echo_info "执行【github】的脚本 ..."
    bash <(curl -sSL https://raw.githubusercontent.com/renkx/s/main/install_docker.sh)
  else
    echo_info "执行【gitee】的脚本 ..."
    bash <(curl -sSL https://gitee.com/renkx/ss/raw/main/install_docker.sh)
  fi
}

install_docker_compose()
{
  if [[ "$IsGlobal" == "1" ]];then
    echo_info "执行【github】的脚本 ..."
    bash <(curl -sSL https://raw.githubusercontent.com/renkx/s/main/install_docker_compose.sh)
  else
    echo_info "执行【gitee】的脚本 ..."
    bash <(curl -sSL https://gitee.com/renkx/ss/raw/main/install_docker_compose.sh)
  fi
}

install_on_my_zsh()
{
  if [[ "$IsGlobal" == "1" ]];then
    echo_info "执行【github】的脚本 ..."
    bash <(curl -sSL https://raw.githubusercontent.com/renkx/s/main/myzsh.sh)
  else
    echo_info "执行【gitee】的脚本 ..."
    bash <(curl -sSL https://gitee.com/renkx/ss/raw/main/myzsh.sh)
  fi
}

# 系统优化
optimizing_system() {
  if [ ! -f "/etc/sysctl.d/99-sysctl.conf" ]; then
    touch /etc/sysctl.d/99-sysctl.conf
  fi

# 该操作会取消软链接
# 新系统是 99-sysctl.conf -> ../sysctl.conf
# 不需要更改sysctl.conf ，所以执行下面的替换操作，可以取消软链接
sed -i '/renkx/d' /etc/sysctl.d/99-sysctl.conf

# 覆盖写入
  cat >'/etc/sysctl.d/99-sysctl.conf' <<EOF
net.ipv4.tcp_fack = 1
net.ipv4.tcp_early_retrans = 3
net.ipv4.neigh.default.unres_qlen=10000
net.ipv4.conf.all.route_localnet=1
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.default.forwarding = 1
#net.ipv6.conf.all.forwarding = 1  #awsipv6问题
net.ipv6.conf.default.forwarding = 1
net.ipv6.conf.lo.forwarding = 1
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.lo.disable_ipv6 = 0
net.ipv6.conf.all.accept_ra = 2
net.ipv6.conf.default.accept_ra = 2
net.core.netdev_max_backlog = 100000
net.core.netdev_budget = 50000
net.core.netdev_budget_usecs = 5000
#fs.file-max = 51200
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 67108864
net.core.wmem_default = 67108864
net.core.optmem_max = 65536
net.core.somaxconn = 1000000
net.ipv4.icmp_echo_ignore_all = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.all.rp_filter = 0
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 2
net.ipv4.tcp_synack_retries = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 0
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_tw_reuse = 0
net.ipv4.tcp_fin_timeout = 15
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_autocorking = 0
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_max_syn_backlog = 819200
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_no_metrics_save = 0
net.ipv4.tcp_ecn = 1
net.ipv4.tcp_ecn_fallback = 1
net.ipv4.tcp_frto = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.neigh.default.gc_thresh3=8192
net.ipv4.neigh.default.gc_thresh2=4096
net.ipv4.neigh.default.gc_thresh1=2048
net.ipv6.neigh.default.gc_thresh3=8192
net.ipv6.neigh.default.gc_thresh2=4096
net.ipv6.neigh.default.gc_thresh1=2048
net.ipv4.tcp_orphan_retries = 1
net.ipv4.tcp_retries2 = 5
vm.swappiness = 1
vm.overcommit_memory = 1
kernel.pid_max=64000
net.netfilter.nf_conntrack_max = 262144
net.nf_conntrack_max = 262144
net.netfilter.nf_conntrack_icmp_timeout=10
net.netfilter.nf_conntrack_tcp_timeout_syn_recv=5
net.netfilter.nf_conntrack_tcp_timeout_syn_sent=5
net.netfilter.nf_conntrack_tcp_timeout_established=600
net.netfilter.nf_conntrack_tcp_timeout_fin_wait=10
net.netfilter.nf_conntrack_tcp_timeout_time_wait=10
net.netfilter.nf_conntrack_tcp_timeout_close_wait=10
net.netfilter.nf_conntrack_tcp_timeout_last_ack=10
## Enable bbr
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_low_latency = 1
EOF

  # 载入配置使其生效
  sysctl -p
  sysctl --system
  #
  echo always >/sys/kernel/mm/transparent_hugepage/enabled

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

  cat >'/etc/security/limits.conf' <<EOF
root     soft   nofile    1000000
root     hard   nofile    1000000
root     soft   nproc     unlimited
root     hard   nproc     unlimited
root     soft   core      unlimited
root     hard   core      unlimited
root     hard   memlock   unlimited
root     soft   memlock   unlimited
*     soft   nofile    1000000
*     hard   nofile    1000000
*     soft   nproc     unlimited
*     hard   nproc     unlimited
*     soft   core      unlimited
*     hard   core      unlimited
*     hard   memlock   unlimited
*     soft   memlock   unlimited
EOF

  sed -i '/ulimit -SHn/d' /etc/profile
  sed -i '/ulimit -SHu/d' /etc/profile
  echo "ulimit -SHn 1000000" >>/etc/profile

  if grep -q "pam_limits.so" /etc/pam.d/common-session; then
    :
  else
    sed -i '/required pam_limits.so/d' /etc/pam.d/common-session
    echo "session required pam_limits.so" >>/etc/pam.d/common-session
  fi
  systemctl daemon-reload

  echo_info "优化应用结束，需要重启！"
}

# 只能升级debian系统
upgrading_system() {
  # 升级内核
  bash <(curl -sSL https://raw.githubusercontent.com/renkx/s/main/upgrading_system.sh)
}

# 虚拟内存设置
update_swap() {
  if [[ "$IsGlobal" == "1" ]];then
    echo_info "执行【github】的脚本 ..."
    bash <(curl -sSL https://raw.githubusercontent.com/renkx/s/main/swap.sh)
  else
    echo_info "执行【gitee】的脚本 ..."
    bash <(curl -sSL https://gitee.com/renkx/ss/raw/main/swap.sh)
  fi
}

# 安装 ag
install_ag()
{
  if [ ! -d ~/ag/ ]; then
    mkdir -p ~/ag/
    judge "创建目录 (mkdir -p ~/ag/)"

    if [[ "$IsGlobal" == "1" ]];then
      echo_info "git拉取【github】ag ..."
      git clone https://github.com/renkx/ag.git ~/ag/
    else
      echo_info "git拉取【gitee】ag ..."
      git clone https://gitee.com/renkx/ag.git ~/ag/
    fi
    judge "安装 ag"
    ln -sf ~/ag/default.env ~/ag/.env
    judge "创建软链接 (ln -sf ~/ag/default.env ~/ag/.env) "
    if [ ! -d ~/ag/conf/default/ ]; then
        mkdir -p ~/ag/conf/default/
        judge "创建目录 (mkdir -p ~/ag/conf/default/)"
    fi
  fi
}

# 更新 nameserver
update_nameserver()
{
  chattr -i /etc/resolv.conf
  judge "chattr -i /etc/resolv.conf 解锁"
  # 锁定DNS解析（第一个异常会请求第二个，为了防止docker容器还没启动。比如warp就会出问题）

  if [[ "$IsGlobal" == "1" ]];then
  echo_info "8.8.8.8 设置中。。。"
  cat >/etc/resolv.conf <<'EOF'
nameserver 127.0.0.1
nameserver 8.8.8.8
EOF
  else
  echo_info "223.5.5.5 设置中。。。"
  cat >/etc/resolv.conf <<'EOF'
nameserver 127.0.0.1
nameserver 223.5.5.5
EOF
  fi

  judge "设置 nameserver"

  chattr +i /etc/resolv.conf
  judge "chattr +i /etc/resolv.conf 加锁"
}

get_opsy() {
  if [ -f /etc/os-release ]; then
    awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release
  elif [ -f /etc/lsb-release ]; then
    awk -F'[="]+' '/DESCRIPTION/{print $2}' /etc/lsb-release
  elif [ -f /etc/system-release ]; then
    cat /etc/system-release | awk '{print $1,$2}'
  fi
}

get_system_info() {
  opsy=$(get_opsy)
  arch=$(uname -m)
  kern=$(uname -r)
  virt_check
}

# from LemonBench
virt_check() {
  if [ -f "/usr/bin/systemd-detect-virt" ]; then
    Var_VirtType="$(/usr/bin/systemd-detect-virt)"
    # 虚拟机检测
    if [ "${Var_VirtType}" = "qemu" ]; then
      virtual="QEMU"
    elif [ "${Var_VirtType}" = "kvm" ]; then
      virtual="KVM"
    elif [ "${Var_VirtType}" = "zvm" ]; then
      virtual="S390 Z/VM"
    elif [ "${Var_VirtType}" = "vmware" ]; then
      virtual="VMware"
    elif [ "${Var_VirtType}" = "microsoft" ]; then
      virtual="Microsoft Hyper-V"
    elif [ "${Var_VirtType}" = "xen" ]; then
      virtual="Xen Hypervisor"
    elif [ "${Var_VirtType}" = "bochs" ]; then
      virtual="BOCHS"
    elif [ "${Var_VirtType}" = "uml" ]; then
      virtual="User-mode Linux"
    elif [ "${Var_VirtType}" = "parallels" ]; then
      virtual="Parallels"
    elif [ "${Var_VirtType}" = "bhyve" ]; then
      virtual="FreeBSD Hypervisor"
    # 容器虚拟化检测
    elif [ "${Var_VirtType}" = "openvz" ]; then
      virtual="OpenVZ"
    elif [ "${Var_VirtType}" = "lxc" ]; then
      virtual="LXC"
    elif [ "${Var_VirtType}" = "lxc-libvirt" ]; then
      virtual="LXC (libvirt)"
    elif [ "${Var_VirtType}" = "systemd-nspawn" ]; then
      virtual="Systemd nspawn"
    elif [ "${Var_VirtType}" = "docker" ]; then
      virtual="Docker"
    elif [ "${Var_VirtType}" = "rkt" ]; then
      virtual="RKT"
    # 特殊处理
    elif [ -c "/dev/lxss" ]; then # 处理WSL虚拟化
      Var_VirtType="wsl"
      virtual="Windows Subsystem for Linux (WSL)"
    # 未匹配到任何结果, 或者非虚拟机
    elif [ "${Var_VirtType}" = "none" ]; then
      Var_VirtType="dedicated"
      virtual="None"
      local Var_BIOSVendor
      Var_BIOSVendor="$(dmidecode -s bios-vendor)"
      if [ "${Var_BIOSVendor}" = "SeaBIOS" ]; then
        Var_VirtType="Unknown"
        virtual="Unknown with SeaBIOS BIOS"
      else
        Var_VirtType="dedicated"
        virtual="Dedicated with ${Var_BIOSVendor} BIOS"
      fi
    fi
  elif [ ! -f "/usr/sbin/virt-what" ]; then
    Var_VirtType="Unknown"
    virtual="[Error: virt-what not found !]"
  elif [ -f "/.dockerenv" ]; then # 处理Docker虚拟化
    Var_VirtType="docker"
    virtual="Docker"
  elif [ -c "/dev/lxss" ]; then # 处理WSL虚拟化
    Var_VirtType="wsl"
    virtual="Windows Subsystem for Linux (WSL)"
  else # 正常判断流程
    Var_VirtType="$(virt-what | xargs)"
    local Var_VirtTypeCount
    Var_VirtTypeCount="$(echo $Var_VirtTypeCount | wc -l)"
    if [ "${Var_VirtTypeCount}" -gt "1" ]; then # 处理嵌套虚拟化
      virtual="echo ${Var_VirtType}"
      Var_VirtType="$(echo ${Var_VirtType} | head -n1)"                          # 使用检测到的第一种虚拟化继续做判断
    elif [ "${Var_VirtTypeCount}" -eq "1" ] && [ "${Var_VirtType}" != "" ]; then # 只有一种虚拟化
      virtual="${Var_VirtType}"
    else
      local Var_BIOSVendor
      Var_BIOSVendor="$(dmidecode -s bios-vendor)"
      if [ "${Var_BIOSVendor}" = "SeaBIOS" ]; then
        Var_VirtType="Unknown"
        virtual="Unknown with SeaBIOS BIOS"
      else
        Var_VirtType="dedicated"
        virtual="Dedicated with ${Var_BIOSVendor} BIOS"
      fi
    fi
  fi
}

# 检查系统当前状态
check_status() {
  kernel_version=$(uname -r | awk -F "-" '{print $1}')
  kernel_version_full=$(uname -r)
  net_congestion_control=$(cat /proc/sys/net/ipv4/tcp_congestion_control | awk '{print $1}')
  net_qdisc=$(cat /proc/sys/net/core/default_qdisc | awk '{print $1}')
  if [[ ${kernel_version_full} == *bbrplus* ]]; then
    kernel_status="BBRplus"
  elif [[ ${kernel_version_full} == *4.9.0-4* || ${kernel_version_full} == *4.15.0-30* || ${kernel_version_full} == *4.8.0-36* || ${kernel_version_full} == *3.16.0-77* || ${kernel_version_full} == *3.16.0-4* || ${kernel_version_full} == *3.2.0-4* || ${kernel_version_full} == *4.11.2-1* || ${kernel_version_full} == *2.6.32-504* || ${kernel_version_full} == *4.4.0-47* || ${kernel_version_full} == *3.13.0-29 || ${kernel_version_full} == *4.4.0-47* ]]; then
    kernel_status="Lotserver"
  elif [[ $(echo ${kernel_version} | awk -F'.' '{print $1}') == "4" ]] && [[ $(echo ${kernel_version} | awk -F'.' '{print $2}') -ge 9 ]] || [[ $(echo ${kernel_version} | awk -F'.' '{print $1}') == "5" ]] || [[ $(echo ${kernel_version} | awk -F'.' '{print $1}') == "6" ]]; then
    kernel_status="BBR"
  else
    kernel_status="noinstall"
  fi

  if [[ ${kernel_status} == "BBR" ]]; then
    run_status=$(cat /proc/sys/net/ipv4/tcp_congestion_control | awk '{print $1}')
    if [[ ${run_status} == "bbr" ]]; then
      run_status=$(cat /proc/sys/net/ipv4/tcp_congestion_control | awk '{print $1}')
      if [[ ${run_status} == "bbr" ]]; then
        run_status="BBR启动成功"
      else
        run_status="BBR启动失败"
      fi
    elif [[ ${run_status} == "bbr2" ]]; then
      run_status=$(cat /proc/sys/net/ipv4/tcp_congestion_control | awk '{print $1}')
      if [[ ${run_status} == "bbr2" ]]; then
        run_status="BBR2启动成功"
      else
        run_status="BBR2启动失败"
      fi
    elif [[ ${run_status} == "tsunami" ]]; then
      run_status=$(lsmod | grep "tsunami" | awk '{print $1}')
      if [[ ${run_status} == "tcp_tsunami" ]]; then
        run_status="BBR魔改版启动成功"
      else
        run_status="BBR魔改版启动失败"
      fi
    elif [[ ${run_status} == "nanqinlang" ]]; then
      run_status=$(lsmod | grep "nanqinlang" | awk '{print $1}')
      if [[ ${run_status} == "tcp_nanqinlang" ]]; then
        run_status="暴力BBR魔改版启动成功"
      else
        run_status="暴力BBR魔改版启动失败"
      fi
    else
      run_status="未安装加速模块"
    fi

  elif [[ ${kernel_status} == "Lotserver" ]]; then
    if [[ -e /appex/bin/lotServer.sh ]]; then
      run_status=$(bash /appex/bin/lotServer.sh status | grep "LotServer" | awk '{print $3}')
      if [[ ${run_status} == "running!" ]]; then
        run_status="启动成功"
      else
        run_status="启动失败"
      fi
    else
      run_status="未安装加速模块"
    fi
  elif [[ ${kernel_status} == "BBRplus" ]]; then
    run_status=$(cat /proc/sys/net/ipv4/tcp_congestion_control | awk '{print $1}')
    if [[ ${run_status} == "bbrplus" ]]; then
      run_status=$(cat /proc/sys/net/ipv4/tcp_congestion_control | awk '{print $1}')
      if [[ ${run_status} == "bbrplus" ]]; then
        run_status="BBRplus启动成功"
      else
        run_status="BBRplus启动失败"
      fi
    elif [[ ${run_status} == "bbr" ]]; then
      run_status="BBR启动成功"
    else
      run_status="未安装加速模块"
    fi
  fi
}

menu() {

    echo
    echo -e "${GreenBG}—————————————— 安装向导 ——————————————${Font}"
    echo -e "${Green}0.${Font} 退出"
    echo -e "${Green}1.${Font} 系统优化"
    echo -e "${Green}2.${Font} 安装 docker"
    echo -e "${Green}3.${Font} 安装 docker-compose"
    echo -e "${Green}4.${Font} 安装 on-my-zsh"
    echo -e "${Green}5.${Font} 安装 ag"
    echo -e "${Green}6.${Font} 卸载 qemu-guest-agent"
    echo -e "${Green}7.${Font} 更新 /etc/resolv.conf"
    echo -e "${Green}8.${Font} 虚拟内存设置"
    echo -e "${Green}33.${Font} 一键 1、2、3、4、5、6、7"
    echo -e "————————————————————————————————————————————————————————————————"

    check_status
    get_system_info
    echo -e " 系统信息: $opsy ${Green}$virtual${Font} $arch ${Green}$kern${Font} "
    if [[ ${kernel_status} == "noinstall" ]]; then
      echo -e " 当前状态: 未安装 加速内核 请先安装内核"
    else
      echo -e " 当前状态: ${Green}已安装${Font} ${Red}${kernel_status}${Font} 加速内核 , ${Green}${run_status}${Font}"
    fi
    echo -e " 当前拥塞控制算法为: ${Green}${net_congestion_control}${Font} 当前队列算法为: ${Green}${net_qdisc}${Font} "

    read -rp " 请输入数字：" menu_num
    case $menu_num in
    0)
        exit 0
        ;;
    1)
        optimizing_system
        menu
        ;;
    2)
        install_docker
        menu
        ;;
    3)
        install_docker_compose
        menu
        ;;
    4)
        install_on_my_zsh
        menu
        ;;
    5)
        install_ag
        menu
        ;;
    6)
        apt -y autoremove --purge qemu-guest-agent
        menu
        ;;
    7)
        update_nameserver
        menu
        ;;
    8)
        update_swap
        menu
        ;;
    33)
        optimizing_system
        install_docker
        install_docker_compose
        install_on_my_zsh
        install_ag
        apt -y autoremove --purge qemu-guest-agent
        update_nameserver
        menu
        ;;
    *)
        echo -e "${RedBG}请输入正确的数字${Font}"
        menu
        ;;
    esac
}

menu
