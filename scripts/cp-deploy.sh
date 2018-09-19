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
#		/tmp/brokers, /tmp/zookeepers, /tmp/workers
#			NOTE: for some cluster configurations (eg a simple 1-node cluster),
#			all 3 files will specify the same server.
#
# Final state
#	Core services configured and running
#		Zookeeper on all nodes in /tmp/zookeepers
#		Kafka on all nodes in /tmp/brokers
#
#	Confluent services deployed on nodes defined by /tmp/workers
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


# We'll set the password for the kadmin user to
# private ... the instance_id.  For "secure" clusters,
# use a consistent password across ALL instances.
#
# Input: KADMIN_PASSWD {optional override}
#
update_kadmin_user() {
	if [ -z "$KADMIN_PASSWD" ] ; then
		grep -q -i "Enabled" /tmp/csecurity 2> /dev/null
		if [ $? -eq 0 ] ; then
			broker0_instance_id=$(head -1 /tmp/brokers | awk '{print $3}')
			KADMIN_PASSWD=${broker0_instance_id:-C0nfluent}
		else
			instance_id=$(curl -f -s $murl_top/id 2> /dev/null)
			KADMIN_PASSWD=${instance_id:-C0nfluent}
		fi
	fi

	if [ -n "$KADMIN_PASSWD" ] ; then
		passwd $KADMIN_USER << passwdEOF
$KADMIN_PASSWD
$KADMIN_PASSWD
passwdEOF
	fi

	export KADMIN_PASSWD
}

# For those circumstances where a minor problem exists in the
# VM Image, fixing it with the template script is simpler than
# publishing a new AMI.   The logic here should be BULLETPROOF.
#
patch_confluent_installation() {
	if [ -d $CP_HOME/share/java ] ; then
		CP_JAVA_DIR=${CP_HOME}/share/java
	else
		CP_JAVA_DIR=/usr/share/java
	fi

		# Known problem with 3.2.2 ... conflicting versions of servlet-api jar
    echo "Applying servlet-api patch to 3.2.2 (if necessary)" | tee -a $LOG
	if [ -f ${CP_JAVA_DIR}/kafka/javax.servlet-api-3.*.jar ] ; then
    	echo "  removing servlet-api-2*.jar files from kafka-connect-* libraries" | tee -a $LOG
		rm -f ${CP_JAVA_DIR}/kafka-connect-*/servlet-api-2*.jar
	fi
}

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
archive_cfg() {
	NOW=$(date +"%F-%H:%M")

	if [ -d $CP_HOME ] ; then  backup_dir=$CP_HOME/etc/archive_${NOW}
	else                       backup_dir=/etc/confluent_archive_${NOW}
	fi

	mkdir -p $backup_dir

	cp -p $ZK_CFG $backup_dir
	cp -p $BROKER_CFG $backup_dir
	cp -p $REST_PROXY_CFG $backup_dir
	cp -p $SCHEMA_REG_CFG $backup_dir
	cp -p $KAFKA_CONNECT_CFG $backup_dir
	cp -p $LEGACY_CONSUMER_CFG $backup_dir
	cp -p $CONTROL_CENTER_CFG $backup_dir
}

# Add/update config file parameter
#	$1 : config file
#	$2 : property
#	$3 : new value
#	$4 (optional) : 0: delete old value; 1[default]: retain old value
#
# The sed logic in this functions works given following limitations
#	1. At most one un-commented setting for a given parameter
#	2. If ONLY commented values exist, the FIRST ONE will be overwritten
#
set_property() {
	[ ! -f $1 ] && return 1

	local cfgFile=$1
	local property=$2
	local newValue=$3
	local doArchive=${4:-1}

	grep -q "^${property}=" $cfgFile
	overwriteMode=$?

	grep -q "^#${property}=" $cfgFile
	restoreMode=$?


	if [ $overwriteMode -eq 0 ] ; then
		if [ $doArchive -ne 0 ] ; then
				# Add the new setting, then comment out the old
			sed -i "/^${property}=/a ${property}=$newValue" $cfgFile
			sed -i "0,/^${property}=/s|^${property}=|# ${property}=|" $cfgFile
		else
			sed -i "s|^${property}=.*$|${property}=${newValue}|" $cfgFile
		fi
	elif [ $restoreMode -eq 0 ] ; then
				# "Uncomment" first entry, then replace it
				# This helps us by leaving the setting in the same place in the file
		sed -i "0,/^#${property}=/s|^#${property}=|${property}=|" $cfgFile
		sed -i "s|^${property}=.*$|${property}=${newValue}|" $cfgFile
	else
		echo "" >> $cfgFile
		echo "${property}=${newValue}" >> $cfgFile

	fi
}



