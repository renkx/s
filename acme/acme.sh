#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
set -e

# 获取绝对路径，确保 cron 执行时逻辑一致
HOME_DIR="${HOME:-/root}"
# 将 CONF_FILE 转为绝对路径
CONF_FILE=$(realpath "$1" 2>/dev/null || echo "$1")
# 判断是否是手动强制执行 (crontab 任务不会带这个参数)
FORCE_RENEW=0
[[ "$2" == "--force" ]] && FORCE_RENEW=1
# 证书默认阈值 30天
RENEW_BEFORE_DAYS=30

# 加锁，保证唯一执行
LOCK_FILE="/tmp/acme_install_cert.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "❌ 脚本已经在运行中，退出"
    exit 1
fi
# 退出时先关闭 fd 200（这会自动释放锁），再删掉临时锁文件
trap 'exec 200>&-; rm -f "$LOCK_FILE"' EXIT

# 参数校验
if [ -z "$CONF_FILE" ] || [ ! -f "$CONF_FILE" ]; then
    echo "❌ 配置文件不存在: $CONF_FILE"
    exit 1
fi

# 读取配置文件 (告诉 ShellCheck 忽略外部源缺失警告)
# shellcheck source=/dev/null
source "$CONF_FILE"

# 最终生成的本地脚本文件
RUNNER="$HOME_DIR/acme.sh"

# 变量存在性校验
: "${CERT_ITEMS:?CERT_ITEMS 未定义}"

ACME_INS="$HOME_DIR/.acme.sh/acme.sh"
LOG="/var/log/acme_install_cert.log"
LOGROTATE_CONF="/etc/logrotate.d/acme_install_cert"

# ===== 自动创建 logrotate 配置 =====
if [ ! -f "$LOGROTATE_CONF" ]; then
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
}
EOF
fi

# 终端可见 + 写日志 + 重定向 stdout
log() {
  local msg
  msg="$(date '+%F %T') $1"
  # -a 追加，-i 忽略中断信号（防止 Ctrl+C 时 log 写入不完整）
  echo "$msg" | tee -a -i "$LOG"
}

# 检测网络
check_network_env() {
  [ -n "${IsGlobal:-}" ] && return

  log "🔍 正在分析网络路由 ..."

  # 1. 核心判断：使用 Google 204 服务进行内容校验
  # -L: 跟踪重定向 (防止某些机房劫持到自己的登录页)
  # -w %{http_code}: 只输出 HTTP 状态码
  # --connect-timeout 2: 尝试建立连接的最长等待时间
  # -m 4: 整个请求（包括下载数据）的总限时
  local check_code
  check_code=$(curl -sL -k --connect-timeout 2 -m 4 -w "%{http_code}" "https://www.google.com/generate_204" -o /dev/null 2>/dev/null)

  if [ "$check_code" = "204" ]; then
    ENV_TIP="🌍 海外 (Global)"
    IsGlobal=1
  else
    # 2. 如果 Google 不通，尝试国内高可靠地址确认是否断网
    # 阿里或百度的 HTTPS 服务在国内是绝对稳定的
    local cn_code
    cn_code=$(curl -sL -k --connect-timeout 2 -m 3 -w "%{http_code}" "https://www.baidu.com" -o /dev/null 2>/dev/null)

    if [ "$cn_code" = "200" ]; then
      ENV_TIP="🇨🇳 国内 (Mainland China)"
      IsGlobal=0
    else
      ENV_TIP="🚫 网络连接异常"
      IsGlobal=0
    fi
  fi

  export IsGlobal
  log "📍 网络定位: $ENV_TIP"
}

