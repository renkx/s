#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
set -e

# 获取绝对路径，确保 cron 执行时逻辑一致
HOME_DIR="${HOME:-/root}"
# 将 CONF_FILE 转为绝对路径
CONF_FILE=$(realpath "$1" 2>/dev/null || echo "$1")

# 加锁，保证唯一执行
LOCK_FILE="/tmp/acme_install_cert.lock"
exec 200>"$LOCK_FILE"
flock -n 200 || { echo "❌ 脚本已经在运行中，退出"; exit 1; }
trap 'rm -f "$LOCK_FILE"' EXIT

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

# 生成并安装证书
gen_install_cert() {
  local any_success=0

  for item in "${CERT_ITEMS[@]}"; do
    IFS='|' read -r domain provider key_file fullchain_file VALUE1 VALUE2 VALUE3 <<< "$item"

    log "👉 处理域名: $domain (dns=$provider)"

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

    # 为执行路径加双引号，防止潜在空格问题
    if ! "$ACME_INS" --issue \
      --dns "$dns_type" \
      --keylength ec-256 \
      --force \
      -d "$domain"; then
      log "❌ 申请证书失败: $domain"
      continue
    fi

    "$ACME_INS" --install-cert --ecc \
      -d "$domain" \
      --key-file "$key_file" \
      --fullchain-file "$fullchain_file"

    log "✅ 证书安装成功: $domain"
    any_success=1
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

  # 混合 [主机名 + 配置文件名] 生成唯一种子
  # 这样：不同机器会错开，同机器不同配置也会错开
  local seed=$(echo "$(hostname)$CONF_FILE" | cksum | cut -d' ' -f1)

  local rand_min=$(( seed % 60 ))
  # 比如限制在凌晨 0-5 点之间随机
  local rand_hour=$(( seed % 6 ))

  local cmd_part="bash $RUNNER $CONF_FILE"
  local cron_time="$rand_min $rand_hour 1,15 * *"
  local full_entry="$cron_time $cmd_part > /dev/null 2>&1"

  local current_cron
  current_cron="$(crontab -l 2>/dev/null || true)"

  # 2. 检查【全匹配】：如果时间、脚本、参数完全一致，不做任何操作
  if echo "$current_cron" | grep -qF "$full_entry"; then
    log "ℹ️ 任务 [$CONF_FILE] 已存在且配置一致，跳过"
    return 0
  fi

  local new_cron
  # 3. 检查【特征匹配】：匹配 "脚本 + 对应配置文件"
  # 这样即使有多个任务用同一个 $RUNNER 但不同 $CONF_FILE，也不会互相干扰
  if echo "$current_cron" | grep -qF "$cmd_part"; then
    # 匹配到了该脚本和对应的配置文件，但时间或其他部分不一致：原位更新
    new_cron=$(echo "$current_cron" | sed "s@.*$cmd_part.*@$full_entry@")
    log "🔄 任务 [$CONF_FILE] 配置有变，已原位更新时间"
  else
    # 该脚本+该配置文件的组合在 crontab 里完全不存在：追加
    new_cron="$(echo -e "$current_cron\n$full_entry")"
    log "✅ 任务 [$CONF_FILE] 不存在，已新增"
  fi

  # 4. 写入并清理空行
  echo "$new_cron" | sed '/^$/d' | crontab -
}

# 生成本地可执行脚本
# shellcheck disable=SC2120
generate_acme() {
  cat > "$RUNNER" <<'EOF'
#!/usr/bin/env bash
# 增加 set -u，如果变量没定义就报错，方便我们定位
set -u

# 接收配置文件路径参数
CONF_FILE="$1"
if [ -z "$CONF_FILE" ] || [ ! -f "$CONF_FILE" ]; then
    echo "❌ 配置文件不存在: $CONF_FILE"
    exit 1
fi

GITHUB_URL="https://raw.githubusercontent.com/renkx/s/main/acme/acme.sh"
GITEE_URL="https://gitee.com/renkx/ss/raw/main/acme/acme.sh"

test_speed() {
  local res
  # 确保即使 curl 失败也返回数字
  res=$(curl -sL --connect-timeout 3 --max-time 5 -w "%{time_total}" -o /dev/null "$1" 2>/dev/null || echo "999")
  [[ "$res" =~ ^[0-9.]+$ ]] && echo "$res" || echo "999"
}

echo "⏱ 正在检测 GitHub 网络质量 ..."
github_time=$(test_speed "$GITHUB_URL")

# 判定阈值（秒）
# 国内 GitHub 常见：2~5s
# 国外 / 代理：< 0.5s
THRESHOLD=1.5

if awk "BEGIN {exit !(${github_time} < ${THRESHOLD})}"; then
  echo "✅ GitHub 网络良好（${github_time}s < ${THRESHOLD}s），使用 GitHub"
  UPDATE_URL="$GITHUB_URL"
else
  echo "⚠️ GitHub 网络较慢（${github_time}s ≥ ${THRESHOLD}s），切换 Gitee"
  UPDATE_URL="$GITEE_URL"
fi

echo "🚀 执行更新脚本：$UPDATE_URL"

CURL_OPTS=(
  # 静默执行，不展示下载进度条
  --silent
  # 有错误提示
  --show-error
  # 自动跟随 HTTP 重定向（3xx）
  --location
  # 最多等待 3 秒建立 TCP 连接
  --connect-timeout 3
  # 整个 curl 命令最大执行时间 = 10 秒
  --max-time 10
  # 失败后自动重试 2 次
  --retry 2
  # 每次重试前等待 1 秒
  --retry-delay 1
)

# 处理成字符串
CURL_OPTS_STR="${CURL_OPTS[*]}"

if ! bash <(curl "${CURL_OPTS[@]}" "$UPDATE_URL") "$CONF_FILE"; then
  echo "❌ 脚本执行失败"
  echo "👉 执行命令:"
  # 日志展示也要加上参数，方便以后排查
  echo "bash <(curl $CURL_OPTS_STR $UPDATE_URL) $CONF_FILE"
  exit 1
fi
EOF

  chmod +x "$RUNNER"
  log "✅ 已生成 cron: $RUNNER"
}

if [ ! -f "$ACME_INS" ]; then
  log "🚀 开始安装 acme.sh ..."

  # 1. 检测网络环境
  check_net() {
      curl -sL --connect-timeout 3 --max-time 5 -w "%{time_total}" -o /dev/null "$1" || echo 999
  }

  GITHUB_URL="https://raw.githubusercontent.com/acmesh-official/acme.sh/master/acme.sh"
  github_time=$(check_net "$GITHUB_URL")

  if awk "BEGIN {exit !($github_time < 1.5)}"; then
      log "✅ GitHub 良好 (${github_time}s)，使用官方快捷安装"
      curl "$GITHUB_URL" | sh -s -- --install-online -m m@renkx.com
  else
      log "⚠️ GitHub 较慢 (${github_time}s)，采用官方推荐国内 Git 方案"

      # 2. 检查 git 是否安装
      if command -v git >/dev/null 2>&1; then
          rm -rf /tmp/acme_git_src
          if git clone --depth 1 https://gitee.com/neilpang/acme.sh.git /tmp/acme_git_src; then
              cd /tmp/acme_git_src
              ./acme.sh --install -m m@renkx.com
              cd - > /dev/null
              rm -rf /tmp/acme_git_src
          fi
      else
          log "⚠️ 未发现 git，退回到 Gitee Curl 方案"
          curl -sL https://gitee.com/neilpang/acme.sh/raw/master/acme.sh | sh -s -- --install-online -m m@renkx.com
      fi
  fi

  # 3. 最终校验
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