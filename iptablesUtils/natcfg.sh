#!/bin/bash

red="\033[31m"
black="\033[0m"

base=/etc/dnat
mkdir -p $base 2>/dev/null
conf=$base/conf
touch $conf

# 准备工作：按需安装依赖并初始化 ipset
init_dependency() {
    local needs_install=false

    # 1. 检查必要命令是否存在
    if ! type dig >/dev/null 2>&1 || ! type ipset >/dev/null 2>&1; then
        needs_install=true
    fi

    # 2. 只有缺失依赖时才运行 apt
    if [ "$needs_install" = "true" ]; then
        echo "检测到依赖缺失，正在安装...."
        apt update -y &> /dev/null
        apt install -y dnsutils ipset &> /dev/null
    fi

    # 创建两个集合，一个处理 v4，一个处理 v6
    ipset create dnat_whitelist hash:ip,port -exist
    ipset create dnat_whitelist_v6 hash:ip,port family inet6 -exist
}

setupService(){
    cat > /usr/local/bin/dnat.sh <<'AAAA'
#!/bin/bash
[[ "$EUID" -ne '0' ]] && echo "Error:必须以root运行" && exit 1;

base=/etc/dnat
conf=$base/conf
ipset_v4="dnat_whitelist"
ipset_v6="dnat_whitelist_v6"

# 1. 初始化内核参数 (双栈转发)
init_kernel(){
    sysctl -w net.ipv4.ip_forward=1 > /dev/null
    sysctl -w net.ipv6.conf.all.forwarding=1 > /dev/null
}

# 2. 核心策略保活 (双栈)
ensure_base_policy(){
    # IPv4
    iptables -C FORWARD -m state --state RELATED,ESTABLISHED -m comment --comment "dnat_rule" -j ACCEPT 2>/dev/null || \
    iptables -I FORWARD 1 -m state --state RELATED,ESTABLISHED -m comment --comment "dnat_rule" -j ACCEPT
    iptables -C FORWARD -m set --match-set $ipset_v4 dst,dst -m comment --comment "dnat_rule" -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -m set --match-set $ipset_v4 dst,dst -m comment --comment "dnat_rule" -j ACCEPT

    # IPv6
    ip6tables -C FORWARD -m state --state RELATED,ESTABLISHED -m comment --comment "dnat_rule" -j ACCEPT 2>/dev/null || \
    ip6tables -I FORWARD 1 -m state --state RELATED,ESTABLISHED -m comment --comment "dnat_rule" -j ACCEPT
    ip6tables -C FORWARD -m set --match-set $ipset_v6 dst,dst -m comment --comment "dnat_rule" -j ACCEPT 2>/dev/null || \
    ip6tables -A FORWARD -m set --match-set $ipset_v6 dst,dst -m comment --comment "dnat_rule" -j ACCEPT
}

# 3. 清理逻辑 (双栈)
clear_all_rules() {
    # 清理 IPv4 NAT & FORWARD
    for chain in PREROUTING POSTROUTING; do
        while num=$(iptables -t nat -L $chain --line-numbers | grep "dnat_rule" | awk '{print $1}' | head -n 1) && [ -n "$num" ]; do
            iptables -t nat -D $chain $num
        done
    done
    while num=$(iptables -L FORWARD --line-numbers | grep "dnat_rule" | awk '{print $1}' | head -n 1) && [ -n "$num" ]; do
        iptables -D FORWARD $num
    done

    # 清理 IPv6 NAT & FORWARD
    for chain in PREROUTING POSTROUTING; do
        while num=$(ip6tables -t nat -L $chain --line-numbers | grep "dnat_rule" | awk '{print $1}' | head -n 1) && [ -n "$num" ]; do
            ip6tables -t nat -D $chain $num
        done
    done
    while num=$(ip6tables -L FORWARD --line-numbers | grep "dnat_rule" | awk '{print $1}' | head -n 1) && [ -n "$num" ]; do
        ip6tables -D FORWARD $num
    done

    ipset flush $ipset_v4 2>/dev/null
    ipset flush $ipset_v6 2>/dev/null
}

apply_rules() {
    local lport=$1; local rhost=$2; local rport=$3; local lip=$4; local version=$5
    if [ "$version" = "v4" ]; then
        iptables -t nat -A PREROUTING -p tcp --dport $lport -m comment --comment "dnat_rule" -j DNAT --to-destination $rhost:$rport
        iptables -t nat -A PREROUTING -p udp --dport $lport -m comment --comment "dnat_rule" -j DNAT --to-destination $rhost:$rport
        iptables -t nat -A POSTROUTING -p tcp -d $rhost --dport $rport -m comment --comment "dnat_rule" -j SNAT --to-source $lip
        iptables -t nat -A POSTROUTING -p udp -d $rhost --dport $rport -m comment --comment "dnat_rule" -j SNAT --to-source $lip
        ipset add $ipset_v4 $rhost,tcp:$rport -exist
        ipset add $ipset_v4 $rhost,udp:$rport -exist
    else
        ip6tables -t nat -A PREROUTING -p tcp --dport $lport -m comment --comment "dnat_rule" -j DNAT --to-destination [$rhost]:$rport
        ip6tables -t nat -A PREROUTING -p udp --dport $lport -m comment --comment "dnat_rule" -j DNAT --to-destination [$rhost]:$rport
        ip6tables -t nat -A POSTROUTING -p tcp -d $rhost --dport $rport -m comment --comment "dnat_rule" -j SNAT --to-source $lip
        ip6tables -t nat -A POSTROUTING -p udp -d $rhost --dport $rport -m comment --comment "dnat_rule" -j SNAT --to-source $lip
        ipset add $ipset_v6 $rhost,tcp:$rport -exist
        ipset add $ipset_v6 $rhost,udp:$rport -exist
    fi
}

init_kernel
last_md5=""

while true; do
    # 每次循环都检查一次基础规则是否存在，不存在则补上
    ensure_base_policy

    # 0. 预先探测本地双栈能力
    localIP4=$(ip route get 119.29.29.29 2>/dev/null | grep -Po '(?<=src )(\d{1,3}.){3}\d{1,3}' || ip -o -4 addr list | grep -Ev '\s(docker|lo)' | awk '{print $4}' | cut -d/ -f1 | head -n 1)
    localIP6=$(ip -6 route get 2400:3200::1 2>/dev/null | grep -Po '(?<=src )[0-9a-fA-F:]+' || ip -o -6 addr list | grep 'scope global' | grep -v 'temporary' | awk '{print $4}' | cut -d/ -f1 | head -n 1)

    [ -n "$localIP4" ] && HAS_LOCAL_V4=true || HAS_LOCAL_V4=false
    [ -n "$localIP6" ] && HAS_LOCAL_V6=true || HAS_LOCAL_V6=false

    # 准备本轮解析的内存缓存
    valid_configs=()
    conf_line_count=0
    dns_changed=false

    while read -r line || [ -n "$line" ]; do
        [[ -z "$line" || "$line" == "#"* ]] && continue
        ((conf_line_count++))
        lport=$(echo $line | cut -d'>' -f1)
        r_part=$(echo $line | cut -d'>' -f2)
        rhost_name=$(echo $r_part | cut -d':' -f1)
        rport=$(echo $r_part | cut -d':' -f2)

        # --- IPv4 处理逻辑 ---
        if [ "$HAS_LOCAL_V4" = "true" ]; then
            if [[ $rhost_name =~ ^[0-9.]+$ ]]; then
                rip4=$rhost_name
            else
                rip4=$(dig +short +time=1 +tries=1 A $rhost_name | grep -E '^[0-9.]+$' | head -n1)
            fi

            old_v4=$(cat "$base/${lport}.v4" 2>/dev/null)
            [ -z "$rip4" ] && rip4=$old_v4 # 降级使用历史IP

            if [ -n "$rip4" ]; then
                valid_configs+=("$lport|$rip4|$rport|v4")
                [ "$rip4" != "$old_v4" ] && dns_changed=true
            fi
        fi

        # --- IPv6 处理逻辑 (只有本地支持 V6 才解析) ---
        if [ "$HAS_LOCAL_V6" = "true" ]; then
            if [[ $rhost_name =~ : ]]; then
                rip6=$rhost_name
            else
                rip6=$(dig +short +time=1 +tries=1 AAAA $rhost_name | grep -E '^[0-9a-fA-F:]+$' | head -n1)
            fi

            old_v6=$(cat "$base/${lport}.v6" 2>/dev/null)
            [ -z "$rip6" ] && rip6=$old_v6

            if [ -n "$rip6" ]; then
                valid_configs+=("$lport|$rip6|$rport|v6")
                [ "$rip6" != "$old_v6" ] && dns_changed=true
            fi
        fi
    done < "$conf"

    current_md5=$(md5sum "$conf" 2>/dev/null | awk '{print $1}')
    md5_changed=false
    if [ "$current_md5" != "$last_md5" ]; then
        md5_changed=true
        last_md5=$current_md5
    fi

    if [ "$md5_changed" = "true" ] || [ "$dns_changed" = "true" ]; then
        if [ "$conf_line_count" -gt 0 ] && [ "${#valid_configs[@]}" -eq 0 ]; then
            echo "[CRITICAL] 所有解析均失败且无缓存，放弃本次重载"
            last_md5="RETRY"
        else
            echo "[$(date '+%m-%d %H:%M:%S')] 触发重载 (MD5:$md5_changed, DNS:$dns_changed)"

            clear_all_rules
            ensure_base_policy

            # 初始化计数器
            local v4_success=0
            local v6_success=0

            for config in "${valid_configs[@]}"; do
                IFS='|' read -r lp rp rpt ver <<< "$config"
                if [ "$ver" = "v4" ] && [ -n "$localIP4" ]; then
                    apply_rules $lp $rp $rpt $localIP4 v4
                    echo "$rp" > "$base/${lp}.v4"
                    ((v4_success++))
                elif [ "$ver" = "v6" ] && [ -n "$localIP6" ]; then
                    apply_rules $lp $rp $rpt $localIP6 v6
                    echo "$rp" > "$base/${lp}.v6"
                    ((v6_success++))
                fi
            done

            echo "[SUCCESS] ${#valid_configs[@]} 条规则，同步完成: IPv4规则 ${v4_success} 条, IPv6规则 ${v6_success} 条"
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
    # 顺便清理历史缓存文件
    rm -f $base/${lport}.v4 $base/${lport}.v6
    setupService
}

init_dependency
clear
echo -e "${red}>>> iptables DNAT 管理脚本 <<<${black}"

select todo in 增加转发规则 删除转发规则 强制刷新服务 查看当前ipset放行名单 查看iptables配置
do
    case $todo in
    增加转发规则) addDnat ;;
    删除转发规则) rmDnat ;;
    强制刷新服务) setupService && ipset list dnat_whitelist && ipset list dnat_whitelist_v6 ;;
    查看当前ipset放行名单)
        echo "--- IPv4 Set ---"; ipset list dnat_whitelist
        echo "--- IPv6 Set ---"; ipset list dnat_whitelist_v6
        ;;
    查看iptables配置)
        echo "--- IPv4 NAT ---";
        iptables -t nat -L -n --line-numbers
        echo "--- IPv4 FORWARD链 ---"
        iptables -L FORWARD -n --line-numbers
        echo "--- IPv6 NAT ---";
        ip6tables -t nat -L -n --line-numbers
        echo "--- IPv6 FORWARD链 ---"
        ip6tables -L FORWARD -n --line-numbers
        ;;
    *) exit ;;
    esac
done