#!/bin/bash
# Set up Ubuntu
# 
# Author: Kelwin Guevara Ortiz
#

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

###########
# ENV
MYIP=$(hostname -I | cut -f1 -d' ')
UPINTEFACE=$(ip -o link show | awk '{print $2,$9}' | grep UP | cut -d: -f1)
PUSER=$(who am i | awk '{print $1}')

MYSQLPASS="mysqlpassword"
NEO4JPASS="neo4jpassword"
GIT_NAME="Your Name"
GIT_EMAIL="youremail@domain.com"
LOG_FILE=/var/log/setup.log

cat > /etc/logrotate.d/setup << EOF
$LOG_FILE {
        missingok
        rotate 2
        size 100
        su root root
        create 644 root
}
EOF

logLocal(){
GETCURRDATE=$(date +"%D-%T")
echo -e "=========== $1 @ $GETCURRDATE ===========" >> $LOG_FILE

if [ ! -z "$2" ] && "$2" ; then
	echo -e "=========== $1 @ $GETCURRDATE ==========="
fi
}


logLocal "Start Setup" true
logLocal "Update"  true

apt-get update -qq

###########
# Global app.
installGlobal(){
apt-get install -y htop curl ccze vim ssh nmap lolcat ngrok-client httpie acct iftop links
logLocal "Done Install Global" true
}

# Optional mail tool.
# apt-get install mutt
# apt-get install mailutils

###########
# ssh welcome.
setWelcomeSSH(){
logLocal "Setup Welcome SSH" true
cat > /etc/profile.d/motd.sh << EOF
if hash lolcat 2>/dev/null; then
	echo "" # for spacing
	w | lolcat # uptime information and who is logged in
	echo "" # for spacing
	df -h -x tmpfs -x udev | lolcat # disk usage, minus def and swap
else
	echo "" # for spacing
	w # uptime information and who is logged in
	echo "" # for spacing
	df -h -x tmpfs -x udev # disk usage, minus def and swap
fi
EOF
}


###########
# Nodejs
installNode(){
apt-get install npm
npm cache clean -f
npm install -g n
n stable
node -v
npm -v

# Global packages
npm install -g pm2
pm2 startup
npm install -g nodemon bower jshint mocha xo http-server npm-check
logLocal "Done Install Nodejs" true
}


###########
# Port knocking
installPortKnocking(){
apt-get install knockd
mv /etc/knockd.conf /etc/knockd.conf.old

cat > /etc/knockd.conf << EOF
[options]
	logfile = /var/log/knockd.log
[SSH]
	sequence = 1111,2222,3333
	tcpflags = syn
	seq_timeout = 10
	start_command = ufw allow ssh
	cmd_timeout = 10
	stop_command = ufw deny ssh
EOF

cat > /etc/default/knockd << EOF
################################################
#
# knockd's default file, for generic sys config
#
################################################

# control if we start knockd at init or not
# 1 = start
# anything else = don't start
#
# PLEASE EDIT /etc/knockd.conf BEFORE ENABLING
START_KNOCKD=1

# command line options
KNOCKD_OPTS="-i $UPINTEFACE"
EOF

service knockd restart

logLocal "knock $MYIP 1111 2222 3333 -v && ssh $PUSER@$MYIP" true

logLocal "Done Install Port Knocking" true
}

###########
# Firewall ufw.
installFirewall(){
apt-get install ufw
ufw default reject incoming
ufw default allow outgoing
ufw --force enable
logLocal "Done Install Firewall ufw" true
}

###########
# Git config.
installGit(){
apt-get install git
# Git user config.
su $PUSER -c 'git config --global user.name $GIT_NAME'
su $PUSER -c 'git config --global user.email $GIT_EMAIL'

# Git system config.
git config --system color.ui "auto"
git config --system color.status.header "cyan"
git config --system color.status.added "bold green"
git config --system color.status.changed "bold yellow"
git config --system color.status.untracked "bold red"
git config --system color.status.branch "bold magenta"
git config --system color.status.nobranch "red"
git config --system core.editor "vim"
logLocal "Done Install Git" true
}

###########
# Generate ssh key.
setSSHKey(){
if [ -f $HOME/.ssh/id_rsa ]; then
	logLocal "SSH key exists." true
else
	su $PUSER -c 'ssh-keygen -t rsa -N "" -f $HOME/.ssh/id_rsa'
	su $PUSER -c 'chmod 600 $HOME/.ssh/id_rsa*'
	logLocal "Done Generate SSH key" true
fi
}

installMongoDB(){
apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 0C49F3730359A14518585931BC711F9BA15703C6
echo "deb [ arch=amd64,arm64 ] http://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/3.4 multiverse" > /etc/apt/sources.list.d/mongodb-org-3.4.list
cat > /etc/systemd/system/mongodb.service << EOF
[Unit]
Description=High-performance, schema-free document-oriented database
After=network.target

[Service]
User=mongodb
ExecStart=/usr/bin/mongod --quiet --config /etc/mongod.conf

[Install]
WantedBy=multi-user.target
EOF

apt-get update -qq
apt-get install -y mongodb-org
systemctl start mongodb
systemctl enable mongodb
logLocal "Done Install MongoDB" true
}

installRedis(){
apt-get install -y redis-server
logLocal "Done Install Redis Server" true
}

installMSQL(){
if [ -z "$MYSQLPASS" ]; then
	logLocal "Set mysql pass. (MYSQLPASS)" true
else
	export DEBIAN_FRONTEND="noninteractive"
	debconf-set-selections <<< "mysql-server mysql-server/root_password password $MYSQLPASS"
	debconf-set-selections <<< "mysql-server mysql-server/root_password_again password MYSQLPASS"
	apt-get install -y mysql-server
	logLocal "Done Install MySQL Server" true
fi
}

installNeo4j(){
if [ -z "$NEO4JPASS" ]; then
	logLocal "Set neo4j pass. (NEO4JPASS)" true
else
	wget -O - http://debian.neo4j.org/neotechnology.gpg.key | apt-key add -
	echo 'deb http://debian.neo4j.org/repo stable/' > /etc/apt/sources.list.d/neo4j.list
	apt-get update -qq

	hash http 2>/dev/null || {
		logLocal "Installing httpie" true
		apt-get install httpie
		logLocal "Done Install httpie" true
	}

	apt-get install -y neo4j=3.1.3
	http -a neo4j:neo4j POST http://localhost:7474/user/neo4j/password password=$NEO4JPASS
	logLocal "Done Install Neo4j" true
fi
}

installPHP(){
add-apt-repository -y ppa:ondrej/php
apt-get update -qq
apt-get install -y php7.1 php7.1-common \
php7.1-curl php7.1-xml php7.1-zip php7.1-gd \
php7.1-mysql  php7.1-mbstring php7.1-bcmath \
php7.1-mcrypt php7.1-dev php7.1-cli php-imagick php7.1-dom \
php-dompdf php-pear php-pecl-http php-mongodb php-gettext php7.1-gd \
logLocal "Done Install PHP" true
}

installApache(){
apt-get install apache2
a2enmod rewrite
logLocal "Done Install Apache" true
}

# installGlobal
# setWelcomeSSH
# installPortKnocking
# installFirewall
# setSSHKey
# installNode
# installGit
# installPHP
# installMongoDB
# installMSQL
# installNeo4j
# installApache
# installRedis


logLocal "End Setup" true