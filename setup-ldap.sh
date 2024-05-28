#!/bin/bash

# Made for Debian 11
# This script installs slapd, enable & force SSL and create an "admin" group
# SUDO for LDAP users and LAM frontend can be installed optionally

if [[ $UID -ne 0 ]]; then
	echo "This script must be run as root."
    exit 1
fi

ldap_server_ip="192.168.1.4"
base_dn="dc=jaaj,dc=local"
sudo_ou="SUDOers"
sudo_group="admin"



function server-setup {
	read -r -p "Install sudo-ldap (y/n)? " sudo_ans
	while [[ "$sudo_ans" != "y" && "$sudo_ans" != "n" ]]; do
		read -r -p "Install sudo-ldap (y/n)? " sudo_ans
	done
	
	read -r -p "Install LAM (y/n)? " lam_ans
	while [[ "$lam_ans" != "y" && "$lam_ans" != "n" ]]; do
		read -r -p "Install LAM (y/n)? " lam_ans
	done

	pkgs=(slapd)
	if [[ "$sudo_ans" = "y" ]]; then
		pkgs+=("sudo-ldap")
	fi
	if [[ "$lam_ans" = "y" ]]; then
		pkgs+=("ldap-account-manager")
	fi

	# Install the OpenLDAP package
	apt install -y ${pkgs[@]}

	# SSL configuration
	certfile="/etc/ssl/slapd.pem" # Where to store certificate
	keyfile="/etc/ssl/slapd.key" # Where to store certificate key
	openssl req -new -x509 -nodes -out "$certfile" -keyout "$keyfile" -days 365 -subj '/C=FR/ST=Jaaj City/O=Jaaj Corp.' # Create self-signed certificate
	chown root:openldap "$keyfile"
	chmod 640 "$keyfile"

    ldapmodify -Y EXTERNAL -H ldapi:/// <<- EOF
		dn: cn=config
		add: olcPasswordHash
		olcPasswordHash: {CRYPT}
		olcPasswordCryptSaltFormat: \$6\$rounds=500000\$%.86s
		-
		changeType: modify
		replace: olcTLSCertificateKeyFile
		olcTLSCertificateKeyFile: $keyfile
		-
		replace: olcTLSCertificateFile
		olcTLSCertificateFile: $certfile
	EOF

	sed -i -e 's~^SLAPD_SERVICES=.*~SLAPD_SERVICES="ldap:///127.0.0.1:389 ldapi:/// ldaps:///"~'

	# Create people & groups objects
    ldapadd -xWD "cn=admin,$base_dn" <<- EOF
		dn: ou=people,$base_dn
		objectClass: organizationalUnit
		objectClass: top
		ou: people

		dn: ou=groups,$base_dn
		objectClass: organizationalUnit
		objectClass: top
		ou: groups
	EOF

	systemctl restart slapd

	if [[ "$sudo_ans" = "y" ]]; then
		sudo-setup
	fi
	if [[ "$lam_ans" = "y" ]]; then
		lam-setup
	fi
}



function lam-setup {
	# LAM web frontend configuration
	cat <<- EOF

		-----LDAP Account Manager configuration-----
		Creating SSL certificate
	EOF
 	certfile="/etc/ssl/apache.pem" # Where to store certificate
	keyfile="/etc/ssl/apache.key" # Where to store certificate key
	# Create self-signed certificate
	openssl req -new -x509 -nodes -out "$certfile" -keyout "$keyfile" -days 365 -subj '/C=FR/ST=Jaaj City/O=Jaaj Corp.'
	chown root:www-data "$keyfile"
	chmod 640 "$keyfile"
	cat <<- EOF
		Certificate file: $certfile
		Certificate key file: $keyfile
	EOF


	# Apache configuration
	echo "Configuring Apache"
	sed -i '/^Alias \/lam .*/d' /etc/ldap-account-manager/apache.conf
	# Redirect HTTP to HTTPS
	sed -i '/DocumentRoot/i <Location "\/">\n	Redirect permanent "https://%{HTTP_POST}%{REQUEST_URI}\n	</Location>' /etc/apache2/sites-available/000-default.conf
	cat <<- EOF
		Redirect HTTP to HTTPS
		/etc/apache2/sites-available/000-default.conf:
		$(grep -e 'Location' -e 'Redirect' /etc/apache2/sites-available/000-default.conf)
	EOF

	# Change LAM location to root of server & enable SSL
	cat <<- EOF
		Change LAM location to root of web server and enable SSL
		/etc/apache2/sites-available/default-ssl.conf:
	EOF
	declare -A opt=(
		[DocumentRoot]="/usr/share/ldap-account-manager"
		[SSLEngine]="on"
		[SSLCertificateFile]="$certfile"
		[SSLCertificateKeyFile]="$keyfile"
	)
	for key in "${!opt[@]}"; do
		value="${opt[$key]}"
		sed -Ei "s~#?$key.*~$key $value~" /etc/apache2/sites-available/default-ssl.conf
		grep -P "\t+$key" /etc/apache2/sites-available/default-ssl.conf
	done

	echo "Enable sites 000-default.conf & default-ssl.conf, and SSL module"
	a2ensite 000-default.conf
	a2ensite default-ssl.conf
	a2enmod ssl
	echo "Restart apache2 to apply changes"
	systemctl restart apache2
}



function sudo-setup {
	# Configure OpenLDAP server to add LDAP users/groups with sudo privileges
	cat <<- EOF

		-----Importing SUDO schema to slapd-----
	EOF
	ldapadd -Y EXTERNAL -H ldapi:/// -f "/usr/share/doc/sudo-ldap/schema.olcSudo" # Import sudo schema to LDAP server
	cat <<- EOF
		Sudo ou: $sudo_ou
		Sudo group: $sudo_group
	EOF
	# Create necessary entries to use sudo
	ldapadd -xWD "cn=$sudo_group,$base_dn" <<- EOF
		dn: ou=$sudo_ou,$base_dn
		objectClass: organizationalUnit
		objectClass: top
		ou: $sudo_ou

		dn: cn=defaults,ou=$sudo_ou,$base_dn
		objectClass: sudoRole
		cn: defaults
		sudoOption: env_keep+=SSH_AUTH_SOCK

		dn: $base_dn
		add: olcDbIndex
		olcDbIndex: sudoUser eq

		dn: cn=%$sudo_group,ou=$sudo_ou,$base_dn
		objectClass: sudoRole
		cn: %$sudo_group
		sudoUser: %$sudo_group
		sudoHost: ALL
		sudoRunAsUser: ALL
		sudoRunAsGroup: ALL
		sudoCommand: ALL 
	EOF
}



echo "##### LDAP Server setup #####"
cat <<- EOF
  LDAP server ip: $ldap_server_ip
  Base DN: $base_dn
  SUDO Organizational Unit name: $sudo_ou
  SUDO group: $sudo_group
EOF

server-setup
