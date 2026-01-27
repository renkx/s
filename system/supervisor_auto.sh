#!/bin/bash
# ========================================================
# 功能:
#   1. deploy 模式: 检测网络，生成指向 GitHub/Gitee 的引导脚本
#   2. run 模式: 自动安装、监控配置变化、资源自动启停
# ========================================================

# [配置区] 定义两个源地址
GITHUB_URL="https://raw.githubusercontent.com/renkx/s/main/system/supervisor_auto.sh"
GITEE_URL="https://gitee.com/renkx/ss/raw/main/system/supervisor_auto.sh"

SOURCE_CONF="$HOME/ag/conf/default/supervisor.conf"
TARGET_LINK="/etc/supervisor/conf.d/supervisor.conf"
SERVICE_NAME="supervisor-auto"

# --- 核心函数：网络环境判断 (决定后续下载源) ---
check_network_env() {
  [ -n "${IsGlobal:-}" ] && return

  echo "🔍 正在分析网络路由以选择最佳下载源..."

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

# --- 模式 1: 部署模式 (用户手动执行) ---
if [[ "$1" == "deploy" ]]; then
    echo "🚀 正在执行部署模式..."

    # 1. 运行网络检测并获取地址
    check_network_env

    if [[ "$IsGlobal" == "1" ]];then
      echo "🌍 检测到海外环境，使用 GitHub 源"
      SELECTED_URL=$GITHUB_URL
    else
      echo "🇨🇳 检测到国内环境，使用 Gitee 源"
      SELECTED_URL=$GITEE_URL
    fi

    # 2. 生成引导脚本：根据检测到的网络环境写入固定的远程地址
    cat << EOF > /usr/local/bin/supervisor-boot.sh
#!/bin/bash
# 自动生成的引导脚本，地址已根据部署时的网络环境优化
REMOTE_URL="$SELECTED_URL"
echo "🔄 [\$(date)] 正在同步远程逻辑: \$REMOTE_URL"
curl -sL --connect-timeout 10 --retry 3 "\$REMOTE_URL" | bash -s -- run
EOF
    chmod +x /usr/local/bin/supervisor-boot.sh

    # 3. 写入 Systemd 服务配置
    cat << EOF > /etc/systemd/system/${SERVICE_NAME}.service
[Unit]
Description=Supervisor Remote Auto-Monitor
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/supervisor-boot.sh
User=root
Restart=always
RestartSec=15
# 确保无人值守安装
Environment=DEBIAN_FRONTEND=noninteractive

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now ${SERVICE_NAME}.service
    echo "✅ 部署完成！当前节点已绑定源: $SELECTED_URL"
    exit 0
fi

# --- 模式 2: 运行模式 (由引导脚本调用) ---
if [[ "$1" == "run" ]]; then
    LAST_MD5=""
    echo "👀 远程监控逻辑已激活 (PID: $$)..."

    while true; do
        # 1. 检查源文件是否存在
        if [ -f "$SOURCE_CONF" ]; then

            # A. 确保安装 Supervisor
            if ! command -v supervisorctl &> /dev/null; then
                echo "📦 正在安装 Supervisor..."
                apt-get update -qq && apt-get install -y -qq supervisor
            fi

            # B. 检查并修正软链接
            if [ "$(readlink -f "$TARGET_LINK")" != "$SOURCE_CONF" ]; then
                echo "🔗 建立/修正软链接: $TARGET_LINK -> $SOURCE_CONF"
                mkdir -p "$(dirname "$TARGET_LINK")"
                ln -sf "$SOURCE_CONF" "$TARGET_LINK"
                systemctl restart supervisor
            fi

            # C. 确保服务在线
            if ! systemctl is-active --quiet supervisor; then
                echo "▶️ 启动 Supervisor 服务..."
                systemctl start supervisor
            fi

            # D. 配置变动检测 (MD5 校验)
            CURRENT_MD5=$(md5sum "$SOURCE_CONF" | awk '{print $1}')
            if [ "$CURRENT_MD5" != "$LAST_MD5" ]; then
                if [ -n "$LAST_MD5" ]; then
                    echo "⚡ 检测到配置变更，执行 supervisorctl update..."
                    supervisorctl update
                fi
                LAST_MD5="$CURRENT_MD5"
            fi

        else
            # 2. 如果源文件不存在，停止进程节省资源
            if systemctl is-active --quiet supervisor; then
                echo "💤 未发现配置，停止 Supervisor..."
                systemctl stop supervisor
            fi
            LAST_MD5=""
        fi

        sleep 10
    done
fi

echo "用法: curl ... | bash -s -- deploy"
exit 1