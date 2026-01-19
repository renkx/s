#!/bin/bash
# 设置环境变量，确保 crontab 运行时能找到命令
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# --- CHANGE THESE ---
# 阿里云更新域名Api Host 默认:https://alidns.aliyuncs.com
var_aliyun_ddns_api_host="https://alidns.aliyuncs.com"
# 阿里云授权Key
var_access_key_id=$1
# 阿里云授权Key Secret
var_access_key_secret=$2
# 一级域名 例如:example.com
var_first_level_domain=$3
# 二级域名 例如:testddns
var_second_level_domain=$4

# 域名解析类型：A、NS、MX、TXT、CNAME、SRV、AAAA、CAA、REDIRECT_URL、FORWARD_URL
var_domain_record_type="A"
# 域名线路,默认为默认
var_domain_line="default"
# 域名生效时间,默认:600 单位:秒
if [ "$5" ]; then var_domain_ttl=$5; else var_domain_ttl=600; fi

# --- 核心：保持原代码的时间戳处理方式 ---
var_now_timestamp=$(date -u "+%Y-%m-%dT%H%%3A%M%%3A%SZ")

# --- 增强：多源 IP 获取 ---
get_ip() {
    local ipv4=""
    ipv4=$(curl -s4 -m 5 --connect-timeout 2 http://ipv4.icanhazip.com 2>/dev/null | grep -Po '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$ipv4" ] && ipv4=$(curl -s4 -m 5 --connect-timeout 2 ip.sb 2>/dev/null | grep -Po '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$ipv4" ] && ipv4=$(curl -s4 -m 5 --connect-timeout 2 http://ident.me 2>/dev/null | grep -Po '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    echo "$ipv4"
}

if [ "$6" ]; then ip=$6; else ip=$(get_ip); fi

# 文件路径
log_file=~/aliyun_ddns_ali_${var_second_level_domain}.log
lock_file=/tmp/ali_ddns_${var_second_level_domain}.lock

# 终端可见 + 写日志
log() {
  local msg
  msg="[$(date '+%Y-%m-%d %H:%M:%S')] - $1"
  echo "$msg" | tee -a "$log_file"
}

# --- 增强：并发锁，防止进程堆积 ---
if [ -f "$lock_file" ]; then
    pid=$(cat "$lock_file")
    if ps -p "$pid" > /dev/null; then exit 1; fi
fi
echo $$ > "$lock_file"
trap 'rm -f "$lock_file"' EXIT

# --- 增强：日志轮转 (5MB) ---
if [[ -f $log_file ]]; then
  LOG_SIZE=$(stat -c%s "$log_file" 2>/dev/null || du -b "$log_file" | awk '{print $1}')
  if [ "${LOG_SIZE:-0}" -gt 5242880 ]; then
      log "日志文件过大，执行轮转..."
      mv "$log_file" "${log_file}.old"
  fi
fi

# 检查依赖
[[ ! -f "/usr/bin/openssl" ]] && apt-get install openssl -y
[[ ! -f "/usr/bin/uuidgen" ]] && apt-get install -y uuid-runtime

# --- 原版函数逻辑（不修改以免破坏签名） ---
function fun_parse_json(){
    echo "${1//\"/}" | grep "$2" |  sed "s/.*$2:\([^,}]*\).*/\1/"
}

function get_signature() {
    echo -ne "$2" | openssl dgst -$1 -hmac "$3" -binary | base64
}

function fun_get_uuid(){
    echo $(uuidgen | tr '[A-Z]' '[a-z]')
}

function fun_url_encode() {
    # 修复原版 read 处理最后一个字符的问题，加入拼接逻辑
    local out=""
    local input="$1"
    for (( i=0; i<${#input}; i++ )); do
        c=${input:$i:1}
        case ${c} in
            [a-zA-Z0-9._-]) out="$out$c" ;;
            *) out="$out$(printf '%%%02X' "'$c")" ;;
        esac
    done
    echo -n "${out}"
}

function fun_send_request() {
    local args="$2"
    # 这里保持原版的加密逻辑
    local message="$1&$(fun_url_encode "/")&$(fun_url_encode "$args")"
    local key="$var_access_key_secret&"
    local string_to_sign=$(get_signature "sha1" "$message" "$key")
    local signature=$(fun_url_encode "$string_to_sign")
    local request_url="$var_aliyun_ddns_api_host/?$args&Signature=$signature"

    # 增加超时处理：连接限制 5 秒，总限时 15 秒
    curl -s4 -m 15 --connect-timeout 5 "${request_url}"
}

function fun_query_record_id_send() {
    local query_url="AccessKeyId=$var_access_key_id&Action=DescribeSubDomainRecords&DomainName=$var_first_level_domain&Format=json&SignatureMethod=HMAC-SHA1&SignatureNonce=$(fun_get_uuid)&SignatureVersion=1.0&SubDomain=$var_second_level_domain.$var_first_level_domain&Timestamp=$var_now_timestamp&Version=2015-01-09"
    fun_send_request "GET" "${query_url}"
}

function fun_update_record_send() {
    local query_url="AccessKeyId=$var_access_key_id&Action=UpdateDomainRecord&Format=json&Line=$var_domain_line&RR=$var_second_level_domain&RecordId=$1&SignatureMethod=HMAC-SHA1&SignatureNonce=$(fun_get_uuid)&SignatureVersion=1.0&TTL=$var_domain_ttl&Timestamp=$var_now_timestamp&Type=$var_domain_record_type&Value=$ip&Version=2015-01-09"
    fun_send_request "GET" "${query_url}"
}

# --- 执行逻辑 ---
# 向云端查询当前记录
response_query=$(fun_query_record_id_send)
var_domain_record_id=$(echo "$response_query" | grep -Eo '"RecordId":"[0-9]+"' | cut -d':' -f2 | tr -d '"')
# 当前云端IP
var_current_ali_ip=$(echo "$response_query" | grep -Eo '"Value":"[0-9.]+"' | cut -d':' -f2 | tr -d '"' | head -n1)

if [[ "${var_domain_record_id}" = "" ]]; then
    log "获取record_id失败，请检查域名记录是否存在。响应: $response_query"
    exit 1
fi

# 对比云端 IP 与 当前 IP
if [ "$ip" == "$var_current_ali_ip" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] - IP has not changed (Cloud: $var_current_ali_ip). Skip update."
    exit 0
fi

# 只有不一致时才执行更新
response_update=$(fun_update_record_send ${var_domain_record_id})
code=$(fun_parse_json "$response_update" "Code")
message=$(fun_parse_json "$response_update" "Message")

if [[ "$code" = "" || "$code" == "null" ]]; then
    log "IP updated from $var_current_ali_ip to $ip"
    exit 0
else
    log "error code：$code error message：$message"
    exit 1
fi