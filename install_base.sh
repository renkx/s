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

# source 只有在bash下才可用
source '/etc/os-release'

#从VERSION中提取发行版系统的英文名称，为了在debian/ubuntu下添加相对应的Nginx apt源
VERSION=$(echo "${VERSION}" | awk -F "[()]" '{print $2}')


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

chrony_install() {
  # 检查并安装 chrony
  if ! command -v chronyd &>/dev/null && ! command -v chrony &>/dev/null; then
      ${INS} -y install chrony
      judge "安装 chrony 时间同步服务 "
  fi

  check_network_env

  echo_info "正在根据网络环境配置 NTP 源..."

  # 停止服务以便重写配置
  systemctl stop chrony 2>/dev/null || systemctl stop chronyd 2>/dev/null

  # --- 核心改进：基于 IsGlobal 动态配置 NTP 源 ---
  if [[ "$IsGlobal" == "1" ]]; then
      # 海外机器：使用 Google 和 Debian 官方源
      local ntp_servers="pool time.google.com iburst
pool time.cloudflare.com iburst
pool 2.debian.pool.ntp.org iburst"
  else
      # 国内机器：首选阿里、腾讯、国家授时中心源
      local ntp_servers="pool ntp.aliyun.com iburst
pool ntp.tencent.com iburst
pool ntp.ntsc.ac.cn iburst"
  fi

  # 备份旧配置并重写
  [ -f /etc/chrony/chrony.conf ] && mv /etc/chrony/chrony.conf /etc/chrony/chrony.conf.bak

  # 重写配置文件，保留你发现的关键目录引用
    cat <<EOF > /etc/chrony/chrony.conf
$ntp_servers

# 保持与 DHCP 获取的源兼容 (sourcedir 允许从云厂商内网获取源)
sourcedir /run/chrony-dhcp
sourcedir /etc/chrony/sources.d

# 基础文件路径设置
keyfile /etc/chrony/chrony.keys
driftfile /var/lib/chrony/chrony.drift
ntsdumpdir /var/lib/chrony
logdir /var/log/chrony

maxupdateskew 100.0
leapseclist /usr/share/zoneinfo/leap-seconds.list

# 核心同步逻辑优化
# 如果偏差大于 1 秒，则不限次数强制步进对齐 (解决 503 和时间大幅偏差的关键)
makestep 1.0 -1
rtcsync

# 包含 conf.d 目录下的其他配置
confdir /etc/chrony/conf.d
EOF

  # 确保服务没有被 mask，然后启动
  local service_name="chrony"
  [[ "${ID}" == "centos" ]] && service_name="chronyd"
  systemctl unmask $service_name >/dev/null 2>&1
  systemctl enable $service_name
  systemctl restart $service_name
  judge "chronyd 启动与配置应用"

  # 显式开启系统 NTP 同步开关
  timedatectl set-ntp true
  check_result "设置系统时间同步服务"

  timedatectl set-timezone Asia/Shanghai
  check_result "设置时区为 Asia/Shanghai"

  # 强制让 chrony 立即尝试探测源，而不是等待轮询周期
  chronyc burst 4/4 >/dev/null 2>&1
  # 立即执行步进对齐
  chronyc makestep >/dev/null 2>&1

  echo_ok "等待 Chrony 同步时间中 ..."
  MAX_WAIT=60    # 最多等待 60 秒
  INTERVAL=2     # 每 2 秒检查一次
  elapsed=0

  while true; do
    # 获取系统与 NTP 偏差（以秒为单位）
    # 增加判断：只有 Reference ID 不是 0.0.0.0 时，offset 才有意义
    tracking_info=$(chronyc tracking 2>/dev/null)
    if echo "$tracking_info" | grep -q "Reference ID" && ! echo "$tracking_info" | grep -q "0.0.0.0"; then
        offset=$(echo "$tracking_info" | awk '/System time/ {print $4}')
        # 去掉负号，并判断是否小于 1 秒
        abs_offset=$(echo "$offset" | tr -d '-' | awk '{print ($1 < 1.0) ? "pass" : "fail"}')

        if [[ "$abs_offset" == "pass" ]]; then
            echo_ok "时间同步完成，系统与 NTP 偏差：${offset} 秒"
            break
        fi
    fi

    sleep $INTERVAL
    elapsed=$((elapsed + INTERVAL))
    if [[ $elapsed -ge $MAX_WAIT ]]; then
        echo_error "时间同步握手超时。建议检查机器 UDP 123 端口出站权限，当前偏差: ${offset:-未知} 秒。"
        break
    fi
  done

  # 最终状态展示
  chronyc sourcestats -v
  check_result "查看时间同步源"
  chronyc tracking -v
  check_result "查看时间同步状态"
  date
  check_result "查看最终系统时间"
}

