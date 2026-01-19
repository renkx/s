#!/bin/bash
# 设置环境变量，确保 crontab 运行时能找到命令
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# --- CHANGE THESE ---
# 阿里云更新域名Api Host 默认:https://alidns.aliyuncs.com
var_aliyun_ddns_api_host="https://alidns.aliyuncs.com"
# 阿里云授权Key
var_access_key_id="${1:-"你的AccessKeyID"}"
# 阿里云授权Key Secret
var_access_key_secret="${2:-"你的AccessKeySecret"}"
# 一级域名 例如:example.com
var_first_level_domain="${3:-"example.com"}"
# 二级域名 例如:testddns
var_second_level_domain="${4:-"www"}"

# 域名解析类型：A、NS、MX、TXT、CNAME、SRV、AAAA、CAA
var_domain_record_type="A"
# 域名线路,默认为默认
var_domain_line="default"
# 域名生效时间,默认:600 单位:秒
var_domain_ttl="${5:-600}"

# --- MAYBE CHANGE THESE ---
# 强化 IP 获取函数，应对国内网络卡顿
get_ip() {
    local ipv4=""
    ipv4=$(curl -s4 -m 4 --connect-timeout 2 http://ipv4.icanhazip.com 2>/dev/null | grep -Po '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$ipv4" ] && ipv4=$(curl -s4 -m 4 --connect-timeout 2 ip.sb 2>/dev/null | grep -Po '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$ipv4" ] && ipv4=$(curl -s4 -m 4 --connect-timeout 2 http://ident.me 2>/dev/null | grep -Po '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    echo "$ipv4"
}

if [ "$6" ]; then
    ip=$6
else
    ip=$(get_ip)
fi

# 文件路径设置
ip_file=~/aliyun_ddns_ip_${var_second_level_domain}.txt
log_file=~/aliyun_ddns_ali_${var_second_level_domain}.log
lock_file=/tmp/ali_ddns_${var_second_level_domain}.lock

# 终端可见 + 写日志
log() {
  local msg
  msg="[$(date '+%Y-%m-%d %H:%M:%S')] - $1"
  echo "$msg" | tee -a "$log_file"
}

# --- 优化点：防止重复运行 ---
if [ -f "$lock_file" ]; then
    pid=$(cat "$lock_file")
    if ps -p "$pid" > /dev/null; then exit 1; fi
fi
echo $$ > "$lock_file"
trap 'rm -f "$lock_file"' EXIT

# 日志轮转 (5MB)
if [[ -f $log_file ]]; then
  LOG_SIZE=$(stat -c%s "$log_file" 2>/dev/null || du -b "$log_file" | awk '{print $1}')
  if [ "${LOG_SIZE:-0}" -gt 5242880 ]; then
      mv "$log_file" "${log_file}.old"
  fi
fi

# 检查 IP 是否有效
if [ -z "$ip" ]; then
    log "错误: 无法获取公网 IP"
    exit 1
fi

# 检查 IP 是否发生变化
if [ -f "$ip_file" ]; then
    old_ip=$(cat "$ip_file")
    if [ "$ip" == "$old_ip" ]; then
        exit 0 # IP 未变，静默退出
    fi
fi

# 验证 IP 格式
if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    log "错误: 获取到的 IP [$ip] 格式不正确"
    exit 1
fi

# 检查依赖并尝试安装
check_deps() {
    if ! command -v openssl >/dev/null; then apt-get update && apt-get install openssl -y; fi
    if ! command -v uuidgen >/dev/null; then apt-get update && apt-get install -y uuid-runtime; fi
}
check_deps

# 依赖检查：是否有 jq
HAS_JQ=false
if command -v jq >/dev/null 2>&1; then HAS_JQ=true; fi

# url编码函数 (符合阿里云要求的 RFC3986 标准)
function fun_url_encode() {
    local string="${1}"
    # 如果字符串为空，直接输出空并返回
    if [ -z "$string" ]; then
        echo -n ""
        return
    fi
    # 使用安全的参数传递方式，并明确指定编码逻辑
    # 注意：这里改成了 "a=$string" 然后用 cut 删掉前面的 "a="，这是最兼容的写法
    curl -s -o /dev/null -w %{url_effective} --get --data-urlencode "a=$string" "" | sed 's/.*a=//'
}

# 当前时间戳 (阿里云要求 ISO8601 格式)
var_now_timestamp=$(date -u "+%Y-%m-%dT%H:%M:%SZ")
# 编码后的时间戳用于 URL
var_now_timestamp_enc=$(fun_url_encode "$var_now_timestamp")

# json转换函数 fun_parse_json "json" "key_name"
function fun_parse_json(){
    if $HAS_JQ; then
        echo "$1" | jq -r ".$2 // empty"
    else
        echo "${1//\"/}" | grep "$2" |  sed "s/.*$2:\([^,}]*\).*/\1/"
    fi
}

# hmac-sha1 签名
function get_signature() {
    echo -ne "$2" | openssl dgst -sha1 -hmac "$3" -binary | base64
}

# 生成uuid
function fun_get_uuid(){
    uuidgen | tr '[A-Z]' '[a-z]'
}

# 发送请求
function fun_send_request() {
    local method="$1"
    local args="$2"
    # 构造待签名字符串
    local canonicalized_query_string=$(echo -n "$args" | tr '&' '\n' | sort | tr '\n' '&' | sed 's/&$//')
    local string_to_sign="${method}&$(fun_url_encode "/")&$(fun_url_encode "$canonicalized_query_string")"

    # 计算签名
    local key="${var_access_key_secret}&"
    local signature=$(get_signature "sha1" "$string_to_sign" "$key")
    local signature_enc=$(fun_url_encode "$signature")

    # 最终请求地址 (增加超时控制)
    local request_url="${var_aliyun_ddns_api_host}/?${args}&Signature=${signature_enc}"
    curl -s4 -m 15 --connect-timeout 5 "${request_url}"
}

# 查询 RecordId
function fun_query_record_id_send() {
    local query_params="AccessKeyId=$var_access_key_id&Action=DescribeSubDomainRecords&DomainName=$var_first_level_domain&Format=json&SignatureMethod=HMAC-SHA1&SignatureNonce=$(fun_get_uuid)&SignatureVersion=1.0&SubDomain=$var_second_level_domain.$var_first_level_domain&Timestamp=$var_now_timestamp_enc&Version=2015-01-09"
    fun_send_request "GET" "${query_params}"
}

# 更新解析记录
function fun_update_record_send() {
    local record_id="$1"
    local update_params="AccessKeyId=$var_access_key_id&Action=UpdateDomainRecord&Format=json&Line=$var_domain_line&RR=$var_second_level_domain&RecordId=$record_id&SignatureMethod=HMAC-SHA1&SignatureNonce=$(fun_get_uuid)&SignatureVersion=1.0&TTL=$var_domain_ttl&Timestamp=$var_now_timestamp_enc&Type=$var_domain_record_type&Value=$ip&Version=2015-01-09"
    fun_send_request "GET" "${update_params}"
}

# --- 执行逻辑 ---

# 1. 获取 record_id
response_query=$(fun_query_record_id_send)
if $HAS_JQ; then
    var_domain_record_id=$(echo "$response_query" | jq -r '.DomainRecords.Record[0].RecordId // empty')
else
    var_domain_record_id=$(echo "$response_query" | grep -Eo '"RecordId":"[0-9]+"' | cut -d':' -f2 | tr -d '"' | head -1)
fi

if [ -z "${var_domain_record_id}" ]; then
    msg="获取record_id失败，检查域名 $var_second_level_domain.$var_first_level_domain 是否存在"
    log "$msg"
    exit 1
fi

# 2. 更新记录
response_update=$(fun_update_record_send "${var_domain_record_id}")

# 3. 结果解析
# 阿里云成功时通常不返回 Code 字段，直接返回解析后的结果 JSON
code=$(fun_parse_json "$response_update" "Code")
message=$(fun_parse_json "$response_update" "Message")

if [ -z "$code" ]; then
    echo "$ip" > "$ip_file"
    log "更新成功: $ip"
else
    if [[ "$code" == "DomainRecordDuplicate" ]]; then
        echo "$ip" > "$ip_file"
        log "记录未变化 (Duplicate): $ip"
    else
        log "API错误: $code - $message"
        exit 1
    fi
fi