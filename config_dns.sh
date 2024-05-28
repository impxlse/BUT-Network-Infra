#!/bin/bash

# A utiliser en root
# fichier qui paramettre le serveur dns

if [[ $UID -ne 0 ]]; then
	echo "This script must be run as root."
	exit 1
fi


apt -y install bind9




# configuration named.conf.default-zones

echo '
zone "jaaj.local" {
	type master;
	file "/etc/bind/db.jaaj.local";
};

zone "1.168.192.in-addr.arpa" {
	type master;
	file "/etc/bind/db.192.168.1";
};

zone "0.168.192.in-addr.arpa" {
	type master;
	file "/etc/bind/db.192.168.0";
};' >> /etc/bind/named.conf.default-zones





# configuration du réseau 192.168.0.x   #zone démilitarisée

echo '$TTL	600

@	IN	SOA	dns.jaaj.local.	root.jaaj.local.	(
				20140901
				3600
				600
				86400
				600	)

@	IN	NS	dns.jaaj.local.

1	IN	PTR	router.jaaj.local.
2	IN	PTR	web-inter.jaaj.local.
3	IN	PTR	psql-inter.jaaj.local.' >> /etc/bind/db.192.168.0




echo '$TTL	600

@	IN	SOA	dns.jaaj.local.	root.jaaj.local.	(
				20140901
				3600
				600
				86400
				600	)

@	IN	NS	dns.jaaj.local.

1	IN	PTR	router.jaaj.local.
2	IN	PTR	dhcp.jaaj.local.
3	IN	PTR dns.jaaj.local.
4	IN	PTR ldap.jaaj.local.
5	IN	PTR logging.jaaj.local.
6	IN	PTR monitoring.jaaj.local.
7	IN	PTR nfs.jaaj.local.
8	IN	PTR web-intra.jaaj.local.
9	IN	PTR psql-intra.jaaj.local.' >> /etc/bind/db.192.168.1






echo '$TTL	600

@	IN	SOA	dns.jaaj.local.	root.jaaj.local.	(
				20140901
				3600
				600
				86400
				600	)

@	IN	NS	dns.jaaj.local.

router.jaaj.local.		IN	A	192.168.1.1
dhcp.jaaj.local.		IN	A	192.168.1.2
dns.jaaj.local.			IN	A	192.168.1.3
ldap.jaaj.local.		IN	A	192.168.1.4
logging.jaaj.local.		IN	A	192.168.1.5
monitoring.jaaj.local.	IN	A	192.168.1.6
nfs.jaaj.local.			IN	A	192.168.1.7
web-intra.jaaj.local.	IN	A	192.168.1.8
psql-intra.jaaj.local.	IN	A	192.168.1.9

router.jaaj.local.		IN	A	192.168.0.1
web-inter.jaaj.local.	IN	A	192.168.0.2
psql-inter.jaaj.local.	IN	A	192.168.0.3' >> /etc/bind/db.jaaj.local



# modifier les parametres de démarage de bind (parce que le réseau ne supporte pas l'ipv6)

echo "#" > /etc/default/named
echo '# run resolvconf?
RESOLVCONF=no

# startup options for the server
OPTIONS="-u bind -4"' >> /etc/default/named

systemctl reload named