# 检测证书过期时间
check_cert_expiry() {
  local cert_path="$1"
  # 默认阈值 30天
  local renew_limit="${2:-30}"

  # 1. 检查文件是否存在
  if [ ! -f "$cert_path" ]; then
    return 0 # 不存在则需要申请
  fi

  # 2. 获取证书到期日期字符串
  local raw_date
  raw_date=$(openssl x509 -in "$cert_path" -noout -enddate | cut -d= -f2)

  # 3. 转换为 Unix 时间戳 (核心优化点：使用 TZ=UTC 确保跨系统一致)
  local expire_timestamp
  expire_timestamp=$(TZ=UTC date -d "$raw_date" +%s 2>/dev/null)

  # 如果常规 date 解析失败，尝试针对旧版或不同格式进行手动处理
  if [ -z "$expire_timestamp" ]; then
    # 移除 GMT 字样再试一次
    local clean_date="${raw_date/ GMT/}"
    expire_timestamp=$(TZ=UTC date -d "$clean_date" +%s 2>/dev/null)
  fi

  # 4. 如果依然解析失败，安全起见返回 0 (申请新证书)
  if [ -z "$expire_timestamp" ]; then
    log "⚠️ 无法解析证书日期格式: $raw_date，将重新申请"
    return 0
  fi

  # 5. 获取当前时间戳并计算剩余天数
  local now_timestamp
  now_timestamp=$(date +%s)
  local remaining_days=$(( (expire_timestamp - now_timestamp) / 86400 ))

  if [ "$remaining_days" -le "$renew_limit" ]; then
    log "📅 证书剩余 $remaining_days 天，准备更新 (阈值: $renew_limit 天)"
    return 0 # 需要更新
  else
    log "✅ 证书剩余 $remaining_days 天，跳过更新"
    return 1 # 跳过
  fi
}

# 生成并安装证书
gen_install_cert() {
  local any_success=0
  # 从配置文件读取 RENEW_BEFORE_DAYS，若无则默认为 30
  local renew_limit="${RENEW_BEFORE_DAYS:-30}"

  for item in "${CERT_ITEMS[@]}"; do
    IFS='|' read -r domain provider key_file fullchain_file VALUE1 VALUE2 VALUE3 <<< "$item"

    log "👉 处理域名: $domain (dns=$provider)"

    local need_issue=0

    # 如果不是强制模式，且证书还在有效期内，则跳过
    if [ "$FORCE_RENEW" -eq 1 ]; then
        log "🚀 [手动模式] 强制申请开启"
        need_issue=1
    else
        # 自动模式/常规运行：检查有效期
        if check_cert_expiry "$fullchain_file" "$renew_limit"; then
            need_issue=1
        fi
    fi

    # 只有当需要更新时，才走申请和安装逻辑
    if [ "$need_issue" -eq 1 ]; then
        # --- 自动创建证书存放目录 ---
        # 使用 dirname 获取文件所在的父目录
        local key_dir=$(dirname "$key_file")
        local cert_dir=$(dirname "$fullchain_file")

        if [ ! -d "$key_dir" ]; then
            log "📁 创建 Key 存放目录: $key_dir"
            mkdir -p "$key_dir"
        fi

        if [ ! -d "$cert_dir" ]; then
            log "📁 创建证书存放目录: $cert_dir"
            mkdir -p "$cert_dir"
        fi

        case "$provider" in
          cf)
            local TOKEN="${VALUE1:-$CF_Token}"
            local ACCOUNT_ID="${VALUE2:-$CF_Account_ID}"
            local ZONE_ID="${VALUE3:-$CF_Zone_ID}"

            if [ -z "$TOKEN" ] || [ -z "$ACCOUNT_ID" ] || [ -z "$ZONE_ID" ]; then
              log "⚠️ 跳过 $domain：CF 参数不完整"
              continue
            fi
            export CF_Token="$TOKEN" CF_Account_ID="$ACCOUNT_ID" CF_Zone_ID="$ZONE_ID"
            dns_type="dns_cf"
            ;;
          ali)
            local KEY="${VALUE1:-$Ali_Key}"
            local SECRET="${VALUE2:-$Ali_Secret}"

            if [ -z "$KEY" ] || [ -z "$SECRET" ]; then
              log "⚠️ 跳过 $domain：Aliyun 参数不完整"
              continue
            fi
            export Ali_Key="$KEY" Ali_Secret="$SECRET"
            dns_type="dns_ali"
            ;;
          *)
            log "❌ 未知 DNS provider: $provider"
            continue
            ;;
        esac

        # 申请并安装
        if "$ACME_INS" --issue --dns "$dns_type" --keylength ec-256 --force -d "$domain"; then
            if "$ACME_INS" --install-cert --ecc -d "$domain" --key-file "$key_file" --fullchain-file "$fullchain_file"; then
                log "✅ 证书安装成功: $domain"
                any_success=1  # 只有这里真正成功了，才会把状态置为 1
            fi
        else
            log "❌ 申请证书失败: $domain"
        fi
    fi
  done

  # 后置命令执行逻辑
  if [ "$any_success" -eq 1 ] && [ "${#POST_HOOK_COMMANDS[@]}" -gt 0 ]; then
    log "👉 执行证书后置命令"
    for cmd in "${POST_HOOK_COMMANDS[@]}"; do
      log "➡️ $cmd"
      if ! bash -c "$cmd"; then
        log "⚠️ 后置命令执行失败: $cmd"
      fi
    done
  fi
}

