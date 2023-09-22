#!/bin/bash

# Check the operating system
os=$(cat /etc/os-release | grep -oP '^ID=\K\w+')

if [ "$os" != "debian" ] && [ "$os" != "ubuntu" ]; then
    echo "Error: This script is intended for Debian and Ubuntu only. Exiting."
    exit 1
fi

# Detect the version and set the default repositories
if [ "$os" == "debian" ]; then
    version=$(grep -oP '^VERSION_CODENAME=\K\w+' /etc/os-release)
    repository_main="deb http://deb.debian.org/debian $version main"
    repository_contrib="deb http://deb.debian.org/debian $version contrib"
    repository_nonfree="deb http://deb.debian.org/debian $version non-free"
    repository_security="deb http://security.debian.org/debian-security $version/updates main contrib non-free"
elif [ "$os" == "ubuntu" ]; then
    codename=$(lsb_release -cs)
    repository_main="deb http://archive.ubuntu.com/ubuntu/ $codename main"
    repository_universe="deb http://archive.ubuntu.com/ubuntu/ $codename universe"
    repository_restricted="deb http://archive.ubuntu.com/ubuntu/ $codename restricted"
    repository_multiverse="deb http://archive.ubuntu.com/ubuntu/ $codename multiverse"
    repository_security="deb http://security.ubuntu.com/ubuntu $codename-security main universe restricted multiverse"
fi

# Replace the default repositories with the detected ones
sed -i "s/^deb http:\/\/deb.debian.org\/debian.*/$repository_main/g" /etc/apt/sources.list
sed -i "s/^deb http:\/\/deb.debian.org\/debian.*/$repository_contrib/g" /etc/apt/sources.list
sed -i "s/^deb http:\/\/deb.debian.org\/debian.*/$repository_nonfree/g" /etc/apt/sources.list
sed -i "s/^deb http:\/\/security.debian.org\/debian-security.*/$repository_security/g" /etc/apt/sources.list

# Update the package list and upgrade existing packages
apt update
apt upgrade -y


# Prompt for library-related information
read -p "Library Name: " library_name
read -p "Library Short Name: " library_shortname
read -p "Library Email: " library_email
read -p "SMTP Email (optional): " smtp_email
read -p "SMTP Username (optional): " smtp_username
read -s -p "SMTP Password (optional): " smtp_password
echo

# Set the hostname to the library shortname
hostnamectl set-hostname "$library_shortname"
echo "$library_shortname" > /etc/hostname

# Update the package list and upgrade existing packages
apt update
apt upgrade -y

# Install required packages
apt install -y apache2 mariadb-server php phpmyadmin postfix

# Install Koha dependencies
echo "deb [signed-by=/usr/share/keyrings/koha-keyring.gpg] https://debian.koha-community.org/koha 22.11 main" > /etc/apt/sources.list.d/koha.list
apt install -y wget sudo gnupg2
wget -qO - https://debian.koha-community.org/koha/gpg.asc | gpg --dearmor -o /usr/share/keyrings/koha-keyring.gpg
sudo apt-get update

# Install Webmin
echo "deb http://download.webmin.com/download/repository sarge contrib" > /etc/apt/sources.list.d/webmin.list
wget http://www.webmin.com/jcameron-key.asc
apt-key add jcameron-key.asc
apt update
apt install -y webmin

# Install Koha
apt install -y koha-common

# Enable necessary Apache2 modules (cgi)
a2enmod cgi rewrite
# Disable Apache2 default configuration to avoid conflicts
a2dissite 000-default

systemctl restart apache2
# Create Koha ILS database with short name
if koha-create --create-db "$library_shortname"; then
    echo "Koha database created successfully."
else
    echo "Error: Koha database creation failed. Please check for any errors in the command."
    exit 1  # Exit the script with an error code
fi

# Configure Postfix for Gmail SMTP (relayhost) if SMTP information is provided
if [ -n "$smtp_email" ] && [ -n "$smtp_username" ] && [ -n "$smtp_password" ]; then
    cat <<EOF >> /etc/postfix/main.cf
# Gmail SMTP Relay Configuration
relayhost = [smtp.gmail.com]:587
smtp_use_tls = yes
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous
smtp_sasl_tls_security_options = noanonymous
smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt
EOF

    # Create Postfix SMTP credentials file
    echo "[smtp.gmail.com]:587 $smtp_username:$smtp_password" > /etc/postfix/sasl_passwd

    # Secure the SMTP credentials file
    chmod 600 /etc/postfix/sasl_passwd

    # Generate the hash map for Postfix
    postmap /etc/postfix/sasl_passwd
fi

# Reload Postfix
systemctl reload postfix



# Start and enable services
systemctl start apache2
systemctl enable apache2
systemctl start mariadb
systemctl enable mariadb
systemctl start koha-common
systemctl enable koha-common
systemctl start webmin
systemctl enable webmin

# Modify the default.idx file as described
if grep -q "charmap word-phrase-utf.chr" /etc/koha/zebradb/etc/default.idx; then
    sed -i 's/charmap word-phrase-utf.chr/icuchain words-icu.xml/' /etc/koha/zebradb/etc/default.idx
fi

koha-rebuild-zebra -a -b -v -f $library_shortname

# Prompt the user to choose between domain and port (optional)
echo "Do you want to configure the interfaces with domains (1) or default ports (2)?"
read -p "Enter your choice (1 or 2): " interface_choice

