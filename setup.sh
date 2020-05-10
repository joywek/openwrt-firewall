#!/bin/bash

set -e

EXTIF="eth0.2"
INTIF="br-lan"
CONFIG_PATH="/etc/config/shadowsocks.json"

command_exists() {
	command -v "$@" >/dev/null 2>&1
}

setup_color() {
	if [ -t 1 ]; then
		RED=$(printf '\033[31m')
		GREEN=$(printf '\033[32m')
		YELLOW=$(printf '\033[33m')
		BLUE=$(printf '\033[34m')
		BOLD=$(printf '\033[1m')
		RESET=$(printf '\033[m')
	else
		RED=""
		GREEN=""
		YELLOW=""
		BLUE=""
		BOLD=""
		RESET=""
	fi
}

error() {
	echo ${RED}"Error: $@"${RESET} >&2
}

setup_config() {
	if [ ! -f $CONFIG_PATH ]; then
		read -p "Remote Host: " SS_REMOTE_HOST
		if [ ! -n $SS_REMOTE_HOST ]; then
			error "Invalid remote host."
			exit 1
		fi
		read -p "Remote Port: " SS_REMOTE_PORT
		if [ ! -n $SS_REMOTE_PORT ]; then
			error "Invalid remote port."
			exit 1
		fi
		read -s -p "Password: " SS_PASSWORD
		if [ ! -n $SS_PASSWORD ]; then
			error "Invalid password."
			exit 1
		fi
		read -p "Enter local port:" SS_LOCAL_PORT
		if [ ! -n $SS_LOCAL_PORT ]; then
			error "Invalid local port."
			exit 1
		fi
		mkdir -p /etc/config
		echo "{
	\"server\": \"$SS_REMOTE_HOST\",
	\"server_port\": \"$SS_REMOTE_PORT\",
	\"password\": \"$SS_PASSWORD\",
	\"method\": \"aes-256-gcm\",
	\"local_port\": \"$SS_LOCAL_PORT\",
	\"fast_open\": false
}" >> $CONFIG_PATH
	else
		SS_REMOTE_HOST=`cat $CONFIG_PATH | awk -F "[:,\"]" '/server[^_]/{print $5}'`
		SS_REMOTE_PORT=`cat $CONFIG_PATH | awk -F "[:,\"]" '/server_port/{print $5}'`
		SS_LOCAL_PORT=`cat $CONFIG_PATH |  awk -F "[:,\"]" '/local_port/{print $5}'`
	fi
}

setup_firewall() {
	command_exists iptables || {
		error "The command \`iptables\` is not found."
		exit 1
	}

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

	iptables -A INPUT -i $INTIF -j ACCEPT

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
}

setup_proxy() {
	iptables -t nat -N SHADOWSOCKS
	iptables -t mangle -N SHADOWSOCKS

	# Ignore your shadowsocks server's addresses
	# It's very IMPORTANT, just be careful.
	iptables -t nat -A SHADOWSOCKS -d $SS_SERVER -j RETURN

	# Ignore LANs and any other addresses you'd like to bypass the proxy
	# See Wikipedia and RFC5735 for full list of reserved networks.
	# See ashi009/bestroutetb for a highly optimized CHN route list.
	iptables -t nat -A SHADOWSOCKS -d 0.0.0.0/8 -j RETURN
	iptables -t nat -A SHADOWSOCKS -d 10.0.0.0/8 -j RETURN
	iptables -t nat -A SHADOWSOCKS -d 127.0.0.0/8 -j RETURN
	iptables -t nat -A SHADOWSOCKS -d 169.254.0.0/16 -j RETURN
	iptables -t nat -A SHADOWSOCKS -d 172.16.0.0/12 -j RETURN
	iptables -t nat -A SHADOWSOCKS -d 192.168.0.0/16 -j RETURN
	iptables -t nat -A SHADOWSOCKS -d 224.0.0.0/4 -j RETURN
	iptables -t nat -A SHADOWSOCKS -d 240.0.0.0/4 -j RETURN

	# Anything else should be redirected to shadowsocks's local port
	iptables -t nat -A SHADOWSOCKS -p tcp -j REDIRECT --to-ports $SS_LOCAL_PORT

	# Add any UDP rules
	ip route add local default dev lo table 100
	ip rule add fwmark 1 lookup 100
	iptables -t mangle -A SHADOWSOCKS -p udp --dport 53 -j TPROXY --on-port $SS_LOCAL_PORT --tproxy-mark 0x01/0x01

	# Apply the rules
	iptables -t nat -A PREROUTING -p tcp -j SHADOWSOCKS
	iptables -t mangle -A PREROUTING -j SHADOWSOCKS

	# Start the shadowsocks-redir
	ss-redir -u -c $CONFIG_PATH -f /var/run/shadowsocks.pid
}

main() {
	setup_color
	setup_config
	setup_firewall
	setup_proxy
}

main "$@"
