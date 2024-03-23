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

# 直接开始系统优化
export startOptimizing='0'

while [[ $# -ge 1 ]]; do
	case $1 in
	--startOptimizing)
		shift
		startOptimizing="1"
		;;
	*)
		echo -ne "\nInvaild option: '$1'\n\n";
		exit 1
		;;
	esac
done

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

_exists() {
    local cmd="$1"
    if eval type type >/dev/null 2>&1; then
        eval type "$cmd" >/dev/null 2>&1
    elif command >/dev/null 2>&1; then
        command -v "$cmd" >/dev/null 2>&1
    else
        which "$cmd" >/dev/null 2>&1
    fi
    local rt=$?
    return ${rt}
}

# 检查虚拟化类型
check_virt() {
    _exists "dmesg" && virtualx="$(dmesg 2>/dev/null)"
    if _exists "dmidecode"; then
        sys_manu="$(dmidecode -s system-manufacturer 2>/dev/null)"
        sys_product="$(dmidecode -s system-product-name 2>/dev/null)"
        sys_ver="$(dmidecode -s system-version 2>/dev/null)"
    else
        sys_manu=""
        sys_product=""
        sys_ver=""
    fi
    if grep -qa docker /proc/1/cgroup; then
        virt="Docker"
    elif grep -qa lxc /proc/1/cgroup; then
        virt="LXC"
    elif grep -qa container=lxc /proc/1/environ; then
        virt="LXC"
    elif [[ -f /proc/user_beancounters ]]; then
        virt="OpenVZ"
    elif [[ "${virtualx}" == *kvm-clock* ]]; then
        virt="KVM"
    elif [[ "${sys_product}" == *KVM* ]]; then
        virt="KVM"
    elif [[ "${cname}" == *KVM* ]]; then
        virt="KVM"
    elif [[ "${cname}" == *QEMU* ]]; then
        virt="KVM"
    elif [[ "${virtualx}" == *"VMware Virtual Platform"* ]]; then
        virt="VMware"
    elif [[ "${sys_product}" == *"VMware Virtual Platform"* ]]; then
        virt="VMware"
    elif [[ "${virtualx}" == *"Parallels Software International"* ]]; then
        virt="Parallels"
    elif [[ "${virtualx}" == *VirtualBox* ]]; then
        virt="VirtualBox"
    elif [[ -e /proc/xen ]]; then
        if grep -q "control_d" "/proc/xen/capabilities" 2>/dev/null; then
            virt="Xen-Dom0"
        else
            virt="Xen-DomU"
        fi
    elif [ -f "/sys/hypervisor/type" ] && grep -q "xen" "/sys/hypervisor/type"; then
        virt="Xen"
    elif [[ "${sys_manu}" == *"Microsoft Corporation"* ]]; then
        if [[ "${sys_product}" == *"Virtual Machine"* ]]; then
            if [[ "${sys_ver}" == *"7.0"* || "${sys_ver}" == *"Hyper-V" ]]; then
                virt="Hyper-V"
            else
                virt="Microsoft Virtual Machine"
            fi
        fi
    else
        virt="Dedicated"
    fi
}

