##### openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout ./nginx.key -out ./nginx.crt

##### 好用的命令
```shell
## 系统信息查看脚本
wget -qO- bench.sh | bash
bash <(wget -qO- https://down.vpsaff.net/linux/speedtest/superbench.sh)
# 服务器的GB5测试
bash <(curl -sL bash.icu/gb5)
## 检测解锁状态
bash <(curl -L -s https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/check.sh)
bash <(curl -L -s check.unlock.media)
bash <(curl -L -s check.unlock.media) -P http://127.0.0.1:10801
bash <(curl -L -s media.ispvps.com)
bash <(curl -L -s media.ispvps.com) -P http://127.0.0.1:10801
bash <(curl -L -s https://github.com/1-stream/RegionRestrictionCheck/raw/main/check.sh)
# 节点测试脚本
[nodeseek](https://www.nodeseek.com/post-297125-1)
bash <(curl -sL https://run.NodeQuality.com)
## IP质量体检脚本 https://github.com/xykt/IPQuality
bash <(curl -sL IP.Check.Place)
## 网络质量体检脚本 https://github.com/xykt/NetQuality
bash <(curl -Ls https://Net.Check.Place)
## VPS融合怪服务器测评脚本
bash <(wget -qO- bash.spiritlhl.net/ecs)
## 检测ChatGPT是否可用
bash <(curl -sSL https://raw.githubusercontent.com/Netflixxp/chatGPT/main/chat.sh)
## 循环消耗入站流量
screen -dmS run bash -c "while true; do yt-dlp -o '~/test.mp4' -f 247 https://www.youtube.com/watch?v=fItf_CEb3jw && rm ~/test.mp4; done;"

## wgcf ipv6安装
[nodeseek](https://www.nodeseek.com/post-23836-1)
wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh

curl -s http://ipv4.icanhazip.com 
curl -s http://ipv6.icanhazip.com
curl -s4 ip.sb
curl -s6 ip.sb

# 查看当前bbr
modinfo tcp_bbr

# 好用的shell工具箱
curl -sS -O https://raw.githubusercontent.com/kejilion/sh/main/kejilion.sh && chmod +x kejilion.sh && ./kejilion.sh

## 独有的.env配置，创建软连接
[ -f ~/ag/conf/default/docker.env ] && ln -sf ~/ag/conf/default/docker.env ~/ag/.env

## acme命令动态配置域名证书
bash <(curl -sSL https://raw.githubusercontent.com/renkx/s/main/acme/acme.sh) ~/ag/conf/default/acme.conf
bash <(curl -sSL https://gitee.com/renkx/ss/raw/main/acme/acme.sh) ~/ag/conf/default/acme.conf

# TCP加速 内核升级
bash <(curl -sSL https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcpx.sh)

## 程序安装 github
bash <(curl -sSL https://raw.githubusercontent.com/renkx/s/main/install_tool.sh)

## 程序安装 gitee
bash <(curl -sSL https://gitee.com/renkx/ss/raw/main/install_tool.sh)
```

##### iptablesUtils [github](https://github.com/arloor/iptablesUtils)
```shell
# github
bash <(curl -fsSL https://raw.githubusercontent.com/arloor/iptablesUtils/master/natcfg.sh)
# 国内
bash <(curl -fsSL https://www.arloor.com/sh/iptablesUtils/natcfg.sh)
# 以下是改版，上面旧脚本不要使用了
bash <(curl -fsSL https://raw.githubusercontent.com/renkx/s/main/iptablesUtils/natcfg.sh)
bash <(curl -fsSL https://gitee.com/renkx/ss/raw/main/iptablesUtils/natcfg.sh)
## iptables转发配置，创建软连接（创建完成后，执行脚本的时候选择：强制刷新服务，就可以了）
ln -sf ~/ag/conf/default/dnatconf /etc/dnat/conf
# 实时查看日志
journalctl -u dnat -f
```

##### NextTrace [github](https://github.com/nxtrace/NTrace-core) [github cn](https://github.com/nxtrace/NTrace-core/blob/main/README_zh_CN.md)
```shell
# Linux 安装
curl nxtrace.org/nt |bash
# 网络测速脚本
curl -fsSL git.io/speedtest-cli.sh | bash
```

