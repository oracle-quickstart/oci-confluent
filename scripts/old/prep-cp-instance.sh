#!/bin/bash

# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#
#

# set -x

LOG=/tmp/prep-cp-instance.log


# Oracle OCI - get instance metadata
murl_top=http://169.254.169.254/opc/v1/instance/metadata


KADMIN_UID=${KADMIN_UID:-2000}
KADMIN_USER=${KADMIN_USER:-kadmin}
KADMIN_GROUP=`id -gn ${KADMIN_USER}`
KADMIN_GROUP=${KADMIN_GROUP:-kadmin}
KADMIN_PASSWD=${KADMIN_PASSWD:-C0nfluent}



# The first DHCP boot of the instacne might set
# the hostname WITHOUT updating the /etc/sysconfig file that
# will define that value on subsequent boots.   This may be
# a side effect of cloud-init  ... I don't know.   But we
# have to fix it for our VPC installations.
#
verify_instance_hostname() {
	SYSCONFIG_NETWORK=/etc/sysconfig/network
	CUR_FQDN=`hostname -f`

	if [ -f $SYSCONFIG_NETWORK ] ; then
		CFG_FQDN=`grep ^HOSTNAME= $SYSCONFIG_NETWORK | cut -d "=" -f2`

		if [ "$CFG_FQDN" != "$CUR_FQDN" ] ; then
			sed -i "s/^HOSTNAME=.*$/HOSTNAME=$CUR_FQDN/" $SYSCONFIG_NETWORK
		fi
	fi

		# Some CentOS images have hard-coded hostnames left in /etc/hostname
		# Just remove it if it doesn't match (module network domain)
	if [ -f /etc/hostname ] ; then
		CFG_FQDN=`cat /etc/hostname`
		if [ "$CFG_FQDN" != "$CUR_FQDN"  -a  "${CFG_FQDN%%.*}" != "${CUR_FQDN%%.*}" ] ; then
			rm /etc/hostname
		fi
	fi
}


# For CentOS, add the EPEL repo
#
add_epel_repo() {
	which rpm &> /dev/null
	[ $? -ne 0 ] && return

	echo "Configuring EPEL repository"

	yum install -y redhat-lsb-core
	yum install -y yum-utils

	EPEL_RPM=/tmp/epel.rpm
	CVER=`lsb_release -r | awk '{print $2}'`
	if [ "${CVER%%.*}" -eq 6 ] ; then
		EPEL_LOC="epel/epel-release-latest-6.noarch.rpm"
	else
		EPEL_LOC="epel/epel-release-latest-7.noarch.rpm"
	fi

	epel_def=/etc/yum.repos.d/epel.repo
	if [ -f $epel_def ] ; then
		yum-config-manager --enable epel
	else
		curl -f -s -L -o $EPEL_RPM http://dl.fedoraproject.org/pub/$EPEL_LOC
		[ $? -eq 0 ] && rpm --quiet -i $EPEL_RPM
	fi
}

add_confluent_repo_deb() {
	wget -qO - http://packages.confluent.io/deb/5.0/archive.key | apt-key add -

	add-apt-repository "deb [arch=amd64] http://packages.confluent.io/deb/5.0 stable main"

	apt-get -y update
}

add_confluent_repo_centos() {
	REPO_FILE="/etc/yum.repos.d/confluent.repo"
	[ -f $REPO_FILE ] && return

	CVER=`lsb_release -r | awk '{print $2}'`
	CVER=${CVER%%.*}
	[ "${CVER:-0}" -lt 6 ] && return		# CentOS 6 and above only
	[ "${CVER}" -gt 9 ] && CVER=7           

    cat >> $REPO_FILE << EOF_repo
[Confluent.dist]
name=Confluent repository (dist)
baseurl=http://packages.confluent.io/rpm/5.0/$CVER
gpgcheck=1
gpgkey=http://packages.confluent.io/rpm/5.0/archive.key
enabled=1

[Confluent]
name=Confluent repository
baseurl=http://packages.confluent.io/rpm/5.0
gpgcheck=1
gpgkey=http://packages.confluent.io/rpm/5.0/archive.key
enabled=1
EOF_repo

	yum makecache
}

add_confluent_repo() {
	which apt-get &> /dev/null
	if [ $? -eq 0 ] ; then
		add_confluent_repo_deb
	else
		add_confluent_repo_centos
	fi
}

