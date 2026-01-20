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

# 从VERSION中提取发行版系统的英文名称，为了在debian/ubuntu下添加相对应的Nginx apt源
VERSION=$(echo "${VERSION}" | awk -F "[()]" '{print $2}')

# 检测网络
check_network_env() {
  [ -n "${IsGlobal:-}" ] && return

  echo_info "🔍 正在分析网络路由 ..."

  # 1. 核心判断：使用 Google 204 服务进行内容校验
  # -L: 跟踪重定向 (防止某些机房劫持到自己的登录页)
  # -w %{http_code}: 只输出 HTTP 状态码
  # --connect-timeout 2: 尝试建立连接的最长等待时间
  # -m 4: 整个请求（包括下载数据）的总限时
  local check_code
  check_code=$(curl -sL -k --connect-timeout 2 -m 4 -w "%{http_code}" "https://www.google.com/generate_204" -o /dev/null 2>/dev/null)

  if [ "$check_code" = "204" ]; then
    ENV_TIP="🌍 海外 (Global)"
    IsGlobal=1
  else
    # 2. 如果 Google 不通，尝试国内高可靠地址确认是否断网
    # 阿里或百度的 HTTPS 服务在国内是绝对稳定的
    local cn_code
    cn_code=$(curl -sL -k --connect-timeout 2 -m 3 -w "%{http_code}" "https://www.baidu.com" -o /dev/null 2>/dev/null)

    if [ "$cn_code" = "200" ]; then
      ENV_TIP="🇨🇳 国内 (Mainland China)"
      IsGlobal=0
    else
      ENV_TIP="🚫 网络连接异常"
      IsGlobal=0
    fi
  fi

  export IsGlobal
  echo_info "📍 网络定位: $ENV_TIP"
}

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

install_base() {
  check_network_env

  if [[ "$IsGlobal" == "1" ]];then
    echo_info "执行【github】的脚本 ..."
    bash <(curl -sSL https://raw.githubusercontent.com/renkx/s/main/install_base.sh)
  else
    echo_info "执行【gitee】的脚本 ..."
    bash <(curl -sSL https://gitee.com/renkx/ss/raw/main/install_base.sh)
  fi
}

install_docker() {
  check_network_env

  if [[ "$IsGlobal" == "1" ]];then
    echo_info "执行【github】的脚本 ..."
    bash <(curl -sSL https://raw.githubusercontent.com/renkx/s/main/install_docker.sh)
  else
    echo_info "执行【gitee】的脚本 ..."
    bash <(curl -sSL https://gitee.com/renkx/ss/raw/main/install_docker.sh)
  fi
}

install_on_my_zsh() {
  check_network_env

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
  check_network_env

  if [[ "$IsGlobal" == "1" ]];then
    echo_info "执行【github】的脚本 ..."
    bash <(curl -sSL https://raw.githubusercontent.com/renkx/s/main/optimizing_system.sh)
  else
    echo_info "执行【gitee】的脚本 ..."
    bash <(curl -sSL https://gitee.com/renkx/ss/raw/main/optimizing_system.sh)
  fi
}

# 虚拟内存设置
update_swap() {
  check_network_env

  if [[ "$IsGlobal" == "1" ]];then
    echo_info "执行【github】的脚本 ..."
    bash <(curl -sSL https://raw.githubusercontent.com/renkx/s/main/swap.sh)
  else
    echo_info "执行【gitee】的脚本 ..."
    bash <(curl -sSL https://gitee.com/renkx/ss/raw/main/swap.sh)
  fi
}

# 更新 nameserver
update_nameserver() {
  check_network_env

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
  chattr +i /etc/resolv.conf
  judge "设置 nameserver 并 chattr +i /etc/resolv.conf 加锁"
}

# 清理系统垃圾
clean_system_rubbish() {
  echo_info "开始系统保养与深度清理..."

  # 1. 清理云厂商组件 (qemu-guest-agent 等)
  # 存在才删，不浪费性能
  local CLOUD_PACKS="qemu-guest-agent cloud-init"
  for pkg in $CLOUD_PACKS; do
      if dpkg -l | grep -q "$pkg"; then
          echo_info "检测到残留组件: $pkg，正在彻底卸载..."
          apt-get purge -y "$pkg"
      fi
  done

  # 2. 清理残余配置文件 (rc状态)
  # 只要系统在运行，就可能产生 rc 状态的残留
  local RC_LIST=$(dpkg -l | awk '/^rc/ {print $2}')
  if [ -n "$RC_LIST" ]; then
      echo_info "清理残余配置文件..."
      echo "$RC_LIST" | xargs apt-get -y purge
  fi

  # 3. 基础包管理清理 (保留 clean，清理下载缓存)
  echo_info "清理冗余软件包及缓存..."
  apt-get autoremove --purge -y
  apt-get clean -y

  # 4. 日志清理
  # 日常维护建议保留 7 天， size 限制在 100M
  echo_info "压缩并清理系统日志..."
  journalctl --rotate
  journalctl --vacuum-size=100M
  journalctl --vacuum-time=7d

  # 5. 临时文件清理 (只删 24 小时前的，更安全)
  echo_info "清理 24 小时前的临时文件..."
  find /tmp -mindepth 1 -mtime +1 -delete 2>/dev/null
  find /var/tmp -mindepth 1 -mtime +1 -delete 2>/dev/null

  # 6. Docker 冗余清理 (日常建议去掉 -a，只清理无效碎片)
  if command -v docker >/dev/null 2>&1 && systemctl is-active --quiet docker; then
      echo_info "检测到 Docker 运行中，清理无用碎片..."
      docker system prune -f
  fi

  echo_info "系统清理完成！"
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

# 更新motd
update_motd() {
  check_network_env

  if [[ "$IsGlobal" == "1" ]];then
    echo_info "执行【github】的脚本 ..."
    bash <(curl -sSL https://raw.githubusercontent.com/renkx/s/main/update_motd.sh)
  else
    echo_info "执行【gitee】的脚本 ..."
    bash <(curl -sSL https://gitee.com/renkx/ss/raw/main/update_motd.sh)
  fi
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

# 安装acme命令动态配置域名证书
install_acme() {
  check_network_env

  if [[ "$IsGlobal" == "1" ]];then
    echo_info "执行【github】的脚本 ..."
    echo_info "bash <(curl -sSL https://raw.githubusercontent.com/renkx/s/main/acme/acme.sh) ~/ag/conf/default/acme.conf"
    bash <(curl -sSL https://raw.githubusercontent.com/renkx/s/main/acme/acme.sh) ~/ag/conf/default/acme.conf
  else
    echo_info "执行【gitee】的脚本 ..."
    echo_info "bash <(curl -sSL https://gitee.com/renkx/ss/raw/main/acme/acme.sh) ~/ag/conf/default/acme.conf"
    bash <(curl -sSL https://gitee.com/renkx/ss/raw/main/acme/acme.sh) ~/ag/conf/default/acme.conf
  fi
}

# 安装docker容器自动更新
install_docker_auto_update() {
  check_network_env

  if [[ "$IsGlobal" == "1" ]];then
    echo_info "执行【github】的脚本 ..."
    echo_info "bash <(curl -sSL https://raw.githubusercontent.com/renkx/s/main/docker/docker_auto_update.sh) ~/ag"
    bash <(curl -sSL https://raw.githubusercontent.com/renkx/s/main/docker/docker_auto_update.sh) ~/ag
  else
    echo_info "执行【gitee】的脚本 ..."
    echo_info "bash <(curl -sSL https://gitee.com/renkx/ss/raw/main/docker/docker_auto_update.sh) ~/ag"
    bash <(curl -sSL https://gitee.com/renkx/ss/raw/main/docker/docker_auto_update.sh) ~/ag
  fi
}

# 将所有功能逻辑封装到一个独立的函数中
action_logic() {
    case $1 in
    0)
        exit 0
        ;;
    1)
        optimizing_system
        ;;
    2)
        install_base
        ;;
    3)
        install_docker
        ;;
    4)
        install_on_my_zsh
        ;;
    5)
        update_motd
        ;;
    6)
        update_nameserver
        ;;
    7)
        clean_system_rubbish
        ;;
    8)
        update_swap
        ;;
    9)
        install_acme
        ;;
    10)
        install_docker_auto_update
        ;;
    333)
        optimizing_system
        install_base
        install_docker
        install_on_my_zsh
        update_motd
        update_nameserver
        clean_system_rubbish
        ;;
    887)
        check_sys_official_xanmod
        ;;
    888)
        check_sys_official_xanmod_and_detele_kernel
        ;;
    889)
        detele_kernel_custom
        ;;
    *)
        echo -e "${RedBG}错误: 无效的指令 [$1]${Font}"
        return 1
        ;;
    esac
}

