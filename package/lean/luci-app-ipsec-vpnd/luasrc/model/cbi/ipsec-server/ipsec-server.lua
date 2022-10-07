
mp = Map("ipsec", translate("L2TP/IPSec VPN Server"))
mp.description = translate("L2TP/IPSec VPN connectivity using the native built-in VPN Client on iOS or Andriod (IKEv1 with PSK and Xauth)")

mp:section(SimpleSection).template  = "ipsec/ipsec_status"

s = mp:section(NamedSection, "ipsec", "service")
s.anonymouse = true

enabled = s:option(Flag, "enabled", translate("Enable"))
enabled.default = 0
enabled.rmempty = false

l2tpd = s:option(Value, "l2tpd", translate("L2TPD IP"))
l2tpd.datatype = "ip4addr"
l2tpd.optional = false
l2tpd.rmempty = false

remoteip = s:option(Value, "remoteip", translate("L2TP Client IP"))
remoteip.rmempty = true
remoteip.default = "192.168.8.210-220"

clientip = s:option(Value, "clientip", translate("VPN Client IP"))
clientip.datatype = "ip4addr"
clientip.description = translate("LAN DHCP reserved started IP addresses with the same subnet mask")
clientip.optional = false
clientip.rmempty = false

clientdns = s:option(Value, "clientdns", translate("VPN Client DNS"))
clientdns.datatype = "ip4addr"
clientdns.description = translate("DNS using in VPN tunnel.Set to the router's LAN IP is recommended")
clientdns.optional = false
clientdns.rmempty = false


secret = s:option(Value, "secret", translate("Secret Pre-Shared Key"))
secret.password = true

local apply = luci.http.formvalue("cbi.apply")
if apply then
	local bbrbox = luci.http.formvalue("cbid.ipsec.ipsec.enabled")
	if bbrbox then
		luci.sys.exec("ipsec reload")
		luci.sys.exec("ipsec restart")
	else
		luci.sys.exec("/etc/init.d/ipsec start")
		luci.sys.exec("ipsec stop")
	end
end

return mp
