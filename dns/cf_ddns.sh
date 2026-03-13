#!/bin/bash
# 设置环境变量，确保 crontab 运行时能找到命令
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# --- CHANGE THESE ---
auth_key="${1:-"你的API令牌"}"
zone_name="${2:-"example.com"}"
record_name="${3:-"www.example.com"}"
# --------------------

# --- 日志与 Logrotate 配置 ---
LOG="/var/log/cf_ddns_${record_name}.log"
LOGROTATE_CONF="/etc/logrotate.d/cf_ddns_${record_name}"

# 自动创建 logrotate 配置（只在不存在时创建）
# 注意：写入 /etc/logrotate.d 需要 root 权限，建议此脚本使用 sudo 或 root 用户的 crontab 运行
if [ ! -f "$LOGROTATE_CONF" ]; then
  cat > "$LOGROTATE_CONF" <<EOF
$LOG {
    size 10M
    rotate 3
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
fi

# 文件路径设置
id_file="/tmp/cf_ddns_cloudflare_${record_name}.ids"
lock_file="/tmp/cf_ddns_${record_name}.lock"

# 终端可见 + 写日志
log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] - $1"
  echo "$msg" | tee -a "$LOG"
}

# --- 防止重复运行 ---
if [ -f "$lock_file" ]; then
    pid=$(cat "$lock_file")
    if ps -p "$pid" > /dev/null 2>&1; then exit 1; fi
fi
echo $$ > "$lock_file"
trap 'rm -f "$lock_file"' EXIT

# 依赖检查
HAS_JQ=false
if command -v jq >/dev/null 2>&1; then HAS_JQ=true; fi

# --- IP 获取函数 ---
get_ipv4() {
    curl -s4 -m 4 --connect-timeout 2 http://ipv4.icanhazip.com || \
    curl -s4 -m 4 --connect-timeout 2 ip.sb || \
    curl -s4 -m 4 --connect-timeout 2 http://ident.me
}

get_ipv6() {
    curl -s6 -m 4 --connect-timeout 2 http://ipv6.icanhazip.com || \
    curl -s6 -m 4 --connect-timeout 2 ip.sb || \
    curl -s6 -m 4 --connect-timeout 2 http://ident.me
}

# 获取并验证 IP
ip4=$(get_ipv4)
ip6=$(get_ipv6)

if [[ -n "$ip4" && ! "$ip4" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
    log "警告: 获取到的 IPv4 [$ip4] 格式不正确，将跳过 IPv4 更新。"
    ip4=""
fi

if [[ -n "$ip6" && ! "$ip6" =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]]; then
    log "警告: 获取到的 IPv6 [$ip6] 格式不正确，将跳过 IPv6 更新。"
    ip6=""
fi

if [[ -z "$ip4" && -z "$ip6" ]]; then
    log "错误: 未能获取到任何有效的 IPv4 或 IPv6 地址，退出执行。"
    exit 1
fi

# --- 获取 Zone ID ---
if [ -f "$id_file" ]; then
    zone_identifier=$(head -n 1 "$id_file")
else
    zone_res=$(curl -s -m 15 -X GET "https://api.cloudflare.com/client/v4/zones?name=$zone_name" \
             -H "Authorization: Bearer $auth_key" \
             -H "Content-Type: application/json")
    if $HAS_JQ; then
        zone_identifier=$(echo "$zone_res" | jq -r '.result[0].id // empty')
    else
        zone_identifier=$(echo "$zone_res" | grep -Po '(?<="id":")[^"]*' | head -1)
    fi
fi

if [[ -z "$zone_identifier" ]]; then
    [ -f "$id_file" ] && rm "$id_file"
    log "错误: 无法获取 Zone ID，请检查 Token 或域名配置。"
    exit 1
else
    echo "$zone_identifier" > "$id_file"
fi

# --- 核心更新函数 ---
update_record() {
    local record_type=$1   # 'A' 或 'AAAA'
    local current_ip=$2    # 实际获取到的本地 IP

    if [[ -z "$current_ip" ]]; then
        return 0 # 没有获取到该类型的IP，静默跳过
    fi

    # 查询对应的 DNS 记录 (增加 type 过滤，防止 A 和 AAAA 互相干扰)
    local record_res=$(curl -s -m 15 -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?name=$record_name&type=$record_type" \
               -H "Authorization: Bearer $auth_key" \
               -H "Content-Type: application/json")

    local record_identifier current_cloud_ip proxied_status
    if $HAS_JQ; then
        record_identifier=$(echo "$record_res" | jq -r '.result[0].id // empty')
        current_cloud_ip=$(echo "$record_res" | jq -r '.result[0].content // empty')
        proxied_status=$(echo "$record_res" | jq -r '.result[0].proxied // false')
    else
        record_identifier=$(echo "$record_res" | grep -Po '(?<="id":")[^"]*' | head -1)
        current_cloud_ip=$(echo "$record_res" | grep -Po '(?<="content":")[^"]*' | head -1)
        proxied_status=$(echo "$record_res" | grep -Po '(?<="proxied":)true|false' | head -1)
    fi

    if [[ -z "$record_identifier" ]]; then
        log "[$record_type] 警告: 云端找不到 $record_name 的记录。请先在 Cloudflare 后台手动创建一条任意 IP 的 $record_type 记录。"
        return 1
    fi

    # 对比 IP
    if [[ "$current_ip" == "$current_cloud_ip" ]]; then
        log "[$record_type] IP 未改变 (Cloud: $current_cloud_ip)。跳过。"
        return 0
    fi

    # 执行更新
    local update_res=$(curl -s -m 25 -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" \
         -H "Authorization: Bearer $auth_key" \
         -H "Content-Type: application/json" \
         --data "{\"type\":\"$record_type\",\"name\":\"$record_name\",\"content\":\"$current_ip\",\"ttl\":120,\"proxied\":$proxied_status}")

    if [[ $update_res == *"\"success\":true"* ]]; then
        log "[$record_type] 更新成功: $current_cloud_ip -> $current_ip (Proxied: $proxied_status)"
    else
        log "[$record_type] 更新失败! 详细响应: $update_res"
    fi
}

# --- 依次尝试更新 A 记录和 AAAA 记录 ---
update_record "A" "$ip4"
update_record "AAAA" "$ip6"

exit 0