#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

cd "$(
    cd "$(dirname "$0")" || exit
    pwd
)" || exit

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

# 版本
shell_version="0.1.0"
# git分支
github_branch="main"
version_cmp="/tmp/docker_sh_version_cmp.tmp"

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

# 只能升级debian系统
upgrading_system() {
  # 升级内核
  bash <(curl -sSL https://raw.githubusercontent.com/renkx/s/main/upgrading_system.sh)
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

menu() {

    echo
    echo -e "${GreenBG}—————————————— 安装向导 ——————————————${Font}"
    echo -e "${Green}0.${Font} 退出"
    echo -e "${Green}1.${Font} 安装 docker"
    echo -e "${Green}2.${Font} 安装 docker-compose"
    echo -e "${Green}3.${Font} 升级 debian 系统内核"
    echo -e "${Green}4.${Font} 安装 on-my-zsh"
    echo -e "${Green}5.${Font} 安装 ag"
    echo -e "${Green}6.${Font} 卸载 qemu-guest-agent"
    echo -e "${Green}7.${Font} 更新 /etc/resolv.conf \n"

    read -rp "请输入数字：" menu_num
    case $menu_num in
    0)
        exit 0
        ;;
    1)
        install_docker
        menu
        ;;
    2)
        install_docker_compose
        menu
        ;;
    3)
        upgrading_system
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
    *)
        echo -e "${RedBG}请输入正确的数字${Font}"
        menu
        ;;
    esac
}

menu
