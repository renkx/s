#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

cd "$(
    cd "$(dirname "$0")" || exit
    pwd
)" || exit

# 脚本工作目录（存放 IP 记录文件的目录）
STATE_DIR="/root/nginx_reload"
# 日志文件路径
LOG="/var/log/nginx_reload_log_domain.log"
# logrotate 配置文件路径
LOGROTATE_CONF="/etc/logrotate.d/nginx_reload_log_domain"

# ===== 自动创建 logrotate 配置（只在不存在且有权限时） =====
if [ ! -f "$LOGROTATE_CONF" ] && [ -w "/etc/logrotate.d/" ]; then
  cat > "$LOGROTATE_CONF" <<EOF
$LOG {
    # 超过 10MB 才轮转
    size 10M
    # 最多保留 3 个旧日志
    rotate 3
    # gzip 压缩
    compress
    # 本次轮转先不压缩，等下一次再压缩
    delaycompress
    # 文件不存在不报错
    missingok
    # 空文件不轮转
    notifempty
    # 不影响正在写日志的脚本
    copytruncate
    create 0644 root root
}
EOF
fi

# 终端可见 + 写日志 + 重定向 stdout
log() {
  local msg
  msg="$(date '+%F %T') $1"
  echo "$msg" | tee -a "$LOG"
}

# 适配 Alpine/BusyBox 容器的获取函数
nslookup_ip() {
    # 提取所有 Address 行的最后一个字段，并跳过第一行的本地 DNS Server
    local ip_list=$(docker exec nginx nslookup "$1" 2>/dev/null | grep "Address" | sed '1d' | awk '{print $NF}' | sort -u | tr '\n' ',' | sed 's/,$//')
    echo "$ip_list"
}

# nginx重载
nginx_reload() {
    max_retries=5
    retry_count=0
    while [ $retry_count -lt $max_retries ]; do
        # 加上超时控制，防止 docker exec 卡死整个脚本
        output=$(timeout 10s docker exec nginx nginx -s reload 2>&1)
        if [ $? -eq 0 ]; then
            log "Success: docker exec nginx nginx -s reload."
            # 关键：reload 成功后强制等待，给系统时间回收旧的连接
            sleep 10
            break
        else
            log "Attempt $((retry_count + 1)) Fail: $output"
            ((retry_count++))
            sleep 2
        fi
    done
}

domain_check() {
    # 自动创建状态目录
    if [ ! -d "$STATE_DIR" ]; then
        mkdir -p "$STATE_DIR"
        log "创建状态存储目录: $STATE_DIR"
    fi

    # 每次检查时重新提取域名，实现“配置热同步”
    local domains=()
    mapfile -t domains < <(docker exec nginx grep -rhE '^\s*server\s+[a-zA-Z0-9.-]+\.[a-z]{2,}' /etc/nginx/conf.d/ | \
        grep -v "#" | \
        sed -E 's/^\s*server\s+([^:; ]+).*/\1/' | \
        grep -vE '127.0.0.1|localhost|0.0.0.0' | sort -u)

    if [ ${#domains[@]} -eq 0 ]; then
        log "未发现有效域名，跳过本次检查。"
        return
    fi

    should_reload=false
    for domain in "${domains[@]}"; do
        ip_file="${STATE_DIR}/nginx_reload_ip_${domain}.txt"
        new_ip=$(nslookup_ip "$domain")
        # 减缓对 Docker 守护进程的瞬时压力
        sleep 0.1

        # 如果解析不到 IP，跳过该域名，防止误删旧 IP 导致 reload 失败
        [ -z "$new_ip" ] && { log "$domain 解析失败，跳过"; continue; }

        if [ -f "$ip_file" ]; then
            old_ip=$(cat "$ip_file")
            if [ "$new_ip" != "$old_ip" ]; then
                should_reload=true
                echo "$new_ip" > "$ip_file"
                log "$domain IP 变动: $old_ip -> $new_ip"
            fi
        else
            should_reload=true
            echo "$new_ip" > "$ip_file"
            log "$domain 初始解析 IP: $new_ip"
        fi
    done

    [ "$should_reload" = true ] && nginx_reload
}

domain_check