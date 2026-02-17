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

# 1. 初始化内核参数（只做内核设置，不清理）
init_kernel(){
    sysctl -w net.ipv4.ip_forward=1 > /dev/null
}

# 2. 核心策略保活（放入循环，应对 UFW 重置）
ensure_base_policy(){
    # 允许回程流量 (最高优先级)
    iptables -C FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -m state --state RELATED,ESTABLISHED -j ACCEPT

    # 允许匹配 ipset 的转发
    iptables -C FORWARD -m set --match-set $ipset_name dst,dst -m comment --comment "dnat_rule" -j ACCEPT 2>/dev/null || iptables -A FORWARD -m set --match-set $ipset_name dst,dst -m comment --comment "dnat_rule" -j ACCEPT
}

# 3. 清理逻辑
clear_all_rules() {
    # 精准删除 iptables NAT 规则 (PREROUTING & POSTROUTING)
    for chain in PREROUTING POSTROUTING; do
        while true; do
            num=$(iptables -t nat -L $chain --line-numbers | grep "dnat_rule" | awk '{print $1}' | head -n 1)
            [ -z "$num" ] && break
            iptables -t nat -D $chain $num
        done
    done

    # 精准删除 FORWARD (虽然 ensure_base_policy 会补，但清理干净更稳)
    while true; do
        num=$(iptables -L FORWARD --line-numbers | grep "dnat_rule" | awk '{print $1}' | head -n 1)
        [ -z "$num" ] && break
        iptables -D FORWARD $num
    done

    ipset flush $ipset_name 2>/dev/null
}

apply_rules() {
    local lport=$1; local rhost=$2; local rport=$3; local lip=$4
    # 因为我们现在走的是“全量刷新”逻辑，进来前已经清空过了
    iptables -t nat -A PREROUTING -p tcp --dport $lport -m comment --comment "dnat_rule" -j DNAT --to-destination $rhost:$rport
    iptables -t nat -A PREROUTING -p udp --dport $lport -m comment --comment "dnat_rule" -j DNAT --to-destination $rhost:$rport
    iptables -t nat -A POSTROUTING -p tcp -d $rhost --dport $rport -m comment --comment "dnat_rule" -j SNAT --to-source $lip
    iptables -t nat -A POSTROUTING -p udp -d $rhost --dport $rport -m comment --comment "dnat_rule" -j SNAT --to-source $lip
    # 更新 ipset 通行证
    ipset add $ipset_name $rhost,tcp:$rport -exist
    ipset add $ipset_name $rhost,udp:$rport -exist
}

init_kernel
last_md5=""

while true; do
    # 每次循环都检查一次基础规则是否存在，不存在则补上
    ensure_base_policy
    # 准备本轮解析的内存缓存
    valid_configs=()
    conf_line_count=0
    dns_changed=false

    # 1. 预解析 + 变更检测
    while read -r line || [ -n "$line" ]; do
        [[ -z "$line" || "$line" == "#"* ]] && continue
        ((conf_line_count++))

        lport=$(echo $line | cut -d'>' -f1)
        r_part=$(echo $line | cut -d'>' -f2)
        rhost_name=$(echo $r_part | cut -d':' -f1)
        rport=$(echo $r_part | cut -d':' -f2)

        # 解析 IP
        if [[ $rhost_name =~ ^[0-9.]+$ ]]; then
            rip=$rhost_name
        else
            rip=$(dig +short +time=1 +tries=1 A $rhost_name | grep -E '^[0-9.]+$' | head -n1)
        fi

        # 降级逻辑：解析失败用历史
        old_rip=$(cat "$base/${lport}.ip" 2>/dev/null)
        if [ -z "$rip" ]; then
            if [ -n "$old_rip" ]; then
                rip=$old_rip
                echo "[WARN] 端口 $lport 解析失败，回退至历史 IP: $rip"
            fi
        fi

        # 如果最终拿到了 IP (无论是新的还是历史的)
        if [ -n "$rip" ]; then
            valid_configs+=("$lport|$rip|$rport")
            # 对比是否发生变化
            [ "$rip" != "$old_rip" ] && dns_changed=true
        fi
    done < "$conf"

    # 2. 检查配置文件 MD5 是否变化
    current_md5=$(md5sum "$conf" 2>/dev/null | awk '{print $1}')
    md5_changed=false
    if [ "$current_md5" != "$last_md5" ]; then
        md5_changed=true
        last_md5=$current_md5
    fi

    # 3. 决定是否重载
    # 情况 A: 配置文件变了 (可能是增删规则)
    # 情况 B: 域名解析变了 (DDNS 更新)
    if [ "$md5_changed" = "true" ] || [ "$dns_changed" = "true" ]; then

        # 安全熔断：如果配置非空但解析全失败，保护现有连接
        if [ "$conf_line_count" -gt 0 ] && [ "${#valid_configs[@]}" -eq 0 ]; then
            echo "[CRITICAL] 所有解析均失败且无缓存，放弃本次重载"
            last_md5="RETRY" # 下次强刷
        else
            echo "[$(date '+%m-%d %H:%M:%S')] 触发重载 (MD5:$md5_changed, DNS:$dns_changed)"

            localIP=$(ip route get 119.29.29.29 2>/dev/null | grep -Po '(?<=src )(\d{1,3}.){3}\d{1,3}' || ip -o -4 addr list | grep -Ev '\s(docker|lo)' | awk '{print $4}' | cut -d/ -f1 | head -n 1)

            if [ -z "$localIP" ]; then
                echo "[ERROR] 无法获取本地出口IP，跳过本次重载"
                last_md5="RETRY"
                continue
            fi

            clear_all_rules
            ensure_base_policy

            for config in "${valid_configs[@]}"; do
                IFS='|' read -r lp rp rpt <<< "$config"
                apply_rules $lp $rp $rpt $localIP
                echo "$rp" > "$base/${lp}.ip"
            done
            echo "[SUCCESS] 已同步 ${#valid_configs[@]} 条规则"
        fi
    fi

    sleep 5
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
    sed -i --follow-symlinks "/^$lport>.*/d" $conf
    # 确保文件末尾有换行并追加
    [ -n "$(tail -c1 $conf 2>/dev/null)" ] && echo "" >> $conf
    echo "$lport>$rhost:$rport" >> $conf

    echo "已添加: $lport>$rhost:$rport"
    setupService
}

rmDnat(){
    echo -n "要删除的本地端口号:" ;read lport
    sed -i --follow-symlinks "/^$lport>.*/d" $conf
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