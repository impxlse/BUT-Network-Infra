#!/bin/bash

# A utiliser en root
if [[ $UID -ne 0 ]]; then
	echo "This script must be run as root."
	exit 1
fi

apt update
apt install -y nftables


# configuration des addresses IP

dossier=/etc/network/interfaces

echo source /etc/network/interfaces.d/* > $dossier 
echo "" >> $dossier
echo "# Loopback" >>$dossier
echo "auto lo" >> $dossier
echo "iface lo inet loopback" >> $dossier
echo "" >> $dossier
echo "# The primary network interface" >> $dossier
echo "allow-hotplug enp0s2" >> $dossier
echo "iface enp0s2 inet static" >> $dossier
echo "        address 192.168.14.231/24" >> $dossier
echo "        gateway 192.168.14.3" >> $dossier
echo "        broadcast 192.168.14.255" >> $dossier

# Automatic start up
echo "        pre-up nft -f /root/nftables/nftables.rules" >> $dossier

echo "" >> $dossier
echo "
allow-hotplug enp0s3
iface enp0s3 inet static
        address 192.168.0.1/24
        broadcast 192.168.0.255" >> $dossier



echo "" >> $dossier
echo "allow-hotplug enp0s4" >> $dossier
echo "iface enp0s4 inet dhcp" >> $dossier

echo "" >> $dossier
echo '
allow-hotplug enp0s5
iface enp0s5 inet dhcp' >> $dossier

# Nftables

    # Activation du nat
echo "1" > /proc/sys/net/ipv4/ip_forward

cat <<EOF > /root/nftables/filtrage_nat

# Activation du filtrage nat
add table filtrage_nat
add chain filtrage_nat prerouting {type nat hook prerouting priority 0 ; }
add chain filtrage_nat postrouting {type nat hook postrouting priority 0 ; }

# redirection de ports
add rule filtrage_nat prerouting iif enp0s2 tcp dport 80 dnat 192.168.0.2
add rule filtrage_nat prerouting iif enp0s2 tcp dport 443 dnat 192.168.0.2
add rule filtrage_nat prerouting iif enp0s2 tcp dport 5432 dnat 192.168.0.3

# accès "transparent" à l'exterieur

# accès serveurs intranet à internet
add rule filtrage_nat postrouting ip saddr 192.168.1.0/24 oif enp0s2 snat 192.168.14.231

# accès serveurs publicc à internet
add rule filtrage_nat postrouting ip saddr 192.168.0.0/24 oif enp0s2 snat 192.168.14.231

# accès postes utilisateurs / imprimantes à internet
add rule filtrage_nat postrouting ip saddr 192.168.2.0/24 oif enp0s2 snat 192.168.14.231


#Les postes usinages n'ont pas d'accès à internet car ils tournent sur debian 8, une distribution morte.

EOF

cat <<EOF > /root/nftables/filtrage_stateless
#!/usr/sbin/nft -f

#initialisation du filtrage stateless
#
add table filter
add chain filter input {type filter hook input priority 0; policy accept;}
add chain filter output {type filter hook output priority 0; policy accept;}
add chain filter forward {type filter hook forward priority 0; policy accept;}


#selection des programmes autorisés à passer.
#       table input
add rule filter input ip protocol icmp icmp type echo-request limit rate 5/second accept
add rule filter input tcp dport ssh accept
add rule filter input tcp dport 88 accept       # kerberos
add rule filter input tcp dport 749 accept      # kerberos
add rule filter input tcp dport 53 accept
add rule filter input tcp dport http accept
add rule filter input tcp dport https accept
add rule filter input tcp dport 10050 accept  # rsyslog
add rule filter input tcp dport 636 accept      # ldap
add rule filter input udp dport 88 accept       # kerberos
add rule filter input udp dport 749 accept      # kerberos
add rule filter input udp dport 68 accept  # dhcp
add rule filter input udp dport 67 accept
add rule filter input udp dport 43364 accept  # zabbix
add rule filter input udp dport 53 accept
add rule filter input ct state established accept

#       table output
add rule filter output ip protocol icmp icmp type echo-request accept
add rule filter output tcp dport ssh accept
add rule filter output tcp dport 88 accept      # kerberos
add rule filter output tcp dport 749 accept     # kerberos
add rule filter output tcp dport 53 accept
add rule filter output tcp dport http accept
add rule filter output tcp dport https accept
add rule filter output tcp dport 10050 accept
add rule filter output tcp dport 636 accept     # ldap
add rule filter output udp dport 88 accept      # kerberos
add rule filter output udp dport 749 accept     # kerberos
add rule filter output udp dport 68 accept			# dhcp
add rule filter output udp dport 67 accept
add rule filter output udp dport 43364 accept		# zabbix
add rule filter output udp dport 53 accept
add rule filter output ct state established accept

#       table forward
#       On fait confiance aux utilisateurs de notre réseau pour ne pas faire de bétises.


#Solution finale, tue tout ce qui n'as pas été choisis.
#
add rule filter input drop
add rule filter output drop
#add rule filter forward drop

EOF

# Table nft
chmod u+x /root/nftables/filtrage_nat
chmod u+x /root/nftables/filtrage_stateless
/root/nftables/filtrage_nat
/root/nftables/filtrage_stateless
nft list ruleset > nftables.rules


# config de isc-dhcp-relay

apt install -y isc-dhcp-relay

cat <<EOF > /etc/default/isc-dhcp-relay
# Defaults for isc-dhcp-relay initscript
# sourced by /etc/init.d/isc-dhcp-relay
# installed at /etc/default/isc-dhcp-relay by the maintainer scripts

#
# This is a POSIX shell fragment
#

# What servers should the DHCP relay forward requests to?
SERVERS="192.168.1.2"

# On what interfaces should the DHCP relay (dhrelay) serve DHCP requests?
INTERFACES="enp0s3 enp0s4 enp0s5"

# Additional options that are passed to the DHCP relay daemon?
OPTIONS=""
EOF

systemctl restart isc-dhcp-relay


