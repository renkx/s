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

#获取系统相关参数
# source 只有在bash下才可用
source '/etc/os-release'

#从VERSION中提取发行版系统的英文名称，为了在debian/ubuntu下添加相对应的Nginx apt源
VERSION=$(echo "${VERSION}" | awk -F "[()]" '{print $2}')

# 卸载软件
remove() {
  if [ $# -eq 0 ]; then
      echo_error "未提供软件包参数!"
      return 1
  fi

  for package in "$@"; do
      if command -v apt &>/dev/null; then
          apt purge -y "$package"
      elif command -v yum &>/dev/null; then
          yum remove -y "$package"
      elif command -v apk &>/dev/null; then
          apk del "$package"
      else
          echo_error "未知的包管理器!"
          return 1
      fi
  done

  return 0
}

check_system() {
  if [[ "${ID}" == "debian" && ${VERSION_ID} -ge 8 ]]; then
    echo_ok "当前系统为 Debian ${VERSION_ID} ${VERSION}"
    INS="apt"
    $INS update
  else
    echo_error "当前系统为 ${ID} ${VERSION_ID} ${VERSION} 不在支持的系统列表内，安装中断"
    exit 1
  fi
}

is_root() {
  if [ 0 == $UID ]; then
    echo_ok "当前用户是root用户，进入安装流程"
    sleep 1
  else
    echo_error "当前用户不是root用户，请切换到root用户后重新执行脚本"
    exit 1
  fi
}

iptables_open() {
  iptables -P INPUT ACCEPT
  iptables -P FORWARD ACCEPT
  iptables -P OUTPUT ACCEPT
  iptables -F

  ip6tables -P INPUT ACCEPT
  ip6tables -P FORWARD ACCEPT
  ip6tables -P OUTPUT ACCEPT
  ip6tables -F
}

install_docker() {
  is_root
  check_system

# iptables-persistent 是一个用于在 Debian 系统上保存和恢复 iptables 防火墙规则的工具
# 它允许你在系统重启后保留之前设置的 iptables 规则，从而确保防火墙在重新启动后仍然有效。
if dpkg -l | grep -q iptables-persistent; then

  echo_ok "防火墙已安装"
else

  echo_ok "安装防火墙，进入安装流程.."
  iptables_open
  remove iptables-persistent
  check_result "卸载原有的 iptables-persistent"

  remove ufw
  check_result "卸载 ufw"

  apt update -y && apt install -y iptables-persistent
  check_result "安装 iptables-persistent"

  rm /etc/iptables/rules.v4
  echo_ok "删除原有的 /etc/iptables/rules.v4"

  # 获取ssh端口
  current_port=$(grep -E '^ *Port [0-9]+' /etc/ssh/sshd_config | awk '{print $2}')

  cat > /etc/iptables/rules.v4 << EOF
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A FORWARD -i lo -j ACCEPT
-A INPUT -p tcp --dport $current_port -j ACCEPT
COMMIT
EOF
  check_result "写入iptables规则到 /etc/iptables/rules.v4"

  iptables-restore < /etc/iptables/rules.v4
  check_result "iptables-restore < /etc/iptables/rules.v4 使规则生效"

  systemctl enable netfilter-persistent
  check_result "netfilter-persistent 设置开机启动"

  echo_ok "防火墙安装完成"
fi

    echo_info "检测是否能ping谷歌"
    IsGlobal="0"
    delay="$(ping -4 -c 2 -w 2 www.google.com | grep rtt | cut -d'/' -f4 | awk '{ print $3 }' | sed -n '/^[0-9]\+\(\.[0-9]\+\)\?$/p')";
    if [ "$delay" != "" ] ; then
    	IsGlobal="1"
    	echo_info "延迟：$delay ms , ping yes"
    else
      echo_info "延迟：$delay ms , ping no"
    fi

    if [[ "${ID}" == "debian" ]]; then
        # 参考：https://docs.docker.com/engine/install/debian/#install-using-the-repository
        $INS update
        $INS install -y ca-certificates curl
        install -m 0755 -d /etc/apt/keyrings
        judge "安装 docker 依赖"

        # 检测是国外
        if [[ "$IsGlobal" == "1" ]];then

            echo_ok "能访问国外，使用官方docker源"

            # 添加官方GPG key
            curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
            chmod a+r /etc/apt/keyrings/docker.asc
            judge "添加官方GPG key"

            # 设置源
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
              $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
              tee /etc/apt/sources.list.d/docker.list > /dev/null
            judge "设置 docker 源"
            $INS update
            judge "更新 apt 缓存"
            $INS install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            judge "安装 docker"

            ## 配置docker镜像加速器
            if [ ! -d /etc/docker/ ]; then
              mkdir -p /etc/docker
              check_result "创建 /etc/docker/ 目录"
            fi
            touch /etc/docker/daemon.json
            judge "创建 /etc/docker/daemon.json 文件"

            ## "bip": "172.17.0.1/16", # docker网段设置
            cat > /etc/docker/daemon.json << EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "1m",
    "max-file": "3"
  }
}
EOF
            check_result "配置 docker 镜像加速器"

            systemctl daemon-reload && systemctl restart docker
            judge "重启 docker"
            echo_ok "能访问国外，无需配置docker国内镜像加速器"
        else

            echo_ok "不能访问国外，使用阿里的docker源"
            # 安装GPG证书
            curl -fsSL https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
            chmod a+r /etc/apt/keyrings/docker.asc
            judge "添加GPG key"

            # 设置源
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://mirrors.ustc.edu.cn/docker-ce/linux/debian \
              $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
              tee /etc/apt/sources.list.d/docker.list > /dev/null
            judge "设置 docker 源"
            $INS update
            judge "更新 apt 缓存"
            $INS install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            judge "安装 docker"

            ## 配置docker镜像加速器
            if [ ! -d /etc/docker/ ]; then
              mkdir -p /etc/docker
              check_result "创建 /etc/docker/ 目录"
            fi
            touch /etc/docker/daemon.json
            judge "创建 /etc/docker/daemon.json 文件"

            ## "bip": "172.17.0.1/16", # docker网段设置
            cat > /etc/docker/daemon.json << EOF
{
  "registry-mirrors": [
    "https://m9wl9ue4.mirror.aliyuncs.com",
    "https://docker.mirrors.ustc.edu.cn",
    "https://reg-mirror.qiniu.com"
  ],
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "1m",
    "max-file": "3"
  }
}
EOF
            check_result "配置 docker 镜像加速器"
            systemctl daemon-reload && systemctl restart docker
            judge "重启 docker"
            echo_ok "不能访问国外，已配置docker国内镜像加速器"
        fi

    else
      echo_error "当前系统为 ${ID} ${VERSION_ID} 不在支持的系统列表内，安装中断"
      exit 1
    fi
}

install_docker
