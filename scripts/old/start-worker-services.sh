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
#
# Script to configure the Confluent Platform packages
# as part of a total cluster deployment operation.
#
# Expectations :
#	Script run as root
#
# Pre-requisites
#	Confluent installation (usually at CP_HOME=/opt/confluent, but we
#		support the Linux package installs {deb/rpm} to /usr)
#
#	List of cluster hosts by role (/tmp/cphosts)
#		/home/opc/brokers, /home/opc/zookeepers, /home/opc/workers
#			NOTE: for some cluster configurations (eg a simple 1-node cluster),
#			all 3 files will specify the same server.
#
# Final state
#	Core services configured and running
#		Zookeeper on all nodes in /home/opc/zookeepers
#		Kafka on all nodes in /home/opc/brokers
#
#	Confluent services deployed on nodes defined by /home/opc/workers
#		Control-Center service runs on worker0
#		SchemaRegistry service runs on worker1 (or worker 0 if numWorkers == 1)
#		RestProxy and Connect run worker1 through workerN (or worker0 if numWorkers == 1)
#
#
#

set -x

THIS_SCRIPT=`readlink -f $0`
SCRIPTDIR=`dirname ${THIS_SCRIPT}`

LOG=/tmp/cp-deploy.log

# Extract useful details from the OCI MetaData
# The information there should be treated as the source of truth,
# even if the internal settings are temporarily incorrect.
murl_top=http://169.254.169.254/opc/v1/instance/

# THIS_FQDN=$(curl -f -s $murl_top/hostname)
# [ -z "${THIS_FQDN}" ] &&
THIS_FQDN=$(hostname --fqdn)
THIS_HOST=${THIS_FQDN%%.*}


# Validated for versions 3.1 and beyond

KADMIN_USER=${KADMIN_USER:-kadmin}
KADMIN_GROUP=${KADMIN_GROUP:-kadmin}

# Bite the bullet, since cp-install.sh supports tarball or package installs
CP_HOME=${CP_HOME:-/opt/confluent}
if [ -d $CP_HOME ] ; then
	CP_BIN_DIR=$CP_HOME/bin
	CP_ETC_DIR=$CP_HOME/etc
else
	CP_BIN_DIR=/usr/bin
	CP_ETC_DIR=/etc
fi

if [ -f /tmp/clustername ] ; then
	CLUSTERNAME=$(awk '{print $1}' /tmp/clustername)
else
	CLUSTERNAME="ociqs"
fi



# Locate the configuration files (since we use them all the time)
# Should be called ONLY after the software has been installed.
locate_cfg() {
	ZK_CFG=${CP_ETC_DIR}/kafka/zookeeper.properties
	BROKER_CFG=${CP_ETC_DIR}/kafka/server.properties
	REST_PROXY_CFG=${CP_ETC_DIR}/kafka-rest/kafka-rest.properties
	SCHEMA_REG_CFG=${CP_ETC_DIR}/schema-registry/schema-registry.properties
	KAFKA_CONNECT_CFG=${CP_ETC_DIR}/kafka/connect-distributed.properties
	LEGACY_CONSUMER_CFG=${CP_ETC_DIR}/kafka/consumer.properties
	LEGACY_PRODUCER_CFG=${CP_ETC_DIR}/kafka/producer.properties
	CONTROL_CENTER_CFG=${CP_ETC_DIR}/confluent-control-center/control-center.properties
}

# Locate the start scripts for any changes.
# Should be called ONLY after the software has been installed.
locate_start_scripts() {
	BIN_DIR=${CP_HOME}/bin
	[ ! -d $CP_HOME ] && BIN_DIR="/usr/bin"

	ZK_SCRIPT=${BIN_DIR}/zookeeper-server-start
	BROKER_SCRIPT=${BIN_DIR}/kafka-server-start
	REST_PROXY_SCRIPT=${BIN_DIR}/kafka-rest-start
	SCHEMA_REG_SCRIPT=${BIN_DIR}/schema-registry-start
	KAFKA_CONNECT_SCRIPT=${BIN_DIR}/connect-distributed
	CONTROL_CENTER_SCRIPT=${BIN_DIR}/control-center-start
}

