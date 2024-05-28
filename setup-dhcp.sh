#!/bin/bash

# This script configure the network
# installs isc-dhcp-server
# and set the subnets & static leases

if [[ $UID -ne 0 ]]; then
	echo "This script must be run as root."
	exit 1
fi



echo "#####Running DHCP Server setup#####"

# Source the file containing the list of VMs & subnets
source "$(dirname "$0")/network-structure.sh" || echo "Can't find network-structure.sh"; exit 1



# Append a static lease to end of dhcpd.conf file
function addStaticLease {
    hostname="$1"
    macaddr="$2"
    ipv4addr="$3"
    cat <<- EOF >> /etc/dhcp/dhcpd.conf

		host $hostname {
		  hardware ethernet $macaddr;
		  fixed-address $ipv4addr;
		}
	EOF
}



# Append a subnet to end of dhcpd.conf file
function addSubnet {
    subnet="$1"
    netmask="$2"
    gateway="$3"
    broadcast="$4"
	cat <<- EOF >> /etc/dhcp/dhcpd.conf
		subnet $subnet netmask $netmask {
		  option routers $gateway;
		  option broadcast-address $broadcast;
		}
	EOF
	if [[ "$subnet" != "192.168.1.0" ]]; then
		range="$(echo "$subnet" | cut -d '.' -f -3).20"
		sed -i "s/^subnet $subnet/a   $range;/" /etc/dhcp/dhcpd.conf
	fi
}



# Configure the DHCP server network interface
dhcp_if="enp0s2"
dhcp_ip="$(echo "${vms[dhcp]}" | cut -d ';' -f 2)/24"
dhcp_network_id="$(echo "${vms[dhcp]}" | cut -d ';' -f 4)"
dhcp_gateway="$(echo "${networks[$dhcp_network_id]}" | cut -d ';' -f 3)"
dhcp_broadcast="$(echo "${networks[$dhcp_network_id]}" | cut -d ';' -f 4)"
cat << EOF > /etc/network/interfaces
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

allow-hotplug $dhcp_if
iface $dhcp_if inet static
	address $dhcp_ip
	gateway $dhcp_gateway
	broadcast $dhcp_broadcast
EOF
echo "-----DHCP Server network configuration-----"
cat /etc/network/interfaces


# Configure DNS
cat << EOF > /etc/resolv.conf
nameserver $dns_shared
nameserver 1.1.1.1
EOF
cat /etc/resolv.conf


# Apply changes
echo "Restarting $dhcp_if interface"
ifdown "$dhcp_if"
ifup "$dhcp_if"



# Install the package
apt install -y isc-dhcp-server


echo "-----ISC DHCP server configuration-----"
# Set the common DN & DNS
sed -i -E "s/^#?option domain-name-servers.*/option domain-name-servers $dns_shared;/" /etc/dhcp/dhcpd.conf
sed -i -E "s/^#?option domain-name.*/option domain-name \"$dn_shared\";/" /etc/dhcp/dhcpd.conf
grep -E '^option domain-name' /etc/dhcp/dhcpd.conf



# Interfaces to listen to
sed -i -e "s/^INTERFACESv4=.*/INTERFACESv4=\"$dhcp_if\"/" /etc/default/isc-dhcp-server
echo "Listen on interfaces(/etc/default/isc-dhcp-server): $(grep -E '^INTERFACESv4=' /etc/default/isc-dhcp-server)"



# Delete all existing hosts & subnets
sed ':again;$!N;$!b again; s/\nsubnet.*{[^}]*}//g' /etc/dhcp/dhcpd.conf
sed ':again;$!N;$!b again; s/\nhost.*{[^}]*}//g' /etc/dhcp/dhcpd.conf



# Declare subnets in dhcpd.conf file
echo "-----Setting subnets-----"
for network in "${networks[@]}"; do
    subnet="$(echo "$network" | cut -d ';' -f 1)"
    netmask="$(echo "$network" | cut -d ';' -f 2)"
    gateway="$(echo "$network" | cut -d ';' -f 3)"
    broadcast="$(echo "$network" | cut -d ';' -f 4)"
    dns="$(echo "$network" | cut -d ';' -f 5)"
    
    addSubnet "$subnet" "$netmask" "$gateway" "$broadcast" "$dns"
done



# Declare static leases for VMs
echo "-----Setting static leases-----"
for vm in "${!vms[@]}"; do
    key="$vm"
    value="${vms[$key]}"
    
    hostname="$key"
    ipv4addr="$(echo "$value" | cut -d ';' -f 2)"
    macaddr="$(echo "$value" | cut -d ';' -f 3)"

    addStaticLease "$hostname" "$macaddr" "$ipv4addr"
done



# Restart dhcp daemon to apply changes
echo "Restarting isc-dhcp-server service"
systemctl restart isc-dhcp-server.service
