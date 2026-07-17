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

# 远程脚本执行函数
remote_execute() {
    local file_path=$1
    shift # 移除 file_path，剩下的就是传给脚本的参数

    # 检查网络
    check_network_env

    local base_url="https://raw.githubusercontent.com/renkx/s/main"
    [[ "$IsGlobal" != "1" ]] && base_url="https://gitee.com/renkx/ss/raw/main"

    echo_info "正在获取脚本: ${file_path} ..."

    # 建议先下载到临时变量或文件，确保下载成功再执行
    local script_content
    script_content=$(curl -sSL "${base_url}/${file_path}")

    if [ -n "$script_content" ]; then
        # 将当前的参数列表 "$@" 传递给 bash 执行的脚本
        bash <(echo "$script_content") "$@"
    else
        echo_error "脚本下载失败，请检查网络连接。"
    fi
}

# 更新 nameserver
update_nameserver() {
  check_network_env

  chattr -i /etc/resolv.conf
  echo_ok "chattr -i /etc/resolv.conf 解锁"

  # 锁定DNS解析（第一个异常会请求第二个，为了防止docker容器还没启动。比如warp就会出问题）
  local dns_server="8.8.8.8"
  [[ "$IsGlobal" != "1" ]] && dns_server="223.5.5.5"

  cat >/etc/resolv.conf <<EOF
nameserver 127.0.0.1
nameserver $dns_server
EOF
    chattr +i /etc/resolv.conf
    echo_ok "DNS 已更新为 $dns_server 并加锁"
}

# 移除云厂商软件
remove_cloud_pkg() {
  # 清理云厂商组件 (qemu-guest-agent 等)
  # 存在才删，不浪费性能
  local CLOUD_PACKS="qemu-guest-agent cloud-init"
  for pkg in $CLOUD_PACKS; do
      if dpkg -l | grep -q "$pkg"; then
          echo_info "检测到残留组件: $pkg，正在彻底卸载..."
          apt-get purge -y "$pkg"
      fi
  done
}

