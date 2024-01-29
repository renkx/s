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
  if [[ -f ~/smartdns.conf ]]; then
      echo -e "${OK} ${GreenBG} 准备设置smartdns ${Font}"
      echo
  else
    touch ~/smartdns.conf

  cat >~/smartdns.conf <<EOF
# UDP
bind 127.0.0.1:53
# TCP
bind-tcp 127.0.0.1:53

# dns cache size
cache-size 100000
rr-ttl-min 600
# fatal,error,warn,notice,info,debug default:error
log-level error

server 114.114.114.114
server 114.114.115.115
server 119.29.29.29
server 182.254.118.118
server 223.5.5.5
server 223.6.6.6

server-tcp 114.114.114.114
server-tcp 114.114.115.115
server-tcp 119.29.29.29
server-tcp 182.254.118.118
server-tcp 223.5.5.5
server-tcp 223.6.6.6

serve-expired yes
serve-expired-ttl 86400


prefetch-domain yes
speed-check-mode tcp:443,tcp:80,ping

EOF
      echo -e "${OK} ${GreenBG} 已创建~/smartdns.conf文件，准备设置smartdns ${Font}"
      echo
  fi

  # host网络模式启动
  docker run -itd --name smartdns --network host --privileged=true --restart=always -v ~/:/etc/smartdns/ registry.cn-beijing.aliyuncs.com/renkx/smartdns:latest

  judge "启动 smartdns "

}

docker_run