# 设置 crontab 任务
set_cronjob() {
  [ -f "$RUNNER" ] || {
    log "❌ runner 不存在，跳过 cron 设置"
    return 1
  }

  # 结合主机名和路径生成固定随机时间 (0-59 min, 0-5 hour)
  # 这样：不同机器会错开，同机器不同配置也会错开
  local seed=$(echo "$(hostname)$CONF_FILE" | cksum | cut -d' ' -f1)
  local rand_min=$(( seed % 60 ))
  # 比如限制在凌晨 0-5 点之间随机
  local rand_hour=$(( seed % 6 ))

  local cmd_part="bash $RUNNER $CONF_FILE"
  local cron_time="$rand_min $rand_hour * * *"
  local full_entry="$cron_time $cmd_part > /dev/null 2>&1"

  # 获取当前 crontab，确保换行符正确
  local current_cron
  current_cron="$(crontab -l 2>/dev/null || true)"

  # 幂等检查：完全一致则跳过
  if echo "$current_cron" | grep -qF "$full_entry"; then
    log "ℹ️ 任务 [$CONF_FILE] 已在 $cron_time 运行，无需更新"
    return 0
  fi

  local new_cron
  if echo "$current_cron" | grep -qF "$cmd_part"; then
    # 使用 awk 进行精确匹配替换
    new_cron=$(export SEARCH="$cmd_part" REPLACE="$full_entry"; \
                   echo "$current_cron" | awk '{ if (index($0, ENVIRON["SEARCH"]) > 0) print ENVIRON["REPLACE"]; else print $0 }')
    log "🔄 任务 [$CONF_FILE] 配置已原位更新"
  else
    # 使用 printf 确保换行符干净，避免 echo 产生的兼容性问题
    new_cron=$(printf "%s\n%s" "$current_cron" "$full_entry")
    log "✅ 任务 [$CONF_FILE] 已新增至末尾"
  fi

  # 5. 回写并过滤空行
  echo "$new_cron" | grep -v '^$' | crontab -
}

# 生成本地可执行脚本
generate_acme() {
  cat > "$RUNNER" <<'EOF'
#!/usr/bin/env bash
# 增加 set -u，如果变量没定义就报错，方便我们定位
set -u

# 加上这行，确保 cron 自动执行时能认得 curl 等命令
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# 接收配置文件路径参数
CONF_FILE="$1"
if [ -z "$CONF_FILE" ] || [ ! -f "$CONF_FILE" ]; then
    echo "❌ 配置文件不存在: $CONF_FILE"
    exit 1
fi

# 检测网络
IsGlobal=0
check_network_env() {
  echo "🔍 正在分析网络路由 ..."

  # 1. 核心判断：使用 Google 204 服务进行内容校验
  # -L: 跟踪重定向 (防止某些机房劫持到自己的登录页)
  # -w %{http_code}: 只输出 HTTP 状态码
  # --connect-timeout 2: 尝试建立连接的最长等待时间
  # -m 4: 整个请求（包括下载数据）的总限时
  local check_code
  check_code=$(curl -sL -k --connect-timeout 2 -m 4 -w "%{http_code}" "https://www.google.com/generate_204" -o /dev/null 2>/dev/null)

  if [ "$check_code" = "204" ]; then
    ENV_TIP="🌍 海外 (Global)"
    IsGlobal=1
  else
    # 2. 如果 Google 不通，尝试国内高可靠地址确认是否断网
    # 阿里或百度的 HTTPS 服务在国内是绝对稳定的
    local cn_code
    cn_code=$(curl -sL -k --connect-timeout 2 -m 3 -w "%{http_code}" "https://www.baidu.com" -o /dev/null 2>/dev/null)

    if [ "$cn_code" = "200" ]; then
      ENV_TIP="🇨🇳 国内 (Mainland China)"
      IsGlobal=0
    else
      ENV_TIP="🚫 网络连接异常"
      IsGlobal=0
    fi
  fi

  echo "📍 网络定位: $ENV_TIP"
}

check_network_env

# 统一 Curl 下载参数
# --connect-timeout 6: 连接超时
# --max-time 30: 增加到 30 秒，确保脚本下载完整
CURL_OPTS=(
  --silent
  --show-error
  --location
  --connect-timeout 6
  --max-time 30
  --retry 2
  --retry-delay 1
)

GITHUB_URL="https://raw.githubusercontent.com/renkx/s/main/acme/acme.sh"
GITEE_URL="https://gitee.com/renkx/ss/raw/main/acme/acme.sh"

if [[ "$IsGlobal" == "1" ]]; then
  echo "🌍 检测到海外环境，优先使用 GitHub 源：$GITHUB_URL"
  # 尝试读取 GitHub，如果失败则自动切换到 Gitee
  if curl "${CURL_OPTS[@]}" "$GITHUB_URL" > /tmp/dynamic_acme.sh 2>/tmp/acme_curl_err.log; then
    echo "🚀 GitHub 源下载成功"
  else
    echo "⚠️ GitHub 连接超时或失败，错误日志如下："
    cat /tmp/acme_curl_err.log
    rm -f /tmp/acme_curl_err.log
    echo "🔄 正在尝试切换到 Gitee 备用源：$GITEE_URL"
    if ! curl "${CURL_OPTS[@]}" "$GITEE_URL" > /tmp/dynamic_acme.sh; then
      echo "❌ 所有更新源均不可用，执行失败"
      exit 1
    fi
  fi
else
  echo "🇨🇳 检测到国内环境，使用 Gitee 源：$GITEE_URL"
  if ! curl "${CURL_OPTS[@]}" "$GITEE_URL" > /tmp/dynamic_acme.sh; then
    echo "❌ Gitee 源下载失败"
    exit 1
  fi
fi

# 直接执行下载好的临时脚本
if ! bash /tmp/dynamic_acme.sh "$@"; then
  echo "❌ 更新脚本执行失败"
  rm -f /tmp/dynamic_acme.sh
  exit 1
fi
rm -f /tmp/dynamic_acme.sh
rm -f /tmp/acme_curl_err.log

EOF

  chmod +x "$RUNNER"
  log "✅ 已生成 cron 脚本: $RUNNER"
}

