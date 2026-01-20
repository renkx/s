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

# 防火墙处理
setup_firewall() {
  # iptables-persistent 是一个用于在 Debian 系统上保存和恢复 iptables 防火墙规则的工具
  # 它允许你在系统重启后保留之前设置的 iptables 规则，从而确保防火墙在重新启动后仍然有效。
  if dpkg -l | grep -q iptables-persistent; then
    echo_ok "防火墙已安装"
  else
    # 关闭所有交互界面 让包管理器使用 默认值（debconf 中预设的默认选项）来安装
    export DEBIAN_FRONTEND=noninteractive

    echo_ok "安装防火墙，进入安装流程.."
    iptables_open
    remove iptables-persistent
    check_result "卸载原有的 iptables-persistent"

    remove ufw
    check_result "卸载 ufw"

    apt update -y && apt install -y iptables-persistent
    check_result "安装 iptables-persistent"

    rm -f /etc/iptables/rules.v4
    echo_ok "删除原有的 /etc/iptables/rules.v4"

    # 获取ssh端口
    current_port=$(ss -tlnp | grep sshd | awk '{print $4}' | grep -oE '[0-9]+$' | head -n1)
    current_port=${current_port:-22}

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
}

# 检测网络
check_network_env() {
  [ -n "${IsGlobal:-}" ] && return

  echo_info "🔍 正在分析网络路由 ..."

  # 1. 核心判断：使用 Google 204 服务进行内容校验
  # -L: 跟踪重定向 (防止某些机房劫持到自己的登录页)
  # -w %{http_code}: 只输出 HTTP 状态码
  # --connect-timeout 2: 尝试建立连接的最长等待时间
  # -m 4: 整个请求（包括下载数据）的总限时
  local check_code
  check_code=$(curl -sL -k --connect-timeout 2 -m 4 -w "%{http_code}" "https://www.google.com/generate_204" -o /dev/null 2>/dev/null)

  if [ "$check_code" = "204" ]; then
    ENV_TIP="🌍 海外 (Global)"
    IsGlobal=1
  else
    # 2. 如果 Google 不通，尝试国内高可靠地址确认是否断网
    # 阿里或百度的 HTTPS 服务在国内是绝对稳定的
    local cn_code
    cn_code=$(curl -sL -k --connect-timeout 2 -m 3 -w "%{http_code}" "https://www.baidu.com" -o /dev/null 2>/dev/null)

    if [ "$cn_code" = "200" ]; then
      ENV_TIP="🇨🇳 国内 (Mainland China)"
      IsGlobal=0
    else
      ENV_TIP="🚫 网络连接异常"
      IsGlobal=0
    fi
  fi

  export IsGlobal
  echo_info "📍 网络定位: $ENV_TIP"
}

install_docker() {
  is_root
  check_system
  # 防火墙处理
  setup_firewall

  # 检测网络
  check_network_env

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
  "userland-proxy": false,
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
      check_result "配置 /etc/docker/daemon.json"

      systemctl daemon-reload && systemctl restart docker
      judge "重启 docker 使配置生效"

    else

      echo_ok "不能访问国外，使用阿里的docker源"
      # 安装GPG证书
      curl -fsSL https://mirrors.ustc.edu.cn/docker-ce/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
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
      ## Docker 默认会启动一个叫 docker-proxy 的进程来处理端口转发。在高并发下，这个进程的效率远低于内核的 iptables/nftables
      ## 关闭它，强制 Docker 使用内核原生的 NAT，这样能减轻 nf_conntrack 的压力并提升性能
      cat > /etc/docker/daemon.json << EOF
{
  "userland-proxy": false,
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
      check_result "配置 /etc/docker/daemon.json"
      systemctl daemon-reload && systemctl restart docker
      judge "重启 docker 使配置生效"
    fi

    else
      echo_error "当前系统为 ${ID} ${VERSION_ID} 不在支持的系统列表内，安装中断"
      exit 1
    fi
}

install_docker
