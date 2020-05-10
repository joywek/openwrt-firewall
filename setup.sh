#!/bin/bash

EXTIF="eth0.2"
INIF="br-lan"

iptables -F
iptables -X
iptables -Z

iptables -P INPUT   ACCEPT
iptables -P OUTPUT  ACCEPT
iptables -P FORWARD ACCEPT

iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

iptables -A INPUT -i $EXTIF -p icmp -j ACCEPT

iptables -A INPUT -p TCP -i $EXTIF --dport 22 -j ACCEPT # SSH
iptables -A INPUT -p TCP -i $EXTIF --dport 80 -j ACCEPT # HTTP
iptables -A INPUT -p TCP -i $EXTIF --dport 443 -j ACCEPT # HTTPS

iptables -A INPUT -i $INIF -j ACCEPT

iptables -F -t nat
iptables -X -t nat
iptables -Z -t nat

iptables -t nat -P PREROUTING  ACCEPT
iptables -t nat -P POSTROUTING ACCEPT
iptables -t nat -P OUTPUT      ACCEPT

iptables -t nat -A POSTROUTING -o $EXTIF -j MASQUERADE

# NAT 服务器后端的 LAN 内对外之服务器设定
# iptables -t nat -A PREROUTING -p tcp -i $EXTIF --dport 80 \
#   --to-destination 192.168.1.210:80 -j DNAT 
