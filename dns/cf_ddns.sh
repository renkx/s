#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# CHANGE THESE
auth_key=$1 # https://dash.cloudflare.com/profile/api-tokens
zone_name=$2
record_name=$3
# auth_key="c2547eb745079dac9320b638f5e225cf483" # https://dash.cloudflare.com/profile/api-tokens 创建令牌
# zone_name="example.com" # 顶级域名
# record_name="www.example.com" # 要改dns的域名

# MAYBE CHANGE THESE
if [ "$4" ]; then
ip=$4
else
ip=$(curl -s http://ipv4.icanhazip.com)
fi

ip_file=~/cf_ddns_ip_${record_name}.txt
id_file=~/cf_ddns_cloudflare_${record_name}.ids
log_file=~/cf_ddns_cloudflare_${record_name}.log

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

# 删除ID文件
rm_id_file() {
    # 删除ID文件
    if [ -f $id_file ]; then
        rm $id_file
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

if [ -f $id_file ] && [ $(wc -l $id_file | cut -d " " -f 1) == 2 ]; then
    zone_identifier=$(head -1 $id_file)
    record_identifier=$(tail -1 $id_file)
fi

if [ ! "$zone_identifier" ] || [ ! "$record_identifier" ];then
    zone_identifier=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$zone_name" -H "Authorization: Bearer $auth_key" -H "Content-Type: application/json" | grep -Po '(?<="id":")[^"]*' | head -1 )
    record_identifier=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?name=$record_name" -H "Authorization: Bearer $auth_key" -H "Content-Type: application/json"  | grep -Po '(?<="id":")[^"]*')

    if [ "$zone_identifier" ] && [ "$record_identifier" ];then
        echo "$zone_identifier" > $id_file
        echo "$record_identifier" >> $id_file
    else
        # 删除ID文件
        rm_id_file
        echo_set "ID acquisition exception."
        log "ID acquisition exception."
        exit 1
    fi
fi

update=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" -H "Authorization: Bearer $auth_key" -H "Content-Type: application/json" --data "{\"id\":\"$zone_identifier\",\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$ip\"}")

if [[ $update == *"\"success\":false"* ]]; then
    rm_id_file
    message="API UPDATE FAILED. DUMPING RESULTS:\n$update"
    log "$message"
    echo_set "$message"
    exit 1 
else
    message="IP changed to: $ip"
    echo "$ip" > $ip_file
    log "$message"
    echo_set "$message"
fi