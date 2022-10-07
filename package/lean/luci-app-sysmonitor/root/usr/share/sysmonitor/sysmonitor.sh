#!/bin/bash

if [ "$(ps | grep -v grep | grep sysmonitor.sh | wc -l)" -gt 2 ]; then
	exit 1
fi

sleep_unit=1
NAME=sysmonitor
APP_PATH=/usr/share/$NAME
/etc/init.d/nfs disable

uci_get_by_name() {
	local ret=$(uci get $1.$2.$3 2>/dev/null)
	echo ${ret:=$4}
}

uci_set_by_name() {
	uci set $1.$2.$3=$4 2>/dev/null
	uci commit $1
}

ping_url() {
	local url=$1
	for i in $( seq 1 3 ); do
		status=$(ping -c 1 -W 1 $url | grep -o 'time=[0-9]*.*' | awk -F '=' '{print$2}'|cut -d ' ' -f 1)
		[ "$status" == "" ] && status=0
		[ "$status" != 0 ] && break
	done
	echo $status
}

check_ip() {
	if [ ! -n "$1" ]; then
		#echo "NO IP!"
		echo ""
	else
 		IP=$1
    		VALID_CHECK=$(echo $IP|awk -F. '$1<=255&&$2<=255&&$3<=255&&$4<=255{print "yes"}')
		if echo $IP|grep -E "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$">/dev/null; then
			if [ ${VALID_CHECK:-no} == "yes" ]; then
				# echo "IP $IP available."
				echo $IP
			else
				#echo "IP $IP not available!"
				echo ""
			fi
		else
			#echo "IP is name convert ip!"
			dnsip=$(nslookup $IP|grep Address|sed -n '2,2p'|cut -d' ' -f2)
			if [ ! -n "$dnsip" ]; then
				#echo "Inull"
				echo $test
			else
				#echo "again check"
				echo $(check_ip $dnsip)
			fi
		fi
	fi
}
	
m=$(cat /etc/config/firewall|grep "config zone"|wc -l)
let "m=m-1"
for ((i=$m;i>=0;i--))
do
	[ $(uci get firewall.@zone[$i].name) == "wan" ] && uci del firewall.@zone[$i]	
done

m=$(cat /etc/config/firewall|grep "config forwarding"|wc -l)
let "m=m-1"
for ((i=$m;i>=0;i--))
do
	uci del firewall.@forwarding[$i]
done
uci commit firewall
cat >> /etc/config/firewall <<EOF
config forwarding
	option src 'wghome'
	option dest 'lan'
EOF
/etc/init.d/firewall restart >/dev/null 2>&1 &

sysctl -w net.ipv4.tcp_congestion_control=bbr
gateway=$(uci get network.lan.gateway)
d=$(date "+%Y-%m-%d %H:%M:%S")
echo $d": Sysmonitor up now." >> /var/log/sysmonitor.log
echo $d": gateway="$gateway >> /var/log/sysmonitor.log

while [ "1" == "1" ]; do #死循环
	ipv6=$(ip -o -6 addr list br-lan | cut -d ' ' -f7 | cut -d'/' -f1 |head -n1)
	cat /etc/lighttpd/lighttpd.conf | grep $ipv6 > /dev/null
	[  $? -ne 0 ] && { 
		gateway=$(check_ip $(route |grep default|sed 's/default[[:space:]]*//'|sed 's/[[:space:]].*$//'))
		status=$(ping_url $gateway)
		if [ "$status" != 0 ]; then
			/usr/share/sysmonitor/sysapp.sh lighttpd
		fi
	}

	homeip=$(uci_get_by_name $NAME sysmonitor gateway 0)
	vpnip=$(uci_get_by_name $NAME sysmonitor vpnip 0)
	gateway=$(uci get network.lan.gateway)
	runssr=0
	[ -f "/etc/init.d/shadowsocksr" ] && runssr=$(ps |grep ssrplus/bin/ssr-|grep -v grep |wc -l)
	if [ "$runssr" == 0 ];then
		[ -f "/etc/init.d/passwall" ] && runssr=$(ps |grep /etc/passwall |grep -v grep |wc -l)
	fi
	if [ "$runssr" -gt 0 ]; then
		vpnok=0
		if [ $gateway == $vpnip ]; then	
			d=$(date "+%Y-%m-%d %H:%M:%S")
			echo $d": gateway="$homeip "(Local VPN)" >> /var/log/sysmonitor.log
			uci set network.lan.gateway=$homeip
			sed -i '/list dns/d' /etc/config/network
			uci add_list network.lan.dns=$homeip
			uci commit network
			/etc/init.d/odhcpd restart
			uci set dhcp.@dnsmasq[0].rebind_localhost='1'
			uci set dhcp.@dnsmasq[0].rebind_protection='1'
			uci commit dhcp
			ifup lan
			ifup lan6
			/etc/init.d/odhcpd restart
		fi
	else
		status=$(ping_url $vpnip)
		if [ "$status" == 0 ]; then
			vpnok=0
			if [ $gateway == $vpnip ]; then
				d=$(date "+%Y-%m-%d %H:%M:%S")
				echo $d": gateway="$homeip >> /var/log/sysmonitor.log

				uci set network.lan.gateway=$homeip
				sed -i '/list dns/d' /etc/config/network
				uci add_list network.lan.dns=$homeip
				uci commit network
				uci set dhcp.@dnsmasq[0].rebind_localhost='1'
				uci set dhcp.@dnsmasq[0].rebind_protection='1'
				uci commit dhcp
				ifup lan
				ifup lan6
				/etc/init.d/odhcpd restart
			fi
		else
			vpnok=1
			if [ $gateway == $homeip ]; then
				d=$(date "+%Y-%m-%d %H:%M:%S")
				echo $d": VPN-gateway="$vpnip >> /var/log/sysmonitor.log
				uci set network.lan.gateway=$vpnip
				sed -i '/list dns/d' /etc/config/network
				uci add_list network.lan.dns=$vpnip
				uci commit network
				uci set dhcp.@dnsmasq[0].rebind_localhost='0'
				uci set dhcp.@dnsmasq[0].rebind_protection='0'
				uci commit dhcp
				ifup lan
				ifup lan6
				$APP_PATH/sysapp.sh set_smartdns
				/etc/init.d/odhcpd restart
			fi
		fi
	fi
	[ $(uci_get_by_name $NAME sysmonitor enable 0) == 0 ] && exit 0
	num=0
	while [ $num -le 10 ]; do
		sleep $sleep_unit
		[ $(uci_get_by_name $NAME sysmonitor enable 0) == 0 ] && exit 0
		let num=num+sleep_unit
		if [ -f "/tmp/sysmonitor" ]; then
			rm /tmp/sysmonitor
			num=50
		fi
	done
done