# Archive the configuration file sto a known location




# This function handles the launching of worker
# services as either basic Linux services or via
# standalone commands.   The deployment process that
# uses the standalone commands is fragile ... so we
# do some extra work and retry the startup command
# multiple times if we don't see a successful start.
start_worker_services() {
		# Schema registy on second worker (or first if there's only one)
	numWorkers=$(echo "${workers//,/ }" | wc -w)
	if [ $numWorkers -le 1 ] ; then
		srWorker=${workers%%,*}
	else
		srWorker=$(echo $workers | cut -d, -f2)
	fi

	echo "${srWorker}" | grep -q -w "$THIS_HOST"
	if [ $? -eq 0 ] ; then
		if [ -x $CP_HOME/initscripts/cp-schema-service ] ; then
			ln -s  $CP_HOME/initscripts/cp-schema-service  /etc/init.d
			chkconfig cp-schema-service on
			[ $? -ne 0 ] && systemctl enable cp-schema-service

#			$CP_HOME/initscripts/cp-schema-service start
#			/etc/init.d/cp-schema-service start
			service cp-schema-service start
		else
			local LOGS_DIR=${CP_BIN_DIR}/../logs
			[ ! -d $LOGS_DIR ] && LOGS_DIR=/var/log

			launch_attempt=1
			curl -f -s http://localhost:8081
			while [ $? -ne 0  -a  $launch_attempt -le 3 ] ; do
				$(cd $LOGS_DIR; $CP_BIN_DIR/schema-registry-start -daemon $SCHEMA_REG_CFG > /dev/null)
				sleep 10

				launch_attempt=$[launch_attempt+1]
				curl -f -s http://localhost:8081
			done
		fi
	fi

	echo "$workers" | grep -q -w "$THIS_HOST"
	if [ $? -eq 0 ] ; then
		if [ -x $CP_HOME/initscripts/cp-rest-service ] ; then
			ln -s  $CP_HOME/initscripts/cp-rest-service  /etc/init.d
			chkconfig cp-rest-service on
			[ $? -ne 0 ] && systemctl enable cp-rest-service

#			$CP_HOME/initscripts/cp-rest-service start
#			/etc/init.d/cp-rest-service start
			service cp-rest-service start
		else
			local LOGS_DIR=${CP_BIN_DIR}/../logs
			[ ! -d $LOGS_DIR ] && LOGS_DIR=/var/log

			launch_attempt=1
			curl -f -s http://localhost:8082
			while [ $? -ne 0  -a  $launch_attempt -le 3 ] ; do
				$(cd $LOGS_DIR; $CP_BIN_DIR/kafka-rest-start -daemon $REST_PROXY_CFG > /dev/null)
				sleep 10

				launch_attempt=$[launch_attempt+1]
				curl -f -s http://localhost:8082
			done
		fi
	fi

	echo "$workers" | grep -q -w "$THIS_HOST"
	if [ $? -eq 0 ] ; then
		if [ -x $CP_HOME/initscripts/cp-connect-service ] ; then
			ln -s  $CP_HOME/initscripts/cp-connect-service  /etc/init.d
			chkconfig cp-connect-service on
			[ $? -ne 0 ] && systemctl enable cp-connect-service

#			$CP_HOME/initscripts/cp-connect-service start
#			/etc/init.d/cp-connect-service start
			service cp-connect-service start
		else
			launch_attempt=1
			curl -f -s http://localhost:8083
			while [ $? -ne 0  -a  $launch_attempt -le 3 ] ; do
				$CP_BIN_DIR/connect-distributed -daemon $KAFKA_CONNECT_CFG
				sleep 10

				launch_attempt=$[launch_attempt+1]
				curl -f -s http://localhost:8083
			done
		fi
	fi
}

