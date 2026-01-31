#!/usr/bin/env bash

# --- 第一部分：立即安装依赖（仅在执行本部署脚本时运行一次） ---
echo "正在检查并安装必要依赖..."
if ! command -v turbostat > /dev/null 2>&1; then
    apt update && apt install -y linux-cpupower
    modprobe msr
    echo msr > /etc/modules-load.d/turbostat-msr.conf
    chmod +s /usr/sbin/turbostat
    echo "依赖安装成功。"
else
    echo "依赖已存在，跳过安装。"
fi

# --- 第二部分：生成自动修复脚本 ---
CHECK_EXE="/usr/local/bin/pve-auto-repair-mod.sh"
echo "正在生成自动修复脚本..."

cat > $CHECK_EXE << 'EOF'
#!/usr/bin/env bash

TARGET="/usr/share/perl5/PVE/API2/Nodes.pm"

# 1. 如果 UI 修改还在，直接闪人
if grep -q 'modbyshowtempfreq' "$TARGET"; then
    exit 0
fi

echo "$(date): 检测到 UI 修改丢失，等待联网..."

# 2. 等待联网循环 (40次 * 15秒 = 10分钟)
MAX_RETRIES=40
RETRY_COUNT=0
until ping -c 1 -W 2 223.5.5.5 > /dev/null 2>&1; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "联网超时，退出。"
        exit 1
    fi
    sleep 15
done

# 3. 联网成功，直接拉取并执行作者脚本
echo "网络已就绪，正在重新应用 UI 补丁..."
(curl -Lf -o /tmp/temp.sh https://raw.githubusercontent.com/a904055262/PVE-manager-status/main/showtempcpufreq.sh || \
 curl -Lf -o /tmp/temp.sh https://mirror.ghproxy.com/https://raw.githubusercontent.com/a904055262/PVE-manager-status/main/showtempcpufreq.sh) && \
 chmod +x /tmp/temp.sh && \
 /tmp/temp.sh remod
EOF

chmod +x $CHECK_EXE

# --- 第三部分：创建 Systemd 服务 ---
SERVICE_PATH="/etc/systemd/system/pve-mod-check.service"
echo "正在配置 Systemd 服务..."

cat > $SERVICE_PATH << EOF
[Unit]
Description=PVE UI Auto-Repair (After Network)
After=pve-guests.service

[Service]
Type=oneshot
ExecStart=$CHECK_EXE
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable pve-mod-check.service

# 最后：尝试立即跑一次修复，看看当前需不需要改
systemctl start pve-mod-check.service

echo "------------------------------------------------"
echo "配置完成！"
echo "以后只需关注：PVE 升级重启后，等上网拨号成功，UI 会自动变回来。"
echo "------------------------------------------------"