##### bin456789 [github地址](https://github.com/bin456789/reinstall)
```shell
# 国外服务器：
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh || wget -O ${_##*/} $_ && bash reinstall.sh debian 13 --password '88889999' --ssh-port '12722'

# 国内服务器：
curl -O https://cnb.cool/bin456789/reinstall/-/git/raw/main/reinstall.sh || wget -O ${_##*/} $_ && bash reinstall.sh debian 13 --password '88889999' --ssh-port '12722'

## 当前才能DD的：搬瓦工、aws，阿里抢占式ecs自定义alpine镜像
```

##### LeitboGi0ro [github地址](https://github.com/leitbogioro/Tools) [nodeseek地址](https://www.nodeseek.com/post-9383-1)
```shell
# github 脚本下载
curl -O https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh || wget -O ${_##*/} $_ && bash InstallNET.sh -debian 13 -pwd '88889999' -port 12722
# github 脚本下载 清华大学开源软件镜像
curl -O https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh || wget -O ${_##*/} $_ && bash InstallNET.sh -debian 13 -pwd '88889999' -port 12722 -mirror "http://mirrors.tuna.tsinghua.edu.cn/debian"

# gitee 脚本下载
curl -O https://gitee.com/mb9e8j2/Tools/raw/master/Linux_reinstall/InstallNET.sh || wget -O ${_##*/} $_ && bash InstallNET.sh -debian 13 -pwd '88889999' -port 12722
# gitee 脚本下载 清华大学开源软件镜像
curl -O https://gitee.com/mb9e8j2/Tools/raw/master/Linux_reinstall/InstallNET.sh || wget -O ${_##*/} $_ && bash InstallNET.sh -debian 13 -pwd '88889999' -port 12722 -mirror "http://mirrors.tuna.tsinghua.edu.cn/debian"

## 当前不能DD的：搬瓦工（有几率无线重启）、aws（重启就断连）、阿里抢占式ecs自定义alpine镜像（各种报错）
```

```shell
## debian 系统更新
apt update -y && apt full-upgrade -y && apt autoremove -y && apt autoclean -y

# debian 系统清理
apt autoremove --purge -y
apt clean -y
apt autoclean -y
apt remove --purge $(dpkg -l | awk '/^rc/ {print $2}') -y
journalctl --rotate
journalctl --vacuum-time=1s
journalctl --vacuum-size=50M
apt remove --purge $(dpkg -l | awk '/^ii linux-(image|headers)-[^ ]+/{print $2}' | grep -v $(uname -r | sed 's/-.*//') | xargs) -y
```

[私有agConf](https://github.com/renkx/myconf/tree/agconf)

[docker容器脚本](./README_D.md)

[归档](./README_ARCHIVE.md)

##### 相关说明
```shell
## linode DD遇到问题：https://github.com/leitbogioro/Tools/issues/87
## linode、vultr 遇到网络问题，网卡 auto 改为 allow-hotplug，dd脚本参数加：--autoplugadapter "0"
## aws的新加坡比较好用，天津只是偶尔波动大。日本的北京晚高峰特别烂
## misaka 21$ PCCW线路，晚高峰联通爆炸
## zgocloud debian10可以dd，用debian11 dd会报磁盘错误（首次dd，没有二次尝试直接换10了）
## 搬瓦工迁移之后连不上网，有可能是 /etc/network/interfaces 的配置和 ip a 看到的不一样，改一下就行，改完重启：systemctl restart networking
## 如果网络配置文件被反复修改导致网络连接不上，就锁死：chattr +i /etc/network/interfaces

#####
## 重启后一定要执行 sysctl -a | grep conntrack ，查看 conntrack_max 是不是20+万，有些参数重启后不生效
## systemctl status systemd-sysctl.service 可以看下具体报错
## 会出现【nf_conntrack: nf_conntrack: table full, dropping packet】错误，用itdog一直发送tcping就会产生
## 执行生效命令：sysctl --system
## 原因：安装docker造成的，docker启动时会重写某些nf内核配置
#####

## debian 12之前，系统日志：/var/log/messages，之后为 journalctl -ef
## https://www.debian.org/releases/stable/i386/release-notes/ch-information.zh-cn.html#changes-to-system-logging
```

#### [系统安装步骤](https://app.yinxiang.com/fx/4c75d6ad-a9fa-4aff-8914-28a19b7ad9a0)