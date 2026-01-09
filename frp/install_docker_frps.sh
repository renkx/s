#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:$HOME/bin
export PATH
set -euo pipefail

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

# 优先级：位置参数 > 环境变量
FRPS_CONF="${1:-${FRPS_CONF:-}}"

if [[ -z "${FRPS_CONF}" ]]; then
    echo -e "${Error} ${RedBG} 请指定 frps 配置文件路径 ${Font}"
    echo "用法：$0 $HOME/ag/conf/default/frps.toml"
    exit 1
fi

if [[ ! -f "${FRPS_CONF}" ]]; then
    echo -e "${Error} ${RedBG} ${FRPS_CONF} 文件不存在 ${Font}"
    exit 1
fi

docker_run() {
  echo -e "${OK} ${GreenBG} 使用 frps 配置：${FRPS_CONF} ${Font}"
  echo

  if docker ps -a --format '{{.Names}}' | grep -q '^frps$'; then
      echo -e "${OK} ${GreenBG} 已存在 frps 容器，先删除 ${Font}"
      docker rm -f frps
  fi

  # host网络模式启动 如果host模式还设置端口映射 会出错
  docker run -itd \
    --name frps \
    --init \
    --network host \
    --restart=always \
    --log-opt max-size=1m \
    --log-opt max-file=3 \
    --workdir=/root \
    -v "${FRPS_CONF}:/frps.toml" \
    --label auto.update=true \
    --label auto.update.image=registry.cn-beijing.aliyuncs.com/renkx/frp:latest \
    --label "auto.update.run=docker run -itd --name frps --init --network host --restart=always --log-opt max-size=1m --log-opt max-file=3 --workdir=/root -v ${FRPS_CONF}:/frps.toml registry.cn-beijing.aliyuncs.com/renkx/frp:latest /frp/frps -c /frps.toml" \
    registry.cn-beijing.aliyuncs.com/renkx/frp:latest \
    /frp/frps -c /frps.toml

  echo -e "${OK} ${GreenBG} 启动 frps 内网穿透 完成 ${Font}"
}

docker_run