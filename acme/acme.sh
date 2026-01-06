#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
set -e

# 获取跟路径
HOME_DIR="${HOME:-/root}"

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
    IFS='|' read -r domain provider key_file fullchain_file <<< "$item"

    log_set "👉 处理域名: $domain (dns=$provider)"
    echo "👉 处理域名: $domain (dns=$provider)"

    case "$provider" in
      cf)
        if [ -z "$CF_Token" ] || [ -z "$CF_Account_ID" ] || [ -z "$CF_Zone_ID" ]; then
          log_set "⚠️ 跳过 $domain：CF 参数不完整"
          echo "⚠️ 跳过 $domain：CF 参数不完整"
          continue
        fi
        export CF_Token CF_Account_ID CF_Zone_ID
        dns_type="dns_cf"
        ;;
      ali)
        if [ -z "$Ali_Key" ] || [ -z "$Ali_Secret" ]; then
          log_set "⚠️ 跳过 $domain：Aliyun 参数不完整"
          echo "⚠️ 跳过 $domain：Aliyun 参数不完整"
          continue
        fi
        export Ali_Key Ali_Secret
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

  if ! $_CRONTAB -l 2>/dev/null | grep -F "$RUNNER" >/dev/null; then
    $_CRONTAB -l 2>/dev/null | {
      cat
      echo "0 0 1,15 * * bash $RUNNER > /dev/null 2>&1"
    } | $_CRONTAB -
  fi

  log_set "✅ crontab 已设置"
  echo "✅ crontab 已设置"
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