# 一键添加带智能检测的 ag 定时重启任务
set_ag_restart() {
  # 目标定时任务字符串
  local cron_job="0 3 * * * docker ps --format '{{.Names}}' | grep -E '^ag$' >/dev/null && docker restart ag"

  # 精准去重检查
  if crontab -l 2>/dev/null | grep -Fq "docker restart ag"; then
    echo "【跳过】ag 定时任务已存在，无需重复设置。"
  else
    # 写入系统
    (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
    echo "【成功】已成功为您添加 ag 运行期智能重启任务！"
  fi
}

# 清理系统垃圾
clean_system_rubbish() {
  echo_info "开始系统保养与深度清理..."

  # 清理残余配置文件 (rc状态)
  # 只要系统在运行，就可能产生 rc 状态的残留
  local RC_LIST=$(dpkg -l | awk '/^rc/ {print $2}')
  if [ -n "$RC_LIST" ]; then
      echo_info "清理残余配置文件..."
      echo "$RC_LIST" | xargs apt-get -y purge
  fi

  # 基础包管理清理 (保留 clean，清理下载缓存)
  echo_info "清理冗余软件包及缓存..."
  apt-get autoremove --purge -y
  apt-get autoclean -y
  apt-get clean -y

  # 日志清理
  # 日常维护建议保留 7 天， size 限制在 100M
  echo_info "压缩并清理系统日志..."
  journalctl --rotate
  journalctl --vacuum-size=100M
  journalctl --vacuum-time=7d

  # 临时文件清理 (只删 24 小时前的，更安全)
  echo_info "清理 24 小时前的临时文件..."
  find /tmp -mindepth 1 -mtime +1 -delete 2>/dev/null
  find /var/tmp -mindepth 1 -mtime +1 -delete 2>/dev/null

  # 安全清理 APT 列表缓存
  # 直接删除 /var/lib/apt/lists/ 下的文件是清理索引最彻底且安全的方法
  # 下次执行 apt update 会自动重新下载最干净的索引
  echo_info "深度清理 APT 索引缓存..."
  find /var/lib/apt/lists/ -type f -delete

  # Docker 冗余清理 (日常建议去掉 -a，只清理无效碎片)
  if command -v docker >/dev/null 2>&1 && systemctl is-active --quiet docker; then
      echo_info "检测到 Docker 运行中，清理无用碎片..."
      docker system prune -f
  fi

  echo_info "系统清理完成！"
  echo_info "提示：APT 索引已清理，下次安装软件前请执行 apt update"
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
  net_congestion_control=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
  net_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "unknown")

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

install_base() {
  remote_execute "install_base.sh"
}

install_docker() {
  remote_execute "install_docker.sh"
}

install_on_my_zsh() {
  remote_execute "myzsh.sh"
}

# 系统优化
optimizing_system() {
  remote_execute "optimizing_system.sh"
}

# 虚拟内存设置
update_swap() {
  remote_execute "swap.sh" "$@"
}

# 更新motd
update_motd() {
  remote_execute "update_motd.sh"
}

# 安装acme命令动态配置域名证书
install_acme() {
  remote_execute "acme/acme.sh" ~/ag/conf/default/acme.conf
}

# 安装docker容器自动更新
install_docker_auto_update() {
  remote_execute "docker/docker_auto_update.sh" ~/ag
}

# 安装 UFW、Fail2ban 和 ipSet
install_ufw() {
  remote_execute "system/install_ufw.sh"
}

install_supervisor() {
  remote_execute "system/supervisor_auto.sh" deploy
}

# 将所有功能逻辑封装到一个独立的函数中
action_logic() {
    local cmd_num=$1
    shift # 移除第一个参数（编号），剩下的 $@ 就是要传递给子脚本的参数

    case $cmd_num in
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
        install_ufw
        ;;
    4)
        install_docker
        ;;
    5)
        install_on_my_zsh
        ;;
    6)
        update_motd
        ;;
    7)
        update_nameserver
        ;;
    8)
        install_supervisor
        ;;
    9)
        clean_system_rubbish
        ;;
    10)
        remove_cloud_pkg
        ;;
    11)
        set_ag_restart
        ;;
    100)
        update_swap "$@"
        ;;
    110)
        install_acme
        ;;
    120)
        install_docker_auto_update
        ;;
    666)
        echo_info "🚀 开始全自动化安装与优化..."
        # 创建1024M虚拟内存
        update_swap 1025
        for cmd in optimizing_system install_base install_ufw install_docker install_on_my_zsh update_motd install_supervisor clean_system_rubbish; do
            echo "------------------------------------------------------"
            echo_info "正在执行: $cmd"
            $cmd
        done
        echo_ok "✅ 所有任务已完成！"
        ;;
    *)
        echo -e "${RedBG}错误: 无效的指令 [$cmd_num]${Font}"
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
    echo -e "${Green}3.${Font} 安装 ufw、fail2ban"
    echo -e "${Green}4.${Font} 安装 docker"
    echo -e "${Green}5.${Font} 安装 on-my-zsh"
    echo -e "${Green}6.${Font} 更新 motd"
    echo -e "${Green}7.${Font} 更新 nameserver"
    echo -e "${Green}8.${Font} 部署 supervisor"
    echo -e "${Green}9.${Font} 清理系统垃圾"
    echo -e "${Green}10.${Font} 移除云厂商软件"
    echo -e "${Green}11.${Font} 设置ag定时重启"
    echo -e "${Green}100.${Font} 虚拟内存设置"
    echo -e "${Green}110.${Font} 安装acme命令动态配置域名证书"
    echo -e "${Green}120.${Font} 安装docker容器自动更新"

    echo -e "${Green}666.${Font} 一键 100、1、2、3、4、5、6、8、9"
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
    # 使用 "$@" 确保所有参数（如 3 a b c）都被完整传递
    action_logic "$@"
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
