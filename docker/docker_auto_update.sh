#!/bin/bash
set -u
set -o pipefail

COMPOSE_DIRS=("$@")

# 有效compose目录
VALID_COMPOSE_DIRS=()
# 校验compose目录
for dir in "${COMPOSE_DIRS[@]}"; do
  if [ ! -d "$dir" ]; then
    echo "❌ directory not found: $dir"
    continue
  fi

  if [ ! -f "$dir/docker-compose.yml" ] && [ ! -f "$dir/compose.yml" ]; then
    echo "❌ no compose file in $dir"
    continue
  fi

  VALID_COMPOSE_DIRS+=("$dir")
done

# 获取跟路径
HOME_DIR="${HOME:-/root}"
# 最后生成的本地脚本文件
RUNNER="$HOME_DIR/docker_auto_update.sh"

LOG="/var/log/docker_auto_update.log"
LOGROTATE_CONF="/etc/logrotate.d/docker_auto_update"

# ===== 自动创建 logrotate 配置（只在不存在时） =====
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
  echo "$msg" | tee -a "$LOG"
}

# 设置 crontab 任务
set_cronjob() {
  [ -f "$RUNNER" ] || {
    log "❌ runner 不存在，跳过 cron 设置"
    return 1
  }

  # 1. 生成随机分钟 (0-59)，基于主机名保证每台机器固定但各不相同
  local seed=$(echo "$(hostname)" | cksum | cut -d' ' -f1)
  local rand_min=$(( seed % 60 ))

  # 2. 构造命令部分和完整行
  # 唯一特征标识：bash $RUNNER
  local cmd_part="bash $RUNNER"

  # 如果有参数，拼接到命令中
  local full_cmd_with_args
  if [ "${#COMPOSE_DIRS[@]}" -gt 0 ]; then
    full_cmd_with_args="$cmd_part ${COMPOSE_DIRS[*]}"
  else
    full_cmd_with_args="$cmd_part"
  fi

  # 最终的 cron 行：随机分钟 每小时 执行
  local cron_time="$rand_min * * * *"
  local full_entry="$cron_time $full_cmd_with_args > /dev/null 2>&1"

  # 3. 获取当前 crontab
  local current_cron
  current_cron="$(crontab -l 2>/dev/null || true)"

  # 4. 幂等检查：如果完全一致，直接返回
  if echo "$current_cron" | grep -qF "$full_entry"; then
    log "ℹ️ 任务已存在且配置一致 (时间: $cron_time)，跳过"
    return 0
  fi

  # 5. 原位替换或追加
  local new_cron
  if echo "$current_cron" | grep -qF "$cmd_part"; then
    # 发现包含 "bash $RUNNER" 的行，进行原位替换
    # 使用 ENVIRON 方式传递变量给 awk，绝对安全
    new_cron=$(export SEARCH="$cmd_part" REPLACE="$full_entry"; \
               echo "$current_cron" | awk '{ if (index($0, ENVIRON["SEARCH"]) > 0) print ENVIRON["REPLACE"]; else print $0 }')
    log "🔄 任务已原位更新 (随机分钟: $rand_min)"
  else
    # 彻底不存在，追加到末尾
    new_cron=$(printf "%s\n%s" "$current_cron" "$full_entry")
    log "✅ 任务已新增 (随机分钟: $rand_min)"
  fi

  # 6. 回写并清理空行
  echo "$new_cron" | grep -v '^$' | crontab -
}

