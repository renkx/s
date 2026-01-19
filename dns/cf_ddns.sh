#!/bin/bash
# 设置环境变量，确保 crontab 运行时能找到命令
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# --- CHANGE THESE ---
auth_key="${1:-"你的API令牌"}"
zone_name="${2:-"example.com"}"
record_name="${3:-"www.example.com"}"
# --------------------

# --- IP 获取函数 ---
get_ip() {
    local ipv4=$(curl -s4 -m 4 --connect-timeout 2 http://ipv4.icanhazip.com || \
                 curl -s4 -m 4 --connect-timeout 2 ip.sb || \
                 curl -s4 -m 4 --connect-timeout 2 http://ident.me)
    echo "$ipv4"
}

if [ "$4" ]; then ip=$4; else ip=$(get_ip); fi

# 文件路径设置
id_file=~/cf_ddns_cloudflare_${record_name}.ids
log_file=~/cf_ddns_cloudflare_${record_name}.log
lock_file=/tmp/cf_ddns_${record_name}.lock

# 终端可见 + 写日志
log() {
  local msg
  msg="[$(date '+%Y-%m-%d %H:%M:%S')] - $1"
  echo "$msg" | tee -a "$log_file"
}

# --- 防止重复运行 ---
if [ -f "$lock_file" ]; then
    pid=$(cat "$lock_file")
    if ps -p "$pid" > /dev/null; then exit 1; fi
fi
echo $$ > "$lock_file"
trap 'rm -f "$lock_file"' EXIT

# 依赖检查
HAS_JQ=false
if command -v jq >/dev/null 2>&1; then HAS_JQ=true; fi

# 日志轮转 (5MB)
if [[ -f $log_file ]]; then
  LOG_SIZE=$(stat -c%s "$log_file" 2>/dev/null || du -b "$log_file" | awk '{print $1}')
  if [ "${LOG_SIZE:-0}" -gt 5242880 ]; then
      log "日志文件过大，执行轮转..."
      mv "$log_file" "${log_file}.old"
  fi
fi

# 验证 IP 格式
if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    log "错误: 获取到的 IP [$ip] 格式不正确"
    exit 1
fi

# --- 获取域名信息 (Zone ID / Record ID / Cloud IP) ---
# 注意：即使有缓存，我们每次也要请求一次以确认云端当前的 content (IP)
log "正在获取 Cloudflare 云端记录信息..."

# 1. 获取 Zone ID (如果没缓存)
if [ -f "$id_file" ]; then
    zone_identifier=$(head -n 1 "$id_file")
else
    zone_res=$(curl -s4 -m 15 -X GET "https://api.cloudflare.com/client/v4/zones?name=$zone_name" \
             -H "Authorization: Bearer $auth_key" \
             -H "Content-Type: application/json")
    if $HAS_JQ; then
        zone_identifier=$(echo "$zone_res" | jq -r '.result[0].id // empty')
    else
        zone_identifier=$(echo "$zone_res" | grep -Po '(?<="id":")[^"]*' | head -1)
    fi
fi

# 2. 获取 Record ID、当前云端 IP 和 Proxied 状态
record_res=$(curl -s4 -m 15 -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?name=$record_name" \
           -H "Authorization: Bearer $auth_key" \
           -H "Content-Type: application/json")

if $HAS_JQ; then
    record_identifier=$(echo "$record_res" | jq -r '.result[0].id // empty')
    current_cloud_ip=$(echo "$record_res" | jq -r '.result[0].content // empty')
    proxied_status=$(echo "$record_res" | jq -r '.result[0].proxied // false')
else
    record_identifier=$(echo "$record_res" | grep -Po '(?<="id":")[^"]*' | head -1)
    current_cloud_ip=$(echo "$record_res" | grep -Po '(?<="content":")[^"]*' | head -1)
    proxied_status=$(echo "$record_res" | grep -Po '(?<="proxied":)true|false' | head -1)
fi

# 校验基础信息
if [[ -z "$zone_identifier" || -z "$record_identifier" ]]; then
    [ -f "$id_file" ] && rm "$id_file"
    log "错误: 无法获取 Zone ID 或 Record ID，请检查 Token 或域名配置。"
    exit 1
else
    # 缓存 Zone ID 备用
    echo "$zone_identifier" > "$id_file"
fi

# --- 核心判断：对比当前 IP 与云端 IP ---
if [ "$ip" == "$current_cloud_ip" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] - IP has not changed (Cloud: $current_cloud_ip). Skip."
    exit 0
fi

# --- 执行更新操作 ---
update=$(curl -s4 -m 25 -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" \
     -H "Authorization: Bearer $auth_key" \
     -H "Content-Type: application/json" \
     --data "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":120,\"proxied\":$proxied_status}")

# 结果判断
if [[ $update == *"\"success\":true"* ]]; then
    log "更新成功: $record_name $current_cloud_ip -> $ip (Proxied: $proxied_status)"
    exit 0
else
    log "更新失败! 详细响应: $update"
    exit 1
fi