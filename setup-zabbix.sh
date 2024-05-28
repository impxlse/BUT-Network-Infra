#!/bin/bash

# Made for use with Debian 11
# This script is used to install & setup a new Zabbix server
# along with its PostgreSQL database and Zabbix agents
# To use it, type setup-zabbix.sh { zabbix-server | zabbix-agent | psql-server }
# zabbix-server: Installs Zabbix 6.4 server/agent, PostgreSQL 15 client, Apache
# forces SSL on Apache, creates PostgreSQL database
# zabbix-agent: Adds the Zabbix 6.4 repository & install/configure Zabbix Agent with PSK
# psql-server: Installs PostgreSQL 15, create zabbix user & allow only SSL connections

if [[ $UID -ne 0 ]]; then
    echo 'This script must be run as root.'
    exit 1
fi

# Set the ip of the Zabbix server
zabbix_server_ip="192.168.1.6"

# Set PostgreSQL server, database & user to use for Zabbix
psql_server_ip="192.168.1.9"
psql_db="zabbix"
psql_user="zabbix"
psql_user_pw="nerfriven"

# Set the location of the pre-shared key file
# to be used for SSL connections between Zabbix agents & server
psk_location="/etc/zabbix/zabbix.psk"

# Where to store SSL certificate for Apache
cert_folder="/etc/ssl"
website_name="zabbix"



# Display the help
function show-help {
    echo -e "Usage: $(basename "$0") { zabbix-server | zabbix-agent | psql-server }\n" \
            "   zabbix-server|zs        Install Zabbix server, Apache, PostgreSQL Client\n" \
            "   zabbix-agent|za         Install Zabbix Agent\n" \
            "   psql-server|psql        Install PostgreSQL Server & Zabbix database"
}



function show-env {
	cat <<- EOF
		Zabbix server IP: $zabbix_server_ip
		PostgreSQL server IP: $psql_server_ip
		PostgreSQL database: $psql_db
		PostgreSQL user: $psql_user
		PostgreSQL password: $psql_user_pw
		Zabbix Agent PSK location: $psk_location
		Apache Certificate location: $cert_folder
		Apache Certificate name: $website_name (.pem/.key)
	EOF
	read -rp "Press any key to run setup"
}



# Add the Zabbix 6.4 Debian repository
function add-zabbix-repo {
    echo -e "\n----------Adding Zabbix repository----------"
    wget -O /tmp/zabbix.deb 'https://repo.zabbix.com/zabbix/6.4/debian/pool/main/z/zabbix-release/zabbix-release_6.4-1+debian11_all.deb'
    dpkg -i /tmp/zabbix.deb
    rm /tmp/zabbix.deb
}


function add-php-repo {
    echo -e "\n----------Adding PHP repository----------"
    sh -c 'echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list' 
    wget -O - https://packages.sury.org/php/apt.gpg | apt-key add - 
}


