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

# 获取操作系统名称
get_opsy() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release && echo "$PRETTY_NAME"
    elif [ -f /etc/system-release ]; then
        head -n1 /etc/system-release
    else
        echo "Unknown OS"
    fi
}

# 检查虚拟化环境
virt_check() {
  if [ -f "/usr/bin/systemd-detect-virt" ]; then
      Var_VirtType=$(/usr/bin/systemd-detect-virt 2>/dev/null)
  else
      Var_VirtType=$(virt-what 2>/dev/null | tail -n1)
  fi

  case "${Var_VirtType:-none}" in
      qemu)           virtual="QEMU" ;;
      kvm)            virtual="KVM" ;;
      vmware)         virtual="VMware" ;;
      microsoft)      virtual="Hyper-V" ;;
      openvz)         virtual="OpenVZ" ;;
      lxc*)           virtual="LXC" ;;
      docker)         virtual="Docker" ;;
      wsl)            virtual="WSL" ;;
      none)           virtual="Dedicated" ;;
      *)              virtual="Unknown" ;;
  esac
}

# 检查内核与加速状态
check_status() {
  # 基础信息
  opsy=$(get_opsy)
  virt_check
  kern=$(uname -r)
  arch=$(uname -m)
  net_congestion_control=$(sysctl -n net.ipv4.tcp_congestion_control)
  net_qdisc=$(sysctl -n net.core.default_qdisc)

  # 1. 内核类型判定
  if [[ "$kern" == *bbrplus* ]]; then
      kernel_status="BBRplus"
  elif [[ "$kern" =~ (4\.9\.0-4|4\.15\.0-30|4\.8\.0-36|3\.16\.0-77|2\.6\.32-504) ]]; then
      kernel_status="Lotserver"
  elif [[ $(echo "${kern%%-*}" | awk -F. '{if($1>4 || ($1==4 && $2>=9)) print "yes"}') == "yes" ]]; then
      kernel_status="BBR"
  else
      kernel_status="noinstall"
  fi

  # 2. 运行状态判定 (通过 case 简化)
  case "$kernel_status" in
      "BBR"|"BBRplus")
          # 检查当前算法是否匹配内核类型，或者是否为常见的 bbr 变体
          if [[ "$net_congestion_control" =~ (bbr|bbrplus|bbr2|tsunami|nanqinlang) ]]; then
              run_status="${net_congestion_control} 启动成功"
          else
              run_status="插件未启动"
          fi
          ;;
      "Lotserver")
          if [ -f "/appex/bin/lotServer.sh" ]; then
              /appex/bin/lotServer.sh status | grep -q "running!" && run_status="启动成功" || run_status="启动失败"
          else
              run_status="未安装加速模块"
          fi
          ;;
      *)
          run_status="未安装加速模块"
          ;;
  esac
}

# 检查磁盘空间
check_disk_space() {
    # 检查是否存在 bc 命令
    if ! command -v bc &> /dev/null; then
        echo "安装 bc 命令..."
        # 检查系统类型并安装相应的 bc 包
        if [ -f /etc/redhat-release ]; then
            yum install -y bc
        elif [ -f /etc/debian_version ]; then
            apt-get update
            apt-get install -y bc
        else
            echo_error "无法确定系统类型，请手动安装 bc 命令。"
            return 1
        fi
    fi

    # 获取当前磁盘剩余空间
    available_space=$(df -h / | awk 'NR==2 {print $4}')

    # 移除单位字符，例如"GB"，并将剩余空间转换为数字
    available_space=$(echo $available_space | sed 's/G//' | sed 's/M//')

    # 如果剩余空间小于等于0，则输出警告信息
    if [ $(echo "$available_space <= 0" | bc) -eq 1 ]; then
        echo_error "警告：磁盘空间已用尽，请勿重启，先清理空间。建议先卸载刚才安装的内核来释放空间，仅供参考。"
    else
        echo_info "当前磁盘剩余空间：$available_space GB"
    fi
}

# 更新引导
update_grub() {
  if _exists "update-grub"; then
    update-grub
  elif [ -f "/usr/sbin/update-grub" ]; then
    /usr/sbin/update-grub
  else
    apt install grub2-common -y
    update-grub
  fi
  check_disk_space
}

