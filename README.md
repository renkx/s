##### openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout ./nginx.key -out ./nginx.crt

##### 好用的命令
```shell
## 系统信息查看脚本
wget -qO- bench.sh | bash
bash <(wget -qO- https://down.vpsaff.net/linux/speedtest/superbench.sh)

## 网络测速脚本
curl -fsSL git.io/speedtest-cli.sh | bash

## 检测解锁状态
bash <(curl -L -s https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/check.sh)
bash <(curl -L -s check.unlock.media)
## 使用代理检测
bash <(curl -L -s check.unlock.media) -P socks5://127.0.0.1:40000

## VPS融合怪服务器测评脚本
bash <(wget -qO- bash.spiritlhl.net/ecs)

## wgcf ipv6安装
bash <(curl -sSL https://raw.githubusercontent.com/renkx/s/main/warp/wgcf.sh)
bash <(curl -fsSL git.io/warp.sh) 6

[warp-yg](https://github.com/yonggekkk/warp-yg)
bash <(wget -qO- https://gitlab.com/rwkgyg/CFwarp/raw/main/CFwarp.sh 2> /dev/null)

## 检测ChatGPT是否可用
bash <(curl -sSL https://raw.githubusercontent.com/Netflixxp/chatGPT/main/chat.sh)

## 锁定DNS解析（第一个异常会请求第二个，为了防止docker容器还没启动。比如warp就会出问题）
chattr -i /etc/resolv.conf && echo "nameserver 127.0.0.1\nnameserver 8.8.8.8" > /etc/resolv.conf && chattr +i /etc/resolv.conf

curl -s http://ipv4.icanhazip.com 
curl -s http://ipv6.icanhazip.com
curl -s4 ip.sb
curl -s6 ip.sb

# 查看当前bbr
modinfo tcp_bbr

# 好用的shell工具箱
curl -sS -O https://raw.githubusercontent.com/kejilion/sh/main/kejilion.sh && chmod +x kejilion.sh && ./kejilion.sh

## 独有的.env配置，创建软连接
ln -sf ~/ag/conf/default/docker.env ~/ag/.env

## acme命令动态配置域名证书
bash ~/ag/conf/default/acme.sh

# TCP加速 内核升级
bash <(curl -sSL https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcpx.sh)

## 程序安装 github
yum install -y curl 2> /dev/null || apt install -y curl && bash <(curl -sSL https://raw.githubusercontent.com/renkx/s/main/docker.sh)

## 程序安装 gitee
yum install -y curl 2> /dev/null || apt install -y curl && bash <(curl -sSL https://gitee.com/renkx/ss/raw/main/docker.sh)
```

##### watchtower [p3terx地址](https://p3terx.com/archives/docker-watchtower.html) [地址](https://containrrr.dev/watchtower/arguments/)
```shell
$ 自动更新
docker run -d \
    --name watchtower \
    --init \
    --restart unless-stopped \
    --log-opt max-size=1m \
    --log-opt max-file=3 \
    -e TZ=Asia/Shanghai \
    -v /var/run/docker.sock:/var/run/docker.sock \
    containrrr/watchtower -c \
    --interval 300
# 运行完删除watchtower容器
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock containrrr/watchtower -cR xxx
```

##### NextTrace [github](https://github.com/nxtrace/NTrace-core) [github cn](https://github.com/nxtrace/NTrace-core/blob/main/README_zh_CN.md)
```shell
# Linux 安装
curl nxtrace.org/nt |bash
```

##### swap.sh
```shell
# github
yum install -y curl 2> /dev/null || apt install -y curl && bash <(curl -sSL https://raw.githubusercontent.com/renkx/s/main/swap.sh)
# gitee
yum install -y curl 2> /dev/null || apt install -y curl && bash <(curl -sSL https://gitee.com/renkx/ss/raw/main/swap.sh)
```

##### LeitboGi0ro [github地址](https://github.com/leitbogioro/Tools) [nodeseek地址](https://www.nodeseek.com/post-9383-1)
```shell
# github 脚本下载
wget --no-check-certificate -qO InstallNET.sh 'https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh' && chmod a+x InstallNET.sh

# gitee 脚本下载
wget --no-check-certificate -qO InstallNET.sh 'https://gitee.com/mb9e8j2/Tools/raw/master/Linux_reinstall/InstallNET.sh' && chmod a+x InstallNET.sh

# debian 12 国内外自动切换镜像
bash InstallNET.sh -debian 12 -pwd '88889999' -port "22"

# debian 12 阿里镜像
bash InstallNET.sh -debian 12 -pwd '88889999' -port "22" -mirror "http://mirrors.aliyun.com/debian"

```

[私有agConf](https://github.com/renkx/myconf/tree/agconf)

[docker容器脚本](./README_D.md)

[归档](./README_ARCHIVE.md)

##### 相关说明
```markdown
## 每次升级系统都需要重新设置bbr，否则会初始化
## 需要安装 XANMOD官方内核(EDGE)(36)，并且删除旧内核，删除内核提示的时候选择NO (52)，最后开启优化方案2(22)
## 搬瓦工的机器迁移之后，/etc/hostname 会发生变化，chattr +i锁住就行了
## linode DD遇到问题：[github](https://github.com/leitbogioro/Tools/issues/87)

#####   以下问题已经用rc.local自启逻辑解决
## 重启后一定要执行 sysctl -a | grep conntrack ，查看 conntrack_max 是不是20+万，有些参数重启后不生效
## systemctl status systemd-sysctl.service 可以看下具体报错
## 会出现【nf_conntrack: nf_conntrack: table full, dropping packet】错误，用itdog一直发送tcping就会产生
## 执行生效命令：sysctl --system
#####

## debian 12之前，系统日志：/var/log/messages，之后为 journalctl -ef [说明](https://www.debian.org/releases/stable/i386/release-notes/ch-information.zh-cn.html#changes-to-system-logging)
```