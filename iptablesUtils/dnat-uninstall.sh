#!/bin/bash

red="\033[31m"
black="\033[0m"

echo "正在卸载 dnat 转发服务..."

# 1. 停止并禁用 Systemd 服务
systemctl stop dnat 2>/dev/null
systemctl disable dnat 2>/dev/null
rm -f /lib/systemd/system/dnat.service
systemctl daemon-reload

# 2. 清理相关文件
base=/etc/dnat
# 如果 /etc/dnat/conf 是个软链接，只删除链接本身
if [ -L "$base/conf" ]; then
    rm -f "$base/conf"
fi
rm -rf $base
rm -f /usr/local/bin/dnat.sh
rm -f /iptables_nat.sh # 清理旧脚本可能留下的残留

# 3. 清理 iptables NAT 规则
iptables -t nat -F PREROUTING
iptables -t nat -F POSTROUTING

# 4. 清理 FORWARD 链上的精准放行规则 (关键点)
# 查找并删除包含 dnat_whitelist 的规则
echo "清理 FORWARD 链..."
while iptables -L FORWARD --line-numbers | grep -q "dnat_whitelist"; do
    index=$(iptables -L FORWARD --line-numbers | grep "dnat_whitelist" | head -n 1 | awk '{print $1}')
    iptables -D FORWARD $index
done

# 查找并删除 RELATED,ESTABLISHED 规则（如果担心误删其他服务的，可以跳过，但建议清理）
while iptables -L FORWARD --line-numbers | grep -q "RELATED,ESTABLISHED"; do
    index=$(iptables -L FORWARD --line-numbers | grep "RELATED,ESTABLISHED" | head -n 1 | awk '{print $1}')
    iptables -D FORWARD $index
done

# 5. 销毁 ipset 集合 (关键点)
echo "清理 ipset 集合..."
ipset flush dnat_whitelist 2>/dev/null
ipset destroy dnat_whitelist 2>/dev/null

echo -e "${red}卸载完成！${black}"
echo "注意：内核转发参数 (net.ipv4.ip_forward) 仍保持开启状态，如需关闭请手动执行: sysctl -w net.ipv4.ip_forward=0"