init_sys_services () {
		# Install ntp daemon - it will automatically start on boot
		# (NOTE: run ntpdate first to be sure we're in sync)
	if which apt-get &> /dev/null ; then
		apt-get -y install ntpdate
		ntpdate -u pool.ntp.org
		apt-get -y install ntp
	else
		yum install -y ntpdate
		ntpdate -u pool.ntp.org
		yum install -y ntp
		yum install -y bind-utils
	fi

		# Remove annoying ssh banners
	SSHD_BANNER=/etc/ssh/sshd_banner
	[ -f $SSHD_BANNER ] && mv $SSHD_BANNER $SSHD_BANNER.ami
}

install_os_tools() {
	if which apt-get &> /dev/null ; then
		apt-get -y update

		apt-get install -y wget realpath
		apt-get install -y lsof nc
		apt-get install -y clustershell jq
		apt-get install -y mdadm

			# Make sure we have XFS file system support
		apt-get install -y xfsprogs
	elif which yum &> /dev/null ; then
		yum install -y wget realpath
		yum install -y lsof nc bind-utils
		yum install -y clustershell jq
		yum install -y mdadm

			# Make sure we have XFS file system support
		yum install -y xfsprogs

		which pip &> /dev/null
        [ $? -ne 0 ] && yum install -y python-pip
		pip install --upgrade pip
	fi

		# Add the python pip "requests" package to all instances
	pip install --upgrade requests
}

install_openjdk_deb() {
	apt-get install -y x11-utils
	apt-get install -y openjdk-8-jdk openjdk-8-doc

	jcmd=`readlink -f /usr/bin/java`
	JAVA_HOME=${jcmd%/bin/java}
	export JAVA_HOME
}

install_oracle_jdk_deb() {
    apt-get -y update
    apt-get install -y software-properties-common python-software-properties
    add-apt-repository -y ppa:webupd8team/java
    apt-get -y update

    /bin/echo debconf shared/accepted-oracle-license-v1-1 select true | /usr/bin/debconf-set-selections
#    apt-get -y install oracle-java7-installer oracle-java7-set-default
    apt-get -y install oracle-java8-installer oracle-java8-set-default
    if [ $? -ne 0 ] ; then
        echo "  Oracle JDK installation failed"
        return 1
    fi

#    export JAVA_HOME=/usr/lib/jvm/java-7-oracle
    export JAVA_HOME=/usr/lib/jvm/java-8-oracle

	return 0
}

install_openjdk_rpm() {
	yum install -y java-1.8.0-openjdk java-1.8.0-openjdk-devel
#	yum install -y java-1.8.0-openjdk-javadoc

	jcmd=`readlink -f /usr/bin/java`
	JAVA_HOME=${jcmd%/bin/java}
	[ -z "${JAVA_HOME}" ] && JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk
	export JAVA_HOME
}

install_oracle_jdk_rpm() {
#    JDK_RPM="http://download.oracle.com/otn-pub/java/jdk/7u75-b13/jdk-7u75-linux-x64.rpm"
    JDK_RPM="http://download.oracle.com/otn-pub/java/jdk/8u91-b16/jdk-8u91-linux-x64.rpm"

    $(cd /tmp; curl -f -s -L -C - -b "oraclelicense=accept-securebackup-cookie" -O $JDK_RPM)

    RPM_FILE=/tmp/`basename $JDK_RPM`
    if [ ! -s $RPM_FILE ] ; then
        echo "  Downloading Oracle JDK failed"
        return 1
    fi

    rpm -ivh $RPM_FILE
    if [ $? -ne 0 ] ; then
        echo "  Oracle JDK installation failed"
        return 1
    fi

    export JAVA_HOME=/usr/java/latest

    return 0
}

# Install JDK (if necessary)
#	Always set JAVA_HOME environment variable for use later
#
install_jdk() {
	echo "Installing JAVA 8"


		# Simply set JAVA_HOME if java installed (should check version)
		#
	javacmd=`which javac 2> /dev/null`
	if [ $? -eq 0  -a  -n "${javacmd:-}" ] ;  then
		jcmd=`realpath $javacmd`
		export JAVA_HOME=${jcmd%/bin/javac}
	else
		if which apt-get &> /dev/null ; then
#			install_oracle_jdk_deb
			install_openjdk_deb
		else
#			install_oracle_jdk_rpm
			install_openjdk_rpm
		fi
	fi
}

