if [ $(id -u) -eq 0 ]; then
    read -s -p "Enter contao user password: " password
    pass=$(perl -e 'print crypt($ARGV[0], "password")' $password)
    useradd -m -p $pass contao -s /bin/bash
    usermod -aG sudo contao
    su -l contao
fi

cd /home/contao
mkdir -p .ssh
touch .ssh/authorized_keys