function add-psql-repo {
    echo -e "\n----------Adding PostgreSQL repository----------"
    sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
    wget -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
}

   
function zabbix-server-setup {
    echo "#####Running Zabbix server setup#####"
    add-php-repo
    add-zabbix-repo
    add-psql-repo
    apt update


    echo -e "\n----------Installing packages----------"
    apt install -y zabbix-server-pgsql zabbix-frontend-php php-pgsql zabbix-apache-conf zabbix-sql-scripts zabbix-agent postgresql-client


	echo -e "\n----------Creating Zabbix database----------"
    zcat /usr/share/zabbix-sql-scripts/postgresql/server.sql.gz | psql -h "$psql_server_ip" -U zabbix zabbix
  /etc/zabbix/zabbix_server.conf


	echo -e "\n----------Zabbix Server configuration----------"
    options=(
        [DBHost]="$psql_server_ip"
        [DBName]="$psql_db"
        [DBUSer]="$psql_user"
        [DBPassword]="$psql_user_pw"
    )
    
    for key in "${!options[@]}"; do
        value="${options[$key]}"
        sed -i -e "/# $key=/a $key=$value/" /etc/zabbix/zabbix_server.conf
		grep -E "^$key" /etc/zabbix/zabbix_server.conf
    done
	

	echo -e "\n----------Apache configuration----------"
	certfile="$cert_folder/$website_name.pem"
	keyfile="$cert_folder/$website_name.key"
	# Create self-signed certificate
	openssl req -new -x509 -nodes -out "$certfile" -keyout "$keyfile" -days 365 -subj '/C=FR/ST=Jaaj City/O=Jaaj Corp.'
    chown root:www-data "$keyfile"
    chmod 640 "$keyfile"
    cat <<- EOF
		Certificate file: $certfile
		Certificate key file: $keyfile
	EOF

	sed -i '/^Alias \/zabbix .*/d' /etc/zabbix/apache.conf
    # Redirect HTTP to HTTPS
    sed -i '/DocumentRoot/i <Location "\/">\n   Redirect permanent "https://%{HTTP_POST}%{REQUEST_URI}\n	</Location>' /etc/apache2/sites-available/000-default.conf
    cat <<- EOF
		Redirect HTTP to HTTPS
		/etc/apache2/sites-available/000-default.conf:
		$(grep -e 'Location' -e 'Redirect' /etc/apache2/sites-available/000-default.conf)
	EOF

	# Change Zabbix location to root of server & enable SSL
	cat <<- EOF
		Change Zabbix location to root of web server and enable SSL
		/etc/apache2/sites-available/default-ssl.conf:
	EOF

	declare -A opt=(
		[DocumentRoot]="/usr/share/zabbix"
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

	echo -e "\n----------Restarting & enabling Zabbix/Apache services----------"
    systemctl restart zabbix-server zabbix-agent apache2
    systemctl enable zabbix-server zabbix-agent apache2 
}



################################################
# Setup a new Zabbix Agent with PSK encryption #
################################################
function zabbix-agent-setup {
    echo "######Running Zabbix Agent setup#####"

    # Add Zabbix repository & install Zabbix Agent if version 6.4 is not installed
    if [[ "$(zabbix_agentd -V | head -n 1 | cut -d ' ' -f 4 | cut -d '.' -f -2)" != "6.4" ]]; then
        add-zabbix-repo # Add the APT repository
        echo -e "\n----------Updating APT repositories----------"
        apt update # Update repositories informations
        echo -e "\n----------Installing Zabbix Agent----------"
        apt install -y zabbix-agent # Install Zabbix Agent 6.4
    else
        echo -e "\nZabbix Agent 6.4 already installed."
    fi

    # Create a new pre-shared key for SSL communication between the agent & server
    echo -e "\n----------Generating Pre-shared key----------"
    touch "$psk_location" # Create an empty file to store the PSK
    chmod 640 "$psk_location" # Change the permissions to only allow owner & group to read it
    chown root:zabbix "$psk_location" # Set the owner to root and group to zabbix, zabbix & root can read it, but only root can modify it
    openssl rand -hex 256 > "$psk_location" # Generate a new 2048-bit PSK and store it into the newly created file
    echo "File location: $psk_location" # Display the location of the PSK file
    echo "PSK: $(cat "$psk_location")" # Display the PSK value

    # Edit Zabbix Agent configuration
    echo -e "\n----------Tweaking Zabbix Agent configuration file----------"
    declare -A options # Declare a dictionnary to store the options we want to change
    options=(
        [Server]="$zabbix_server_ip"
        [ServerActive]="$zabbix_server_ip"
        [Hostname]="$(hostname)"
        [TLSConnect]="psk"
        [TLSAccept]="psk"
        [TLSPSKIdentity]="$(hostname)"
        [TLSPSKFile]="$psk_location"
    )

    # Edit the configuration file for each option
    for key in "${!options[@]}"; do
        value="${options[$key]}"
        
		# Modify the configuration file accordingly if the option is already present or not 
        if grep -qE "^$key=" /etc/zabbix/zabbix_agentd.conf; then
	    sed -i -e "s~^$key=.*~$key=$value~" /etc/zabbix/zabbix_agentd.conf # Change the value if the option is already set
        else
            sed -i -e "/^# $key=/a $key=$value" /etc/zabbix/zabbix_agentd.conf # If the option is not set, add a new line following the comment paragraph concerning this option
        fi
		grep -E "^$key" /etc/zabbix_agentd.conf
    done

    # Restart Zabbix Agent service to apply changes
    echo -e "\n----------Enabling & restarting Zabbix Agent service----------"
    systemctl enable zabbix-agent
    if systemctl restart zabbix-agent; then

        # Display tips to configure this new host on the Zabbix Server front-end
        echo -e "\nYou can now add this host on the Zabbix Server: Data Collection > Hosts > Create host\n" \
                "Host\n" \
                "   Host name: $(hostname)\n" \
                "   Templates: Linux by Zabbix agent\n" \
                "   Host groups: Linux Servers\n" \
                "   Interfaces: Agent\n" \
                "Inventory\n" \
                "   Automatic\n" \
                "Encryption\n" \
                "   Connections to host: PSK\n" \
                "   Connections from host: PSK\n" \
                "   PSK identity: $(hostname)\n" \
                "   PSK: $(cat "$psk_location")"
    fi
}



function zabbix-psql-server-setup {
    echo -e "-----\nRunning PostgreSQL server setup\n-----"
    add-psql-repo
    apt update

    echo -e "-----Installing PostgreSQL server\n-----"
    apt install -y postgresql
    
    echo -e "-----\nCreating zabbix user & database\n-----"
    sudo -u postgres createuser --pwprompt "$psql_user"
    sudo -u postgres createdb -O "$psql_db" "$psql_user"

	# Allow remote connetions to zabbix database
	echo -e "\n-----Allowing remote connections to Zabbix database-----"
	psql_cf="/etc/postgresql/15/main"
	pg_hba_entry="hostssl $psql_db          $psql_user          192.168.1.0/24          scram-sha-256"
	if grep -P "^hostssl.*$psql_db.*$psql_user" "$psql_cf/pg_hba.conf"; then
		sed -i "s~^hostssl.*$psql_db.*$psql_user.*~$pg_hba_entry~" "$psql_cf/pg_hba.conf"
	else
		echo "$pg_hba_entry" >> "$psql_cf/pg_hba.conf"
	fi
	echo "$psql_cf/pg_hba.conf:"
	grep -E "^hostssl $psql_db" "$psql_cf/pg_hba.conf"

	sed -Ei "s~^#?listen_addresses = \S*~listen_addresses = '192.168.1.0/24'~" "$psql_cf/postgresql.conf"
	echo "$psql_cf/postgresql.conf:"
	grep -P "^#?listen_addresses" "$psql_cf/postgresql.conf"
}



# Run the corresponding function to the first parameter
case "$1" in
    zabbix-agent|za)
		show-env
        zabbix-agent-setup;;
    zabbix-server|zs)
		show-env
		zabbix-server-setup;;
    psql-server|psql)
		show-env
		zabbix-psql-server-setup;;
    *)
        echo "Error: Wrong argument."
        show-help
        exit 1;;
esac