# A series of sub-functions to update the key properties
# for the different services.
#
# TO DO
#	Replace this logic with the use of the dub tool

configure_confluent_zk() {
	[ ! -f $ZK_CFG ] && return 1

	grep -q ^initLimit $ZK_CFG
	[ $? -ne 0 ] && echo "initLimit=5" >> $ZK_CFG

	grep -q ^syncLimit $ZK_CFG
	[ $? -ne 0 ] && echo "syncLimit=2" >> $ZK_CFG

	myid=0
	zidx=1
	for znode in ${zknodes//,/ } ; do
		set_property $ZK_CFG "server.$zidx" "$znode:2888:3888" 0
		[ ${znode%%.*} = $THIS_HOST ] && myid=$zidx
		zidx=$[zidx+1]
	done

		# If we're not a ZK node, there's nothing more to do
	echo $zknodes | grep -q -w $THIS_HOST
	[ $? -ne 0 ] && return 0

		# Simple deployment : ZK data in $CP_HOME/zkdata
	CP_ZKDATA_DIR=${CP_HOME}/zkdata
	[ ! -d $CP_HOME ] && CP_ZKDATA_DIR=/zkdata

	mkdir -p $CP_ZKDATA_DIR
	chown --reference=$CP_ETC_DIR $CP_ZKDATA_DIR

	set_property $ZK_CFG "dataDir" "$CP_ZKDATA_DIR"
	set_property $ZK_CFG "autopurge.purgeInterval" 72		# purge the stale snapshots every 3 days

	if [ $myid -gt 0 ] ; then
		echo $myid > $CP_ZKDATA_DIR/myid
		chown --reference=$CP_ETC_DIR $CP_ZKDATA_DIR/myid
	fi
}

configure_kafka_broker() {
	[ ! -f $BROKER_CFG ] && return 1

	local numBrokers=`echo ${brokers//,/ } | wc -w`

	local ncpu=$(grep ^processor /proc/cpuinfo | wc -l)
	ncpu=${ncpu:-2}

	myid=-1
	bidx=0
	for bnode in ${brokers//,/ } ; do
		[ ${bnode%%.*} = $THIS_HOST ] && myid=$bidx
		bidx=$[bidx+1]
	done

		# Choose between explicit setting of broker.id or auto-generation
		# As of 3.1.2, ConfluentMetricsReporter class did not properly
		# report broker metrics when auto-generation was enabled.

	if [ $myid -ge 0 ] ; then
		set_property $BROKER_CFG "broker.id" "$myid"
	else
		sed -i "s/^broker\.id=.*$/# broker\.id=$myid/" $BROKER_CFG
		sed -i "s/^broker\.id\.generation\.enabled=false/broker\.id\.generation\.enabled=true/" $BROKER_CFG
	fi

		# Set target zookeeper quorum and VERY LONG timeout (5 minutes)
		# (since we don't know how long before other nodes will come on line)
	set_property $BROKER_CFG "zookeeper.connect" "$zconnect"
	set_property $BROKER_CFG "zookeeper.connection.timeout.ms" 300000

	if [ -n "$DATA_DIRS" ] ; then
		for d in $DATA_DIRS ; do
			chown --reference=$CP_ETC_DIR $d
		done

		set_property $BROKER_CFG "log.dirs" "${DATA_DIRS// /,}"
		set_property $BROKER_CFG "num.recovery.threads.per.data.dir" $[ncpu*4]

			# Could also bump num.io.threads (default: 8) and
			# num.network.threads (default: 3) here.
	fi

		# Simulate rack location based on availability domain
	THIS_AZ=$(curl -f -s ${murl_top}/availabilityDomain)
	if [ -n "$THIS_AZ" ] ; then
		set_property $BROKER_CFG "broker.rack" "$THIS_AZ"
	fi

		# Topic management settings
	set_property $BROKER_CFG "auto.create.topics.enable" "false"
	set_property $BROKER_CFG "delete.topic.enable" "true"

		# Enable graceful leader migration
	set_property $BROKER_CFG "controlled.shutdown.enable" "true"

		# For tracking activity in the cloud.
	set_property $BROKER_CFG "confluent.support.customer.id" "OCI_BYOL"

		# Enable replicator settings if the rebalancer is present
	which confluent-rebalancer &> /dev/null
	if [ $? -eq 0  -o  -x $CP_BIN_DIR/confluent-rebalancer ] ; then
		mr_topic_replicas=3
		[ $mr_topic_replicas -gt $numBrokers ] && mr_topic_replicas=$numBrokers

		set_property $BROKER_CFG "metric.reporters" "io.confluent.metrics.reporter.ConfluentMetricsReporter"
		set_property $BROKER_CFG "confluent.metrics.reporter.topic.replicas" "$mr_topic_replicas"
		set_property $BROKER_CFG "confluent.metrics.reporter.bootstrap.servers" "$bconnect"
		set_property $BROKER_CFG "confluent.metrics.reporter.zookeeper.connect" "$zconnect"
	fi
}

configure_schema_registry() {
	[ ! -f $SCHEMA_REG_CFG ] && return 1

	set_property $SCHEMA_REG_CFG "kafkastore.connection.url" "$zconnect"
	set_property $SCHEMA_REG_CFG "kafkastore.zk.session.timeout.ms" "300000"
	set_property $SCHEMA_REG_CFG "kafkastore.init.timeout.ms" "300000"
}

configure_rest_proxy() {
	[ ! -f $REST_PROXY_CFG ] && return 1

	myid=-1
	widx=0
	# It was using bnode instead of wnode. Assuming it was a bug,  replaced with wnode
	for wnode in ${workers//,/ } ; do
		[ ${wnode%%.*} = $THIS_HOST ] && myid=$widx
		widx=$[widx+1]
	done

	if [ $myid -ge 0 ] ; then
		set_property $REST_PROXY_CFG "id" "kafka-rest-${CLUSTERNAME}-${myid}" 0
	fi

		# TBD : get much smarter about Schema Registry Port
		# Should grab this from zookeeper if it's available
	set_property $REST_PROXY_CFG "schema.registry.url" "http://$srconnect" 0
	set_property $REST_PROXY_CFG "zookeeper.connect" "$zconnect" 0
	set_property $REST_PROXY_CFG "bootstrap.servers" "${bconnect}" 0

		# TBD (when the startup script includes interceptor classpath)
	# set_property $REST_PROXY_CFG "consumer.interceptor.classes" "io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor" 0
	# set_property $REST_PROXY_CFG "producer.interceptor.classes" "io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor" 0
}

# Configure the JAAS security and add it to the
# invocation of the Control Center application.
configure_control_center_security() {
	[ ! -f $CONTROL_CENTER_CFG ] && return 1

	CC_REALM=c3
	CC_ADMIN_ROLE=Administrators
	CC_CFG_DIR=$(dirname $CONTROL_CENTER_CFG)
	CC_JAAS_CONF=$CC_CFG_DIR/jaas.conf
	CC_JAAS_LOGIN_PROPERTIES=$CC_CFG_DIR/jaas-login.properties

    cat > $CC_JAAS_CONF << EOF_jaas_conf
$CC_REALM {
  org.eclipse.jetty.jaas.spi.PropertyFileLoginModule required
  	debug="true" file="$CC_JAAS_LOGIN_PROPERTIES";
};
EOF_jaas_conf

    cat > $CC_JAAS_LOGIN_PROPERTIES << EOF_jaas_login_properties
$KADMIN_USER: ${KADMIN_PASSWD:-C0nfluent}, $CC_ADMIN_ROLE
disallowed: no_access
EOF_jaas_login_properties

		# Lastly, update the start script to include
		# the JAAS specification (be paranoid ... add this
		# only if the CONF file was created)
	if [ -f $CC_JAAS_CONF  -a  -f $CC_JAAS_LOGIN_PROPERTIES ] ; then
		sed -i '/^bin_dir=/a \ \
export CONTROL_CENTER_OPTS=\"-Djava.security.auth.login.config='$CC_JAAS_CONF'\"' $CONTROL_CENTER_SCRIPT
	fi
}

configure_control_center() {
	[ ! -f $CONTROL_CENTER_CFG ] && return 1

	local ncpu=$(grep ^processor /proc/cpuinfo | wc -l)
	ncpu=${ncpu:-2}

	local numBrokers=`echo ${brokers//,/ } | wc -w`
	local numWorkers=`echo ${workers//,/ } | wc -w`

		# Configure the local storage location
		#	Put control center data on larger storage
		#		(if available and not used for broker storage)
	CC_DATA_DIR=${CC_DATA_DIR:-/var/lib/confluent/control-center}
	if [ -n "$DATA_DIRS" ] ; then
		echo "$brokers" | grep -q -w "$THIS_HOST"
		if [ $? -ne 0 ] ; then
			CC_DATA_DIR=${DATA_DIRS##* }
			CC_DATA_DIR=${CC_DATA_DIR}/confluent/control-center
		fi
	fi
	mkdir -p $CC_DATA_DIR
	chown --reference=$CP_ETC_DIR/confluent-control-center $CC_DATA_DIR
	set_property $CONTROL_CENTER_CFG "confluent.controlcenter.data.dir" "${CC_DATA_DIR}"

		# When Control Center is NOT hosted alongside brokers,
		# allow a few more threads if we won't compete with other
		# services (Control Center deserves a bigger percentage of worker-0)
	echo "$brokers" | grep -q -w "$THIS_HOST"
	if [ $? -ne 0 ] ; then
		if [ $numWorkers -gt 1  -a  $ncpu -gt 8 ] ; then
			set_property $CONTROL_CENTER_CFG "confluent.controlcenter.streams.num.stream.threads" "$ncpu"
		fi
	fi

		# REST properties for service
	set_property $CONTROL_CENTER_CFG "confluent.controlcenter.rest.compression.enable" "true"

	cc_topics_replicas=3
	[ $cc_topics_replicas -gt $numBrokers ] && cc_topics_replicas=$numBrokers

	monitoring_topics_replicas=2
	[ $monitoring_topics_replicas -gt $numBrokers ] && monitoring_topics_replicas=$numBrokers

	cc_partitions=5
	[ $cc_partitions -gt $numBrokers ] && cc_partitions=$numBrokers

		# Update properties for the Control Center
	set_property $CONTROL_CENTER_CFG "bootstrap.servers" "$bconnect" 0
	set_property $CONTROL_CENTER_CFG "zookeeper.connect" "$zconnect" 0

	set_property $CONTROL_CENTER_CFG "confluent.controlcenter.internal.topics.partitions" $cc_partitions
	set_property $CONTROL_CENTER_CFG "confluent.controlcenter.internal.topics.replication" $cc_topics_replicas
	set_property $CONTROL_CENTER_CFG "confluent.controlcenter.command.topic.partitions" $cc_partitions
	set_property $CONTROL_CENTER_CFG "confluent.controlcenter.command.topic.replication" $cc_topics_replicas
	set_property $CONTROL_CENTER_CFG "confluent.monitoring.interceptor.topic.partitions" $cc_partitions
	set_property $CONTROL_CENTER_CFG "confluent.monitoring.interceptor.topic.replication" $monitoring_topics_replicas

	set_property $CONTROL_CENTER_CFG "confluent.controlcenter.connect.cluster" "$wconnect" 0


		# Control Center installs separate Kafka Connect config files
		# ... customize those as well
	CC_CONNECT_CFG=$CP_ETC_DIR/confluent-control-center/connect-cc.properties
	cp -p $CP_ETC_DIR/schema-registry/connect-avro-distributed.properties $CC_CONNECT_CFG

	set_property $CC_CONNECT_CFG "consumer.interceptor.classes" "io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor" 0
	set_property $CC_CONNECT_CFG "producer.interceptor.classes" "io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor" 0

	set_property $CC_CONNECT_CFG "key.converter.schema.registry.url" "http://$srconnect" 0
	set_property $CC_CONNECT_CFG "value.converter.schema.registry.url" "http://$srconnect" 0
	set_property $CC_CONNECT_CFG "confluent.controlcenter.data.dir" "${CC_DATA_DIR}"
}

configure_workers() {
	if [ -f $LEGACY_CONSUMER_CFG ] ; then
		set_property $LEGACY_CONSUMER_CFG "group.id" "${CLUSTERNAME}-consumer-group"
		set_property $LEGACY_CONSUMER_CFG "zookeeper.connect" "$zconnect"
		set_property $LEGACY_CONSUMER_CFG "zookeeper.connection.timeout.ms" 30000
		set_property $LEGACY_CONSUMER_CFG "interceptor.classes" "io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor"
	fi

	if [ -f $LEGACY_PRODUCER_CFG ] ; then
		set_property $LEGACY_PRODUCER_CFG "bootstrap.servers" "${bconnect}"
		set_property $LEGACY_PRODUCER_CFG "request.timeout.ms" "100"
		set_property $LEGACY_PRODUCER_CFG "interceptor.classes" "io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor"
	fi

		# Configure the Kafka Connect workers
		#   We'll default to the Avro converters since we know
		#   we'll have the Schema Registry .   Also enable the
		#   interceptors for Control Center Monitoring

		# Starting with CP 3.3, Kafka Connect supports classpath isolation.  We'll put
		# extra connectors in here.
		# NOTE: this should match setting in cp-retrieve-connect-jars.sh
	grep -q -e "plugin.path" $KAFKA_CONNECT_CFG
	if [ $? -eq 0 ] ; then
		if [ -d $CP_HOME/share/java ] ; then
			KC_PLUGIN_DIR=${CP_HOME}/share/java/kc-plugins
			KC_PLUGIN_PATH=$CP_HOME/share/java,$KC_PLUGIN_DIR
		else
			KC_PLUGIN_DIR=/usr/share/java/kc-plugins
			KC_PLUGIN_PATH=/usr/share/java,$KC_PLUGIN_DIR
		fi
		mkdir -p $KC_PLUGIN_DIR
	fi

	if [ -f $KAFKA_CONNECT_CFG ] ; then
		set_property $KAFKA_CONNECT_CFG "group.id" "${CLUSTERNAME}-connect-cluster"
		set_property $KAFKA_CONNECT_CFG "bootstrap.servers" "${bconnect}"

		set_property $KAFKA_CONNECT_CFG  "key.converter" "io.confluent.connect.avro.AvroConverter"
		set_property $KAFKA_CONNECT_CFG  "key.converter.schema.registry.url" "http://${srconnect}"
		set_property $KAFKA_CONNECT_CFG  "key.converter.schemas.enable" "true"
		set_property $KAFKA_CONNECT_CFG  "value.converter" "io.confluent.connect.avro.AvroConverter"
		set_property $KAFKA_CONNECT_CFG  "value.converter.schema.registry.url" "http://${srconnect}"
		set_property $KAFKA_CONNECT_CFG  "value.converter.schemas.enable" "true"

		set_property $KAFKA_CONNECT_CFG  "consumer.interceptor.classes" "io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor"
		set_property $KAFKA_CONNECT_CFG  "producer.interceptor.classes" "io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor"

		[ -n "$KC_PLUGIN_PATH" ] && [ -d "$KC_PLUGIN_DIR" ] \
			&& set_property $KAFKA_CONNECT_CFG "plugin.path" "$KC_PLUGIN_PATH"
	fi

		# There are multiple "connect-*.properties" files in
		# the schema registry location that need to be updated as well
	for f in $CP_ETC_DIR/schema-registry/connect-*.properties ; do
		set_property $f "bootstrap.servers" "${bconnect}" 0
		set_property $f "key.converter.schema.registry.url" "http://${srconnect}" 0
		set_property $f "value.converter.schema.registry.url" "http://${srconnect}" 0
	done

	for f in $CP_ETC_DIR/schema-registry/*-distributed.properties ; do
		set_property $KAFKA_CONNECT_CFG "group.id" "${CLUSTERNAME}-connect-cluster" 0
	done
}

#
# Sets several important variables for use in sub-functions
#	zconnect : zookeeper connect arg (<host1>:<port1>[,<host2>:<port2> ...]
#	bconnect : broker connect arg (<host1>:<port1>[,<host2>:<port2> ...]
#	srconnect : schema registry connect arg (<host1>:<port1>[,<host2>:<port2> ...]
#
# TBD : We could be smarter about bconnect, putting only a few hosts in the list
# rather than all of them.
configure_confluent_node() {
		# Assemble Zookeeper Connect and Broker List strings  once,
		# since we may use themm in multiple places
	if [ -f $ZK_CFG ] ; then
		eval $(grep ^clientPort= $ZK_CFG)
		zkPort=${clientPort:-2181}
	fi

	zconnect=""
	for znode in ${zknodes//,/ } ; do
		if [ -z "$zconnect" ] ; then
			zconnect="$znode:${zkPort:-2181}"
		else
			zconnect="$zconnect,$znode:${zkPort:-2181}"
		fi
	done

	if [ -f $BROKER_CFG ] ; then
		eval $(grep ^listeners= $BROKER_CFG)
		brokerPort=${listeners##*:}
		brokerPort=${brokerPort:-9092}
	fi

	bconnect=""
	for bnode in ${brokers//,/ } ; do
		if [ -z "$bconnect" ] ; then
			bconnect="$bnode:${brokerPort:-9092}"
		else
			bconnect="$bconnect,$bnode:${brokerPort:-9092}"
		fi
	done

		# Schema Registry runs on the second worker
	numWorkers=$(echo "${workers//,/ }" | wc -w)
	if [ $numWorkers -le 1 ] ; then
		srconnect=${workers%%,*}:8081
	else
		srconnect=$(echo $workers | cut -d, -f2)
		srconnect=${srconnect}:8081
	fi


	if [ -f $KAFKA_CONNECT_CFG ] ; then
		connectRestPort=$(grep -e ^rest.port= $KAFKA_CONNECT_CFG | cut -d'=' -f2)
		connectRestPort=${connectRestPort:-8083}
	fi

		# REST path for Connect workers (probably don't need all of them)
	wconnect=""
	for wnode in ${workers//,/ } ; do
		if [ -z "$wconnect" ] ; then
			wconnect="$wnode:${connectRestPort:-8083}"
		else
			wconnect="$wconnect,$wnode:${connectRestPort:-8083}"
		fi
	done

		# Remember that Connect won't run on worker0 if we have more than 1 worker
	#if [ $numWorkers -gt 1 ] ; then
	#	wconnect=${wconnect##*,}
	#fi

		# Save off the configuration details before making our changes.
	archive_cfg

	configure_confluent_zk
	configure_kafka_broker
	configure_schema_registry
	configure_rest_proxy

	configure_workers
	[ -n "$workers" ] && configure_control_center

		# Custom configuration when security is enabled
	grep -q -i "Enabled" /tmp/csecurity 2> /dev/null
	if [ $? -eq 0 ] ; then
		[ -n "$workers" ] && configure_control_center_security
	fi
}

# Sets memory allocation in start scripts
#	Assumes that the "locate_start_scripts" has been run
#
update_service_heap_opts() {
	if [ ! -x $SCRIPTDIR/compute-heap-opts ] ; then
		return
	fi

	ZK_SCRIPT=${BIN_DIR}/zookeeper-server-start
	BROKER_SCRIPT=${BIN_DIR}/kafka-server-start
		# Source the script that sets *_HEAP_OPTS
	. $SCRIPTDIR/compute-heap-opts

		# Since the ZK_SCRIPT already has an override, we need to
		# be careful and replace it in the right place
	echo "$zknodes" | grep -q -w "$THIS_HOST"
	if [ $? -eq 0  -a  -n "$ZOOKEEPER_HEAP_OPTS" ] ; then
		sed -i "/ export KAFKA_HEAP_OPTS=/a\ \ \ \ export KAFKA_HEAP_OPTS=\"$ZOOKEEPER_HEAP_OPTS\"" $ZK_SCRIPT
		sed -i "0,/ export KAFKA_HEAP_OPTS=/s| export KAFKA_HEAP_OPTS=|#export KAFKA_HEAP_OPTS==|" $ZK_SCRIPT
	fi

		# Since the BROKER_SCRIPT already has an override, we need to
		# be careful and replace it in the right place
	echo "$brokers" | grep -q -w "$THIS_HOST"
	if [ $? -eq 0  -a  -n "$BROKER_HEAP_OPTS" ] ; then
		sed -i "/ export KAFKA_HEAP_OPTS=/a\ \ \ \ export KAFKA_HEAP_OPTS=\"$BROKER_HEAP_OPTS\"" $BROKER_SCRIPT
		sed -i "0,/ export KAFKA_HEAP_OPTS=/s| export KAFKA_HEAP_OPTS=|#export KAFKA_HEAP_OPTS==|" $BROKER_SCRIPT
	fi

	echo "$workers" | grep -q -w "$THIS_HOST"
	if [ $? -eq 0 ] ; then
		[ -n "$CONNECT_HEAP_OPTS" ] && \
		  sed -i "/^exec /i export KAFKA_HEAP_OPTS=\"$CONNECT_HEAP_OPTS\"" $KAFKA_CONNECT_SCRIPT
		[ -n "$REST_HEAP_OPTS" ] && \
		  sed -i "/^exec /i export KAFKAREST_HEAP_OPTS=\"$REST_HEAP_OPTS\"" $REST_PROXY_SCRIPT
	fi

		# Control Center is the first worker
	#if [ "${workers%%,*}" = $THIS_HOST ] ; then
	echo "$workers" | grep -q -w "$THIS_HOST"
	if [ $? -eq 0 ] ; then
		[ -n "$CC_HEAP_OPTS" ] && \
		  sed -i "/^exec /i export CONTROL_CENTER_HEAP_OPTS=\"$CC_HEAP_OPTS\"" $CONTROL_CENTER_SCRIPT
	fi

		# Schema registy on second worker (or first if there's only one)
	numWorkers=$(echo "${workers//,/ }" | wc -w)
	if [ $numWorkers -le 1 ] ; then
		srWorker=${workers%%,*}
	else
		srWorker=$(echo $workers | cut -d, -f2)
	fi

  #if [ "${srWorker}" = $THIS_HOST ] ; then
	echo "$srWorkers" | grep -q -w "$THIS_HOST"
	if [ $? -eq 0 ] ; then
		[ -n "$SR_HEAP_OPTS" ] && \
		  sed -i "/^exec /i export SCHEMA_REGISTRY_HEAP_OPTS=\"$SR_HEAP_OPTS\"" $SCHEMA_REG_SCRIPT
	fi
}

# Simple code to wait for formation of zookeeper quorum.
# We know that the "kafka-topics" call to retrieve metadata
# won't work until the quorum is formed ... so use that
# if the cub utility is not present.
#
wait_for_zk_quorum() {

    ZOOKEEPER_WAIT=${1:-300}
    STIME=5

	if [ -x $SCRIPTDIR/cub  -a  -f $SCRIPTDIR/docker-utils.jar ] ; then
		DOCKER_UTILS_JAR=$SCRIPTDIR/docker-utils.jar $SCRIPTDIR/cub zk-ready $zconnect $ZOOKEEPER_WAIT

		[ $? -ne 0 ] && return 1
    	sleep $STIME		# still need some stabilization time

	else
    	SWAIT=$ZOOKEEPER_WAIT
    	${CP_BIN_DIR}/kafka-topics --list --zookeeper ${zconnect} &> /dev/null
    	while [ $? -ne 0  -a  $SWAIT -gt 0 ] ; do
        	sleep $STIME
        	SWAIT=$[SWAIT - $STIME]
    		${CP_BIN_DIR}/kafka-topics --list --zookeeper ${zconnect} &> /dev/null
    	done

		[ $SWAIT -le 0 ] && return 1
	fi

	return 0
}

# Kludgy function to make sure the cluster is formed before
# proceeding with the remaining startup activities.
#
# Later versions of the image will have the
# "Confluent Utility Belt" (cub) utility; use that if present.
#
#	NOTE: We only need to wait for other brokers if THIS NODE
#		is a broker or worker.  zookeeper-only nodes need not
#		waste time here
wait_for_brokers() {
	echo "$brokers" | grep -q -w "$THIS_HOST"
	if [ $? -ne 0 ] ; then
		echo "$workers" | grep -q -w "$THIS_HOST"
		[ $? -ne 0 ] && return 0
	fi

    BROKER_WAIT=${1:-300}
    STIME=5

		# Now that we know the ZK cluster is on line, we can check the number
		# of registered brokers.  Ideally, we'd just look for "enough" brokers,
		# hence the "targetBrokers" logic below
		#
	local numBrokers=`echo ${brokers//,/ } | wc -w`
	local targetBrokers=$numBrokers
	[ $targetBrokers -gt 5 ] && targetBrokers=5

	if [ -x $SCRIPTDIR/cub  -a  -f $SCRIPTDIR/docker-utils.jar ] ; then
		DOCKER_UTILS_JAR=$SCRIPTDIR/docker-utils.jar $SCRIPTDIR/cub kafka-ready -b $bconnect $targetBrokers $BROKER_WAIT
		[ $? -ne 0 ] && return 1

	else
		SWAIT=$BROKER_WAIT
		local runningBrokers=$( echo "ls /brokers/ids" | $CP_BIN_DIR/zookeeper-shell ${zconnect%%,*} | grep '^\[' | tr -d "[:punct:]" | wc -w )
    	while [ $? -ne 0 -a ${runningBrokers:-0} -lt $targetBrokers  -a  $SWAIT -gt 0 ] ; do
        	sleep $STIME
        	SWAIT=$[SWAIT - $STIME]
			runningBrokers=$( echo "ls /brokers/ids" | $CP_BIN_DIR/zookeeper-shell ${zconnect%%,*} | grep '^\[' | tr -d "[:punct:]" | wc -w )
    	done

		[ $SWAIT -le 0 ] && return 1
	fi

	return 0
}



# Use host role to determine services to start.
# Separate "core" and "worker" services, since we
# may need to do some work within the brokers once
# they are able to respond to admin requests.
#
# Configure appropriate services for auto-start
#
#	DANGER : the systemctl logic needs the control
#	operations to run from the SAME LOCATION.  You
#	cannot start with "$CP_HOME/initscripts/cp-*-service"
#	and then stop with "/etc/init.d/cp-*-service"
#
start_core_services() {
	echo "$zknodes" | grep -q -w "$THIS_HOST"
	if [ $? -eq 0 ] ; then
		if [ -x $CP_HOME/initscripts/cp-zk-service ] ; then
			ln -s  $CP_HOME/initscripts/cp-zk-service  /etc/init.d
			chkconfig cp-zk-service on
			[ $? -ne 0 ] && systemctl enable cp-zk-service

#			$CP_HOME/initscripts/cp-zk-service start
#			/etc/init.d/cp-zk-service start
			service cp-zk-service start
		else
			$CP_BIN_DIR/zookeeper-server-start -daemon $ZK_CFG
		fi
	fi

	echo "$brokers" | grep -q -w "$THIS_HOST"
	if [ $? -eq 0 ] ; then
		wait_for_zk_quorum
		if [ $? -ne 0 ] ; then
        	echo "  WARNING: Zookeeper Quorum not formed; broker start may fail" | tee -a $LOG
		fi

		if [ -x $CP_HOME/initscripts/cp-kafka-service ] ; then
			ln -s  $CP_HOME/initscripts/cp-kafka-service  /etc/init.d
			chkconfig cp-kafka-service on
			[ $? -ne 0 ] && systemctl enable cp-kafka-service

#			$CP_HOME/initscripts/cp-kafka-service start
#			/etc/init.d/cp-kafka-service start
			service cp-kafka-service start
		else
			$CP_BIN_DIR/kafka-server-start -daemon $BROKER_CFG
		fi
	fi
}

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
		# (files created by gen-cluster-hosts.sh)
	bhosts=$(awk '{print $1}' /tmp/brokers)
	if [ -n "bhosts" ] ; then
		brokers=`echo $bhosts`			# convert <\n> to ' '
	fi
	brokers=${brokers// /,}

	zkhosts=$(awk '{print $1}' /tmp/zookeepers)
	if [ -n "$zkhosts" ] ; then
		zknodes=`echo $zkhosts`			# convert <\n> to ' '
	fi
	zknodes=${zknodes// /,}		# not really necessary ... but safe

			# external workers
	whosts=$(awk '{print $1}' /tmp/workers)
	if [ -n "whosts" ] ; then
		workers=`echo $whosts`			# convert <\n> to ' '
	fi
	workers=${workers// /,}

	if [ -z "${zknodes}"  -o  -z "${brokers}" ] ; then
	    echo "Insufficient specification for Confluent Platform cluster ... terminating script" >> $LOG
		exit 1
	fi

		# Make sure THIS_HOST is set.  Necessary when DNS resolution is slow.
	while [ -z "$THIS_HOST" ] ; do
		sleep 3
		THIS_HOST=$(hostname -s)
	done

	update_kadmin_user

		# Make sure DATA_DIRS is set.   If it is not passed in (or obvious
		# from the log file generated when we initialized the storage),
		# we can simply look for all "data*" directories # in $CP_HOME.
		# $CP_HOME/data*  will have been created (or linked) by prepare-disks.sh script.
	if [ -z "$DATA_DIRS" ] ; then
		if [ -f /tmp/prepare-disks.log ] ; then
			eval $(grep ^DATA_DIRS= /tmp/prepare-disks.log)
		fi
	fi

	[ -z "$DATA_DIRS" ] && DATA_DIRS=$(ls -d $CP_HOME/data*)

	patch_confluent_installation

	locate_cfg
	locate_start_scripts
	configure_confluent_node
	update_service_heap_opts

	start_core_services
	wait_for_brokers 600 			# rudimentary function

	create_worker_topics
	start_worker_services
	[ -n "$workers" ] && [ -f $CONTROL_CENTER_CFG ] && start_control_center

    echo "$0 script finished at "`date` >> $LOG
}


main $@
exitCode=$?

set +x

exit $exitCode
