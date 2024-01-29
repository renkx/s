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
GreenBG="\033[42;37m"
RedBG="\033[41;37m"
Font="\033[0m"

#notification information
# Info="${Green}[信息]${Font}"
OK="${Green}[OK]${Font}"
Error="${Red}[错误]${Font}"

judge() {
    if [[ 0 -eq $? ]]; then
        echo -e "${OK} ${GreenBG} $1 完成 ${Font}"
        sleep 1
    else
        echo -e "${Error} ${RedBG} $1 失败${Font}"
        exit 1
    fi
}

docker_run() {
  if [[ -f ~/ag/conf/default/frps.ini ]]; then
      echo -e "${OK} ${GreenBG} 准备设置frps ${Font}"
      echo
  else
      echo -e "${Error} ${RedBG} ~/ag/conf/default/frps.ini 文件不存在 ${Font}"
      exit 1
  fi

  # host网络模式启动 如果host模式还设置端口映射 会出错
  docker run -itd --name frps --init --network host --log-opt max-size=1m --log-opt max-file=3 --restart=always -v ~/ag/conf/default/frps.ini:/frps.ini --workdir="/root" registry.cn-beijing.aliyuncs.com/renkx/frp:latest /frp/frps -c /frps.ini

  judge "启动 frps 内网穿透 "

}

docker_run