# 生成本地可执行脚本
generate_update() {
  cat > "$RUNNER" <<'EOF'
#!/usr/bin/env bash
set -u
set -o pipefail

COMPOSE_DIRS=("$@")

# 有效compose目录
VALID_COMPOSE_DIRS=()
# 校验compose目录
for dir in "${COMPOSE_DIRS[@]}"; do
  if [ ! -d "$dir" ]; then
    echo "❌ directory not found: $dir"
    continue
  fi

  if [ ! -f "$dir/docker-compose.yml" ] && [ ! -f "$dir/compose.yml" ]; then
    echo "❌ no compose file in $dir"
    continue
  fi

  VALID_COMPOSE_DIRS+=("$dir")
done

# 检测网络
check_network_env() {
  [ -n "${IsGlobal:-}" ] && return

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

  export IsGlobal
  echo "📍 网络定位: $ENV_TIP"
}

check_network_env

if [[ "$IsGlobal" == "1" ]];then
  echo "🌍 检测到海外环境，使用 GitHub 源"
  UPDATE_URL="https://raw.githubusercontent.com/renkx/s/main/docker/docker_auto_update.sh"
else
  echo "🇨🇳 检测到国内环境，使用 Gitee 源"
  UPDATE_URL="https://gitee.com/renkx/ss/raw/main/docker/docker_auto_update.sh"
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

# 直接使用数组展开 "${VALID_COMPOSE_DIRS[@]}"，完美处理空格
if [ "${#VALID_COMPOSE_DIRS[@]}" -gt 0 ]; then
  if ! bash <(curl "${CURL_OPTS[@]}" "$UPDATE_URL") "${VALID_COMPOSE_DIRS[@]}"; then
    echo "❌ 更新脚本执行失败"
    exit 1
  fi
else
  if ! bash <(curl "${CURL_OPTS[@]}" "$UPDATE_URL"); then
    echo "❌ 更新脚本执行失败"
    exit 1
  fi
fi
EOF

  chmod +x "$RUNNER"
  log "✅ 已生成 cron: $RUNNER"
}

