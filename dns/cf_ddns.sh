#!/bin/bash
# 设置环境变量，确保 crontab 运行时能找到命令
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# --- CHANGE THESE ---
auth_key="${1:-"你的API令牌"}"
zone_name="${2:-"example.com"}"
record_name="${3:-"www.example.com"}"
# auth_key="c2547eb745079dac9320b638f5e225cf483" # https://dash.cloudflare.com/profile/api-tokens 创建令牌
# zone_name="example.com" # 顶级域名
# record_name="www.example.com" # 要改dns的域名
# --------------------

# --- MAYBE CHANGE THESE ---
# --connect-timeout 2: 尝试建立连接的最长等待时间
# -m 4: 整个请求（包括下载数据）的总限时
get_ip() {
    local ipv4=$(curl -s4 -m 4 --connect-timeout 2 http://ipv4.icanhazip.com || \
                 curl -s4 -m 4 --connect-timeout 2 ip.sb || \
                 curl -s4 -m 4 --connect-timeout 2 http://ident.me)
    echo "$ipv4"
}

if [ "$4" ]; then
    ip=$4
else
    ip=$(get_ip)
fi

# 文件路径设置
ip_file=~/cf_ddns_ip_${record_name}.txt
id_file=~/cf_ddns_cloudflare_${record_name}.ids
log_file=~/cf_ddns_cloudflare_${record_name}.log
lock_file=/tmp/cf_ddns_${record_name}.lock

# 终端可见 + 写日志
log() {
  local msg
  msg="[$(date '+%Y-%m-%d %H:%M:%S')] - $1"
  echo "$msg" | tee -a "$log_file"
}

# --- 优化点：防止重复运行 ---
if [ -f "$lock_file" ]; then
    # 检查进程是否真的还在运行
    pid=$(cat "$lock_file")
    if ps -p "$pid" > /dev/null; then
        exit 1
    fi
fi
echo $$ > "$lock_file"
trap 'rm -f "$lock_file"' EXIT # 脚本退出时自动删除锁文件

# 依赖检查
HAS_JQ=false
if command -v jq >/dev/null 2>&1; then HAS_JQ=true; fi

# 删除ID文件
rm_id_file() {
    [ -f "$id_file" ] && rm "$id_file"
}

# 日志轮转 (保持 5MB)
if [[ -f $log_file ]]; then
  LOG_SIZE=$(stat -c%s "$log_file" 2>/dev/null || du -b "$log_file" | awk '{print $1}')
  if [ "${LOG_SIZE:-0}" -gt 5242880 ]; then
      log "日志文件过大，执行轮转..."
      mv "$log_file" "${log_file}.old"
  fi
fi

# 检查 IP 是否发生变化
if [ -f "$ip_file" ]; then
    old_ip=$(cat "$ip_file")
    if [ "$ip" == "$old_ip" ]; then
        echo "IP has not changed."
        exit 0
    fi
fi

# 验证 IP 格式
if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    log "错误: 获取到的 IP [$ip] 格式不正确"
    exit 1
fi

# 获取 Zone ID 和 Record ID
if [ -f "$id_file" ] && [ $(wc -l < "$id_file") -ge 2 ]; then
    zone_identifier=$(head -n 1 "$id_file")
    record_identifier=$(sed -n '2p' "$id_file")
    # 尝试从缓存读取 proxied 状态（第三行）
    proxied_status=$(sed -n '3p' "$id_file")
    [ -z "$proxied_status" ] && proxied_status="false"
else
    log "正在从 Cloudflare 获取域名信息..."

    zone_res=$(curl -s4 -m 15 -X GET "https://api.cloudflare.com/client/v4/zones?name=$zone_name" \
             -H "Authorization: Bearer $auth_key" \
             -H "Content-Type: application/json")

    if $HAS_JQ; then
        zone_identifier=$(echo "$zone_res" | jq -r '.result[0].id // empty')
    else
        zone_identifier=$(echo "$zone_res" | grep -Po '(?<="id":")[^"]*' | head -1)
    fi

    record_res=$(curl -s4 -m 15 -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?name=$record_name" \
               -H "Authorization: Bearer $auth_key" \
               -H "Content-Type: application/json")

    if $HAS_JQ; then
        record_identifier=$(echo "$record_res" | jq -r '.result[0].id // empty')
        # 智能获取当前的云朵状态，避免脚本把云朵关掉
        proxied_status=$(echo "$record_res" | jq -r '.result[0].proxied // false')
    else
        record_identifier=$(echo "$record_res" | grep -Po '(?<="id":")[^"]*' | head -1)
        proxied_status="false" # 无 jq 时默认为 false
    fi

    if [ "$zone_identifier" ] && [ "$record_identifier" ] && [ "$zone_identifier" != "null" ]; then
        echo "$zone_identifier" > "$id_file"
        echo "$record_identifier" >> "$id_file"
        echo "$proxied_status" >> "$id_file"
    else
        rm_id_file
        log "错误: 无法获取 Zone ID 或 Record ID"
        exit 1
    fi
fi

# 执行更新操作 (加入 proxied 状态同步)
update=$(curl -s4 -m 25 -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" \
     -H "Authorization: Bearer $auth_key" \
     -H "Content-Type: application/json" \
     --data "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":120,\"proxied\":$proxied_status}")

# 结果判断
if [[ $update == *"\"success\":true"* ]]; then
    log "更新成功: $record_name IP 已切换至 $ip (Proxied: $proxied_status)"
    echo "$ip" > "$ip_file"
else
    rm_id_file
    log "更新失败! 详细响应: $update"
    exit 1
fi