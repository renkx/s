#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

cd "$(
    cd "$(dirname "$0")" || exit
    pwd
)" || exit

# 获取系统相关参数
source '/etc/os-release'
# wgcf配置
WGCF_Profile='wgcf-profile.conf'

is_root() {
    if [ 0 == $UID ]; then
        echo
        echo -e "当前用户是root用户，准备执行..."
        echo
        sleep 2
    else
        echo
        echo -e "当前用户不是root用户，请切换到root用户后重新执行脚本"
        echo
        exit 1
    fi
}

install_wgcf() {
    curl -fsSL git.io/wgcf.sh | bash
}

register_WARP_Account() {
    while [[ ! -f wgcf-account.toml ]]; do
        install_wgcf
        echo "Cloudflare WARP Account registration in progress..."
        yes | wgcf register
        sleep 3
    done
}

generate_WGCF_Profile() {
    while [[ ! -f ${WGCF_Profile} ]]; do
        register_WARP_Account
        echo "WARP WireGuard profile (wgcf-profile.conf) generation in progress..."
        wgcf generate
    done
}

if [[ "${ID}" == "debian" ]]; then
      is_root
      cd /root
      apt update
      # 安装网络工具包
      apt install net-tools iproute2 openresolv dnsutils -y
      # 安装 wireguard-tools (WireGuard 配置工具：wg、wg-quick)
      apt install wireguard-tools --no-install-recommends -y

      generate_WGCF_Profile
      # 只设置IPV6 并dns为本地
      sed -i 's/1.1.1.1/127.0.0.1/g' wgcf-profile.conf
      sed -i '/0.0.0.0\/0/d' wgcf-profile.conf
      cp wgcf-profile.conf /etc/wireguard/wgcf.conf
      echo "设置wgcf自动启动..."
      echo "systemctl start wg-quick@wgcf && systemctl enable wg-quick@wgcf"
      systemctl start wg-quick@wgcf && systemctl enable wg-quick@wgcf
      echo
      ip a
      # curl -6 ip.p3terx.com

      # 临时开启
      # wg-quick up wgcf
      # 关闭
      # wg-quick down wgcf
else
  echo "系统版本不支持";
  return 1;
fi


