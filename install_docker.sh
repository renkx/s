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
#NAME="CentOS Linux"
#VERSION="7 (Core)"
#ID="centos"
#ID_LIKE="rhel fedora"
#VERSION_ID="7"
#PRETTY_NAME="CentOS Linux 7 (Core)"
#ANSI_COLOR="0;31"
#CPE_NAME="cpe:/o:centos:centos:7"
#HOME_URL="https://www.centos.org/"
#BUG_REPORT_URL="https://bugs.centos.org/"
#CENTOS_MANTISBT_PROJECT="CentOS-7"
#CENTOS_MANTISBT_PROJECT_VERSION="7"
#REDHAT_SUPPORT_PRODUCT="centos"
#REDHAT_SUPPORT_PRODUCT_VERSION="7"
# source 只有在bash下才可用
source '/etc/os-release'

#从VERSION中提取发行版系统的英文名称，为了在debian/ubuntu下添加相对应的Nginx apt源
VERSION=$(echo "${VERSION}" | awk -F "[()]" '{print $2}')

check_system() {
  if [[ "${ID}" == "centos" && ${VERSION_ID} -ge 7 ]]; then
    echo_ok "当前系统为 Centos ${VERSION_ID} ${VERSION}"
    INS="yum"
  elif [[ "${ID}" == "debian" && ${VERSION_ID} -ge 8 ]]; then
    echo_ok "当前系统为 Debian ${VERSION_ID} ${VERSION}"
    INS="apt"
    $INS update
  elif [[ "${ID}" == "ubuntu" && $(echo "${VERSION_ID}" | cut -d '.' -f1) -ge 16 ]]; then
    echo_ok "当前系统为 Ubuntu ${VERSION_ID} ${UBUNTU_CODENAME}"
    INS="apt"
    $INS update
  else
    echo_error "当前系统为 ${ID} ${VERSION_ID} ${VERSION} 不在支持的系统列表内，安装中断"
    exit 1
  fi

  $INS install -y dbus
  check_result "安装 dbus"

  systemctl stop firewalld
  systemctl disable firewalld
  check_result "关闭 firewalld"

  systemctl stop ufw
  systemctl disable ufw
  check_result "关闭 ufw"
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
#    read -rp "请确认时间是否准确,误差范围±3分钟(Y/N): " chrony_install
#    [[ -z ${chrony_install} ]] && chrony_install="Y"
#    case $chrony_install in
#    [yY][eE][sS] | [yY])
#        echo -e "${GreenBG} 继续安装 ${Font}"
#        sleep 2
#        ;;
#    *)
#        echo -e "${RedBG} 安装终止 ${Font}"
#        exit 2
#        ;;
#    esac
}

# 依赖安装
dependency_install() {

    if [[ "${ID}" == "centos" ]]; then
        # 设置软件源，并缓存软件包，【--import设置签名】
        # remi源 php相关环境；ius源 git软件等
        # Remi repository 是包含最新版本 PHP 和 MySQL 包的 Linux 源，由 Remi 提供维护。
        # IUS（Inline with Upstream Stable）是一个社区项目，它旨在为 Linux 企业发行版提供可选软件的最新版 RPM 软件包。
        rpm --import /etc/pki/rpm-gpg/*
        ${INS} -y install yum-fastestmirror
        ${INS} -y install https://mirrors.aliyun.com/remi/enterprise/remi-release-7.rpm
        ${INS} -y install https://mirrors.aliyun.com/ius/ius-release-el7.rpm
        rpm --import /etc/pki/rpm-gpg/*
        ${INS} clean all
        ${INS} makecache
    fi

    ${INS} install wget zsh vim curl net-tools lsof screen vnstat bind9-dnsutils iperf3 -y
    check_result "安装基础依赖"

    if [[ "${ID}" == "centos" ]]; then
        # centos 安装git
        ${INS} install git224 -y
        judge "安装 git"

        ${INS} -y install crontabs
        judge "安装 crontab"
    else
        # debian 安装git
        ${INS} install git -y
        judge "安装 git"

        ${INS} -y install cron
        judge "安装 crontab"
    fi

    if [[ "${ID}" == "centos" ]]; then
        touch /var/spool/cron/root && chmod 600 /var/spool/cron/root
        check_result "创建 crontab 文件"
        systemctl start crond && systemctl enable crond
        judge "启动 crond 服务"
    else
        touch /var/spool/cron/crontabs/root && chmod 600 /var/spool/cron/crontabs/root
        check_result "创建 crontab 文件"
        systemctl start cron && systemctl enable cron
        judge "启动 cron 服务"

    fi

    ${INS} -y install bc
    judge "安装 bc"

    if [[ "${ID}" == "centos" ]]; then
        ${INS} -y install pcre pcre-devel zlib-devel epel-release
        check_result "安装 pcre pcre-devel zlib-devel epel-release"
    else
        ${INS} -y install libpcre3 libpcre3-dev zlib1g-dev
        check_result "安装 libpcre3 libpcre3-dev zlib1g-dev"
    fi
}

install_docker() {
    is_root
    check_system
    chrony_install
    dependency_install

    if [[ "${ID}" == "centos" ]]; then
        # 参考：https://docs.docker.com/engine/install/centos/#install-using-the-repository
        # 安装 yum-utils 软件包（它提供 yum-config-manager 实用程序）
        yum install -y yum-utils
        # 并设置稳定的源。
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        judge "添加 docker 源"
        # 添加Docker软件包源 这是阿里提供的源
        # yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
        # 安装最新版本的 Docker Engine 和 containerd
        yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        judge "安装 docker"
        # 启动并设置开机启动
        systemctl start docker && systemctl enable docker
        judge "启动 docker"
        docker version
    elif [[ "${ID}" == "debian" ]]; then
        # 参考：https://docs.docker.com/engine/install/debian/#install-using-the-repository
        $INS update
        $INS install -y apt-transport-https ca-certificates curl gnupg lsb-release gpg software-properties-common
        judge "安装 docker 依赖"

        # 检测国内还是国外
        ping -c 1 www.google.com >>/dev/null 2>&1
        if [[ $? == 0 ]];then

            echo_ok "能访问国外，使用官方docker源"
            # 添加官方GPG key
            if [[ ! -f /usr/share/keyrings/docker-archive-keyring.gpg ]]; then
                curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
                judge "添加官方GPG key"
            fi
            # 设置源
            echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian \
            $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
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
            curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | apt-key add -
            # 设置源
            echo \
            "deb [arch=$(dpkg --print-architecture)] https://mirrors.aliyun.com/docker-ce/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
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