start_control_center() {
		# Control Center on first worker only
		# Control Center is VERY FRAGILE on start-up,
		#	so we'll isolate the start here in case we need to restart.
	#if [ "${workers%%,*}" = $THIS_HOST ] ; then
	echo "${workers%%,*}" | grep -q -w "$THIS_HOST"
	if [ $? -eq 0 ] ; then
		if [ -x $CP_HOME/initscripts/control-center-service ] ; then
			ln -s  $CP_HOME/initscripts/control-center-service  /etc/init.d
			chkconfig control-center-service on
			[ $? -ne 0 ] && systemctl enable control-center-service

#			$CP_HOME/initscripts/control-center-service start
#			/etc/init.d/control-center-service start
			service control-center-service start
			[ $? -ne 0 ] && service control-center-service start
		else
			local LOGS_DIR=${CP_BIN_DIR}/../logs
			[ ! -d $LOGS_DIR ] && LOGS_DIR=/var/log

			$(cd $LOGS_DIR; $CP_BIN_DIR/control-center-start -daemon $CONTROL_CENTER_CFG > /dev/null)
		fi
	fi
}

# We routinely encounter issues where the
# workers come on line before the brokers / zookeepers are
# ready to handle topic creation.  This is a silly wrapper
# to safely retry topic creation for a more robust behavior.
#
#	Inputs: <topic> <partitions> <replicas>
#	Return: 0 on success, 1 on failure
#
# WARNING: no error checking whatsoever
#

MAX_TOPIC_RETRIES=50
RETRY_INTERVAL_SEC=5
create_topic_safely() {
	local this_retry=1
	local this_topic=$1
	local partitions=$2
	local replicas=$3
	local cleanup_policy=$4

	[ -n "$cleanup_policy" ] && CP_ARG="--config cleanup.policy=$cleanup_policy"

	$CP_BIN_DIR/kafka-topics --zookeeper ${zconnect} \
		--create --if-not-exists \
		--topic $this_topic \
		--replication-factor ${replicas} --partitions ${partitions} $CP_ARG
	while [ $? -ne 0  -a  $this_retry -lt $MAX_TOPIC_RETRIES ] ; do
		this_retry=$[this_retry+1]
		sleep $RETRY_INTERVAL_SEC

		$CP_BIN_DIR/kafka-topics --zookeeper ${zconnect} \
			--create --if-not-exists \
			--topic $this_topic \
			--replication-factor ${replicas} --partitions ${partitions}
	done

	[ $this_retry -ge $MAX_TOPIC_RETRIES ] && return 1
	return 0
}

# Crude function to wait for a topic to exist within the cluster.
#
#	$1: topic name
#	$2: (optional) max wait (defaults to 5 minutes)
wait_for_topic() {
	local topic=${1:-}
    local TOPIC_WAIT=${2:-300}

	[ -z "$topic" ] && return

    SWAIT=$TOPIC_WAIT
    STIME=5
	${CP_BIN_DIR}/kafka-topics --zookeeper ${zconnect} \
		--describe --topic ${topic} | grep -q "^Topic:"
    while [ $? -ne 0  -a  $SWAIT -gt 0 ] ; do
        sleep $STIME
        SWAIT=$[SWAIT - $STIME]
		${CP_BIN_DIR}/kafka-topics --zookeeper ${zconnect} \
			--describe --topic ${topic} | grep -q "^Topic:"
    done

}

