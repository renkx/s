#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

Red="\033[31m"
# 有背景的红色
RedBG="\033[41;37m"
Font="\033[0m"

Error="${Red}[错误]${Font}"

# 检查当前用户是否为 root 用户
if [ "$EUID" -ne 0 ]; then
  echo -e "${Error} ${RedBG} 请使用 root 用户身份运行此脚本 ${Font}" >&2
  exit
fi

# 更新motd
update_motd() {
  # 删除原有的
  rm -rf /etc/update-motd.d/ /etc/motd /run/motd.dynamic
  mkdir -p /etc/update-motd.d/

    cat >/etc/update-motd.d/00-header <<'EOF'
#!/bin/sh

# ---------- 彩色设置 ----------
GREEN="\033[0;32m"
CYAN="\033[0;36m"
RESET="\033[0m"

# ---------- 系统信息 ----------
# 系统发行版描述
if [ -z "$DISTRIB_DESCRIPTION" ] && [ -x /usr/bin/lsb_release ]; then
    DISTRIB_DESCRIPTION=$(lsb_release -s -d)
fi

# 内核版本、系统名、架构
OS_NAME=$(uname -s)
KERNEL_VERSION=$(uname -r)
ARCH=$(uname -m)

# ---------- 输出系统信息 ----------
printf "\n"
printf "${GREEN}Welcome to %s${RESET}\n" "$DISTRIB_DESCRIPTION"
printf "${CYAN}OS: %s %s (%s)${RESET}\n" "$OS_NAME" "$KERNEL_VERSION" "$ARCH"
printf "\n"
EOF

    cat >/etc/update-motd.d/10-sysinfo <<'EOF'
#!/bin/bash

# ===============================================================
#                    系统状态概览 (彩色版 + 异步公网 IP)
# ===============================================================

# ---------- 颜色 ----------
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
RESET="\033[0m"

# ---------- 1. 系统负载 ----------
core_count=$(nproc 2>/dev/null || echo 1)
read load1 load5 load15 _ < /proc/loadavg
# 转换为百分比整数
load_percent=$(awk "BEGIN{printf int(($load1/$core_count)*100)}")

if [ "$load_percent" -gt 90 ]; then
    load_color=$RED
elif [ "$load_percent" -gt 70 ]; then
    load_color=$YELLOW
else
    load_color=$GREEN
fi

# ---------- 1a. 登录信息 ----------
# 安全统计：
# 1. 总登录记录数（用户名不去重，但只统计真正终端 pts/tty）
# 2. 不同用户名数（去重用户名）
# 3. 真实在线会话数（用户名 + 终端 + 远程IP，只统计真正终端 pts/tty）

# 筛选真正终端的 who 输出
who_term_filtered=$(who | awk '{
    term=$2
    if($2=="sshd"){ term=$3 }
    if(term ~ /^pts/ || term ~ /^tty/) print $0
}')

total_login=$(echo "$who_term_filtered" | grep -c '^')
unique_user=$(echo "$who_term_filtered" | awk '{print $1}' | sort -u | grep -c '^')
session_count=$(echo "$who_term_filtered" | awk '{
    ip="本地"
    for(i=1;i<=NF;i++){
        if($i ~ /^\([0-9.:]+\)$/){ ip=$i; break }
    }
    print $1,$2,ip
}' | sort -u | grep -c '^')

echo -e "==============================================================="
echo -e "                   系统状态概览"
echo -e "==============================================================="
echo -e " > 系统已运行: $(uptime -p | sed 's/^up //')"
echo -e " > 系统负载: ${load_color}${load1} ${load5} ${load15} (1/5/15 min, ${load_percent}% CPU负载)${RESET} (基于 $core_count 核心 CPU)"
echo -e " > 登录情况: ${CYAN}${total_login}${RESET} (总登录记录数), ${CYAN}${unique_user}${RESET} (不同用户名), ${CYAN}${session_count}${RESET} (真实会话数: 用户名+终端+远程IP)"

# ---------- 2. 内存使用 (含 Swap) ----------
print_mem_usage() {
    local type=$1
    local total_kb avail_kb used_kb total_mb used_mb avail_mb percent color

    if [ "$type" = "RAM" ]; then
        total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        avail_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        [ -z "$avail_kb" ] && avail_kb=$(grep MemFree /proc/meminfo | awk '{print $2}') # 老内核兼容
        label="内存占用"
    else
        total_kb=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
        avail_kb=$(grep SwapFree /proc/meminfo | awk '{print $2}')
        label="Swap占用"
    fi

    if [ "$total_kb" -gt 0 ]; then
        used_kb=$((total_kb - avail_kb))
        total_mb=$((total_kb / 1024))
        used_mb=$((used_kb / 1024))
        avail_mb=$((avail_kb / 1024))

        # 计算百分比并取整进行逻辑判断
        percent_float=$(awk -v u="$used_kb" -v t="$total_kb" 'BEGIN{printf "%.1f", (u/t)*100}')
        percent_int=${percent_float%.*}

        if [ "$percent_int" -ge 90 ]; then color=$RED
        elif [ "$percent_int" -ge 70 ]; then color=$YELLOW
        else color=$GREEN; fi

        echo -e " > ${label}: ${color}${used_mb}MB / ${total_mb}MB (${percent_float}% 已用, 剩余: ${avail_mb}MB)${RESET}"
    elif [ "$type" = "RAM" ]; then
        echo -e " > ${label}: ${RED}获取失败${RESET}"
    else
        echo -e " > Swap占用: ${CYAN}未启用${RESET}"
    fi
}

print_mem_usage "RAM"
print_mem_usage "SWAP"

# ---------- 3. 磁盘使用 (排除虚拟/容器磁盘) ----------
echo -e " > 磁盘使用情况:"
df -h -x tmpfs -x devtmpfs -x overlay -x squashfs -x loop 2>/dev/null | tail -n +2 | while read line; do
    # 自动解析最后一列为挂载点，倒数第二列为百分比
    mount=$(echo "$line" | awk '{print $NF}')
    pcent=$(echo "$line" | awk '{print $(NF-1)}')
    size=$(echo "$line" | awk '{print $2}')
    used=$(echo "$line" | awk '{print $3}')
    avail=$(echo "$line" | awk '{print $4}')

    pct_num=${pcent%\%}
    if [ "$pct_num" -ge 90 ]; then disk_color=$RED
    elif [ "$pct_num" -ge 70 ]; then disk_color=$YELLOW
    else disk_color=$GREEN; fi

    printf "    %-12s %s / %s (%b%s%b)  可用: %s\n" "$mount" "$used" "$size" "$disk_color" "$pcent" "$RESET" "$avail"
done

# ---------- 4. 内网 IP ----------
ip_list=$(hostname -I 2>/dev/null | awk '{
    for(i=1;i<=NF;i++){
        if($i ~ /^127\./) continue;
        if($i ~ /^10\./ || $i ~ /^172\.(1[6-9]|2[0-9]|3[0-1])\./ || $i ~ /^192\.168\./) printf "%s ", $i;
        if($i ~ /^fc00:/ || $i ~ /^fd00:/) printf "%s ", $i;
    }
}')
echo -e " > 内网 IP: ${CYAN}${ip_list:-未获取到}${RESET}"

# ---------- 5. 公网 IP (带缓存逻辑) ----------
PUBIP_FILE="/tmp/.motd_pubip"
PUBIP_TIME_FILE="/tmp/.motd_pubip_time"
PUBIP_TIMESTAMP_FILE="/tmp/.motd_pubip_ts"

get_pubip_from_net() {
    local ipv4 ipv6 pubip
    ipv4=$(curl -s -4 --connect-timeout 2 --max-time 3 http://ipv4.icanhazip.com 2>/dev/null)
    [ -z "$ipv4" ] && ipv4=$(curl -s -4 --connect-timeout 2 --max-time 3 ip.sb 2>/dev/null)

    ipv6=$(curl -s -6 --connect-timeout 2 --max-time 3 http://ipv6.icanhazip.com 2>/dev/null)
    [ -z "$ipv6" ] && ipv6=$(curl -s -6 --connect-timeout 2 --max-time 3 ip.sb 2>/dev/null)

    pubip=""
    [ -n "$ipv4" ] && pubip="$ipv4"
    [ -n "$ipv6" ] && pubip="$pubip $ipv6"
    [ -z "$pubip" ] && pubip="未获取到"
    echo "$pubip"
}

fetch_pubip() {
    get_pubip_from_net > "$PUBIP_FILE"
    date '+%Y-%m-%d %H:%M:%S' > "$PUBIP_TIME_FILE"
    date +%s > "$PUBIP_TIMESTAMP_FILE"
}

get_cached_pubip() { cat "$PUBIP_FILE" 2>/dev/null || echo "获取中..."; }
get_cached_pubip_time() { cat "$PUBIP_TIME_FILE" 2>/dev/null || echo "未知时间"; }

if [ ! -f "$PUBIP_FILE" ]; then
    fetch_pubip
else
    (
        now=$(date +%s)
        last_ts=$(cat "$PUBIP_TIMESTAMP_FILE" 2>/dev/null || echo 0)
        delta=$((now - last_ts))
        if [ "$delta" -ge 300 ]; then
            new_ip=$(get_pubip_from_net)
            current=$(get_cached_pubip)
            [ "$current" != "$new_ip" ] && fetch_pubip
        fi
    ) &
fi

pubip=$(get_cached_pubip)
pubip_time=$(get_cached_pubip_time)
echo -e " > 公网 IP: ${CYAN}${pubip}${RESET} (${YELLOW}抓取时间: ${pubip_time}${RESET})"

echo -e "==============================================================="
EOF

    cat >/etc/update-motd.d/90-footer <<'EOF'
#!/bin/sh
echo " > 服务器当前时间: $(date '+%Y-%m-%d %H:%M:%S %A')"
printf "\n"
EOF

    chmod +x /etc/update-motd.d/00-header
    chmod +x /etc/update-motd.d/10-sysinfo
    chmod +x /etc/update-motd.d/90-footer
}

update_motd
