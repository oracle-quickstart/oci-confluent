#!/bin/bash
#
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
#
# Script to install the Confluent Platform packages
# as part of a total cluster deployment operation.
#
# Expectations :
#	Script run as root
#
# INPUTS
#	Confluent specification (in files)
#		/tmp/cversion	: Confluent Version (default is 5.0.0)
#		/tmp/cedition	: Enterprise or OpenSource (default is OpenSource)
#	Other details
#		Confluent Admin user/group: $KADMIN_USER:$KADMIN_GROUP (defaults to kadmin:kadmin)
#
# OUTPUT (Results)
#	Tarball downloaded and installed to /opt/confluent-<version>
#	Symlink created (/opt/confluent)
#	Ownership set to $KADMIN_USER
#

set -x

THIS_SCRIPT=`readlink -f $0`
SCRIPTDIR=`dirname ${THIS_SCRIPT}`

LOG=/tmp/cp-install.log

# Extract useful details from the OCI MetaData
# The information there should be treated as the source of truth,
# even if the internal settings are temporarily incorrect.
# Oracle OCI - get instance metadata
murl_top=http://169.254.169.254/opc/v1/instance/metadata
# it does not have hostname, it only has displayName (which is friendly name)
# curl -L http://169.254.169.254/opc/v1/instance/displayName
# curl -L http://169.254.169.254/opc/v1/instance/  - will display all Values

THIS_FQDN=`hostname --fqdn`
THIS_HOST=${THIS_FQDN%%.*}


# Validated for versions 5.0.0 and beyond

KADMIN_USER=${KADMIN_USER:-kadmin}
KADMIN_GROUP=${KADMIN_GROUP:-kadmin}

CP_HOME=${CP_HOME:-/opt/confluent}

if [ -f /tmp/cversion ] ; then
	CP_VERSION=$(cat /tmp/cversion)
else
	CP_VERSION=${CP_VERSION:-5.0.0}
fi
CP_MINOR_VERSION=${CP_VERSION%.*}	# Keep track of "X.Y" version.

SCALA_VERSION=2.11
if [ -f /tmp/cedition ] ; then
 	grep -q -i enterprise /tmp/cedition 2> /dev/null
	if [ $? -eq 0 ] ; then
		CP_TARBALL=confluent-${CP_VERSION%-STAGING}-${SCALA_VERSION}.tar.gz
	else
		CP_TARBALL=confluent-oss-${CP_VERSION%-STAGING}-${SCALA_VERSION}.tar.gz
	fi
else
	CP_TARBALL=confluent-oss-${CP_VERSION%-STAGING}-${SCALA_VERSION}.tar.gz
fi

# Retrieve released versions from packages.confluent.io;
CP_TARBALL_URI=http://packages.confluent.io/archive/${CP_MINOR_VERSION}/$CP_TARBALL



install_confluent_from_tarball() {
    [ -d $CP_HOME ] && return 0

    echo "Installing Confluent Platform"

    curl -f -L -o /tmp/$CP_TARBALL $CP_TARBALL_URI

    if [ ! -s /tmp/$CP_TARBALL ] ; then
        echo "  Downloading Confluent Platform tarball failed"
        echo "    ($CP_TARBALL_URI)"
        return 1
    fi

    tar -C /opt -xvf /tmp/$CP_TARBALL
    ln -s /opt/confluent-${CP_VERSION}* $CP_HOME
    mkdir -p $CP_HOME/logs

    chown -R $KADMIN_USER:$KADMIN_GROUP /opt/confluent-${CP_VERSION}*
}


REPO_FILE="/etc/yum.repos.d/confluent.repo"

add_confluent_repo_centos() {
	[ -f $REPO_FILE ] && return

	CVER=`lsb_release -r | awk '{print $2}'`
	CVER=${CVER%%.*}
	[ "${CVER:-0}" -lt 6 ] && return		# CentOS 6 and above only
	[ "${CVER}" -gt 9 ] && CVER=7           

    cat >> $REPO_FILE << EOF_repo
[Confluent.dist]
name=Confluent repository (dist)
baseurl=http://packages.confluent.io/rpm/${CP_MINOR_VERSION}/$CVER
gpgcheck=1
gpgkey=http://packages.confluent.io/rpm/${CP_MINOR_VERSION}/archive.key
enabled=1

[Confluent]
name=Confluent repository
baseurl=http://packages.confluent.io/rpm/${CP_MINOR_VERSION}
gpgcheck=1
gpgkey=http://packages.confluent.io/rpm/${CP_MINOR_VERSION}/archive.key
enabled=1
EOF_repo
}