# Validate user choice
if [ "$interface_choice" != "1" ] && [ "$interface_choice" != "2" ]; then
    echo "Invalid choice. Configuring interfaces with default ports (OPAC: 80, Staff: 8080)."
    opac_domain=""
    staff_domain="localhost:8080"
else
    if [ "$interface_choice" == "1" ]; then
        # Prompt for domain names
        read -p "Enter OPAC Domain Name: " opac_domain
        read -p "Enter Staff Interface Domain Name: " staff_domain
    else
        opac_domain=""
        staff_domain="localhost:8080"
    fi
fi

# Update the Apache virtual host configuration for the library
apache_config="/etc/apache2/sites-available/$library_shortname.conf"
sed -i -E "s/^(ServerAdmin ).*$/\1$library_email/" "$apache_config"
sed -i -E "s/^(ServerName ).*$/\1$opac_domain/" "$apache_config"
sed -i -E "s/^(ServerAlias ).*$/\1$staff_domain/" "$apache_config"

# Reload Apache to apply changes
systemctl reload apache2

# Print confirmation
if [ "$interface_choice" == "1" ]; then
    echo "Virtual host configuration updated for $library_shortname OPAC with domain: $opac_domain"
    echo "Virtual host configuration updated for $library_shortname Staff Interface with domain: $staff_domain"
else
    echo "Virtual host configuration updated for $library_shortname OPAC using port 80"
    echo "Virtual host configuration updated for $library_shortname Staff Interface using port 8080"
fi

# Install Certbot
apt install -y certbot python3-certbot-apache

# Use library email as the default email address for SSL certificate
ssl_email="$library_email"

# Configure SSL certificate with Certbot (if domains are provided)
if [ -n "$opac_domain" ] && [ -n "$staff_domain" ]; then
    # Obtain SSL certificate for OPAC domain
    certbot --apache -d "$opac_domain" --email "$ssl_email" --agree-tos --no-eff-email
    
    # Obtain SSL certificate for Staff Interface domain
    certbot --apache -d "$staff_domain" --email "$ssl_email" --agree-tos --no-eff-email
    
    # Update virtual host configurations with SSL settings
    sed -i -E "s/^(<VirtualHost \*:80>)/\1\n\tServerName $opac_domain\n\tRedirect permanent \/ https:\/\/$opac_domain\/\n\tSSLEngine on\n\tSSLCertificateFile \/etc\/letsencrypt\/live\/$opac_domain\/fullchain.pem\n\tSSLCertificateKeyFile \/etc\/letsencrypt\/live\/$opac_domain\/privkey.pem\n\tSSLCertificateChainFile \/etc\/letsencrypt\/live\/$opac_domain\/chain.pem/" "$apache_config"
    sed -i -E "s/^(<VirtualHost \*:80>)/\1\n\tServerName $staff_domain\n\tRedirect permanent \/ https:\/\/$staff_domain\/\n\tSSLEngine on\n\tSSLCertificateFile \/etc\/letsencrypt\/live\/$staff_domain\/fullchain.pem\n\tSSLCertificateKeyFile \/etc\/letsencrypt\/live\/$staff_domain\/privkey.pem\n\tSSLCertificateChainFile \/etc\/letsencrypt\/live\/$staff_domain\/chain.pem/" "$apache_config"
fi

# Reload Apache to apply SSL and redirection changes
systemctl reload apache2

# Print confirmation
if [ -n "$opac_domain" ] && [ -n "$staff_domain" ]; then
    echo "SSL certificates obtained and configured for domains:"
    echo "- OPAC: $opac_domain"
    echo "- Staff Interface: $staff_domain"
    echo "HTTP and HTTPS traffic are allowed, and HTTP traffic is redirected to HTTPS."
else
    echo "No SSL certificates obtained. Using default ports for OPAC and Staff Interface."
fi

#get ports 
ssh_port=grep -Ei '^Port ' /etc/ssh/sshd_config
webmin_port=grep -Ei '^port ' /etc/webmin/miniserv.conf

# Open necessary ports in the firewall for Koha, Webmin, and SMTP
ufw allow 80/tcp
ufw allow 8080/tcp
ufw allow 587/tcp  # Gmail SMTP port
ufw allow 22/tcp   # Allow SSH if not already allowed
ufw allow $ssh_port/tcp   # Allow SSH if not already allowed
ufw allow $webmin_port/tcp   # Allow Webmin if not already allowed
ufw allow 443/tcp  # HTTPS
ufw enable

# Search for the crontab.example file
crontab_example_file=$(find / -type f -name "crontab.example" 2>/dev/null)

# Check if the crontab.example file was found
if [ -n "$crontab_example_file" ]; then
    # Read the content of crontab.example
    cronjob_list=$(cat "$crontab_example_file")
    
    # Set the content as the cronjob list
    echo "$cronjob_list" > /etc/cron.d/koha_cronjobs
else
    echo "Warning: crontab.example file not found."
fi

# Set a superuser with sudo privileges
username="mubassir"
password="Admstu@12345"

# Create the user
useradd -m "$username"

# Set the password for the user
echo "$username:$password" | chpasswd

# Add the user to the sudo group to grant sudo privileges
usermod -aG sudo "$username"

# Allow members of the sudo group to execute commands without a password prompt
echo "%sudo ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/90-sudo-users
