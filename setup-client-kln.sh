#!/bin/bash

# For Debian 11
# This script installs and configure required packages
# to use Kerberos authentification + LDAP authorization
# as well as NFS homedirs

if [[ $UID -ne 0 ]]; then
	echo "This script must be run as root."
	exit 1
fi

base_dc="dc=jaaj,dc=local" # Distinguished name of the LDAP directory
base_dn="jaaj.local"
sudo_ou="SUDOers" # Sudoers organizational unit name
ldap_fqdn="ldap.$base_dn" # FQDN of the LDAP server
ldap_ip="192.168.1.4" # IP address of the LDAP server
nfs_ip="192.168.1.7" # IP address of the NFS server
mount_point="/home" # Where to mount the NFS drive
mount_opt="$nfs_ip:$mount_point  $mount_point   nfs4      rw,sync,hard,_netdev,sec=krb5p  0     0" # Option for NFS mount



function kerberos-setup {
	echo -e "\n-----Kerberos client setup-----"

	echo "Configuring etc/krb5.conf:"
	cat <<- EOF > /etc/krb5.conf 
		[libdefaults]
	      default_realm = ${base_dn^^}

		[realms]
		  ${base_dn^^} = {
		    admin_server = $ldap_fqdn
		    kdc = $ldap_fqdn
		    default_principal_flags = +preauth
		  }

		[domain_realm]
		  $base_dn = ${base_dn^^}
		  .$base_dn = ${base_dn^^}

		[logging]
		  kdc = SYSLOG:NOTICE
		  admin_server = SYSLOG:NOTICE
		  default = SYSLOG:NOTICE
	EOF
	cat /etc/krb5.conf


	# Finally, copy kbclient.keytab from the server to the client using SCP or similar, then put it in place with correct permissions: 
	echo -e "\nCopying keytab:"
	scp root@ldap:kbclient.keytab /tmp/
	install -b -o root -g root -m 600 /tmp/kbclient.keytab /etc/krb5.keytab
	rm /tmp/kbclient.keytab


	echo -e "\nDisable idmapping in /etc/modprobe.d/nfsd.conf:"
	cat <<- EOF > /etc/modprobe.d/nfsd.conf
		options nfs nfs4_disable_idmapping=0
		options nfsd nfs4_disable_idmapping=0
	EOF
	cat /etc/modprobe.d/nfsd.conf


	# To fully use idmapping, make sure the domain is configured in /etc/idmapd.conf on both the server and the client: 
	echo -e "\nConfiguring /etc/idmapd.conf:"
	cat <<- EOF > /etc/idmapd.conf
		[General]
		Verbosity = 0
		Pipefs-Directory = /run/rpc_pipefs
		Domain = $base_dn

		[Mapping]
		Nobody-User = nobody
		Nobody-Group = nogroup
	EOF
	cat /etc/idmapd.conf


	if [[ "$(hostname -i | cut -d '.' -f -3)" = "192.168.1" ]]; then
		echo "Host is on network 192.168.1.0/24, restricting ssh access to admin group"
		if grep -P "^AllowGroups" /etc/ssh/sshd_config; then
			sed -i 's/^AllowGroups.*/AllowGroups admin sae/' /etc/ssh/sshd_config
		else
			echo "AllowGroups admin sae" >> /etc/ssh/sshd_config
		fi
		grep -P "^AllowGroups" /etc/ssh/sshd_config
	fi
		

	echo -e "\nRestarting nfs-client.target and rpc-svcgssd"
	systemctl restart nfs-client.target rpc-svcgssd

	klist -ke /etc/krb5.keytab
}



function ldap-setup {
	echo -e "\n-----LDAP client setup-----"

	# Tell sudo where to look for LDAP sudo users
	echo -e "\nSudo configuration (/etc/sudo-ldap.conf):"
    declare -A opt_ldap
    opt_ldap=(
        [URI]="ldaps://$ldap_ip/"
        [BASE]="$base_dc"
        [SUDOERS_BASE]="$sudo_ou,$base_dc"
        [TLS_REQCERT]="allow"
    )
	# Set options in /etc/sudo-ldap.conf
    for key in "${!opt_ldap[@]}"; do
        value="${opt_ldap[$key]}"
        if grep -qE "^#?$key" /etc/sudo-ldap.conf; then
            sed -Ei "s~^#?$key.*~$key\t$value~" /etc/sudo-ldap.conf
        else
            echo -e "$key\t$value" >> /etc/sudo-ldap.conf
        fi
		grep -E "^$key" /etc/sudo-ldap.conf
    done


	# NSLCD configuration
	# Set LDAP server location and enable TLS
	echo -e "\nNSLCD configuration (/etc/nslcd.conf):"
    declare -A opt_nslcd
    opt_nslcd=(
        [uri]="ldaps://$ldap_ip/"
        [base]="$base_dc"
        [ssl]="on"
        [tls_reqcert]="allow"
    )
	# Set options in /etc/nslcd.conf
    for key in "${!opt_nslcd[@]}"; do
        value="${opt_nslcd[$key]}"
        if grep -qE "^#?$key" /etc/nslcd.conf; then
            sed -Ei "s~^#?$key.*~$key $value~" /etc/nslcd.conf
        else
            echo "$key $value" >> /etc/nslcd.conf
        fi
		grep -E "^$key" /etc/nslcd.conf
    done


	# NSS configuration
	# Tell NSS to look for LDAP entries for passwd, group & sudoers
	echo -e "\nNSS configuration (/etc/nsswitch.conf):"
    opt_nss=(
		passwd
        group
		sudoers
	)
	# Set options in /etc/nsswitch.conf
    for key in "${opt_nss[@]}"; do
		if grep -qP "^$key:(?!.*ldap)" /etc/nsswitch.conf; then
            sed -Ei "/^$key:/ s/$/ ldap/" /etc/nsswitch.conf
		elif ! grep -qE "^$key:" /etc/nsswitch.conf; then
            echo -e "$key:  \tldap" >> /etc/nsswitch.conf
        fi
		grep -E "^$key:" /etc/nsswitch.conf
    done

	echo -e "\nRestarting nslcd service"
	# Restart service to apply changes
    systemctl restart nslcd
}



function nfs-setup {
	# Client side
	# Démarre le service nfs
	echo -e "\n-----NFS client setup-----"
	echo "Enabling & starting nfs-client.target"
	systemctl enable --now nfs-client.target
	
	# Montage automatique
	if grep -E "^$nfs_ip:$mount_point" /etc/fstab; then
	    sed -i "s~^$nfs_ip:$mount_point.*~$mount_opt~" /etc/fstab
	else
	    echo "$mount_opt" >> /etc/fstab
	fi
	echo "Adding mount point to /etc/fstab: $(grep "$nfs_ip:$mount_point" /etc/fstab)"

	echo "Mounting to $mount_point"
	mount /home
}



cat << EOF
##### Kerberos + LDAP + NFS client setup #####
  LDAP directory DN: $base_dc
  LDAP Sudoers OU: $sudo_ou
  LDAP Server FQDN: $ldap_fqdn
  LDAP Server IP: $ldap_ip
  Domain name: $base_dn
  NFS Server IP: $nfs_ip
  NFS drive mount point: $mount_point
  Mount options: $mount_opt
EOF

read -rp "Press any key to continue"

DEBIAN_FRONTEND=noninteractive apt install -y libnss-ldapd sudo-ldap krb5-user libpam-krb5 nfs-common
ldap-setup
kerberos-setup
nfs-setup
