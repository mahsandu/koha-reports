#!/bin/bash

# Prompt for library-related information
read -p "Library Name: " library_name
read -p "Library Short Name: " library_shortname
read -p "Library Email: " library_email
read -p "SMTP Email (optional): " smtp_email
read -p "SMTP Username (optional): " smtp_username
read -s -p "SMTP Password (optional): " smtp_password
echo

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

# Create Koha ILS database with short name
koha-create --create-db "$library_shortname"

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

# Enable necessary Apache2 modules (cgi)
a2enmod cgi

# Open necessary ports in the firewall for Koha, Webmin, and SMTP
ufw allow 80/tcp
ufw allow 8080/tcp
ufw allow 587/tcp  # Gmail SMTP port
ufw allow 22/tcp   # Allow SSH if not already allowed
ufw enable

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
    sed -i 's/charmap word-phrase-utf.chr/# charmap word-phrase-utf.chr/' /etc/koha/zebradb/etc/default.idx; then
    sed -i '/# charmap word-phrase-utf.chr/a icuchain words-icu.xml' /etc/koha/zebradb/etc/default.idx
fi

# Add the line "icuchain words-icu.xml" below the commented lines
echo "icuchain words-icu.xml" >> /etc/koha/zebradb/etc/default.idx

# Print instructions for finishing the Koha setup
echo "Koha installation is complete. Please follow the instructions provided in the Koha documentation to complete the setup: https://wiki.koha-community.org/wiki/Koha_on_ubuntu_-_packages"

# Clean up unnecessary files
rm jcameron-key.asc

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

