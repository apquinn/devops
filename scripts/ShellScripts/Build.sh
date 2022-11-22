ScriptsDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$ScriptsDir/Common.sh"

CollectInfo() {
	clear

	## VM Name
  Vars_GetVar "ENTERED_Guest_ShortNameSaved"
	while [ "$ENTERED_Guest_ShortName" == "" ]; do
		if [ "$ENTERED_Guest_ShortNameSaved" != "" ]; then Additional=" (enter for $ENTERED_Guest_ShortNameSaved): "; else Additional=": "; fi
		echo -ne "Please enter a name to use to access your VM$Additional"; 
		read ENTERED_Guest_ShortName
		if [ "$ENTERED_Guest_ShortName" == "" ] && [ "$ENTERED_Guest_ShortNameSaved" != "" ]; then
			ENTERED_Guest_ShortName=$ENTERED_Guest_ShortNameSaved
		fi
	done
	if [ -f "$BaseDir/scripts/UserConfig/$ENTERED_Guest_ShortName.sh" ]; then rm $BaseDir/scripts/UserConfig/$ENTERED_Guest_ShortName.sh; fi
  Vars_SaveVar "ENTERED_Guest_ShortNameSaved" $ENTERED_Guest_ShortName

	## IP
  Vars_GetVar "ENTERED_Address_GuestSaved"
	while [ "$ENTERED_Address_Guest" == "" ]; do
		if [ "$ENTERED_Address_GuestSaved" != "" ]; then Additional=" (enter for $ENTERED_Address_GuestSaved): "; else Additional=": "; fi
		echo -ne "What is the IP or Domain name of this machine$Additional"; 
		read ENTERED_Address_Guest

		if [ "$ENTERED_Address_Guest" == "" ] && [ "$ENTERED_Address_GuestSaved" != "" ]; then
			ENTERED_Address_Guest=$ENTERED_Address_GuestSaved
		fi
	done
  Vars_SaveVar "ENTERED_Address_GuestSaved" $ENTERED_Address_Guest


	## User password for host
  Vars_GetVar "ENTERED_Guest_PWSaved"
	while [ "$ENTERED_Guest_PW" == "" ]; do
		QuestionAddition=""
		echo -ne "\r--- "$QuestionAddition"Please create a password for $(whoami)     "
		read -s ENTERED_Guest_PW1

		echo -ne "\r--- "$QuestionAddition"Please confirm the password for $(whoami)  "
		read -s ENTERED_Guest_PW2

		if [ "$ENTERED_Guest_PW1" == "$ENTERED_Guest_PW2" ]; then
			if [ "$ENTERED_Guest_PW1" != "" ]; then
				ENTERED_Guest_PW="$ENTERED_Guest_PW1";
			elif [ "$ENTERED_Guest_PWSaved" != "" ]; then
				ENTERED_Guest_PW="$ENTERED_Guest_PWSaved";
			fi
			echo -ne "\r                                                                          ";
		fi

		QuestionAddition="Passwords did not match and cannot be blank. Try again. "
	done
	Vars_SaveVar "ENTERED_Guest_PWSaved" $ENTERED_Guest_PW

	## Create guest bootstrap
	echo "Guest_ShortName=\"$ENTERED_Guest_ShortName\"" > $BaseDir/scripts/UserConfig/$ENTERED_Guest_ShortName.sh
	echo "Address_Guest=\"$ENTERED_Address_Guest\"" >> $BaseDir/scripts/UserConfig/$ENTERED_Guest_ShortName.sh
	echo "Guest_PW=\"$ENTERED_Guest_PW\"" >> $BaseDir/scripts/UserConfig/$ENTERED_Guest_ShortName.sh

	source $BaseDir/scripts/UserConfig/$ENTERED_Guest_ShortName.sh
	AddProfile "alias $Guest_ShortName=" "alias $Guest_ShortName='$BaseDir/scripts/ShellScripts/VM-Mgmt.sh --$ENTERED_Guest_ShortName'"
	####### VM CREATED

	### Sync scripts to guest as root
	echo; echo -n "--- Syncing scripts"
	$ScriptsDir/VM-Mgmt.sh --$Guest_ShortName rkh
	{ 
		echo; ssh -o StrictHostKeyChecking=no root@$ENTERED_Address_Guest " echo beef "; echo;
	} &> $VM_Log;
	SyncScripts $ENTERED_Address_Guest root
	echo "		100%"
}