update_confluent_repo_rpm() {
	if [ -f $REPO_FILE ] ; then
		sed -i "s/rpm\/.../rpm\/${CP_MINOR_VERSION}/" $REPO_FILE
	else
		add_confluent_repo_centos
	fi

	yum makecache
}

update_confluent_repo_deb() {
	wget -qO - http://packages.confluent.io/deb/${CP_MINOR_VERSION}/archive.key | apt-key add -

	sed -i "/packages.confluent.io/d" /etc/apt/sources.list
	add-apt-repository "deb [arch=amd64] http://packages.confluent.io/deb/${CP_MINOR_VERSION} stable main"

	apt-get -y update
}

update_confluent_repo_spec() {
	which apt-get &> /dev/null
	if [ $? -eq 0 ] ; then
		update_confluent_repo_deb
	else
		update_confluent_repo_rpm
	fi
}

#Brute force logic ... the complete umbrella package
#	Issue between 3.1 and 3.2 not including new connectors
#	We'll force them by hand.
platform_confluent_packages() {
	if [ -f /tmp/cedition ] ; then
		grep -q -i enterprise /tmp/cedition 2> /dev/null
		if [ $? -eq 0 ] ; then
			pkgs="confluent-platform-${SCALA_VERSION}"
			pkgs="$pkgs confluent-kafka-connect-*"
		else
			pkgs="confluent-platform-oss-${SCALA_VERSION}"
			pkgs="$pkgs confluent-kafka-connect-* -x confluent-kafka-connect-replicator"
		fi
	else
		pkgs="confluent-platform-oss-${SCALA_VERSION}"
		pkgs="$pkgs confluent-kafka-connect-* -x confluent-kafka-connect-replicator"
	fi

	echo $pkgs
}

# Complicated logic
minimal_confluent_packages() {
	include_enterprise=0
	if [ -f /tmp/cedition ] ; then
		grep -q -i enterprise /tmp/cedition 2> /dev/null
		[ $? -eq 0 ] && include_enterprise=1
	fi

		# Include the client-side with all installs
		# (this is all that is needed for zookeeper nodes)
	pkgs="confluent-kafka-${SCALA_VERSION}"

	grep -q $THIS_HOST /tmp/brokers
	if [ $? -eq 0 ] ; then
		if [ $include_enterprise -gt 0 ] ; then
			pkgs="$pkgs confluent-support-metrics"
			pkgs="$pkgs confluent-rebalancer"
		fi
	fi

	grep -q $THIS_HOST /tmp/workers
	if [ $? -eq 0 ] ; then
		pkgs="$pkgs confluent-kafka-rest"
		if [ $include_enterprise -gt 0 ] ; then
			pkgs="$pkgs confluent-kafka-connect-*"
		else
			pkgs="$pkgs confluent-kafka-connect-* -x confluent-kafka-connect-replicator"
		fi

			# Put ControlCenter and SchemaRegistry
			# on the first two workers
		head -2 /tmp/workers | grep -q $THIS_HOST 2> /dev/null
		if [ $? -eq 0 ] ; then
			pkgs="$pkgs confluent-schema-registry"
			[ $include_enterprise -gt 0 ] && \
				pkgs="$pkgs confluent-control-center"
		fi
	fi

	echo $pkgs
}

install_confluent_from_repo() {
	CONFLUENT_PKGS=$(platform_confluent_packages)

	which gcc &> /dev/null
	gcc_available=$?

	which apt-get &> /dev/null
	if [ $? -eq 0 ] ; then
		apt-get -y install $CONFLUENT_PKGS
		[ $gcc_available ] && apt-get -y install librdkafka-dev
	else
		yum install -y $CONFLUENT_PKGS
		[ $gcc_available ] && yum install -y librdkafka-devel
	fi

	[ $gcc_available ] && pip install --upgrade confluent-kafka
}

main()
{
	echo "$0 script started at "`date` >> $LOG

	if [ `id -u` -ne 0 ] ; then
		echo "  ERROR: script must be run as root" >> $LOG
		exit 1
	fi

	update_confluent_repo_spec
#	install_confluent_from_repo
	install_confluent_from_tarball

	echo "$0 script finished at "`date` >> $LOG
}


main $@
exitCode=$?

set +x

exit $exitCode
