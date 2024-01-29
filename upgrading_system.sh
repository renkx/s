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

source '/etc/os-release'

echo_info "检测是否能ping谷歌"
IsGlobal="0"
delay="$(ping -4 -c 2 -w 2 www.google.com | grep rtt | cut -d'/' -f4 | awk '{ print $3 }' | sed -n '/^[0-9]\+\(\.[0-9]\+\)\?$/p')";
if [ "$delay" != "" ] ; then
	IsGlobal="1"
	echo_info "延迟：$delay ms , ping yes"
else
  echo_info "延迟：$delay ms , ping no"
fi

# 升级内核
if [[ "${ID}" == "debian" ]]; then
    apt update
    judge "apt update"
    apt upgrade -y
    judge "apt upgrade"
    apt install lsb-release -y
    judge "apt install lsb-release"
    # 添加源并更新
    if [[ "$IsGlobal" == "1" ]];then
      echo_info "添加官方的源"
      echo "deb http://deb.debian.org/debian $(lsb_release -sc)-backports main" | tee /etc/apt/sources.list.d/sources.list
    else
      echo_info "添加阿里的源"
      echo "deb http://mirrors.aliyun.com/debian $(lsb_release -sc)-backports main" | tee /etc/apt/sources.list.d/sources.list
    fi
    judge "添加源"
    apt update
    judge "apt update"
    # aptitude 与 apt-get apt 都是Debian及其衍生系统中的包管理工具。aptitude 在处理包依赖问题上更好。
    apt install aptitude -y
    judge "apt install aptitude"
    # 更新最新内核 linux-image-amd64 linux-headers-amd64 linux-image-cloud-amd64 linux-headers-cloud-amd64 cloud比较小
    # 用aptitude安装，否则会出现依赖问题
    aptitude -t $(lsb_release -sc)-backports install linux-image-cloud-$(dpkg --print-architecture) linux-headers-cloud-$(dpkg --print-architecture) -y
    judge "升级系统内核"
    echo_info "需要 reboot"
fi