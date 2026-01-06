#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
set -e

# 获取跟路径
HOME_DIR="${HOME:-/root}"

# 加锁，保证唯一执行
LOCK_FILE="/tmp/acme_install_cert.lock"
exec 200>"$LOCK_FILE"
flock -n 200 || { echo "❌ 脚本已经在运行中，退出"; exit 1; }
trap 'rm -f "$LOCK_FILE"' EXIT

# 从参数获取配置文件路径
CONF_FILE="$1"
if [ -z "$CONF_FILE" ] || [ ! -f "$CONF_FILE" ]; then
    echo "❌ 配置文件不存在: $CONF_FILE"
    exit 1
fi

# 读取配置文件
source "$CONF_FILE"

# 最后生成的本地脚本文件
RUNNER="$HOME_DIR/ag/conf/default/acme.sh"

: "${CERT_ITEMS:?CERT_ITEMS 未定义}"

ACME_INS="$HOME_DIR/.acme.sh/acme.sh"
log_file="$HOME_DIR/acme_install_cert.log"

# 生成并安装证书
gen_install_cert() {

  for item in "${CERT_ITEMS[@]}"; do
    # 公共的CF/ALI参数优先级较低，CERT_ITEMS里可以覆盖
    IFS='|' read -r domain provider key_file fullchain_file VALUE1 VALUE2 VALUE3 <<< "$item"

    log_set "👉 处理域名: $domain (dns=$provider)"
    echo "👉 处理域名: $domain (dns=$provider)"

    case "$provider" in
      cf)
        # 优先使用 CERT_ITEMS 里的值，否则使用全局
        TOKEN="${VALUE1:-$CF_Token}"
        ACCOUNT_ID="${VALUE2:-$CF_Account_ID}"
        ZONE_ID="${VALUE3:-$CF_Zone_ID}"

        if [ -z "$TOKEN" ] || [ -z "$ACCOUNT_ID" ] || [ -z "$ZONE_ID" ]; then
          log_set "⚠️ 跳过 $domain：CF 参数不完整"
          echo "⚠️ 跳过 $domain：CF 参数不完整"
          continue
        fi

        export CF_Token="$TOKEN" CF_Account_ID="$ACCOUNT_ID" CF_Zone_ID="$ZONE_ID"
        dns_type="dns_cf"
        ;;
      ali)
        # 公共的CF/ALI参数优先级较低，CERT_ITEMS里可以覆盖
        KEY="${VALUE1:-$Ali_Key}"
        SECRET="${VALUE2:-$Ali_Secret}"

        if [ -z "$KEY" ] || [ -z "$SECRET" ]; then
          log_set "⚠️ 跳过 $domain：Aliyun 参数不完整"
          echo "⚠️ 跳过 $domain：Aliyun 参数不完整"
          continue
        fi

        export Ali_Key="$KEY" Ali_Secret="$SECRET"
        dns_type="dns_ali"
        ;;
      *)
        log_set "❌ 未知 DNS provider: $provider"
        echo "❌ 未知 DNS provider: $provider"
        continue
        ;;
    esac

    if ! ${ACME_INS} --issue \
      --dns "$dns_type" \
      --keylength ec-256 \
      --force \
      -d "$domain"; then
      log_set "❌ 申请证书失败: $domain"
      echo "❌ 申请证书失败: $domain"
      continue
    fi

    ${ACME_INS} --install-cert --ecc \
      -d "$domain" \
      --key-file "$key_file" \
      --fullchain-file "$fullchain_file"

    log_set "✅ 证书安装成功: $domain"
    echo "✅ 证书安装成功: $domain"
  done

  [ -z "${POST_HOOK_COMMANDS+x}" ] && return
  [ ${#POST_HOOK_COMMANDS[@]} -eq 0 ] && return

  log_set "👉 执行证书后置命令"
  echo "👉 执行证书后置命令"

  for cmd in "${POST_HOOK_COMMANDS[@]}"; do
    log_set "➡️ $cmd"
    echo "➡️ $cmd"
    bash -c "$cmd"
    if [ $? -ne 0 ]; then
      log_set "⚠️ 后置命令执行失败: $cmd"
      echo "⚠️ 后置命令执行失败: $cmd"
    fi
  done
}

# LOGGER
log_set() {
    if [ ! -f $log_file ]; then
        touch $log_file
    fi

    if [ "$1" ]; then
        t1=`date "+%Y-%m-%d %H:%M:%S"`
        echo -e "[$t1] - $1" >> $log_file
    fi
}

# 设置 crontab 任务 ：每月1号和15号 执行脚本
set_cronjob() {
  _CRONTAB="crontab"

  [ -f "$RUNNER" ] || {
    log_set "❌ runner 不存在，跳过 cron 设置"
    echo "❌ runner 不存在，跳过 cron 设置"
    return 1
  }

  # 获取当前 crontab
  current_cron="$($_CRONTAB -l 2>/dev/null || true)"

  # 删除已有包含 $RUNNER 的行
  new_cron="$(echo "$current_cron" | grep -vF "$RUNNER")"

  # 添加最新的 cron
  new_cron="$new_cron
0 0 1,15 * * bash $RUNNER $CONF_FILE > /dev/null 2>&1"

  # 安装新的 crontab
  echo "$new_cron" | $_CRONTAB -

  log_set "✅ crontab 已更新"
  echo "✅ crontab 已更新"
}

# 生成本地可执行脚本
generate_acme() {
  cat > "$RUNNER" <<EOF
#!/usr/bin/env bash

# 接收配置文件路径参数
CONF_FILE="\$1"

if [ -z "\$CONF_FILE" ] || [ ! -f "\$CONF_FILE" ]; then
    echo "❌ 配置文件不存在: \$CONF_FILE"
    exit 1
fi

# 检测能否访问 GitHub
if curl -s --connect-timeout 3 https://raw.githubusercontent.com/renkx/s/main/acme/acme.sh -o /dev/null; then
    echo "执行【github】的脚本 ..."
    bash <(curl -sSL https://raw.githubusercontent.com/renkx/s/main/acme/acme.sh) "\$CONF_FILE"
else
    echo "执行【gitee】的脚本 ..."
    bash <(curl -sSL https://gitee.com/renkx/ss/raw/main/acme/acme.sh) "\$CONF_FILE"
fi
EOF

  chmod +x "$RUNNER"
  log_set "✅ 已生成 cron: $RUNNER"
  echo "✅ 已生成 cron: $RUNNER"
}

if [ ! -f $ACME_INS ]; then
  # 安装acme && 自动更新
  curl https://get.acme.sh | sh -s email=m@renkx.com && ${ACME_INS} --upgrade --auto-upgrade
fi

# 使用letsencrypt为默认服务 zerossl的网络有时候不通
# ${ACME_INS} --register-account -m m@renkx.com --server zerossl && ${ACME_INS} --set-default-ca --server zerossl
${ACME_INS} --set-default-ca --server letsencrypt

if [[ -f $log_file ]]; then
  LOG_SIZE=$(du -sh -b $log_file | awk '{print $1}')
  echo -e "日志文件大小 ${LOG_SIZE} byte"
  # 50M=50*1024*1024
  if [ ${LOG_SIZE} -gt 52428800 ]; then
      echo -e "日志文件过大，删除日志文件。。。。"
      rm $log_file
  fi
fi

generate_acme
set_cronjob
gen_install_cert