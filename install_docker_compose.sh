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

# 检查github网络
check_github() {
  # 检测 raw.githubusercontent.com 的可访问性
  if ! curl --head --silent --fail "https://raw.githubusercontent.com" > /dev/null; then
    echo_error "无法访问 https://raw.githubusercontent.com 请检查网络或者本地DNS"
    exit 1
  fi

  # 检测 api.github.com 的可访问性
  if ! curl --head --silent --fail "https://api.github.com" > /dev/null; then
    echo_error "无法访问 https://api.github.com 请检查网络或者本地DNS"
    exit 1
  fi

  # 检测 github.com 的可访问性
  if ! curl --head --silent --fail "https://github.com" > /dev/null; then
    echo_error "无法访问 https://github.com 请检查网络或者本地DNS"
    exit 1
  fi

  # 所有域名均可访问，打印成功提示
  echo_info "github可访问，继续执行脚本..."
}

# 检测root用户
is_root() {
  if [ 0 == $UID ]; then
    echo_ok "当前用户是root用户，准备执行"
    sleep 1
  else
    echo_error "当前用户不是root用户，请切换到root用户后重新执行脚本"
    exit 1
  fi
}

# 校验命令是否存在
command_exists() {
	command -v "$@" >/dev/null 2>&1
}

install_docker_compose()
{
  DOCKER_COMPOSE_VERSION="$(wget -qO- -t1 -T2 'https://api.github.com/repos/docker/compose/releases/latest' | grep 'tag_name' | head -n 1 | awk -F ':' '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')"
  judge "获取最新版本号"

  echo_ok "当前版本 ${DOCKER_COMPOSE_VERSION}，准备执行"
  #read -rp "请输入版本号（默认${DOCKER_COMPOSE_VERSION}）：" dockercomposevnum
  [[ -z ${dockercomposevnum} ]] && dockercomposevnum=${DOCKER_COMPOSE_VERSION}

  curl -L https://github.com/docker/compose/releases/download/${dockercomposevnum}/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
  judge "下载docker-compose"
  chmod +x /usr/local/bin/docker-compose
  judge "修改docker-compose权限"
  docker-compose --version

  echo
  echo_ok "docker-compose 安装完成"
  echo
}

is_root

if ! command_exists curl; then
  echo_error "必须安装 curl"
  exit 1;
fi

check_github
install_docker_compose