# compose更新
docker_compose_update() {
  local dir="$1"
  log "===== 开始更新 compose 项目: $dir ====="
  cd "$dir" || {
    log "❌ 无法进入目录: $dir"
    return
  }

  # --- 新增：判断是否存在 deploy.sh ---
  local COMPOSE_CMD
  if [ -f "./deploy.sh" ]; then
    chmod +x "./deploy.sh"  # 确保有执行权限
    COMPOSE_CMD="./deploy.sh"
    log "⚡️ 检测到 deploy.sh，将使用自定义脚本执行命令"
  else
    COMPOSE_CMD="docker compose"
  fi
  # ---------------------------------

  # 读取 compose.yml 中的 services
  SERVICES=$($COMPOSE_CMD config --services 2>/dev/null || true)

  [ -z "$SERVICES" ] && {
    log "⚠️ 未解析到任何 services，跳过: $dir"
    return
  }

  # 严格找出“已运行”的 services（取交集）
  RUNNING_SERVICES=()

  for svc in $SERVICES; do
    status=$($COMPOSE_CMD ps "$svc" --status running --services 2>/dev/null)
    if [ -n "$status" ]; then
      # --- 校验 auto.update 标签 ---
      # 获取该服务对应容器的 ID (取第一个)
      local container_id
      container_id=$($COMPOSE_CMD ps -q "$svc" | head -n 1)

      if [ -n "$container_id" ]; then
        local auto_update
        auto_update=$(docker inspect -f '{{ index .Config.Labels "auto.update" }}' "$container_id" 2>/dev/null || echo "true")

        if [ "$auto_update" == "false" ]; then
          log "⏭  服务 $svc 已标记为 auto.update=false，跳过更新"
          continue
        fi
      fi
      # ---------------------------------
      RUNNING_SERVICES+=("$svc")
    fi
  done

  if [ ${#RUNNING_SERVICES[@]} -eq 0 ]; then
    log "无需要更新的已启动 service（或均被标记为跳过），跳过"
    return
  fi

  log "待更新 services: ${RUNNING_SERVICES[*]}"

  # pull 已运行 service 的镜像
  for svc in "${RUNNING_SERVICES[@]}"; do
    log "拉取镜像: $svc"
    $COMPOSE_CMD pull "$svc" >> "$LOG" 2>&1
  done

  # 只重建待更新的 service
  log "重建 services"
  $COMPOSE_CMD up -d "${RUNNING_SERVICES[@]}" >> "$LOG" 2>&1

  # 清理无用镜像
  cleanup_images

  log "===== 更新完成: $dir ====="
}

# docker 野生容器更新
update_docker_run_containers() {
  log "===== 开始检查 docker run 野生容器 ====="

  # 先获取符合条件的容器 ID
  mapfile -t CONTAINERS < <(
    docker ps \
      --filter "label=auto.update=true" \
      --format '{{.ID}}'
  )

  # 一个都没有，直接返回
  if [ "${#CONTAINERS[@]}" -eq 0 ]; then
    log "ℹ️ 未发现带 auto.update=true 标签的 docker run 野生容器，跳过"
    return
  fi

  log "发现 ${#CONTAINERS[@]} 个可自动更新的 docker run 容器"

  for cid in "${CONTAINERS[@]}"; do
    name=$(docker inspect -f '{{.Name}}' "$cid" | sed 's#^/##')
    image=$(docker inspect -f '{{ index .Config.Labels "auto.update.image" }}' "$cid")
    run_cmd=$(docker inspect -f '{{ index .Config.Labels "auto.update.run" }}' "$cid")

    if [ -z "$image" ] || [ -z "$run_cmd" ]; then
      log "⚠️ 跳过 $name（缺少 image 或 run 命令）"
      continue
    fi

    if ! [[ "$run_cmd" =~ ^docker[[:space:]]+run[[:space:]] ]]; then
      log "❌ 非法 run 命令，拒绝执行: $name"
      continue
    fi

    log "🔍 检查镜像: $image ($name)"
    docker pull "$image" >> "$LOG" 2>&1 || {
      log "⚠️ 镜像拉取失败，跳过: $name"
      continue
    }

    old_id=$(docker inspect -f '{{.Image}}' "$cid")
    new_id=$(docker image inspect "$image" -f '{{.Id}}')

    if [ "$old_id" = "$new_id" ]; then
      log "✅ $name 镜像未变化，跳过"
      continue
    fi

    # 取旧容器的 auto.update 相关 label
    labels=$(
      docker inspect "$cid" \
        --format '{{ range $k, $v := .Config.Labels }}{{ $k }}={{ $v }}{{ "\n" }}{{ end }}' |
      grep '^auto.update' |
      sed "s/'/'\\\\''/g" | \
      sed "s|^|--label '|; s|$|'|" |
      tr '\n' ' '
    )
    # 防止以后 auto.update.run 里再带 label 自身，越更新越长
    run_cmd="$(echo "$run_cmd" | sed -E "s/--label[[:space:]]+'?auto.update[^']*'?[[:space:]]*//g")"
    # 把 label 注入到 docker run（只替换第一次出现的 docker run）
    new_run_cmd="${run_cmd/docker run /docker run $labels}"

    log "🔁 重建命令:"
    log "$new_run_cmd"

    log "♻️ 更新 $name"
    docker rm -f "$name" >> "$LOG" 2>&1 || {
      log "❌ 删除失败，跳过: $name"
      continue
    }

    bash -c "$new_run_cmd" >> "$LOG" 2>&1 || {
      log "❌ 重建失败: $name"
      continue
    }

    log "✅ $name 更新完成"
  done

  # 清理无用镜像
  cleanup_images

  log "===== docker run 野生容器 更新完成 ====="
}

# 清理容器
cleanup_images() {
  log "🧹 清理未使用的 Docker 镜像"

  docker image prune -f >> "$LOG" 2>&1 || {
    log "⚠️ 镜像清理失败（忽略）"
    return 0
  }

  log "✅ 镜像清理完成"
}

generate_update
set_cronjob

if [ "${#VALID_COMPOSE_DIRS[@]}" -gt 0 ]; then
  for dir in "${VALID_COMPOSE_DIRS[@]}"; do
    docker_compose_update "$dir"
  done
else
  log "ℹ️ 未发现有效 compose 目录，跳过 compose 更新"
fi

update_docker_run_containers