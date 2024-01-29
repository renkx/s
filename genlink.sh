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

vmess_qr_config_file="/root/renkx_vmess_qr.json"

is_root() {
    if [ 0 == $UID ]; then
        echo -e "${OK} ${GreenBG} 当前用户是root用户，进入安装流程 ${Font}"
        sleep 3
    else
        echo -e "${Error} ${RedBG} 当前用户不是root用户，请切换到root用户后重新执行脚本 ${Font}"
        exit 1
    fi
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

create_vmess_URL_config() {

  if [[ -d $vmess_qr_config_file ]]; then
      rm -rf $vmess_qr_config_file
  fi

  read -rp "请输入标题:" title
  read -rp "请输入域名:" domain
  read -rp "请输入id:" id
  read -rp "请输入path:" path

	cat >$vmess_qr_config_file <<-EOF
			{
				"v": "2",
				"ps": "${title}${domain}",
				"add": "${domain}",
				"port": "443",
				"id": "${id}",
				"aid": "0",
				"net": "ws",
				"type": "none",
				"host": "${domain}",
				"path": "${path}",
				"tls": "tls"
			}
		EOF
}

old_config_exist_check() {
    if [[ -f $vmess_qr_config_file ]]; then
        echo -e "${OK} ${GreenBG} 检测到旧配置文件，是否读取旧文件配置 [Y/N]? ${Font}"
        read -r ssl_delete
        case $ssl_delete in
        [yY][eE][sS] | [yY])
            echo_vmess_link
            ;;
        *)
            ;;
        esac
    fi
}

echo_vmess_link()
{

  vmess_link="vmess://$(base64 -w 0 $vmess_qr_config_file)"

  echo
  echo -e "${Red}${vmess_link}${Font}"
  echo
  echo
  exit 0
}

is_root
old_config_exist_check
create_vmess_URL_config
echo_vmess_link