# 依赖安装
dependency_install() {

  # 预设 iperf3 不启动 daemon（自动选择 N）
  echo "iperf3 iperf3/start_daemon boolean false" | debconf-set-selections

  # DEBIAN_FRONTEND=noninteractive + -y 避免任何交互界面，放在一行 DEBIAN_FRONTEND 临时生效
  DEBIAN_FRONTEND=noninteractive ${INS} install wget zsh vim curl net-tools lsof screen vnstat bind9-dnsutils iperf3 -y
  check_result "安装基础依赖"

  # 系统监控工具
  ${INS} install -y htop
  judge "安装 系统监控工具 htop"
  # 网络流量监控工具
  ${INS} install -y iftop
  judge "安装 网络流量监控工具 iftop"
  # 现代化监控工具
  ${INS} install -y btop
  judge "安装 现代化监控工具 btop"
  # 磁盘占用查看工具
  ${INS} install -y gdu
  judge "安装 磁盘占用查看工具 gdu"

  # debian 安装git
  ${INS} install git -y
  judge "安装 git"

  ${INS} -y install cron
  judge "安装 crontab"

  touch /var/spool/cron/crontabs/root && chmod 600 /var/spool/cron/crontabs/root
  check_result "创建 crontab 文件"
  systemctl start cron && systemctl enable cron
  judge "启动 cron 服务"

  if [ "$(printf '%s\n' "$VERSION_ID" "13" | sort -V | head -n1)" = "13" ]; then
    # debian版本大于等于13
    ${INS} -y install libpcre2-dev zlib1g-dev
    check_result "安装 libpcre2-dev zlib1g-dev"
  else
    ${INS} -y install libpcre3 libpcre3-dev zlib1g-dev
    check_result "安装 libpcre3 libpcre3-dev zlib1g-dev"
  fi
}

# /etc/rc.local 开启启动程序开启
rc_local_enable() {
# 不存在才处理
if [[ ! -f /etc/rc.local ]]; then
  cat <<EOF >/etc/rc.local
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "exit 0" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.

exit 0
EOF
  check_result "创建 /etc/rc.local 文件"
  chmod +x /etc/rc.local
  # 启动时无视警告
  systemctl enable --now rc-local
  echo_ok "rc-local 设置开机启动（无视上面自启动警告）"
fi

##### /etc/resolv.conf 不能修改，以下是处理逻辑：#####
# dhclient 这个是debian13之前使用的，13之后就没了
# 以下设置可以不用设置了，统一使用 chattr +i /etc/resolv.conf 加锁的形式，禁止更改
if ! command -v dhclient >/dev/null 2>&1; then
  echo "dhclient 未安装，跳过 resolv.conf hook"
else
# 使用 DHCP 钩子，禁止修改 /etc/resolv.conf
  if [[ ! -f /etc/dhcp/dhclient-enter-hooks.d/nodnsupdate ]]; then
    cat <<EOF >/etc/dhcp/dhclient-enter-hooks.d/nodnsupdate
#!/bin/sh
# 禁止 dhclient 修改 /etc/resolv.conf
make_resolv_conf(){
    :
}
EOF
  check_result "创建 /etc/dhcp/dhclient-enter-hooks.d/nodnsupdate 文件"
  chmod +x /etc/dhcp/dhclient-enter-hooks.d/nodnsupdate
  fi
fi

}

# 安装防爆程序 fail2ban
install_fail2ban() {

  ${INS} install fail2ban -y
  judge "安装 防爆程序 fail2ban"

  # Fail2ban configurations.
  # Reference: https://github.com/fail2ban/fail2ban/issues/2756
  #            https://www.mail-archive.com/debian-bugs-dist@lists.debian.org/msg1879390.html
  if ! grep -qE "^[^#]*allowipv6\s*=\s*auto" "/etc/fail2ban/fail2ban.conf"; then
      sed -i '/^\[Definition\]/a allowipv6 = auto' /etc/fail2ban/fail2ban.conf;
  fi
  sed -ri 's/^backend = auto/backend = systemd/g' /etc/fail2ban/jail.conf;

  # 获取ssh端口
  current_port=$(ss -tlnp | grep sshd | awk '{print $4}' | grep -oE '[0-9]+$' | head -n1)
  current_port=${current_port:-22}
  # 清除默认配置
  rm -rf /etc/fail2ban/jail.d/defaults-debian.conf
  # 设置ssh配置
  cat <<EOF >/etc/fail2ban/jail.d/sshd.local
[sshd]
enabled = true
port = $current_port
# 忽略 IP/段
ignoreip = 192.168.0.0/16 10.0.0.0/8 172.16.0.0/12 127.0.0.1/8 ::1
# 封禁的时长（天）
bantime  = 30d
# 此时长（分）内达到 maxretry 次就执行封禁动作
findtime  = 30m
# 匹配到的阈值（允许失败次数）
maxretry = 2
EOF

  systemctl enable fail2ban
  systemctl restart fail2ban
  systemctl status fail2ban
  # 设置hostname解析，否则fail2ban会出现报错
  # 获取当前 hostname
  hostname=$(hostname)
  # 如果 /etc/hosts 中不存在这一行才追加
  if ! grep -q "127.0.0.1[[:space:]]\+$hostname" /etc/hosts; then
      echo "127.0.0.1    $hostname" >> /etc/hosts
      echo_ok "已添加 hostname 解析到 /etc/hosts"
  fi
  echo_ok "防爆程序 fail2ban 设置完成"
}

install_base() {
  is_root
  check_system
  chrony_install
  dependency_install
  rc_local_enable
  install_fail2ban
}

install_base
