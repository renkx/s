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

edit_zshrc() {
  touch ${zshrc_file}
  cat >${zshrc_file} <<'EOF'
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

echo_info "检测是否能ping谷歌"
IsGlobal="0"
delay="$(ping -4 -c 2 -w 2 www.google.com | grep rtt | cut -d'/' -f4 | awk '{ print $3 }' | sed -n '/^[0-9]\+\(\.[0-9]\+\)\?$/p')";
if [ "$delay" != "" ] ; then
	IsGlobal="1"
	echo_info "延迟：$delay ms , ping yes"
else
  echo_info "延迟：$delay ms , ping no"
fi


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
chsh -s /bin/zsh
judge "更改默认shell为zsh"