update_admin_keys() {
	KADMIN_USER_DIR=`eval "echo ~${KADMIN_USER}"`
	[ ! -d $KADMIN_USER_DIR ] && return 1 ;

		# Create sshkey for $KADMIN_USER (must be done AS KADMIN_USER)
	su $KADMIN_USER -c "mkdir ${KADMIN_USER_DIR}/.ssh ; chmod 700 ${KADMIN_USER_DIR}/.ssh"
	su $KADMIN_USER -c "ssh-keygen -q -t rsa -f ${KADMIN_USER_DIR}/.ssh/id_rsa -P '' "
	su $KADMIN_USER -c "cp -p ${KADMIN_USER_DIR}/.ssh/id_rsa ${KADMIN_USER_DIR}/.ssh/id_launch"
	su $KADMIN_USER -c "cp -p ${KADMIN_USER_DIR}/.ssh/id_rsa.pub ${KADMIN_USER_DIR}/.ssh/authorized_keys"
	su $KADMIN_USER -c "chmod 600 ${KADMIN_USER_DIR}/.ssh/authorized_keys"

		# And copy the cloud infrastructure keys into place
	INFRA_SSH_KEY_FILE=$KADMIN_USER_DIR/.ssh/id_cloud.pub


		# For Oracle OCI the key-pair is in metadata
	curl -f -s ${murl_top}/ssh_authorized_keys > $INFRA_SSH_KEY_FILE

		# For Azure cloud platform, we can use the admin user keys
	if [ $? -ne 0  -a  -r /etc/sudoers.d/waagent ] ; then
		CLOUD_INIT_USER=$(head /etc/sudoers.d/waagent | awk '{print $1}')
		CI_USER_DIR=`eval "echo ~${CLOUD_INIT_USER}"`
		[ -f ${CI_USER_DIR}/.ssh/authorized_keys ] && \
			$(cp -p ${CI_USER_DIR}/.ssh/authorized_keys $INFRA_SSH_KEY_FILE)
	fi

	[ -f $INFRA_SSH_KEY_FILE ] && \
		cat $INFRA_SSH_KEY_FILE >> $KADMIN_USER_DIR/.ssh/authorized_keys
}

create_admin_user() {
	echo "Adding/configuring admin user"

	id $KADMIN_USER &> /dev/null
	if [ $? -ne 0 ] ; then
		useradd -u $KADMIN_UID -c "Confluent Admin" -m -s /bin/bash $KADMIN_USER 2> /dev/null
		if [ $? -ne 0 ] ; then
				# Assume failure was dup uid; try with default uid assignment
			echo "useradd returned $?; trying auto-generated uid"
			useradd -c "Confluent Admin" -m -s /bin/bash $KADMIN_USER
		fi

		id $KADMIN_USER &> /dev/null
		if [ $? -ne 0 ] ; then
			echo "Failed to create new user $KADMIN_USER {error code $?}"
			return 1
		fi
	fi

	if [ -n "$KADMIN_PASSWD" ] ; then
		passwd $KADMIN_USER << passwdEOF
$KADMIN_PASSWD
$KADMIN_PASSWD
passwdEOF
	fi

	update_admin_keys

		# Add admin user to sudo group if it exists
	grep -q -e "^sudo:" /etc/group
	[ $? -eq 0 ] && usermod -G sudo $KADMIN_USER

	KADMIN_USER_DIR=`eval "echo ~${KADMIN_USER}"`
	[ ! -d $KADMIN_USER_DIR ] && return 0 ;

		# Enhance the login with rational defaults for PATH, etc
	grep -q -e "/opt/confluent" $KADMIN_USER_DIR/.bashrc
    [ $? -ne 0 ] && cat >> $KADMIN_USER_DIR/.bashrc << EOF_bashrc

CDPATH=.:$HOME
export CDPATH

CP_HOME=\${CP_HOME:-/opt/confluent}
[ -n "\${JAVA_HOME:-}" ] && PATH=\$PATH:\$JAVA_HOME/bin
[ -n "\${CP_HOME:-}" ] && PATH=\$PATH:\$CP_HOME/bin

set -o vi

EOF_bashrc

	return 0
}

main() {
	echo "$0 script started at "`date` >> $LOG

	verify_instance_hostname

	add_epel_repo
	add_confluent_repo
	init_sys_services
	install_os_tools
	install_jdk

	create_admin_user

	echo "$0 script finished at "`date` >> $LOG

	return 0
}

main $@
exitCode=$?

set +x

exit $exitCode
