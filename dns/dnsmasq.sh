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

command_exists() {
	command -v "$@" >/dev/null 2>&1
}

install_dnsmasq() {

if ! command_exists dnsmasq; then
  if grep -Eqi "CentOS" /etc/issue || grep -Eq "CentOS" /etc/*-release; then
    yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    yum install -y bind-utils
    yum install -y dnsmasq
  elif grep -Eqi "Debian" /etc/issue || grep -Eq "Debian" /etc/*-release; then
    apt-get update
    apt-get install -y dnsutils
    apt install -y dnsmasq
  elif grep -Eqi "Ubuntu" /etc/issue || grep -Eq "Ubuntu" /etc/*-release; then
    apt-get update
    apt-get install -y dnsutils
    apt install -y dnsmasq
  else
    echo -e "${Error} ${RedBG} 当前系统 不在支持的系统列表内，安装中断 ${Font}"
    exit 1
  fi

  if [ $? -eq 0 ]; then
    systemctl enable dnsmasq
    echo -e "${OK} ${GreenBG} dnsmasq 开机自启设置成功 ${Font}"
    dnsmasq_conf
    resolv_dnsmasq_conf
    set_resolv_conf
    systemctl restart dnsmasq
    echo -e "${OK} ${GreenBG} dnsmasq 启动成功 ${Font}"
  else
    echo -e "${Error} ${RedBG} dnsmasq 安装失败${Font}"
  fi
else
  echo -e "${OK} ${GreenBG} dnsmasq 已安装 ${Font}"
fi
}

dnsmasq_conf() {
if command_exists dnsmasq; then

  if [[ ! -f /etc/dnsmasq.conf ]]; then
    touch /etc/dnsmasq.conf
  fi

  cat >/etc/dnsmasq.conf <<EOF
resolv-file=/etc/resolv.dnsmasq.conf

listen-address=127.0.0.1
bind-interfaces

all-servers

clear-on-reload

cache-size=10000

EOF

  if [ $? -eq 0 ]; then
    echo -e "${OK} ${GreenBG} /etc/dnsmasq.conf 已配置 ${Font}"
  fi

else
    echo -e "${Error} ${RedBG} dnsmasq 未安装${Font}"
fi
}

# 设置 /etc/resolv.dnsmasq.conf
resolv_dnsmasq_conf() {
if command_exists dnsmasq; then
  if [[ ! -f /etc/resolv.conf ]]; then
    echo -e "${Error} ${RedBG} /etc/resolv.conf 不存在${Font}"
    exit 1
  fi

#  read -rp "请输入文件路径，默认 /etc/resolv.conf ：" resolvFile
#  [[ -z ${resolvFile} ]] && resolvFile=/etc/resolv.conf

  if [[ ! -f /etc/resolv.dnsmasq.conf ]]; then
    touch /etc/resolv.dnsmasq.conf
  fi

#  cat $resolvFile > /etc/resolv.dnsmasq.conf
  # 删除存在127.0.0.1的行
#  sed -i '/^nameserver 127.0.0.1$/d' /etc/resolv.dnsmasq.conf
#  sed -i '/^nameserver 1.1.1.1$/d' /etc/resolv.dnsmasq.conf
#  sed -i '/^nameserver 8.8.8.8$/d' /etc/resolv.dnsmasq.conf
#  sed -i '/^nameserver 8.8.4.4$/d' /etc/resolv.dnsmasq.conf
#  sed -i '/^nameserver 1.0.0.1$/d' /etc/resolv.dnsmasq.conf
#  sed -i '/^nameserver 168.95.1.1$/d' /etc/resolv.dnsmasq.conf

  echo "nameserver 1.1.1.1" > /etc/resolv.dnsmasq.conf
  echo "nameserver 8.8.8.8" >> /etc/resolv.dnsmasq.conf
  echo "nameserver 8.8.4.4" >> /etc/resolv.dnsmasq.conf
  echo "nameserver 1.0.0.1" >> /etc/resolv.dnsmasq.conf
  echo "nameserver 168.95.1.1" >> /etc/resolv.dnsmasq.conf

  if [ $? -eq 0 ]; then
    echo -e "${OK} ${GreenBG} /etc/resolv.dnsmasq.conf 已配置 ${Font}"
  fi

else
    echo -e "${Error} ${RedBG} dnsmasq 未安装${Font}"
fi
}

# 解锁奈飞
unlock_netflix() {
if command_exists dnsmasq; then

  read -rp "请输入DNS解锁的IP ：" dnsIp

  if [ -n "$dnsIp" ] ;then
    unlockNetflix=/etc/dnsmasq.d/unlock_netflix.conf

    if [[ ! -f $unlockNetflix ]]; then
      touch $unlockNetflix
    fi

    echo "server=/netflix.com/$dnsIp" > $unlockNetflix
    echo "server=/netflix.net/$dnsIp" >> $unlockNetflix
    echo "server=/nflximg.net/$dnsIp" >> $unlockNetflix
    echo "server=/nflximg.com/$dnsIp" >> $unlockNetflix
    echo "server=/nflxvideo.net/$dnsIp" >> $unlockNetflix
    echo "server=/nflxso.net/$dnsIp" >> $unlockNetflix
    echo "server=/nflxext.com/$dnsIp" >> $unlockNetflix

    if [ $? -eq 0 ]; then
      systemctl restart dnsmasq
      echo -e "${OK} ${GreenBG} $unlockNetflix 已配置 ${Font}"
    fi
  else
    echo -e "${Error} ${RedBG} DNS解锁的IP输入有误${Font}"
  fi

else
    echo -e "${Error} ${RedBG} dnsmasq 未安装${Font}"
fi
}

set_resolv_conf() {
  echo
  echo "nameserver 127.0.0.1" > /etc/resolv.conf
  echo -e "${OK} ${GreenBG} /etc/resolv.conf 已配置为 127.0.0.1 ${Font}"
  echo
}

menu() {
    echo
    echo
    echo
    echo -e "\thttps://git.io/renkx\n"

    echo -e "—————————————— 安装向导 ——————————————"""
    echo -e "${Green}0.${Font} 退出"
    echo -e "${Green}1.${Font} 重启 dnsmasq"
    echo -e "${Green}2.${Font} 安装 dnsmasq"
    echo -e "${Green}3.${Font} 设置 /etc/dnsmasq.conf 文件"
    echo -e "${Green}4.${Font} 设置 /etc/resolv.dnsmasq.conf 文件"
    echo -e "${Green}5.${Font} 设置 /etc/resolv.conf 为 127.0.0.1"
    echo -e "${Green}6.${Font} DNS解锁 奈飞 \n"

    read -rp "请输入数字：" menu_num
    case $menu_num in
    0)
        exit 0
        ;;
    1)
        systemctl restart dnsmasq
        menu
        ;;
    2)
        install_dnsmasq
        menu
        ;;
    3)
        dnsmasq_conf
        menu
        ;;
    4)
        resolv_dnsmasq_conf
        menu
        ;;
    5)
        set_resolv_conf
        menu
        ;;
    6)
        unlock_netflix
        menu
        ;;
    *)
        echo -e "${RedBG}请输入正确的数字${Font}"
        ;;
    esac
}

menu
