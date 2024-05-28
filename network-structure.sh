#!/bin/bash

dn_shared="jaaj.local" # DN to use
dns_shared="1.1.1.1" # DNS to use
mac_base="52:55:55:55" # Base MAC address for virtuals machines
img_path="$HOME/SAE4" # Location of VMs img files

# Array of networks
#   id      subnet     netmask       gateway     broadcast    dns        mac_base        mcast
networks=(
    [0]="192.168.0.0;255.255.255.0;192.168.0.1;192.168.0.255;$dns_shared;$mac_base:00;225.0.0.0:5555"
    [1]="192.168.1.0;255.255.255.0;192.168.1.1;192.168.1.255;$dns_shared;$mac_base:01;225.0.0.1:5555"
    [2]="192.168.2.0;255.255.255.0;192.168.2.1;192.168.2.255;$dns_shared;$mac_base:02;225.0.0.2:5555"
    [3]="192.168.3.0;255.255.255.0;192.168.3.1;192.168.3.255;$dns_shared;$mac_base:03;225.0.0.3:5555"
)



# Router interfaces
#    nr     img_name      ipv4             macaddr                          network_id
router_ifaces=(
    [0]="vm-router.img;192.168.0.1;$(echo "${networks[0]}" | cut -d ';' -f 6):01;0"
    [1]="vm-router.img;192.168.1.1;$(echo "${networks[1]}" | cut -d ';' -f 6):01;1"
    [2]="vm-router.img;192.168.2.1;$(echo "${networks[2]}" | cut -d ';' -f 6):01;2"
    [3]="vm-router.img;192.168.3.1;$(echo "${networks[3]}" | cut -d ';' -f 6):01;3"
)



# Array of VMs
declare -A vms
# hostname    img_name     ipv4                 macaddr                     network_id
vms=(
    [dhcp]="vm-dhcp.img;192.168.1.2;$(echo "${networks[1]}" | cut -d ';' -f 6):02;1"
    [dns]="vm-dns.img;192.168.1.3;$(echo "${networks[1]}" | cut -d ';' -f 6):03;1"
    [ldap]="vm-ldap.img;192.168.1.4;$(echo "${networks[1]}" | cut -d ';' -f 6):04;1"
    [logging]="vm-logging.img;192.168.1.5;$(echo "${networks[1]}" | cut -d ';' -f 6):05;1"
    [monitoring]="vm-monitoring.img;192.168.1.6;$(echo "${networks[1]}" | cut -d ';' -f 6):06;1"
    [nfs]="vm-nfs.img;192.168.1.7;$(echo "${networks[1]}" | cut -d ';' -f 6):07;1"
    [web-intra]="vm-web-intra.img;192.168.1.8;$(echo "${networks[1]}" | cut -d ';' -f 6):08;1"
    [psql-intra]="vm-psql-intra.img;192.168.1.9;$(echo "${networks[1]}" | cut -d ';' -f 6):09;1"
	[web-inter]="vm-web-inter.img;192.168.0.2;$(echo "${networks[0]}" | cut -d ';' -f 6):02;0"
    [psql-inter]="vm-psql-inter.img;192.168.0.3;$(echo "${networks[0]}" | cut -d ';' -f 6):03;0"
)
