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
  ${INS} -y install chrony
  judge "安装 chrony 时间同步服务 "

  timedatectl set-ntp true
  check_result "设置系统时间同步服务"

  if [[ "${ID}" == "centos" ]]; then
      systemctl enable chronyd && systemctl restart chronyd
  else
      systemctl enable chrony && systemctl restart chrony
  fi
  judge "chronyd 启动 "

  timedatectl set-timezone Asia/Shanghai
  check_result "设置时区为 Asia/Shanghai"

  echo_ok "等待时间同步，sleep 10"
  sleep 10

  chronyc sourcestats -v
  check_result "查看时间同步源"
  chronyc tracking -v
  check_result "查看时间同步状态"
  date
  check_result "查看时间"
}

# 依赖安装
dependency_install() {

  ${INS} install wget zsh vim curl net-tools lsof screen vnstat bind9-dnsutils iperf3 -y
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

  ${INS} -y install libpcre3 libpcre3-dev zlib1g-dev
  check_result "安装 libpcre3 libpcre3-dev zlib1g-dev"
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

# 使用 DHCP 钩子，禁止修改 /etc/resolv.conf
if [[ ! -f /etc/dhcp/dhclient-enter-hooks.d/nodnsupdate ]]; then
  cat <<EOF >/etc/dhcp/dhclient-enter-hooks.d/nodnsupdate
#!/bin/sh
make_resolv_conf(){
    :
}
EOF
check_result "创建 /etc/dhcp/dhclient-enter-hooks.d/nodnsupdate 文件"
chmod +x /etc/dhcp/dhclient-enter-hooks.d/nodnsupdate
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
  current_port=$(grep -E '^ *Port [0-9]+' /etc/ssh/sshd_config | awk '{print $2}')
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
  hostname=$(hostname) && echo "127.0.0.1    $hostname" >> /etc/hosts
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
