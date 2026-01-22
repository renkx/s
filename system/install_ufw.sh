#!/bin/bash

# --- 工具函数 ---
# 蓝色表示进度，绿色表示成功，黄色表示警告
echo_info() { echo -e "\033[34m[INFO]\033[0m $1"; }
echo_ok() { echo -e "\033[32m[OK]\033[0m $1"; }
echo_warn() { echo -e "\033[33m[WARN]\033[0m $1"; }
# 判断上一步命令是否执行成功
judge() { if [ $? -eq 0 ]; then echo_ok "$1 成功"; else echo "[ERROR] $1 失败"; exit 1; fi }

# --- 全局变量获取 ---
# 获取当前 SSH 服务监听的端口，若获取不到则默认为 22 (实时从内核获取)
get_current_ssh_port() {
  local port=$(ss -tlnp | grep sshd | awk '{print $4}' | grep -oE '[0-9]+$' | head -n1)
  echo "${port:-22}"
}

# --- 核心同步与维护逻辑 ---
sync_all() {
  echo -e "\n\033[1m>>> 正在启动自动化安全配置同步 <<<\033[0m\n"

  # 确保 logrotate 每小时检查一次，防止突发流量撑爆磁盘
  if [ -f /etc/cron.daily/logrotate ]; then
      mv -f /etc/cron.daily/logrotate /etc/cron.hourly/ || true
      echo_ok "已将 Logrotate 检查频率提升至每小时"
  fi

  # --- 环境清理 (幂等性保障) ---
  # [原有注释] 幂等处理：如果检测到旧的 iptables-persistent，则彻底卸载清理，避免干扰 UFW
  # [理解] 必须清理 netfilter-persistent，否则重启后旧规则可能覆盖 UFW 规则
  if dpkg -l | grep -q "iptables-persistent"; then
    echo_info "检测到旧的防火墙工具，正在卸载并迁移至 UFW..."
    export DEBIAN_FRONTEND=noninteractive
    apt purge iptables-persistent netfilter-persistent -y >/dev/null 2>&1
    rm -rf /etc/iptables/rules.v4
  fi

  # --- 核心组件安装 ---
  # [原有注释] 安装 UFW、Fail2ban 和 ipset 工具（ipset 是实现高性能封禁的关键）
  # [理解] 自动检测安装缺失组件 (装过了就不再重复安装)
  local deps=(ufw fail2ban ipset)
  local missing=()
  for pkg in "${deps[@]}"; do
    if ! dpkg -l | grep -q "ii  $pkg "; then missing+=("$pkg"); fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    echo_info "正在安装缺失组件: ${missing[*]}..."
    apt update >/dev/null 2>&1 && apt install -y "${missing[@]}" >/dev/null 2>&1
    judge "核心组件安装"
  fi

  # --- Fail2ban 全局配置 ---
  # [原有注释] A. 写入全局默认配置 (00-default.local) 这里定义了全局默认动作、日志获取方式以及 IPv6 支持
  # [理解] allowipv6=auto 配合全局 banaction，确保所有同步开启的端口都受 ipset 高性能保护
  cat <<EOF >/etc/fail2ban/jail.d/00-default.local
[Definition]
# 开启对 IPv6 地址的自动检测和封禁支持
allowipv6 = auto

[DEFAULT]
# auto 会按顺序尝试 pyinotify 和 polling 来处理日志文件
# pyinotify 更好，是一个 Python 库，需要安装
backend = auto
# 全局默认动作：使用 ipset 进行精准端口拦截 (不限端口则使用 iptables-ipset-proto6-allports)
banaction = iptables-ipset-proto6
# 白名单 IP，避免封禁本地或局域网段
ignoreip = 127.0.0.1/8 ::1 192.168.0.0/16 10.0.0.0/8 172.16.0.0/12
EOF

  # 写入累犯封禁配置 (01-recidive.local)
  # [理解] 这是一个全局通用的监狱，独立于特定服务。它监控 fail2ban.log。
  # 只要任何 Jail (sshd, nginx等) 封禁了某个 IP，它就会记录并累计。
  cat <<EOF >/etc/fail2ban/jail.d/01-recidive.local
[recidive]
enabled = true
logpath  = /var/log/fail2ban.log
filter   = recidive
# 既然是惯犯，直接封锁所有端口，不给任何试探机会，所以用的 allports
banaction = iptables-ipset-proto6-allports
# 默认只有tcp，这块需要封禁全协议
protocol = all
# 封禁时长：365天
bantime  = 365d
# 检测窗口：7天内达到 maxretry 次则执行封禁
findtime  = 7d
maxretry = 2
EOF

  # 只有当日志文件不存在时才初始化，避免干扰已有的日志流
  if [ ! -f /var/log/fail2ban.log ]; then
      echo_info "初始化 Fail2ban 日志文件..."
      touch /var/log/fail2ban.log
      chmod 640 /var/log/fail2ban.log
      # 确保属组正确（在 Debian/Ubuntu 下通常是 adm 组有权查看日志）
      chown root:adm /var/log/fail2ban.log 2>/dev/null
  fi

  # --- 4. 系统环境修复 ---
  # [原有注释] C. 幂等修复 Hostname 解析，防止 Fail2ban 启动时报 "无法解析主机" 的错误
  hn=$(hostname)
  if ! grep -q "127.0.0.1.*$hn" /etc/hosts; then
      echo "127.0.0.1    $hn" >> /etc/hosts
  fi

  # [理解] SSH 监控联动 (直接执行覆盖，确保配置实时更新)
  local current_port=$(get_current_ssh_port)
  echo_info "正在同步 SSH fail2ban 配置 (端口: $current_port)..."
  # 写入 SSH 特定封禁配置 (sshd.local) 特定 Jail 的配置会覆盖 [DEFAULT] 中的同名参数
  cat <<EOF >/etc/fail2ban/jail.d/sshd.local
[sshd]
enabled = true
port = $current_port
# 设定日志抓取后端为 systemd，去读取系统的 journald，sshd需要这个
backend = systemd
# 封禁时长：1小时
bantime  = 1h
# 检测窗口：30分钟内达到 maxretry 次则执行封禁
findtime  = 30m
# 允许失败的最大次数
maxretry = 2
EOF

  # --- Nginx 环境预热与存量对齐 ---
  local host_nginx_dir="/var/log/nginx"
  local host_nginx_error_log="$host_nginx_dir/error_docker.log"
  local host_nginx_access_log="$host_nginx_dir/access_docker.log"
  echo_info "同步 Nginx 日志环境 (处理存量与预热)..."

  [ ! -d "$host_nginx_dir" ] && mkdir -p "$host_nginx_dir"
  chmod 755 "$host_nginx_dir"
  [ ! -f "$host_nginx_error_log" ] && touch "$host_nginx_error_log"
  chmod 666 "$host_nginx_error_log"
  [ ! -f "$host_nginx_access_log" ] && touch "$host_nginx_access_log"
  chmod 666 "$host_nginx_access_log"

  echo_info "写入 Nginx 异常拦截规则..."
  cat <<EOF > /etc/fail2ban/filter.d/nginx-custom-upstream-connect.conf
[INCLUDES]
# 基于官方模板的过滤器
before = nginx-error-common.conf

[Definition]
# 删掉多余空格和末尾引号，实现全路径、全协议通杀
failregex = ^%(__prefix_line)sconnect\(\) failed.*client: <HOST>.*127\.0\.0\.1:9
EOF

  # 写入 Nginx Jail 配置
  cat <<EOF >/etc/fail2ban/jail.d/nginx-upstream-connect.local
[nginx_upstream_connect]
enabled = true
port = http,https
filter = nginx-custom-upstream-connect
logpath = $host_nginx_error_log
backend = auto
bantime  = 24h
findtime = 1h
maxretry = 2
EOF

  # 如果宿主机没有 Nginx 的轮转配置，则创建一个通用的
  if [ ! -f /etc/logrotate.d/nginx-docker ]; then
    cat <<EOF >/etc/logrotate.d/nginx-docker
$host_nginx_dir/*.log {
    # 每天生成轮转
    daily
    # 如果日志超过 20M，提前轮转防止撑爆磁盘
    size 20M
    rotate 5
    missingok
    compress
    # 延迟压缩，确保 fail2ban 处理完最后的记录
    delaycompress
    notifempty
    # 权限对齐
    # 666 确保容器内 nginx 用户和宿主机 fail2ban 都能读写新创建的文件
    create 666 root root
    sharedscripts
    postrotate
        # 容器内日志重开
        docker exec nginx nginx -s reopen 2>/dev/null || true
        # 宿主机 Fail2Ban 文件句柄刷新
        fail2ban-client flushlogs 1>/dev/null || true
    endscript
}
EOF
  fi

      systemctl restart fail2ban >/dev/null 2>&1
      echo_ok "Fail2ban 监控规则已同步更新"

  # ---  UFW 状态重置 ---
  # [原有注释] 设定 UFW 默认规则：拒绝所有进站流量，允许所有出站流量
  # [理解] reset 会清空所有规则并关闭 UFW 状态，确保每次同步都是“一张白纸”，防止规则堆积
  echo_info "正在重置 UFW 规则库并应用默认策略..."
  ufw --force reset > /dev/null
  ufw --force default deny incoming > /dev/null
  ufw --force default allow outgoing > /dev/null

  # --- SSH 端口放行 ---
  # [原有注释] 开启必要端口：SSH
  ufw allow "$current_port/tcp" comment 'SSH (Auto-sync)' > /dev/null

  # --- 动态扫描并同步公网端口 ---
  # [理解] 核心优化：利用 ss 扫描，并通过 sort -u 去重，解决 Nginx 多进程导致的重复输出问题
  echo_info "开始扫描系统活跃端口并同步 UFW..."

  # [优化] 更加稳健的扫描逻辑
  # 1. awk 提取协议和本地地址列
  # 2. 排除所有包含 127.0.0.1 或 ::1 的行
  # 3. 使用 grep -oE '[0-9]+$' 仅提取行尾的端口数字
  # 4. 最后 sort -u 彻底去重
  port_list=$(ss -tunlp | grep -E 'LISTEN|UNCONN' | grep -vE '127\.0\.0\.1|::1' | awk '{print $1, $5}' | while read -r proto addr; do
    port=$(echo "$addr" | grep -oE '[0-9]+$')
    echo "$port $proto"
  done | sort -u)

  while read -r port proto; do
    [ -z "$port" ] && continue

    # 跳过已显式处理的 SSH 端口
    if [ "$port" == "$current_port" ] && [ "$proto" == "tcp" ]; then continue; fi

    # [原有注释] 不指定 /tcp，同时开启 443/tcp 和 443/udp
    # [理解] 这里根据真实协议动态放行，完美支持 HTTP/3 (UDP 443)
    echo -e "  \033[34m+ 发现活跃服务:\033[0m \033[1m$port\033[0m ($proto)"
    ufw allow "$port/$proto" comment "Auto-sync $proto" > /dev/null
  done <<< "$port_list"

  # --- 激活防火墙 ---
  # [原有注释] 激活 UFW 并强制应用
  # [理解] reset 之后必须重新 enable 才能使内核开始拦截并实现开机自启
  echo "y" | ufw enable > /dev/null

  # 展示最终报告
  echo -e "\n\033[1m--- 当前 UFW 生效规则清单 ---\033[0m"
  ufw status | sed 's/^/  /'
  echo -e "\033[1m-----------------------------\033[0m\n"

  echo_ok "所有加固与端口同步操作已完成！"
}

# --- 执行入口 ---
case "$1" in
  *)
    sync_all
    ;;
esac