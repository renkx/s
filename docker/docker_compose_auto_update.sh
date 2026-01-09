#!/bin/bash
set -e

COMPOSE_DIR="${1:-}"

# 存在目录参数，才校验
if [ -n "$COMPOSE_DIR" ]; then
  if [ ! -d "$COMPOSE_DIR" ]; then
    echo "Error: directory not found: $COMPOSE_DIR"
    exit 1
  fi

  cd "$COMPOSE_DIR"

  if [ ! -f docker-compose.yml ] && [ ! -f compose.yml ]; then
    echo "Error: no docker-compose.yml or compose.yml in $COMPOSE_DIR"
    exit 1
  fi
fi

# 获取跟路径
HOME_DIR="${HOME:-/root}"
# 最后生成的本地脚本文件
RUNNER="$HOME_DIR/docker_compose_auto_update.sh"

LOG="/var/log/docker_compose_auto_update.log"
LOGROTATE_CONF="/etc/logrotate.d/docker_compose_auto_update"

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

# 设置 crontab 任务 ：每月1号和15号 执行脚本
set_cronjob() {
  _CRONTAB="crontab"

  [ -f "$RUNNER" ] || {
    log "❌ runner 不存在，跳过 cron 设置"
    return 1
  }

  # 获取当前 crontab
  current_cron="$($_CRONTAB -l 2>/dev/null || true)"

  # 删除已有包含 $RUNNER 的行
  new_cron="$(echo "$current_cron" | grep -vF "$RUNNER")"

  # 添加最新的 cron
  if [ -n "$COMPOSE_DIR" ]; then
    CRON_CMD="bash $RUNNER $COMPOSE_DIR"
  else
    CRON_CMD="bash $RUNNER"
  fi
  new_cron="$new_cron
  */5 * * * * $CRON_CMD > /dev/null 2>&1"

  # 安装新的 crontab
  echo "$new_cron" | $_CRONTAB -

  log "✅ crontab 已更新"
}

# 生成本地可执行脚本
generate_update() {
  cat > "$RUNNER" <<'EOF'
#!/usr/bin/env bash
# 任一命令失败立即退出 使用未定义变量时报错 管道中任一失败即失败
set -euo pipefail

COMPOSE_DIR="${1:-}"

# 存在目录参数，才校验
if [ -n "$COMPOSE_DIR" ]; then
  if [ ! -d "$COMPOSE_DIR" ]; then
    echo "Error: directory not found: $COMPOSE_DIR"
    exit 1
  fi

  cd "$COMPOSE_DIR"

  if [ ! -f docker-compose.yml ] && [ ! -f compose.yml ]; then
    echo "Error: no docker-compose.yml or compose.yml in $COMPOSE_DIR"
    exit 1
  fi
fi

GITHUB_URL="https://raw.githubusercontent.com/renkx/s/main/docker/docker_compose_auto_update.sh"
GITEE_URL="https://gitee.com/renkx/ss/raw/main/docker/docker_compose_auto_update.sh"

# -----------------------------
# 工业级测速函数
# -----------------------------
test_speed() {
  curl -sL \
    --connect-timeout 3 \
    --max-time 5 \
    -w "%{time_total}" \
    -o /dev/null \
    "$1" || echo 999
}

echo "⏱ 正在检测 GitHub 网络质量 ..."

github_time="$(test_speed "$GITHUB_URL")"

# 判定阈值（秒）
# 国内 GitHub 常见：2~5s
# 国外 / 代理：< 0.5s
THRESHOLD=1.5

if awk "BEGIN {exit !($github_time < $THRESHOLD)}"; then
  echo "✅ GitHub 网络良好（${github_time}s < ${THRESHOLD}s），使用 GitHub"
  UPDATE_URL="$GITHUB_URL"
else
  echo "⚠️ GitHub 网络较慢（${github_time}s ≥ ${THRESHOLD}s），切换 Gitee"
  UPDATE_URL="$GITEE_URL"
fi

echo "🚀 执行更新脚本：$UPDATE_URL"

if [ -n "$COMPOSE_DIR" ]; then
  bash <(curl -sSL "$UPDATE_URL") "$COMPOSE_DIR" || {
    echo "❌ 执行更新脚本失败"
    exit 1
  }
else
  bash <(curl -sSL "$UPDATE_URL") || {
    echo "❌ 执行更新脚本失败"
    exit 1
  }
fi
EOF

  chmod +x "$RUNNER"
  log "✅ 已生成 cron: $RUNNER"
}

# compose更新
docker_compose_update() {
  log "===== 开始更新 compose 项目: $COMPOSE_DIR ====="

  # 读取 compose.yml 中的 services
  SERVICES=$(docker compose config --services)

  # 严格找出“已运行”的 services（取交集）
  RUNNING_SERVICES=()

  for svc in $SERVICES; do
    status=$(docker compose ps "$svc" --status running --services)
    if [ -n "$status" ]; then
      RUNNING_SERVICES+=("$svc")
    fi
  done

  if [ ${#RUNNING_SERVICES[@]} -eq 0 ]; then
    log "无已启动的 service，跳过"
    return
  fi

  log "已运行 services: ${RUNNING_SERVICES[*]}"

  # pull 已运行 service 的镜像
  for svc in "${RUNNING_SERVICES[@]}"; do
    log "拉取镜像: $svc"
    docker compose pull "$svc" >> "$LOG" 2>&1
  done

  # 只重建已运行的 service
  log "重建已运行 services"
  docker compose up -d "${RUNNING_SERVICES[@]}" >> "$LOG" 2>&1

  # 清理无用镜像
  docker image prune -f >/dev/null 2>&1 || true

  log "===== 更新完成: $COMPOSE_DIR ====="
}

# docker 野生容器更新
update_docker_run_containers() {
  log "===== 开始检查 docker run 野生容器 ====="

  docker ps --filter "label=auto.update=true" --format '{{.ID}}' | while read -r cid; do
    name=$(docker inspect -f '{{.Name}}' "$cid" | sed 's#^/##')
    image=$(docker inspect -f '{{ index .Config.Labels "auto.update.image" }}' "$cid")
    run_cmd=$(docker inspect -f '{{ index .Config.Labels "auto.update.run" }}' "$cid")

    if [ -z "$image" ] || [ -z "$run_cmd" ]; then
      log "⚠️ 跳过 $name（缺少 image 或 run 命令）"
      continue
    fi

    log "🔍 检查镜像: $image ($name)"
    docker pull "$image" >> "$LOG" 2>&1

    old_id=$(docker inspect -f '{{.Image}}' "$cid")
    new_id=$(docker image inspect "$image" -f '{{.Id}}')

    if [ "$old_id" = "$new_id" ]; then
      log "✅ $name 镜像未变化，跳过"
      continue
    fi

    log "♻️ 更新 $name"
    docker rm -f "$name" >> "$LOG" 2>&1
    eval "$run_cmd" >> "$LOG" 2>&1

    log "✅ $name 更新完成"
  done
}

generate_update
set_cronjob

if [ -n "$COMPOSE_DIR" ]; then
  docker_compose_update
fi

update_docker_run_containers