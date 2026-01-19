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

source '/etc/os-release'

zshrc_file=~/.zshrc
ZSH=~/.oh-my-zsh

command_exists() {
	command -v "$@" >/dev/null 2>&1
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

edit_zshrc() {
  if [ -f "${zshrc_file}" ]; then
      cp "${zshrc_file}" "${zshrc_file}.bak.$(date +%Y%m%d%H%M%S)"
      echo_info "已备份旧的 .zshrc 到 ${zshrc_file}.bak"
  fi
  touch ${zshrc_file}
  cat >${zshrc_file} <<'EOF'
# 解决zsh:no matches found问题
setopt no_nomatch
# zsh其实并不使用/etc/profile文件，而是使用/etc/zsh/下面的zshenv、zprofile、zshrc、zlogin文件，并以这个顺序进行加载
source /etc/profile

export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="ys"

# disable automatic updates
zstyle ':omz:update' mode disabled

plugins=(git zsh-autosuggestions zsh-syntax-highlighting)

source $ZSH/oh-my-zsh.sh

# 解决复制粘贴出现很慢的情况
pasteinit() {
	OLD_SELF_INSERT=${${(s.:.)widgets[self-insert]}[2,3]}
	zle -N self-insert url-quote-magic # I wonder if you'd need `.url-quote-magic`?
}
pastefinish() {
	zle -N self-insert $OLD_SELF_INSERT
}
zstyle :bracketed-paste-magic paste-init pasteinit
zstyle :bracketed-paste-magic paste-finish pastefinish

alias docker-compose='docker compose'

alias ag='export http_proxy=http://127.0.0.1:10801 https_proxy=http://127.0.0.1:10801 all_proxy=socks5://127.0.0.1:10800'

EOF

  judge "替换.zshrc文件..."

  # 进入git目录会检查git的各种状态，所以在跳转的时候会明显变慢，可以使用下面的命令配置关闭检查功能
  git config --global --add oh-my-zsh.hide-status 1
  git config --global --add oh-my-zsh.hide-dirty 1
}

command_exists git || {
  echo_error "git is not installed"
  exit 1
}

if ! command_exists zsh; then
  if [[ "${ID}" == "centos" ]]; then
    yum -y install zsh
  elif [[ "${ID}" == "debian" ]]; then
    apt-get -y install zsh
  elif [[ "${ID}" == "ubuntu" ]]; then
    apt -y install zsh
  else
    echo_error "不支持此系统"
    exit 1
  fi
fi

# 检测网络
check_network_env

if [ -d "$ZSH" ]; then
  echo_info "文件夹已存在 ($ZSH)"
  rm -rf ${ZSH}
  judge "删除文件夹 ($ZSH)"
fi

if [[ "$IsGlobal" == "1" ]];then

  echo_info "git拉取【国外】ohmyzsh ... ($ZSH)"
  git clone https://github.com/ohmyzsh/ohmyzsh.git ${ZSH}
  # 自动补全
  git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git ${ZSH}/custom/plugins/zsh-autosuggestions
  # 高亮
  git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH}/custom/plugins/zsh-syntax-highlighting
else

  echo_info "git拉取【国内】ohmyzsh ... ($ZSH)"
  git clone https://gitee.com/renkx/ohmyzsh.git ${ZSH}
  git clone --depth=1 https://gitee.com/renkx/zsh-autosuggestions.git ${ZSH}/custom/plugins/zsh-autosuggestions
  git clone --depth=1 https://gitee.com/renkx/zsh-syntax-highlighting.git ${ZSH}/custom/plugins/zsh-syntax-highlighting
fi

# 编辑替换主题
edit_zshrc
# 设置默认shell
ZSH_PATH=$(command -v zsh)
chsh -s "$ZSH_PATH"
judge "更改默认shell为zsh"