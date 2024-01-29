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
  if [[ -f ~/gost.json ]]; then
      echo -e "${OK} ${GreenBG} 准备设置gost ${Font}"
      echo
  else
      echo -e "${Error} ${RedBG} ~/gost.json 文件不存在 ${Font}"
      exit 1
  fi

  docker run -itd --name gost --network host --restart=always -v ~/gost.json:/gost.json ginuerzh/gost -C /gost.json

  judge "启动 gost "

}

docker_run