InstallComponents() {
	user=$1
	password=$2
	key=$3
	vm=$4

	VM_Log="/tmp/VMLog.txt"
	touch $VM_Log
	chmod -R 777 $VM_Log

	echo -n "--- Creating Accounts"
	{
		if [ "$(getent passwd $user)" != "" ]; then
			userdel -r $user
		fi

		for group in "wwwmgmt" "www" "wwwapache" "sambausers"; do 
				if [ "$(getent group $group)" != "" ]; then 
					groupdel $group;
				fi
		done; 

		for group in wwwmgmt www wwwapache sambausers; do 
				groupadd $group;
		done; 

		useradd -g wwwmgmt $user
		for group in wwwmgmt www wwwapache sambausers; do 
			usermod -aG $group $user
		done; 

		echo "$password" | passwd $user --stdin
		result=$(grep $user "/etc/sudoers")
		if [ "$result" == "" ]; then echo "$user ALL=(ALL) NOPASSWD: ALL" >>  /etc/sudoers;fi

		mkdir -p /home/$user/.ssh; 
		chmod 700 /home/$user/.ssh; chown $user /home/$user/.ssh; chgrp wwwmgmt /home/$user/.ssh;
		echo "$key" > /home/$user/.ssh/authorized_keys
		chmod 600 /home/$user/.ssh; chown $user /home/$user/.ssh/authorized_keys; chgrp wwwmgmt /home/$user/.ssh/authorized_keys;

		echo -e 'export HISTTIMEFORMAT="%h %d %H:%M:%S "' >> /home/$user/.bashrc
		echo -e 'export HISTSIZE=10000' >> /home/$user/.bashrc
		echo -e 'export HISTFILESIZE=10000' >> /home/$user/.bashrc
		echo -e 'shopt -s histappend' >> /home/$user/.bashrc
		echo -e 'PROMPT_COMMAND="history -a"' >> /home/$user/.bashrc
		echo -e 'export HISTCONTROL=ignorespace:erasedups' >> /home/$user/.bashrc
		echo -e 'export HISTIGNORE="ls:ps:history"' >> /home/$user/.bashrc

	} &> $VM_Log;
	echo "		100%"
	CheckErrors

	echo; echo "BUILDING SERVER"
	#######
	echo -n "--- Basic configuration		"
	{
		source //ScriptFiles/scripts/UserConfig/$vm.sh
		hostnamectl set-hostname $Address_Guest

		sed -i '/SELINUX=/d' /etc/selinux/config
		result=$(grep SELINUX=disabled "/etc/selinux/config")
		if [ "$result" == "" ]; then echo "SELINUX=disabled" >> /etc/selinux/config; fi
		setenforce 0
	} &> $VM_Log; 
	echo "100%"
	CheckErrors

	echo -n "--- Running dnf update		"
	{
		dnf update -y
	} &> $VM_Log;
	echo "100%"
	#CheckErrors	// finds installation of pecl-errors and freaks out

	echo -n "--- Installing wget & git	"
	{
		dnf install -y wget
		dnf install -y git
	} &> $VM_Log;
	echo "100%"
	#CheckErrors	// finds installation of pecl-errors and freaks out

	echo -n "--- Installing Apache		"
	{
		if [ "$(which httpd)" != "/usr/sbin/httpd" ]; then
			yum install -y httpd
			if [ ! -f /usr/local/apache2 ]; then ln -s /etc/httpd/ /usr/local/apache2; fi
			systemctl enable httpd.service
			systemctl start httpd.service
			systemctl start firewalld
			firewall-cmd --permanent --zone=public --add-service=http
			firewall-cmd --permanent --zone=public --add-service=https
			firewall-cmd --reload
			mkdir -p /htdocs/cgi-bin;
			mkdir -p /htdocs/web
			chown -R aquinn:wwwapache /htdocs; chmod -R 775 /htdocs;
		fi
	} &> $VM_Log;
	echo "100%"
	CheckErrors

	echo -n "--- Installing Mariadb		"
	{
		if [ "$(which mariadb)" != "/usr/bin/mariadb" ]; then
			#echo -e "[mariadb] \nname = MariaDB \nbaseurl = http://yum.mariadb.org/10.3.12/centos7-amd64 \ngpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB \ngpgcheck=1 \n" > /etc/yum.repos.d/MariaDB.repo
			curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash
			dnf -y install MariaDB-server MariaDB-client
			systemctl enable mariadb
			systemctl start mariadb

			echo -e "\ny\ny\nnSolidWood1a1\n$password\ny\ny\ny\ny" | mariadb-secure-installation 2>/dev/null
			mariadb -e "CREATE USER IF NOT EXISTS aquinn@localhost IDENTIFIED BY '$password';";
			mariadb -e "GRANT ALL PRIVILEGES ON *.* TO 'aquinn'@localhost IDENTIFIED BY '$password';";

		fi
	} &> $VM_Log;
	echo "100%"
	CheckErrors

	PHPVer="8.1";
	echo -n "--- Installing PHP $PHPVer		"
	{
		if [ "$(which php)" != "/usr/bin/php" ]; then
			dnf config-manager --set-enabled crb

			dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
			dnf install -y https://dl.fedoraproject.org/pub/epel/epel-next-release-latest-9.noarch.rpm
			dnf install -y dnf-utils http://rpms.remirepo.net/enterprise/remi-release-9.rpm
			dnf update --refresh -y
			#dnf remove php php-fpm -y
			#dnf remove php* -y
			dnf module list reset php -y
			dnf module list php

			if [ "PHPVer" == "8.1" ]; then
				dnf module enable php:remi-8.1 -y
			else
				dnf module enable php:remi-7.4 -y
			fi

			dnf install -y php php-{cli,fpm,mysqlnd,zip,devel,gd,mbstring,curl,xml,pear,bcmath,json,opcache}
			dnf install php-fpm -y
		fi
	} &> $VM_Log;
	echo "100%"
	CheckErrors

	echo -n "--- Installing SAMBA		"
	{
		# yum install -y vsftpd
		# systemctl start vsftpd
		# systemctl enable vsftpd

		# firewall-cmd --zone=public --permanent --add-port=21/tcp
		# firewall-cmd --zone=public --permanent --add-service=ftp
		# firewall-cmd --reload

		# yum -y install policycoreutils-python-utils
		# semanage boolean -m ftpd_full_access --on

		dnf install samba samba-client cifs-utils nfs-utils -y

		firewall-cmd --permanent --zone=public --add-service=samba
		firewall-cmd --zone=public --add-service=samba
		firewall-cmd --reload

		setsebool -P samba_enable_home_dirs on
		chcon -t samba_share_t /htdocs/

		# This is only the initial conf file 
		# final config file is copied from SetupFiles/ConfigFiles/samba during the 
		SmbConf="[global] \nworkgroup = MYGROUP \nhosts allow = 127. 198.110.203. 192.168.0. \nmax protocol = SMB2 \nsecurity = user \nunix charset = UTF-8 \ndos charset = CP932 \nmap to guest = Bad User \n
			\nlog file = /var/log/samba/log.%m \nmax log size = 50 \n
			\n[homes] \nbrowsable = yes \nwritable = yes \nvalid users = %S \n"
		echo -e $SmbConf > /etc/samba/smb.conf

		chmod 644 /etc/samba/*

		systemctl enable smb
		systemctl start smb

		systemctl enable nmb
		systemctl start nmb

		echo -e "$password\n$password" | (smbpasswd -a $user)
	} &> $VM_Log;
	echo "100%"
	CheckErrors

	echo -n "--- Installing UNIX Tools	"
	{
		# fail2ban stops SSH attacks
		# bind-utils provides the nslookup tool
		# whois provides the whois lookup for fail2ban

		dnf -y install cronolog mod_ssl sysstat fail2ban bind-utils whois
		systemctl enable fail2ban
	} &> $VM_Log;
	echo "100%"
	CheckErrors

	echo -n "--- Updating $user key		"
	{
		mkdir -p /home/$user/.ssh
		chmod 700 /home/$user/.ssh
		if [ -f /home/$user/.ssh/authorized_keys ]; then
			cat ~/.ssh/authorized_keys > /home/$user/.ssh/authorized_keys
		else
			cp ~/.ssh/authorized_keys /home/$user/.ssh/
			chown $user /home/$user/.ssh/authorized_keys
			chgrp $user /home/$user/.ssh/authorized_keys
		fi

	} &> $VM_Log;
	echo "100%"
	CheckErrors

	echo -n "--- Creating crontab services	"
	{
		crontab -l > ~/mycron &> /dev/null
		echo "@reboot ( sleep 5 ; sh /ScriptFiles/scripts/ShellScripts/Guest_ConfigureMounts.sh )" >> ~/mycron
		echo "0      0     1       *       *     /ScriptFiles/scripts/scripts/ShellScripts/Guest_CertBotRenew.sh" >> ~/mycron
		crontab ~/mycron
		chmod 777 /S
		rm ~/mycron
	} &> $VM_Log;
	echo "100%"
	CheckErrors

	#echo -n "--- Installing OpenSSL"
	#{
		# cd;
		# yum install -y openvpn
		# wget https://github.com/OpenVPN/easy-rsa/archive/v3.0.8.tar.gz
		# tar -xf v3.0.8.tar.gz
		# cd /etc/openvpn/
		# mkdir -p /etc/openvpn/easy-rsa
		# mv /root/easy-rsa-3.0.8 /etc/openvpn/easy-rsa

 		# if [ -f /etc/openvpn/server.conf ]; then sudo rm -rf /etc/openvpn/server.conf; fi; sudo cp /ScriptFiles/SetupFiles/ConfigFiles/openssl/server.conf /etc/openvpn/;
		# openvpn --genkey secret /etc/openvpn/myvpn.tlsauth
		# cd /etc/openvpn/easy-rsa/easy-*
	#} &> $VM_Log;
	#echo "	100%"
	#CheckErrors

	echo -n "--- Final preconfiguration	"
	chown -R $user /ScriptFiles; chgrp -R wwwmgmt /ScriptFiles;
	echo "100%"
}


FinalConfiguration() {
	vm=$1;
	user=$2
	source /ScriptFiles/scripts/UserConfig/$vm.sh

	echo -n "--- Installing Composer		"
	{
		if [ "$(which composer)" != "/usr/local/bin/composer" ]; then
			cd ~
			#sudo dnf -y update
			#sudo dnf groupinstall -y "Development Tools"
			wget https://getcomposer.org/installer -O composer-installer.php
			sudo php composer-installer.php --filename=composer --install-dir=/usr/local/bin
			dir=/usr/local/bin
			rm composer-installer.php
			rm composer-setup.php
			#sudo cp /ScriptFiles/SetupFiles/ConfigFiles/composer/composer.json /usr/local/bin/
		fi
	} &> $VM_Log;
	echo "100%"
	CheckErrors

	echo -n "--- Installing phpMyAdmin	"
	{
		if [ ! -d /htdocs/phpmyadmin ]; then
			cd ~
			composer create-project phpmyadmin/phpmyadmin
			mv ~/phpmyadmin /htdocs
		fi
	} &> $VM_Log;
	echo "done"
	CheckErrors

	#######
	echo -n "--- Configuring git		"
	{
		git config --global user.email "apquinn@gmail.com"; git config --global user.name "$Username"; git config --global push.default simple;
	} &> $VM_Log;
	echo "done"
	CheckErrors

	#######
	echo -n "--- Config symlinks & profile	"
	{
		homeDirBin=/home/$user/bin
		if [ -d $homeDirBin ]; then rm -rf $homeDir; fi

		mkdir -p $homeDirBin
		chmod 777 $homeDirBin
		cd $homeDirBin

		cd /
		chgrp users $homeDirBin
		chown $Username $homeDirBin

		AddProfile "" "if [ -f ~/.bashrc ]; then . ~/.bashrc; fi"		"# .bashrc include" "$user"
		AddProfile "" "PATH=\"\$homeDirBin:\$HOME/.local/bin:\$PATH\""	"" "$user"
		AddProfile "" "PS1='\u@\h: \w\\\$ '" "# setup your default cursor" "$user"
		AddProfile "" "export PATH PS1" "" "$user"
		AddProfile "" "alias perms=\"find . -type d -exec sudo chmod 775 '{}' \;; find . -type f -exec sudo chmod 664 '{}' \;\"" "" "$Username"
		AddProfile "" "" "" "$user"

		AddProfile "" "alias cms='cd /htdocs/scripts/'" "" "$user"
		AddProfile "" "alias ls='ls -l | more'" "" "$user"
		AddProfile "" "alias pids='ps aux | grep -i aquinn'" "" "$user"
		AddProfile "" "alias src='source ~/.bash_profile'" "" "$user"

		source ~/.bash_profile
	} &> $VM_Log;
	echo "done"
	CheckErrors

	#######
	echo -n "--- Configuring other services	"
	{
		if [ -f /htdocs/phpmyadmin/config.inc.php ]; then sudo rm -rf /htdocs/phpmyadmin/config.inc.php; fi; sudo cp /ScriptFiles/SetupFiles/ConfigFiles/phpmyadmin/config.inc.php /htdocs/phpmyadmin;
		#if [ -f /etc/vsftpd/vsftpd.conf ]; then sudo rm -rf /etc/vsftpd/vsftpd.conf; fi; sudo cp /SetupFiles/ConfigFiles/vsftpd/vsftpd.conf /etc/vsftpd/;
		if [ -f /usr/local/apache2/conf/httpd.conf ]; then sudo rm -rf /usr/local/apache2/conf/httpd.conf; fi; sudo cp /ScriptFiles/SetupFiles/ConfigFiles/apache/httpd.conf /usr/local/apache2/conf;
		if [ -f /etc/php.ini ]; then sudo rm -rf /etc/php.ini; fi; sudo cp /ScriptFiles/SetupFiles/ConfigFiles/php/php.ini /etc;
		if [ -f /etc/my.cnf ]; then sudo rm -rf /etc/my.cnf; fi; sudo cp /ScriptFiles/SetupFiles/ConfigFiles/mariadb/my.cnf /etc;
		if [ -f /etc/samba/smb.conf ]; then sudo rm -rf /etc/samba/smb.conf; fi; sudo cp /ScriptFiles/SetupFiles/ConfigFiles/samba/smb.conf /etc/samba;
		#if [ -f /etc/fail2ban/jail.local ]; then sudo rm -rf /etc/fail2ban/jail.local; fi; sudo cp /ScriptFiles/SetupFiles/ConfigFiles/fail2ban/jail.local /etc/fail2ban;
		sudo chmod 644 /etc/php.ini /etc/my.cnf /etc/samba/smb.conf; sudo chmod 775 /etc/fail2ban;

		sudo sed -i "s/.*verbose.*/\$cfg['Servers'][\$i]['verbose'] = '$Address_Guest';/g" /htdocs/phpmyadmin/config.inc.php
		sudo chmod 664 /htdocs/phpmyadmin/config.inc.php

	} &> $VM_Log;
	echo "done"
	CheckErrors


	#######
	echo -n "--- Restarting services		"
	{
		sudo systemctl restart httpd
		sudo systemctl restart mariadb
		sudo systemctl restart sshd
	} &> $VM_Log;
	CheckErrors
	echo "done"


	#######
	echo -n "--- Performing cleanup		"
	{
		if [ ! -f /usr/bin/bash ]; then sudo ln -s /usr/bin/bash /usr/local/bin/bash; fi

		dnf clean all
		sudo rm -rf /tmp/*
		sudo rm -f /var/log/wtmp /var/log/btmp
		history -c
		history -w
	} &> $VM_Log;
	echo "done"
	CheckErrors
}




