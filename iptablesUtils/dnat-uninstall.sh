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

# 3. 精准清理 iptables NAT 规则 (PREROUTING & POSTROUTING)
echo "正在从 NAT 表中移除 DNAT/SNAT 规则..."
for chain in PREROUTING POSTROUTING; do
    while true; do
        # 寻找带有 dnat_rule 备注的规则编号
        num=$(iptables -t nat -L $chain --line-numbers | grep "dnat_rule" | awk '{print $1}' | head -n 1)
        [ -z "$num" ] && break
        iptables -t nat -D $chain $num
    done
done

# 4. 精准清理 FORWARD 链规则
echo "正在从 FORWARD 链中移除放行规则..."
while true; do
    # 无论是匹配 ipset 的还是基础放行，只要带标签就删
    num=$(iptables -L FORWARD --line-numbers | grep "dnat_rule" | awk '{print $1}' | head -n 1)
    [ -z "$num" ] && break
    iptables -D FORWARD $num
done

# 特殊处理：如果没有标签但包含 dnat_whitelist 的遗留规则（兼容旧版本）
while iptables -L FORWARD --line-numbers | grep -q "dnat_whitelist"; do
    num=$(iptables -L FORWARD --line-numbers | grep "dnat_whitelist" | head -n 1 | awk '{print $1}')
    iptables -D FORWARD $num
done

# 5. 销毁 ipset 集合
echo "清理 ipset 集合..."
ipset flush dnat_whitelist 2>/dev/null
ipset destroy dnat_whitelist 2>/dev/null

echo -e "${red}卸载完成！已精准清理所有相关规则，未干扰其他服务。${black}"
echo "注意：内核转发参数 (net.ipv4.ip_forward) 仍保持开启状态，如需关闭请手动执行: sysctl -w net.ipv4.ip_forward=0"