# 检查官方 xanmod 内核并安装
check_sys_official_xanmod() {
  # 获取系统信息
  os_info=$(cat /etc/os-release 2>/dev/null)
  # 判断是否为 Debian 系统
  if [[ "$os_info" != *"Debian"* ]]; then
      echo_error "不支持Debian以外的系统"
      exit 1
  fi

  bit=$(uname -m)
  if [[ ${bit} != "x86_64" ]]; then
    echo_error "不支持x86_64以外的系统 !"
    exit 1
  fi

  if ! wget -O check_x86-64_psabi.sh https://dl.xanmod.org/check_x86-64_psabi.sh; then
    echo_error "CPU 检测脚本下载失败"
    exit 1
  fi

  chmod +x check_x86-64_psabi.sh
  cpu_level=$(./check_x86-64_psabi.sh | awk -F 'v' '{print $2}')
  if [ -z "$cpu_level" ]; then
      echo "CPU级别获取异常！请查看 check_x86-64_psabi.sh 脚本"
      exit 1
  fi
  echo -e "CPU supports \033[32m${cpu_level}\033[0m"
  rm check_x86-64_psabi.sh

  apt update
  apt-get install gnupg2 sudo -y

  wget -qO - https://dl.xanmod.org/archive.key | sudo gpg --dearmor -vo /etc/apt/keyrings/xanmod-archive-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/xanmod-release.list

  apt update
  case "$cpu_level" in
    # 官方不单独发布 v4 包（因为 AVX-512 对内核没好处），直接用v3的包
    4) apt install -y linux-xanmod-rt-x64v3 ;;
    3) apt install -y linux-xanmod-rt-x64v3 ;;
    2) apt install -y linux-xanmod-rt-x64v2 ;;
    # rt版本没有v1，所以改为安装其他版本
    *) apt install -y linux-xanmod-lts-x64v1 ;;
  esac

  # 删除apt源，防止硬盘小的vps没有空间更新内核
  rm -f /etc/apt/sources.list.d/xanmod-release.list
  apt update

  update_grub
  echo_ok "内核安装完毕，请参考上面的信息检查是否安装成功,默认从排第一的高版本内核启动"
}

# 检查官方 xanmod 内核并安装和删除旧版内核
check_sys_official_xanmod_and_detele_kernel() {
  check_sys_official_xanmod

  # 获取最新内核版本编号
  kernel_version=$(dpkg -l | grep linux-image | awk '/xanmod/ {print $2}' | sort -V -r | head -n 1 | sed 's/linux-image-//')
  echo_info "内核保留保留保留的内核关键词 $kernel_version"
  if [ -z "$kernel_version" ]; then
      echo_error "最新内核版本编号获取失败，不执行卸载其他内核操作"
      exit 1
  fi
  detele_kernel
  detele_kernel_head
  update_grub
}

# 删除多余内核
detele_kernel() {
  # 获取系统信息
  os_info=$(cat /etc/os-release 2>/dev/null)
  # 判断是否为 Debian 系统
  if [[ "$os_info" == *"Debian"* ]]; then
    deb_total=$(dpkg -l | grep linux-image | awk '{print $2}' | grep -v "${kernel_version}" | wc -l)
    if [ "$deb_total" -eq 0 ]; then
      echo_info "没有要卸载的内核。"
      exit 1
    elif [ "${deb_total}" -ge 1 ]; then
      echo_info "检测到 ${deb_total} 个其余内核，开始卸载..."
      for ((integer = 1; integer <= ${deb_total}; integer++)); do
        deb_del=$(dpkg -l | grep linux-image | awk '{print $2}' | grep -v "${kernel_version}" | head -${integer})
        echo_info "开始卸载 ${deb_del} 内核..."
        apt-get purge -y ${deb_del}
        apt-get autoremove -y
        echo_info "卸载 ${deb_del} 内核卸载完成，继续..."
      done
      echo_info "内核卸载完毕，继续..."
    else
      echo_error " 检测到 内核 数量不正确，请检查 !"
      update_grub
      exit 1
    fi
  fi
}

detele_kernel_head() {
  # 获取系统信息
  os_info=$(cat /etc/os-release 2>/dev/null)
  # 判断是否为 Debian 系统
  if [[ "$os_info" == *"Debian"* ]]; then
    deb_total=$(dpkg -l | grep linux-headers | awk '{print $2}' | grep -v "${kernel_version}" | wc -l)
    if [ "$deb_total" -eq 0 ]; then
      echo_info "没有要卸载的head内核。"
      exit 1
    elif [ "${deb_total}" -ge 1 ]; then
      echo_info "检测到 ${deb_total} 个其余head内核，开始卸载..."
      for ((integer = 1; integer <= ${deb_total}; integer++)); do
        deb_del=$(dpkg -l | grep linux-headers | awk '{print $2}' | grep -v "${kernel_version}" | head -${integer})
        echo_info "开始卸载 ${deb_del} headers内核..."
        apt-get purge -y ${deb_del}
        apt-get autoremove -y
        echo_info "卸载 ${deb_del} head内核卸载完成，继续..."
      done
      echo_info "head内核卸载完毕，继续..."
    else
      echo_error " 检测到 head内核 数量不正确，请检查 !"
      update_grub
      exit 1
    fi
  fi
}

# 删除保留指定内核
detele_kernel_custom() {
  update_grub
  read -p " 查看上面内核输入需保留保留保留的内核关键词(如:5.15.0-11) :" kernel_version
  detele_kernel
  detele_kernel_head
  update_grub
}