# Some worker services require existing topics
# Do that here (ignoring errors for now).
#
# Use "create_topic_safely" on all nodes, since it
# uses the "--if-not-exists" flag that will correctly
# avoid collisions when multiple workers try to create
# the topics.
#	ALTERNATIVE : Only create topics on worker-0,
#	let other workers wait.
#
create_worker_topics() {
		# Topic creation only executed on brokers/workers ... not ZK-ONLY nodes
	echo "$brokers" | grep -q -w "$THIS_HOST"
	if [ $? -ne 0 ] ; then
		echo "$workers" | grep -q -w "$THIS_HOST"
		[ $? -ne 0 ] && return 0
	fi

		# If this instance won't create the topics ... just wait
		# till the last one shows up.
#	if [ "${workers%%,*}" != $THIS_HOST ] ; then
#		wait_for_topic connect-status
#		return
#	fi

	local numBrokers=`echo ${brokers//,/ } | wc -w`
	local numWorkers=`echo ${workers//,/ } | wc -w`

		# Connect requires some simple topics.  Be sure
		# these align with any overrides when customzing
		# the connect-distributed.properties above.
		# 	config.storage.topic=connect-configs
		#	offset.storage.topic=connect-offsets
		#	status.storage.topic=connect-status
	connect_topic_replicas=3
	[ $connect_topic_replicas -gt $numBrokers ] && connect_topic_replicas=$numBrokers

	connect_config_partitions=1
#	$CP_BIN_DIR/kafka-topics --zookeeper ${zconnect} \
#		--create --topic connect-configs \
#		--replication-factor ${connect_topic_replicas} \
#		--partitions ${connect_config_partitions} \
#		--config cleanup.policy=compact
	create_topic_safely connect-configs \
		${connect_config_partitions} ${connect_topic_replicas} compact

	connect_offsets_partitions=50
	[ $numBrokers -lt 6 ] && connect_offsets_partitions=$[numBrokers*8]
#	$CP_BIN_DIR/kafka-topics --zookeeper ${zconnect} \
#		--create --topic connect-offsets \
#		--replication-factor ${connect_topic_replicas} \
#		--partitions ${connect_offsets_partitions} \
#		--config cleanup.policy=compact
	create_topic_safely connect-offsets \
		${connect_offsets_partitions} ${connect_topic_replicas} compact

	connect_status_partitions=10
#	$CP_BIN_DIR/kafka-topics --zookeeper ${zconnect} \
#		--create --topic connect-status \
#		--replication-factor ${connect_topic_replicas} \
#		--partitions ${connect_status_partitions} \
#		--config cleanup.policy=compact
	create_topic_safely connect-status \
		${connect_status_partitions} ${connect_topic_replicas} compact

}

main()
{
    echo "$0 script started at "`date` >> $LOG

    if [ `id -u` -ne 0 ] ; then
        echo "  ERROR: script must be run as root" >> $LOG
        exit 1
    fi
    

		# Extract the necessary host lists from our environment
	bhosts=$(awk '{print $1}' /home/opc/brokers)
	if [ -n "bhosts" ] ; then
		brokers=`echo $bhosts`			# convert <\n> to ' '
	fi
	brokers=${brokers// /,}

	zkhosts=$(awk '{print $1}' /home/opc/zookeepers)
	if [ -n "$zkhosts" ] ; then
		zknodes=`echo $zkhosts`			# convert <\n> to ' '
	fi
	zknodes=${zknodes// /,}		# not really necessary ... but safe

			# external workers
	whosts=$(awk '{print $1}' /home/opc/workers)
	if [ -n "whosts" ] ; then
		workers=`echo $whosts`			# convert <\n> to ' '
	fi
	workers=${workers// /,}

	if [ -z "${zknodes}"  -o  -z "${brokers}" ] ; then
	    echo "Insufficient specification for Confluent Platform cluster ... terminating script" >> $LOG
		exit 1
	fi

 	zconnect=""
        for znode in ${zknodes//,/ } ; do
                if [ -z "$zconnect" ] ; then
                        zconnect="$znode:${zkPort:-2181}"
                else
                        zconnect="$zconnect,$znode:${zkPort:-2181}"
                fi
        done


		# Make sure THIS_HOST is set.  Necessary when DNS resolution is slow.
	while [ -z "$THIS_HOST" ] ; do
		sleep 3
		THIS_HOST=$(hostname -s)
	done


	locate_cfg
        locate_start_scripts
	create_worker_topics
	start_worker_services
	[ -n "$workers" ] && [ -f $CONTROL_CENTER_CFG ] && start_control_center

    echo "$0 script finished at "`date` >> $LOG
}


main $@
exitCode=$?

set +x

exit $exitCode
