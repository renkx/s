#!/bin/bash

red="\033[31m"
black="\033[0m"

base=/etc/dnat
mkdir -p $base 2>/dev/null
conf=$base/conf
touch $conf

# 准备工作：安装依赖并初始化 ipset
init_dependency() {
    echo "正在安装依赖...."
    apt update -y &> /dev/null
    apt install -y dnsutils ipset &> /dev/null

    # 创建 ipset 集合，hash:ip,port 模式
    ipset create dnat_whitelist hash:ip,port -exist
}

setupService(){
    cat > /usr/local/bin/dnat.sh <<'AAAA'
#!/bin/bash
[[ "$EUID" -ne '0' ]] && echo "Error:必须以root运行" && exit 1;

base=/etc/dnat
conf=$base/conf
ipset_name="dnat_whitelist"

# 1. 初始化内核参数（只需执行一次）
init_kernel(){
    sysctl -w net.ipv4.ip_forward=1 > /dev/null
    # 清理所有 DNAT/SNAT 规则，确保环境干净（反正 while 循环 10 秒内会重新补齐）
    iptables -t nat -F PREROUTING
    iptables -t nat -F POSTROUTING
    ipset flush $ipset_name 2>/dev/null
    rm -f $base/*.ip
}

# 2. 核心策略保活（放入循环，应对 UFW 重置）
ensure_base_policy(){
    # 允许回程流量 (最高优先级)
    iptables -C FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -m state --state RELATED,ESTABLISHED -j ACCEPT

    # 允许匹配 ipset 的转发
    iptables -C FORWARD -m set --match-set $ipset_name dst,dst -j ACCEPT 2>/dev/null || iptables -A FORWARD -m set --match-set $ipset_name dst,dst -j ACCEPT
}

apply_rules() {
    local lport=$1
    local rhost=$2
    local rport=$3
    local lip=$4
    local old_rip=$5

    # 1. 精准清理旧的 NAT 映射
    if [ -n "$old_rip" ]; then
        iptables -t nat -D PREROUTING -p tcp --dport $lport -j DNAT --to-destination $old_rip:$rport 2>/dev/null
        iptables -t nat -D PREROUTING -p udp --dport $lport -j DNAT --to-destination $old_rip:$rport 2>/dev/null
        iptables -t nat -D POSTROUTING -p tcp -d $old_rip --dport $rport -j SNAT --to-source $lip 2>/dev/null
        iptables -t nat -D POSTROUTING -p udp -d $old_rip --dport $rport -j SNAT --to-source $lip 2>/dev/null
        ipset del $ipset_name $old_rip,tcp:$rport 2>/dev/null
        ipset del $ipset_name $old_rip,udp:$rport 2>/dev/null
    fi

    # 2. 注入新映射（由于启动时有 -F，运行中有上面的 -D，这里可以放心 -A）
    iptables -t nat -A PREROUTING -p tcp --dport $lport -j DNAT --to-destination $rhost:$rport
    iptables -t nat -A PREROUTING -p udp --dport $lport -j DNAT --to-destination $rhost:$rport
    iptables -t nat -A POSTROUTING -p tcp -d $rhost --dport $rport -j SNAT --to-source $lip
    iptables -t nat -A POSTROUTING -p udp -d $rhost --dport $rport -j SNAT --to-source $lip

    # 3. 更新 ipset 通行证
    ipset add $ipset_name $rhost,tcp:$rport -exist
    ipset add $ipset_name $rhost,udp:$rport -exist
}

init_kernel

while true; do
    # 每次循环都检查一次基础规则是否存在，不存在则补上
    ensure_base_policy

    localIP=$(ip -o -4 addr list | grep -Ev '\s(docker|lo)' | awk '{print $4}' | cut -d/ -f1 | head -n 1)

    while read -r line || [ -n "$line" ]; do
        [[ -z "$line" || "$line" == "#"* ]] && continue

        lport=$(echo $line | cut -d'>' -f1)
        r_part=$(echo $line | cut -d'>' -f2)
        rhost_name=$(echo $r_part | cut -d':' -f1)
        rport=$(echo $r_part | cut -d':' -f2)

        # 解析 IP
        if [[ $rhost_name =~ ^[0-9.]+$ ]]; then
            rip=$rhost_name
        else
            rip=$(dig +short A $rhost_name | grep -E '^[0-9.]+$' | head -n1)
        fi

        [ -z "$rip" ] && continue

        # 检查变更记录
        ip_file="$base/${lport}.ip"
        old_rip=$(cat "$ip_file" 2>/dev/null)

        if [ "$rip" != "$old_rip" ]; then
            echo "更新规则: $lport -> $rip"
            apply_rules $lport $rip $rport $localIP "$old_rip"
            echo "$rip" > "$ip_file"
        fi
    done < "$conf"

    sleep 10
done
AAAA
    chmod +x /usr/local/bin/dnat.sh

    cat > /lib/systemd/system/dnat.service <<EOF
[Unit]
Description=Dynamic DNAT with ipset
After=network-online.target

[Service]
ExecStart=/bin/bash /usr/local/bin/dnat.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable dnat > /dev/null 2>&1
    systemctl restart dnat > /dev/null 2>&1
    echo -e "${red}服务已刷新并启动，正在监控 /etc/dnat/conf${black}"
}

# 管理端函数
addDnat(){
    echo -n "本地端口号:" ;read lport
    echo -n "远程端口号:" ;read rport
    echo -n "目标域名/IP:" ;read rhost

    # 简单格式校验
    [[ ! $lport =~ ^[0-9]+$ || ! $rport =~ ^[0-9]+$ ]] && echo "端口必须是数字" && return

    # 先清除旧配置行
    sed -i "/^$lport>.*/d" $conf
    # 确保文件末尾有换行并追加
    [ -n "$(tail -c1 $conf 2>/dev/null)" ] && echo "" >> $conf
    echo "$lport>$rhost:$rport" >> $conf

    echo "已添加: $lport>$rhost:$rport"
    setupService
}

rmDnat(){
    echo -n "要删除的本地端口号:" ;read lport
    sed -i "/^$lport>.*/d" $conf
    # 删除缓存的 IP 记录，触发 dnat.sh 逻辑（或手动重启）
    rm -f $base/${lport}.ip
    echo "删除完成，正在重启服务应用变更..."
    setupService
}

init_dependency
clear
echo -e "${red}>>> iptables DNAT 管理脚本 (ipset 模式) <<<${black}"

select todo in 增加转发规则 删除转发规则 强制刷新服务 查看当前ipset放行名单 查看iptables配置
do
    case $todo in
    增加转发规则) addDnat ;;
    删除转发规则) rmDnat ;;
    强制刷新服务) setupService ;;
    查看当前ipset放行名单) ipset list dnat_whitelist ;;
    查看iptables配置)
        echo "--- NAT表 ---"
        iptables -t nat -L -n --line-numbers
        echo "--- FORWARD链 ---"
        iptables -L FORWARD -n --line-numbers
        ;;
    *) exit ;;
    esac
done