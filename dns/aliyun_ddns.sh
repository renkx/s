#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

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
if [ "$5" ]; then
var_domain_ttl=$5
else
var_domain_ttl=600
fi
# 当前时间戳
var_now_timestamp=`date -u "+%Y-%m-%dT%H%%3A%M%%3A%SZ"`
#域名解析记录Id
var_domain_record_id=""

# MAYBE CHANGE THESE
if [ "$6" ]; then
ip=$6
else
ip=$(curl -s http://ipv4.icanhazip.com)
fi

ip_file=~/aliyun_ddns_ip_${var_second_level_domain}.txt
log_file=~/aliyun_ddns_ali_${var_second_level_domain}.log

echo_set() {
  if [ "$1" ]; then
      echo -e "[`date '+%Y-%m-%d %H:%M:%S'`] - $1"
  fi
}

# LOGGER
log() {
    if [ "$1" ]; then
        echo -e "[`date '+%Y-%m-%d %H:%M:%S'`] - $1" >> $log_file
    fi
}

if [[ -f $log_file ]]; then
  LOG_SIZE=$(du -sh -b $log_file | awk '{print $1}')
  echo_set "日志文件大小 ${LOG_SIZE} byte"
  # 50M=50*1024*1024
  if [ ${LOG_SIZE} -gt 52428800 ]; then
      echo_set "日志文件过大，删除日志文件。。。。"
      rm $log_file
  fi
fi

if [ -f $ip_file ]; then
    old_ip=$(cat $ip_file)
    if [ "$old_ip" ] && [ $ip == $old_ip ]; then
        echo_set "IP has not changed."
        exit 1
    fi
fi

if [[ ! -f "/usr/bin/openssl" ]]; then
    apt-get install openssl -y
fi

if [[ ! -f "/usr/bin/uuidgen" ]]; then
    apt-get install -y uuid-runtime
fi

# json转换函数 fun_parse_json "json" "key_name"
function fun_parse_json(){
    echo "${1//\"/}" | grep "$2" |  sed "s/.*$2:\([^,}]*\).*/\1/"
}

#hmac-sha1 签名 usage: get_signature "签名算法" "加密串" "key"
function get_signature() {
    echo -ne "$2" | openssl dgst -$1 -hmac "$3" -binary | base64
}

# 生成uuid
function fun_get_uuid(){
    echo $(uuidgen | tr '[A-Z]' '[a-z]')
}

# url编码
function fun_url_encode() {
    out=""
    while read -n1 c
    do
        case ${c} in
            [a-zA-Z0-9._-]) out="$out$c" ;;
            *) out="$out`printf '%%%02X' "'$c"`" ;;
        esac
    done
    echo -n ${out}
}

# url加密函数
function fun_get_url_encryption() {
    echo -n "$1" | fun_url_encode
}

# 获取域名解析记录Id正则
function fun_get_record_id_regx() {
    grep -Eo '"RecordId":"[0-9]+"' | cut -d':' -f2 | tr -d '"'
}

# 发送请求 eg:fun_send_request "GET" "Action" "动态请求参数（看说明）" "控制是否打印请求响应信息：true false"
function fun_send_request() {
    local args="$3"
    local message="$1&$(fun_get_url_encryption "/")&$(fun_get_url_encryption "$args")"
    local key="$var_access_key_secret&"
    local string_to_sign=$(get_signature "sha1" "$message" "$key")
    local signature=$(fun_get_url_encryption "$string_to_sign")
    local request_url="$var_aliyun_ddns_api_host/?$args&Signature=$signature"
    local response=$(curl -s ${request_url})

    echo $response
}

# 查询域名解析记录值请求
function fun_query_record_id_send() {
    local query_url="AccessKeyId=$var_access_key_id&Action=DescribeSubDomainRecords&DomainName=$var_first_level_domain&Format=json&SignatureMethod=HMAC-SHA1&SignatureNonce=$(fun_get_uuid)&SignatureVersion=1.0&SubDomain=$var_second_level_domain.$var_first_level_domain&Timestamp=$var_now_timestamp&Version=2015-01-09"
    fun_send_request "GET" "DescribeSubDomainRecords" ${query_url}
}

# 更新域名解析记录值请求 fun_update_record "record_id"
function fun_update_record_send() {
    # 更新域名
    local query_url="AccessKeyId=$var_access_key_id&Action=UpdateDomainRecord&Format=json&Line=$var_domain_line&RR=$var_second_level_domain&RecordId=$1&SignatureMethod=HMAC-SHA1&SignatureNonce=$(fun_get_uuid)&SignatureVersion=1.0&TTL=$var_domain_ttl&Timestamp=$var_now_timestamp&Type=$var_domain_record_type&Value=$ip&Version=2015-01-09"

    fun_send_request "GET" "UpdateDomainRecord" ${query_url}
}

# 获取record_id
var_domain_record_id=`fun_query_record_id_send | fun_get_record_id_regx`

if [[ "${var_domain_record_id}" = "" ]]; then
    log_message="获取record_id为空,可能没有获取到有效的解析记录"
    log "$log_message"
    echo_set "$log_message"
    exit 1
fi

# 更新record_id的域名记录
response=`fun_update_record_send ${var_domain_record_id}`

code=$(fun_parse_json "$response" "Code")
message=$(fun_parse_json "$response" "Message")

if [[ "$code" = "" ]]; then
    log_message="IP changed to: $ip"
    echo "$ip" > $ip_file
    log "$log_message"
    echo_set "$log_message"
    exit 0
 else
    if [[ "$code" = "DomainRecordDuplicate" ]]; then
      log_message="domain record duplicate: $ip"
      echo "$ip" > $ip_file
      log "$log_message"
      echo_set "$log_message"
      exit 0
    else
      log_message="error code：$code error message：$message"
      log "$log_message"
      echo_set "$log_message"
      exit 1
    fi
fi