# 交互式菜单界面
menu() {
    clear
    echo -e "${GreenBG}—————————————— 安装向导 ——————————————${Font}"
    echo -e "${Green}0.${Font} 退出"
    echo -e "${Green}1.${Font} 系统优化"
    echo -e "${Green}2.${Font} 安装 系统基础"
    echo -e "${Green}3.${Font} 安装 docker"
    echo -e "${Green}4.${Font} 安装 on-my-zsh"
    echo -e "${Green}5.${Font} 更新 motd"
    echo -e "${Green}6.${Font} 更新 nameserver"
    echo -e "${Green}7.${Font} 清理系统垃圾"
    echo -e "${Green}8.${Font} 虚拟内存设置"
    echo -e "${Green}9.${Font} 安装acme命令动态配置域名证书"
    echo -e "${Green}10.${Font} 安装docker容器自动更新"

    echo -e "${Green}333.${Font} 一键 1、2、3、4、5、6、7"
    echo -e "${Green}987.${Font} 安装 XANMOD 官方内核"
    echo -e "${Green}888.${Font} 安装 XANMOD 官方内核并删除旧内核"
    echo -e "${Green}889.${Font} 删除保留指定内核"
    echo -e "————————————————————————————————————————————————————————————————"

    check_status

    echo -e " 系统信息: $opsy ${Green}$virtual${Font} $arch ${Green}$kern${Font} "

    if [[ "${kernel_status}" == "noinstall" ]]; then
        echo -e " 当前状态: ${Red}未安装${Font} 加速内核 请先安装内核"
    else
        echo -e " 当前状态: ${Green}已安装${Font} ${Red}${kernel_status}${Font} 加速内核 , ${Green}${run_status}${Font}"
    fi

    echo -e " 当前拥塞控制算法为: ${Green}${net_congestion_control}${Font} 当前队列算法为: ${Green}${net_qdisc}${Font} "

    read -rp " 请输入数字：" menu_num < /dev/tty
    action_logic "$menu_num"
}

# 脚本执行入口判断
if [ -n "$1" ]; then
    # 如果命令行有参数，直接执行逻辑
    action_logic "$1"
else
    # 交互模式使用循环，直到用户选择 0 (退出)
    while true; do
        menu
        # 如果 action_logic 内部 exit 0 了就会退出，
        # 如果没有 exit，则在 menu 执行完后回到这里继续下一次循环
        # 增加一个简单的暂停，方便用户看清上一个命令的结果
        echo -e "\n${Info} 按任意键回到菜单..."
        read -n 1 < /dev/tty
    done
fi
