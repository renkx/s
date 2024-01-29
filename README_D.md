##### dns
```shell
wget -N --no-check-certificate -q -O dnsmasq.sh "https://raw.githubusercontent.com/renkx/s/main/dns/dnsmasq.sh" && chmod +x dnsmasq.sh && bash dnsmasq.sh

wget -N --no-check-certificate -q -O docker_smartdns.sh "https://raw.githubusercontent.com/renkx/s/main/dns/docker_smartdns.sh" && chmod +x docker_smartdns.sh && bash docker_smartdns.sh
```

##### aria2 pro https://p3terx.com/archives/docker-aria2-pro.html
```shell
docker run -d \
    --name aria2_pro \
    --restart unless-stopped \
    --log-opt max-size=1m \
    --network host \
    -e PUID=$UID \
    -e PGID=$GID \
    -e RPC_SECRET=<TOKEN> \
    -e RPC_PORT=6800 \
    -e LISTEN_PORT=6888 \
    -e IPV6_MODE=true \
    -v /root/aria2/aria2_config:/config \
    -v /root/aria2/aria2_downloads:/downloads \
    p3terx/aria2-pro
```

##### ariaNg https://p3terx.com/archives/aria2-frontend-ariang-tutorial.html
```shell
docker run -d \
    --name ariang \
    --log-opt max-size=1m \
    --restart unless-stopped \
    --network host \
    p3terx/ariang --port 6880 --ipv6
```

##### [cloudreve](https://hub.docker.com/r/xavierniu/cloudreve) https://docs.cloudreve.org/
```shell
docker run -d \
  --name cloudreve \
  -e PUID=$UID \
  -e PGID=$GID \
  -e TZ="Asia/Shanghai" \
  --restart=unless-stopped \
  --network host \
  -v /data/256/cloudreve/uploads:/cloudreve/uploads \
  -v /data/256/cloudreve/config:/cloudreve/config \
  -v /data/256/cloudreve/db:/cloudreve/db \
  -v /data/256/cloudreve/avatar:/cloudreve/avatar \
  -v /data/256/aria2_downloads:/downloads \
  xavierniu/cloudreve
```

##### [mysql](https://hub.docker.com/_/mysql)

```shell
docker run -d \
    --name mysql \
    --restart always \
    --log-opt max-size=1m \
    -p 4407:4407 \
    -e MYSQL_TCP_PORT=4407 \
    -e MYSQL_ROOT_PASSWORD=123456 \
    -e TZ="Asia/Shanghai" \
    -v ~/data/mysql:/var/lib/mysql \
    mysql:8.0.27
```

##### [shlink](https://shlink.io/documentation/install-docker-image/)

```shell
docker run -d \
    --name shlink \
    --restart always \
    --log-opt max-size=1m \
    -p 127.0.0.1:8800:8080 \
    -e DEFAULT_DOMAIN=rens.cc \
    -e USE_HTTPS=true \
    -e GEOLITE_LICENSE_KEY=bypZ7Fq3hefK \
    -e DB_DRIVER=mysql \
    -e DB_NAME=shlink \
    -e DB_USER=root \
    -e DB_PASSWORD=123456 \
    -e DB_HOST=mysql \
    -e DB_PORT=4407 \
    --link mysql \
    shlinkio/shlink:stable
```

##### [subconverter](https://github.com/tindy2013/subconverter)

```shell
docker run -d \
    --name sub \
    --restart=always \
    --log-opt max-size=1m \
    -p 127.0.0.1:25500:25500 \
    -v ~/ag/conf/default/pref.toml:/base/pref.toml \
    -v ~/ag/conf/default/:/base/ag/ \
    tindy2013/subconverter:0.7.2
```