if [ ! -f "$ACME_INS" ]; then
  log "🚀 开始安装 acme.sh ..."

  check_network_env

  CURL_INSTALL_OPTS=(--silent --show-error --location --connect-timeout 6 --max-time 30 --retry 2)

  if [[ "$IsGlobal" == "1" ]]; then
      log "✅ 尝试从 GitHub 下载官方安装脚本..."
      if curl "${CURL_INSTALL_OPTS[@]}" "https://raw.githubusercontent.com/acmesh-official/acme.sh/master/acme.sh" > /tmp/acme_installer.sh; then
          sh /tmp/acme_installer.sh --install-online -m m@renkx.com
          rm -f /tmp/acme_installer.sh
      else
          log "⚠️ GitHub 下载官方脚本超时，自动降级为国内方案..."
          IsGlobal=0
      fi
  fi

  if [[ "$IsGlobal" == "0" ]]; then
      if command -v git >/dev/null 2>&1; then
          log "⚠️ 采用官方推荐国内 Git 方案"
          rm -rf /tmp/acme_git_src
          if git clone --depth 1 https://gitee.com/neilpang/acme.sh.git /tmp/acme_git_src; then
              cd /tmp/acme_git_src
              ./acme.sh --install -m m@renkx.com
              cd - > /dev/null
              rm -rf /tmp/acme_git_src
          fi
      else
          log "⚠️ 未发现 git，采用 Gitee Curl 落地文件方案"
          if curl "${CURL_INSTALL_OPTS[@]}" "https://gitee.com/neilpang/acme.sh/raw/master/acme.sh" > /tmp/acme_installer.sh; then
              sh /tmp/acme_installer.sh --install-online -m m@renkx.com
              rm -f /tmp/acme_installer.sh
          else
              log "❌ 从 Gitee 下载官方脚本也失败了"
          fi
      fi
  fi

  # 最终校验
  if [ -f "$ACME_INS" ]; then
      log "✅ acme.sh 安装成功"
      "$ACME_INS" --set-default-ca --server letsencrypt
  else
      log "❌ acme.sh 安装失败，请检查网络环境"
      exit 1
  fi
fi

# 使用letsencrypt为默认服务 zerossl的网络有时候不通
# ${ACME_INS} --register-account -m m@renkx.com --server zerossl && ${ACME_INS} --set-default-ca --server zerossl
"$ACME_INS" --set-default-ca --server letsencrypt

generate_acme
set_cronjob
gen_install_cert