install_base() {
  if [[ "$IsGlobal" == "1" ]];then
    echo_info "执行【github】的脚本 ..."
    bash <(curl -sSL https://raw.githubusercontent.com/renkx/s/main/install_base.sh)
  else
    echo_info "执行【gitee】的脚本 ..."
    bash <(curl -sSL https://gitee.com/renkx/ss/raw/main/install_base.sh)
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
  # 更新
  apt update
  # 检查虚拟化类型
  check_virt

  # 获取网卡接口名称
  nic_interface=$(ip addr | grep 'state UP' | awk '{print $2}' | sed 's/.$//')

  # 安装 ethtool（如果未安装）
  if ! [ -x "$(command -v ethtool)" ]; then
      apt -y install ethtool
  fi

  # 检查系统虚拟化类型，如果是 KVM，则关闭 TSO 和 GSO
  if [ "$virt" == "KVM" ]; then
      echo_info "系统虚拟化类型为 KVM，正在关闭 TSO 和 GSO..."
      for interface in $nic_interface; do
          ethtool -K $interface tso off gso off
          echo_info "TSO 和 GSO 关闭于接口 $interface"
      done
  else
      echo_info "系统虚拟化类型非 KVM，不需要关闭 TSO 和 GSO。"
  fi

  echo_info "正在安装 haveged 增强性能中！"
  apt install haveged -y
  echo_ok "安装 haveged"

  echo_info "正在配置 haveged 增强性能中！"
  systemctl disable --now haveged
  systemctl enable --now haveged

  if [ ! -f "/etc/sysctl.d/optimizing-sysctl.conf" ]; then
    touch /etc/sysctl.d/optimizing-sysctl.conf
  fi

# 覆盖写入
  cat >'/etc/sysctl.d/optimizing-sysctl.conf' <<EOF
net.ipv4.tcp_no_metrics_save=1
net.ipv4.tcp_ecn=0
net.ipv4.tcp_frto=0
net.ipv4.tcp_mtu_probing=0
net.ipv4.tcp_rfc1337=0
net.ipv4.tcp_sack=1
net.ipv4.tcp_fack=1
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_adv_win_scale=1
net.ipv4.tcp_moderate_rcvbuf=1
net.core.rmem_max=33554432
net.core.wmem_max=33554432
net.ipv4.tcp_rmem=4096 87380 33554432
net.ipv4.tcp_wmem=4096 16384 33554432
net.ipv4.udp_rmem_min=8192
net.ipv4.udp_wmem_min=8192
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
# 开启内核转发
net.ipv4.conf.all.route_localnet=1
net.ipv4.ip_forward=1
net.ipv4.conf.all.forwarding=1
net.ipv4.conf.default.forwarding=1
# Linux 连接跟踪调优
net.netfilter.nf_conntrack_max = 2621440
net.netfilter.nf_conntrack_tcp_timeout_established=600
EOF

  # 载入配置使其生效
  sysctl -p
  sysctl --system

  # 参考：https://www.emqx.com/zh/blog/emqx-performance-tuning-linux-conntrack-and-mqtt-connections
  # Docker 等应用正在依赖 conntrack 提供服务，我们无法直接关闭它
  # 由于在 Linux 的启动过程中，sysctl 参数设置发生在 nf_conntrack 模块加载之前，
  # 所以仅仅将nf_conntrack_max 等参数的配置写入 /etc/sysctl.conf 中并不能直接令其生效。这也是 sysctl 的一个已知问题
  # 想要解决这个问题，我们可以在 /etc/udev/rules.d 中创建一个 50-nf_conntrack.rules 文件，
  # 然后添加以下 udev 规则，表示仅在 nf_conntrack 模块加载时才执行相应的参数设置：
  cat >'/etc/udev/rules.d/50-nf_conntrack.rules' <<EOF
ACTION=="add", SUBSYSTEM=="module", KERNEL=="nf_conntrack", RUN+="/usr/lib/systemd/systemd-sysctl --prefix=/net/netfilter"
EOF

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

  # 系统日志调整
  cat >'/etc/systemd/journald.conf' <<EOF
[Journal]
SystemMaxUse=300M
SystemMaxFileSize=50M
RuntimeMaxUse=30M
RuntimeMaxFileSize=5M
ForwardToSyslog=no
EOF
  systemctl restart systemd-journald

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

# 更新motd
update_motd() {
  # 删除原有的
  rm -rf /etc/update-motd.d/ /etc/motd /run/motd.dynamic
  mkdir -p /etc/update-motd.d/

    cat >/etc/update-motd.d/00-header <<'EOF'
#!/bin/sh

if
	[ -z "$DISTRIB_DESCRIPTION" ]
	[ -x /usr/bin/lsb_release ]
then
	# Fall back to using the very slow lsb_release utility
	DISTRIB_DESCRIPTION=$(lsb_release -s -d)
fi

printf "Welcome to %s (%s)\n" "$DISTRIB_DESCRIPTION" "$(uname -r)"
printf "\n"
EOF

    cat >/etc/update-motd.d/10-sysinfo <<'EOF'
#!/bin/bash

date=$(date)
load=$(cat /proc/loadavg | awk '{print $1}')
root_usage=$(df -h / | awk '/\// {print $(NF-1)}')
memory_usage=$(free -m | awk '/Mem:/ { total=$2; used=$3 } END { printf("%3.1f%%", used/total*100)}')

[[ $(free -m | awk '/Swap/ {print $2}') == "0" ]] && swap_usage="0.0%" || swap_usage=$(free -m | awk '/Swap/ { printf("%3.1f%%", $3/$2*100) }')
usersnum=$(expr $(users | wc -w) + 1)
time=$(uptime | grep -ohe 'up .*' | sed 's/,/\ hours/g' | awk '{ printf $2" "$3 }')
processes=$(ps aux | wc -l)
localip=$(hostname -I | awk '{print $1}')

IPv4=$(timeout 1s dig -4 TXT +short o-o.myaddr.l.google.com @ns3.google.com | sed 's/\"//g')
[[ "$IPv4" == "" ]] && IPv4=$(timeout 1s dig -4 TXT CH +short whoami.cloudflare @1.0.0.3 | sed 's/\"//g')
IPv6=$(timeout 1s dig -6 TXT +short o-o.myaddr.l.google.com @ns3.google.com | sed 's/\"//g')
[[ "$IPv6" == "" ]] && IPv6=$(timeout 1s dig -6 TXT CH +short whoami.cloudflare @2606:4700:4700::1003 | sed 's/\"//g')
# IP_Check=$(echo $IPv4 | awk -F. '$1<255&&$2<255&&$3<255&&$4<255{print "isIPv4"}')
IP_Check="$IPv4"
if expr "$IP_Check" : '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$' >/dev/null; then
	for i in 1 2 3 4; do
		if [ $(echo "$IP_Check" | cut -d. -f$i) -gt 255 ]; then
			echo "fail ($IP_Check)"
			exit 1
		fi
	done
	IP_Check="isIPv4"
fi

[[ ${IPv6: -1} == ":" ]] && IPv6=$(echo "$IPv6" | sed 's/.$/0/')
[[ ${IPv6:0:1} == ":" ]] && IPv6=$(echo "$IPv6" | sed 's/^./0/')
IP6_Check="$IPv6"":"
IP6_Hex_Num=$(echo "$IP6_Check" | tr -cd ":" | wc -c)
IP6_Hex_Abbr="0"
if [[ $(echo "$IPv6" | grep -i '[[:xdigit:]]' | grep ':') ]] && [[ "$IP6_Hex_Num" -le "8" ]]; then
	for ((i = 1; i <= "$IP6_Hex_Num"; i++)); do
		IP6_Hex=$(echo "$IP6_Check" | cut -d: -f$i)
		[[ "$IP6_Hex" == "" ]] && IP6_Hex_Abbr=$(expr $IP6_Hex_Abbr + 1)
		[[ $(echo "$IP6_Hex" | wc -c) -le "4" ]] && {
			if [[ $(echo "$IP6_Hex" | grep -iE '[^0-9a-f]') ]] || [[ "$IP6_Hex_Abbr" -gt "1" ]]; then
				echo "fail ($IP6_Check)"
				exit 1
			fi
		}
	done
	IP6_Check="isIPv6"
fi

[[ "${IP6_Check}" != "isIPv6" ]] && IPv6="N/A"

[[ "${IP_Check}" != "isIPv4" ]] && IPv4="N/A"

if [[ "${localip}" == "${IPv4}" ]] || [[ "${localip}" == "${IPv6}" ]] || [[ -z "${localip}" ]]; then
	# localip=`ip -o a show | grep -w "lo" | grep -w "inet" | cut -d ' ' -f7 | awk '{split($1, a, "/"); print $2 "" a[1]}'`
	localip=$(cat /etc/hosts | grep "localhost" | sed -n 1p | awk '{print $1}')
fi

echo " System information as of $date"
echo
printf "%-30s%-15s\n" " System Load:" "$load"
printf "%-30s%-15s\n" " Private IP Address:" "$localip"
printf "%-30s%-15s\n" " Public IPv4 Address:" "$IPv4"
printf "%-30s%-15s\n" " Public IPv6 Address:" "$IPv6"
printf "%-30s%-15s\n" " Memory Usage:" "$memory_usage"
printf "%-30s%-15s\n" " Usage On /:" "$root_usage"
printf "%-30s%-15s\n" " Swap Usage:" "$swap_usage"
printf "%-30s%-15s\n" " Users Logged In:" "$usersnum"
printf "%-30s%-15s\n" " Processes:" "$processes"
printf "%-30s%-15s\n" " System Uptime:" "$time"
echo
EOF

    cat >/etc/update-motd.d/90-footer <<'EOF'
#!/bin/sh

UpdateLog="/var/log/PackagesUpdatingStatus.log"
if [ -f "$UpdateLog" ]; then
    rm -rf $UpdateLog
fi

apt list --upgradable 2>/dev/null | awk 'END{print NR}' | tee -a "$UpdateLog" >/dev/null 2>&1
UpdateRemind=$(cat $UpdateLog | tail -n 1)
UpdateNum=$(expr $UpdateRemind - 1)

[ "$UpdateNum" -eq "1" ] && printf "$UpdateNum package can be upgraded. Run 'apt list --upgradable' to see it.\n"
[ "$UpdateNum" -gt "1" ] && printf "$UpdateNum packages can be upgraded. Run 'apt list --upgradable' to see them.\n"

rm -rf $UpdateLog
EOF

    chmod +x /etc/update-motd.d/00-header
    chmod +x /etc/update-motd.d/10-sysinfo
    chmod +x /etc/update-motd.d/90-footer
}

menu() {

    echo
    echo -e "${GreenBG}—————————————— 安装向导 ——————————————${Font}"
    echo -e "${Green}0.${Font} 退出"
    echo -e "${Green}1.${Font} 系统优化"
    echo -e "${Green}2.${Font} 安装 系统基础"
    echo -e "${Green}3.${Font} 安装 docker"
    echo -e "${Green}4.${Font} 安装 on-my-zsh"
    echo -e "${Green}5.${Font} 安装 ag"
    echo -e "${Green}6.${Font} 更新 motd"
    echo -e "${Green}7.${Font} 更新 nameserver"
    echo -e "${Green}8.${Font} 卸载 qemu-guest-agent"
    echo -e "${Green}9.${Font} 虚拟内存设置"
    echo -e "${Green}33.${Font} 一键 1、2、3、4、5、6、7、8"
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
        install_base
        menu
        ;;
    3)
        install_docker
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
        update_motd
        menu
        ;;
    7)
        update_nameserver
        menu
        ;;
    8)
        apt -y autoremove --purge qemu-guest-agent
        menu
        ;;
    9)
        update_swap
        menu
        ;;
    33)
        optimizing_system
        install_base
        install_docker
        install_on_my_zsh
        install_ag
        update_motd
        update_nameserver
        apt -y autoremove --purge qemu-guest-agent
        menu
        ;;
    *)
        echo -e "${RedBG}请输入正确的数字${Font}"
        menu
        ;;
    esac
}

# 直接开始系统优化
if [[ "$startOptimizing" == "1" ]]; then
  optimizing_system
else
  menu
fi
