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

# 3. 清理 IPv4 规则 (NAT & FORWARD)
echo "正在清理 IPv4 相关规则..."
for chain in PREROUTING POSTROUTING; do
    while num=$(iptables -t nat -L $chain --line-numbers | grep "dnat_rule" | awk '{print $1}' | head -n 1) && [ -n "$num" ]; do
        iptables -t nat -D $chain $num
    done
done

while num=$(iptables -L FORWARD --line-numbers | grep "dnat_rule" | awk '{print $1}' | head -n 1) && [ -n "$num" ]; do
    iptables -D FORWARD $num
done

# 4. 清理 IPv6 规则 (NAT & FORWARD)
echo "正在清理 IPv6 相关规则..."
for chain in PREROUTING POSTROUTING; do
    while num=$(ip6tables -t nat -L $chain --line-numbers | grep "dnat_rule" | awk '{print $1}' | head -n 1) && [ -n "$num" ]; do
        ip6tables -t nat -D $chain $num
    done
done

while num=$(ip6tables -L FORWARD --line-numbers | grep "dnat_rule" | awk '{print $1}' | head -n 1) && [ -n "$num" ]; do
    ip6tables -D FORWARD $num
done

# 5. 销毁 ipset 集合 (v4 & v6)
echo "正在清理 ipset 集合..."
ipset flush dnat_whitelist 2>/dev/null
ipset destroy dnat_whitelist 2>/dev/null
ipset flush dnat_whitelist_v6 2>/dev/null
ipset destroy dnat_whitelist_v6 2>/dev/null

echo -e "${red}双栈卸载完成！${black}"
echo "提示：内核转发参数保持开启（以防干扰 Docker），如需关闭请手动执行："
echo "sysctl -w net.ipv4.ip_forward=0"
echo "sysctl -w net.ipv6.conf.all.forwarding=0"