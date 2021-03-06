#!/bin/bash

password=$(openssl rand -base64 14)
echo "The contao/mysql user password: $password"
echo "The install script will continue in 10 seconds"
sleep 10
if [ $(id -u) -eq 0 ]; then
    pass=$(perl -e 'print crypt($ARGV[0], "password")' $password)
    useradd -m -p $pass contao -s /bin/bash
    usermod -aG sudo contao
fi

cd /home/contao
mkdir -p .ssh
touch .ssh/authorized_keys
chown -R contao:contao .ssh

sudo apt update
sudo apt -y install apache2
sudo sed -i "s/Options Indexes FollowSymLinks/Options FollowSymLinks/" /etc/apache2/apache2.conf

sudo systemctl stop apache2.service
sudo systemctl start apache2.service
sudo systemctl enable apache2.service

sudo apt -y install mariadb-server mariadb-client

sudo systemctl stop mariadb.service
sudo systemctl start mariadb.service
sudo systemctl enable mariadb.service

# https://bertvv.github.io/notes-to-self/2015/11/16/automating-mysql_secure_installation/
sudo mysql --user=root <<_EOF_
UPDATE mysql.user SET Password=PASSWORD('${password}') WHERE User='root';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
_EOF_

sudo systemctl restart mysql.service

# https://linuxhostsupport.com/blog/how-to-install-php-7-2-on-debian-9/
sudo apt -y install software-properties-common wget
sudo apt -y install lsb-release apt-transport-https ca-certificates
sudo wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/php.list

sudo apt update
sudo apt -y install php7.2 libapache2-mod-php7.2 php7.2-common php7.2-mbstring php7.2-xmlrpc php7.2-soap php7.2-gd php7.2-xml php7.2-intl php7.2-mysql php7.2-cli php7.2-zip php7.2-curl

# https://stackoverflow.com/a/2464883/5203308
sudo sed -i "s/\(max_execution_time *= *\).*/\1180/" /etc/php/7.2/apache2/php.ini
sudo sed -i "s/\(memory_limit *= *\).*/\1512M/" /etc/php/7.2/apache2/php.ini
sudo sed -i "s/\(post_max_size *= *\).*/\120M/" /etc/php/7.2/apache2/php.ini
sudo sed -i "s/\(upload_max_filesize *= *\).*/\1100M/" /etc/php/7.2/apache2/php.ini

# https://websiteforstudents.com/install-contao-cms-on-ubuntu-16-04-lts-with-apache2-mariadb-and-php-7-1-support/
sudo mysql --user=root <<_EOF_
CREATE DATABASE contaodb;
CREATE USER 'contaouser'@'localhost' IDENTIFIED BY '${password}';
GRANT ALL ON contaodb.* TO 'contaouser'@'localhost' IDENTIFIED BY '${password}' WITH GRANT OPTION;
FLUSH PRIVILEGES;
_EOF_

if ! grep -q "innodb_large_prefix" /etc/mysql/mariadb.conf.d/50-server.cnf; then
    sudo sed  -i '/\[mysqld\]/a innodb_large_prefix = 1\ninnodb_file_format = Barracuda\ninnodb_file_per_table = 1\n' /etc/mysql/mariadb.conf.d/50-server.cnf
fi

sudo systemctl restart mysql.service

curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer

sudo apt -y install unzip

# https://github.com/composer/composer/issues/945#issuecomment-8552757
/bin/dd if=/dev/zero of=/var/swap.1 bs=1M count=1024
/sbin/mkswap /var/swap.1
/sbin/swapon /var/swap.1

su - contao -c "composer create-project --no-dev contao/managed-edition contaoproject"

# https://websiteforstudents.com/install-contao-cms-on-ubuntu-16-04-lts-with-apache2-mariadb-and-php-7-1-support/
ipaddress=$(curl ifconfig.me)
echo "<VirtualHost *:80>
     ServerAdmin admin@example.com
     DocumentRoot /home/contao/contaoproject/web
     ServerName $ipaddress
     ServerAlias $ipaddress

     <Directory /home/contao/contaoproject/web/>
        Options +FollowSymlinks
        AllowOverride All
        Require all granted
     </Directory>

     ErrorLog ${APACHE_LOG_DIR}/error.log
     CustomLog ${APACHE_LOG_DIR}/access.log combined

</VirtualHost>" > /etc/apache2/sites-available/contao.conf

sudo chown -R www-data:www-data contaoproject/
sudo chmod -R 755 contaoproject
sudo a2ensite contao.conf
sudo a2enmod rewrite
sudo systemctl restart apache2.service

echo "Install script done, now open: http://$ipaddress/contao/install"
