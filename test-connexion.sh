#!/bin/bash

source "./network-structure.sh" || exit 1

PING_HOST="142.250.179.174"
PING_COUNT=3
TRACEROUTE_HOST="142.250.179.174"
DNS_SERVER="192.168.1.3"
LDAP_SERVER="192.168.1.4"

# Output colors
red='\033[0;31m'
green='\033[0;32m'
nc='\033[0m'


echo "Testing network connectivity..."

echo   "
*************************************************************************
Le script de connectivité est en cours d'exécution, veuillez patienter... 
*************************************************************************"

# Ping
for vm in "${vms[@]}" "$router_ifaces"; do
	ping_target="$(echo "$vm" | cut -d ';' -f 2)"
	echo -n "Pinging $ping_target..."
	if ping -c $PING_COUNT "$ping_target" > /dev/null; then
		echo -e "${green}Success${nc}"
	else
		echo -e "${red}Fail${nc}"
	fi
done

echo -n "Pinging $PING_HOST (google.com)..."
if ping -c $PING_COUNT $PING_HOST > /dev/null; then
    echo -e "${green}Ping test passed!${nc}"
else
    echo -e "${red}Ping test failed${nc}"
fi



# DNS
for host in "${!vms[@]}" "router"; do
	echo -n "Testing DNS lookup for $host..."
	if nslookup "$host" "$DNS_SERVER" > /dev/null; then
		echo -e "${green}Success${nc}"
	else
		echo -e "${red}Fail${nc}"
	fi
done


echo -n "Testing DNS lookup for google.com..."
if nslookup google.com $DNS_SERVER > /dev/null; then
    echo -e "${green}DNS test passed!${nc}"
else
    echo -e "${red}DNS test failed!${nc}"
fi



# Traceroute
if [[ $UID -ne 0 ]]; then
	echo "Not running as root, skipping traceroute."
else
	echo -n "Tracerouting $TRACEROUTE_HOST..."
	if traceroute $TRACEROUTE_HOST > /dev/null; then
		echo -e "${green}Traceroute test passed!${nc}"
	else
		echo -e "${red}Traceroute test failed!${nc}"
	fi
fi



# LDAP
echo -n "Trying LDAPS connectivity to $LDAP_SERVER..."
if ldapwhoami -x -H "ldaps://$LDAP_SERVER" > /dev/null; then
    echo -e "${green}LDAP test passed!${nc}"
else
    echo -e "${red}LDAP test failed!${nc}"
fi

