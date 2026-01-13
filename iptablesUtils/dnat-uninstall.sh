#! /bin/bash

# 参考：https://github.com/arloor/iptablesUtils/blob/master/dnat-uninstall.sh

base=/etc/dnat
systemctl disable --now dnat
rm -rf $base
iptables -t nat -F PREROUTING
iptables -t nat -F POSTROUTING