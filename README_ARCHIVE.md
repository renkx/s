##### 归档

##### html5-speedtest
```shell
docker run -d --name speedtest --restart=unless-stopped -p 6688:80 renkx/html5-speedtest
```

##### 安装docker
```shell
yum install -y curl 2> /dev/null || apt install -y curl && bash <(curl -sSL https://raw.githubusercontent.com/renkx/s/main/install_docker.sh)
```

##### 安装docker-compose
```shell
yum install -y curl 2> /dev/null || apt install -y curl && bash <(curl -sSL https://raw.githubusercontent.com/renkx/s/main/install_docker_compose.sh)
```

##### 安装on-my-zsh
```shell
yum install -y curl 2> /dev/null || apt install -y curl && bash <(curl -sSL https://raw.githubusercontent.com/renkx/s/main/myzsh.sh)
```

##### install_docker_frp.sh
```shell
wget -N --no-check-certificate -q -O install_docker_frp.sh "https://raw.githubusercontent.com/renkx/s/main/install_docker_frp.sh" && chmod +x install_docker_frp.sh && bash install_docker_frp.sh
```

##### MoeClub.org
```shell
#先切换到root权限
sudo -i
#确保安装了所需软件:
#Debian/Ubuntu:
apt-get update && apt-get install -y xz-utils openssl gawk file wget vim
#RedHat/CentOS:
yum update && yum install -y xz openssl gawk file wget vim

# 安装debian 10 (-firmware 参数说明：额外驱动支持)
bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/veip007/dd/master/InstallNET.sh') -d 10 -v 64 -a -firmware -p 88889999
# 阿里云镜像
bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/veip007/dd/master/InstallNET.sh') -d 10 -v 64 -a -firmware --mirror 'http://mirrors.aliyun.com/debian' -p 88889999
# 腾讯云镜像
bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/veip007/dd/master/InstallNET.sh') -d 10 -v 64 -a -firmware --mirror 'http://mirrors.cloud.tencent.com/debian' -p 88889999
# 中国科学技术大学镜像
bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/veip007/dd/master/InstallNET.sh') -d 10 -v 64 -a -firmware --mirror 'http://mirrors.ustc.edu.cn/debian' -p 88889999
# 腾讯内网镜像
bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/veip007/dd/master/InstallNET.sh') -d 10 -v 64 -a -firmware --mirror 'http://mirrors.tencentyun.com/debian' -p 88889999

# DD完成之后 有些必须安装qemu-guest-agent，否则会出现自动关机的情况
# realServer服务 没有qemu-guest-agent 在备份的时候小鸡不受控制容易导致死机
```

##### cxthhhhh.com
##### [地址](https://cxthhhhh.com/network-reinstall-system-modify)
```shell
# 全球CDN加速 图形化安装界面
wget --no-check-certificate -qO ~/Network-Reinstall-System-Modify.sh 'https://cxthhhhh.com/CXT-Library/Network-Reinstall-System-Modify/Network-Reinstall-System-Modify.sh' && chmod a+x ~/Network-Reinstall-System-Modify.sh && bash ~/Network-Reinstall-System-Modify.sh

# 中国大陆加速 图形化安装界面
wget --no-check-certificate -qO ~/Network-Reinstall-System-Modify.sh 'https://caoxiaotian.com/CXT-Library/Network-Reinstall-System-Modify/Network-Reinstall-System-Modify.sh' && chmod a+x ~/Network-Reinstall-System-Modify.sh && bash ~/Network-Reinstall-System-Modify.sh

# 阿里云镜像
wget --no-check-certificate -qO Core_Install.sh 'https://cxthhhhh.com/CXT-Library/Network-Reinstall-System-Modify/CoreShell/Core_Install_v5.3.sh' && bash Core_Install.sh -d 11 -v 64 -a --mirror 'http://mirrors.aliyun.com/debian'

# github 阿里云镜像
wget --no-check-certificate -qO Core_Install.sh 'https://raw.githubusercontent.com/MeowLove/Network-Reinstall-System-Modify/master/CoreShell/Core_Install_v5.3.sh' && bash Core_Install.sh -d 11 -v 64 -a --mirror 'http://mirrors.aliyun.com/debian'

# 腾讯云镜像
wget --no-check-certificate -qO Core_Install.sh 'https://cxthhhhh.com/CXT-Library/Network-Reinstall-System-Modify/CoreShell/Core_Install_v5.3.sh' && bash Core_Install.sh -d 11 -v 64 -a --mirror 'http://mirrors.cloud.tencent.com/debian'

# 腾讯内网镜像
wget --no-check-certificate -qO Core_Install.sh 'https://cxthhhhh.com/CXT-Library/Network-Reinstall-System-Modify/CoreShell/Core_Install_v5.3.sh' && bash Core_Install.sh -d 11 -v 64 -a --mirror 'http://mirrors.tencentyun.com/debian'
```

##### IdcOffer.com
##### [地址](https://www.idcoffer.com/archives/6644)
```shell
# 面板操作
wget -N --no-check-certificate https://down.vpsaff.net/linux/dd/network-reinstall-os.sh && chmod +x network-reinstall-os.sh && ./network-reinstall-os.sh

# debian 12 阿里镜像 直接安装
wget -N --no-check-certificate https://down.vpsaff.net/linux/dd/network-reinstall.sh && chmod +x network-reinstall.sh && ./network-reinstall.sh -d 12 -p 88889999 --mirror 'http://mirrors.aliyun.com/debian'

wget -N --no-check-certificate https://raw.githubusercontent.com/renkx/d/main/network-reinstall.sh && chmod +x network-reinstall.sh && ./network-reinstall.sh -d 12 -p 88889999 --mirror 'http://mirrors.aliyun.com/debian'

wget -N --no-check-certificate https://gitee.com/renkx/dd/raw/main/network-reinstall.sh && chmod +x network-reinstall.sh && ./network-reinstall.sh -d 12 -p 88889999 --mirror 'http://mirrors.aliyun.com/debian'


```

##### 手动升级debian系统
```shell
# 更新系统到最新
apt-get update && apt-get upgrade
# 切换 Debian 11源到 Debian 12
sed -i 's/bullseye/bookworm/g' /etc/apt/sources.list
# 再次更新系统
apt-get update && apt-get upgrade
# 执行系统更新
apt dist-upgrade
# 重启服务器
reboot
# 清理旧依赖包
apt-get autoremove

```
