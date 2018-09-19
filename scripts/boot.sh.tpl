#!/bin/bash
## cloud-init bootstrap script

set -x 

THIS_FQDN=`hostname --fqdn`
THIS_HOST=$${THIS_FQDN%%.*}



do_curl_retrieval() {
        SRC_URL=$${1%/}
        curl -f -s $SRC_URL/$LFILE -o $TARGET_DIR/$LFILE \
                --retry $MAX_RETRIES --retry-max-time 60
        [ $? -ne 0 ] && return 1
        local rval=0
        for f in $(cat $TARGET_DIR/$LFILE) ; do
                [ -z "$f" ] && continue
                curl -f -s $SRC_URL/$f -o $TARGET_DIR/$f \
                        --retry $MAX_RETRIES --retry-max-time 180
                [ $? -ne 0 ] && rval=1
                chmod a+x $TARGET_DIR/$f
        done
        return $rval
}



echo ${ClusterName} > /tmp/clustername
echo ${ConfluentEdition} > /tmp/cedition
echo ${ConfluentSecurity} > /tmp/csecurity
[ "${ConfluentSecurity}" = 'Disabled' ] && rm /tmp/csecurity
echo ${ConfluentVersion} > /tmp/cversion
CONNECTOR_URLS=${ConnectorURLs}


echo ${ZookeeperNodeCount} > /tmp/zookeepernodecount
echo ${BrokerNodeCount} > /tmp/brokernodecount
echo ${WorkerNodeCount} > /tmp/workernodecount



TARGET_DIR=/tmp/sbin
mkdir $TARGET_DIR
LFILE=scripts.lst
SCRIPT_SRC="https://objectstorage.us-phoenix-1.oraclecloud.com/n/intmahesht/b/oci-quickstart/o/quickstart-confluent-kafka/scripts/"
MAX_RETRIES=10
do_curl_retrieval $SCRIPT_SRC
if [ $? -ne 0 ] ; then
     echo "do_curl_retrieval failed"
fi


set -x 
if [ -f /tmp/brokernodecount ] ; then
        BROKER_NODE_COUNT=$(cat /tmp/brokernodecount)
else
        echo "/tmp/brokernodecount file missing. exiting"
        exit 1
fi

if [ -f /tmp/zookeepernodecount ] ; then
        ZOOKEEPER_NODE_COUNT=$(cat /tmp/zookeepernodecount)
else
        echo "/tmp/zookeepernodecount file missing. exiting"
        exit 1
fi

if [ -f /tmp/workernodecount ] ; then
        WORKER_NODE_COUNT=$(cat /tmp/workernodecount)
else
        echo "/tmp/workernodecount file missing. exiting"
        exit 1
fi


## Set DNS to resolve all subnet domains
sudo rm -f /etc/resolv.conf
sudo echo "search public0.cfvcn.oraclevcn.com public1.cfvcn.oraclevcn.com public2.cfvcn.oraclevcn.com private0.cfvcn.oraclevcn.com private1.cfvcn.oraclevcn.com private2.cfvcn.oraclevcn.com" > /etc/resolv.conf
sudo echo "nameserver 169.254.169.254" >> /etc/resolv.conf



## Cleanup any exiting files just in case
if [ -f /tmp/cphosts ]; then
        rm -f /tmp/cphosts;
        rm -f /tmp/brokers;
        rm -f /tmp/zookeepers;
        rm -f /tmp/workers;
fi

# First do some network & host discovery
domain="cfvcn.oraclevcn.com"
BROKER_HOSTNAME_PREFIX="cf-broker-"
echo "Doing nslookup for Broker nodes"
ct=1;
if [ `cat /tmp/brokernodecount` -gt 0 ]; then
        while [ $ct -le `cat /tmp/brokernodecount` ]; do
                nslk=`nslookup $BROKER_HOSTNAME_PREFIX$${ct}`
                ns_ck=`echo -e $?`
                if [ $ns_ck = 0 ]; then
                        hname=`nslookup $BROKER_HOSTNAME_PREFIX$${ct} | grep Name | gawk '{print $2}'`
                        echo "$hname" >> /tmp/cphosts;
                        echo "$hname" >> /tmp/brokers;
                        ct=$((ct+1));
                else
                        # sleep 10 seconds and check again - infinite loop
                        echo "Sleeping for 10 secs and will check again for nslookup $BROKER_HOSTNAME_PREFIX$${ct}"
                        sleep 10
                fi
        done;
        echo "Found `cat /tmp/brokers | wc -l` nodes";
        echo `cat /tmp/brokers`;
else
        echo "no broker nodes configured, should not happen"
fi


echo "Doing nslookup for Zookeeper nodes"
ct=1;
ZOOKEEPER_HOSTNAME_PREFIX="cf-zookeeper-"
if [ `cat /tmp/zookeepernodecount` -gt 0 ]; then
        while [ $ct -le `cat /tmp/zookeepernodecount` ]; do
                nslk=`nslookup $ZOOKEEPER_HOSTNAME_PREFIX$${ct}`
                ns_ck=`echo -e $?`
                if [ $ns_ck = 0 ]; then
                        hname=`nslookup $ZOOKEEPER_HOSTNAME_PREFIX$${ct} | grep Name | gawk '{print $2}'`
                        echo "$hname" >> /tmp/cphosts;
                        echo "$hname" >> /tmp/zookeepers;
                        ct=$((ct+1));
                else
                        # sleep 10 seconds and check again - infinite loop
                        echo "Sleeping for 10 secs and will check again for nslookup $ZOOKEEPER_HOSTNAME_PREFIX$${ct}"
                        sleep 10
                fi
        done;
        echo "Found `cat /tmp/zookeepers | wc -l` nodes";
        echo `cat /tmp/zookeepers`;
else
        echo "no dedicated zooker nodes configured, use first 3 broker nodes as zookeeper nodes"
        head -3 /tmp/brokers > /tmp/zookeepers
fi




echo "Doing nslookup for Worker nodes"
ct=1;
WORKER_HOSTNAME_PREFIX="cf-worker-"
if [ `cat /tmp/workernodecount` -gt 0 ]; then
        while [ $ct -le `cat /tmp/workernodecount` ]; do
                nslk=`nslookup $WORKER_HOSTNAME_PREFIX$${ct}`
                ns_ck=`echo -e $?`
                if [ $ns_ck = 0 ]; then
                        hname=`nslookup $WORKER_HOSTNAME_PREFIX$${ct} | grep Name | gawk '{print $2}'`
                        echo "$hname" >> /tmp/cphosts;
                        echo "$hname" >> /tmp/workers;
                        ct=$((ct+1));
                else
                        # sleep 10 seconds and check again - infinite loop
                        echo "Sleeping for 10 secs and will check again for nslookup $WORKER_HOSTNAME_PREFIX$${ct}"
                        sleep 10
                fi
        done;
        echo "Found `cat /tmp/workers | wc -l` nodes";
        echo `cat /tmp/workers`;
else
        echo "no dedicated  worker nodes configured, use broker nodes as workers "
        cp /tmp/brokers /tmp/workers
fi



### Firewall setup based on node type
## Get hostname ready in variables 
bhosts=$(awk '{print $1}' /tmp/brokers)
if [ -n "bhosts" ] ; then
	brokers=`echo $bhosts`			# convert <\n> to ' '
fi
brokers=$${brokers// /,}

zkhosts=$(awk '{print $1}' /tmp/zookeepers)
if [ -n "$zkhosts" ] ; then
	zknodes=`echo $zkhosts`			# convert <\n> to ' '
fi
zknodes=$${zknodes// /,}		# not really necessary ... but safe

	# external workers
whosts=$(awk '{print $1}' /tmp/workers)
if [ -n "whosts" ] ; then
	workers=`echo $whosts`			# convert <\n> to ' '
fi
workers=$${workers// /,}

if [ -z "$${zknodes}"  -o  -z "$${brokers}" ] ; then
	echo "Insufficient specification for Confluent Platform cluster ... terminating script" >> $LOG
	exit 1
fi


## Adding whitelist for network to local firewall
local_network=${VPCCIDR}
echo -e "\tAdding whitelist for network $local_network to local firewall on $THIS_HOST"
sudo firewall-offline-cmd --zone=public --add-source=$local_network


## Broker Firewall
                echo "$brokers" | grep -q -w "$THIS_HOST"
                if [ $? -eq 0 ] ; then
                        sudo firewall-offline-cmd --zone=public --add-port=9092/tcp 
                fi

## Zookeeper Firewall
                echo "$zknodes" | grep -q -w "$THIS_HOST"
                if [ $? -eq 0 ] ; then
                        sudo firewall-offline-cmd --zone=public --add-port=2181/tcp
			sudo firewall-offline-cmd --zone=public --add-port=2888/tcp
			sudo firewall-offline-cmd --zone=public --add-port=3888/tcp 
                fi

## REST Proxy Firewall
                echo "$workers" | grep -q -w "$THIS_HOST"
                if [ $? -eq 0 ] ; then
                        sudo firewall-offline-cmd --zone=public --add-port=8082/tcp 
                fi


## Kafka Connect REST API
		numWorkers=$(echo "$${workers//,/ }" | wc -w)
		wconnect=$workers
		# Remember that Connect won't run on worker0 if we have more than 1 worker
		#if [ $numWorkers -gt 1 ] ; then
		#	wconnect=$${wconnect##*,}
		#fi

                echo "$wconnect" | grep -q -w "$THIS_HOST"
                if [ $? -eq 0 ] ; then
                        sudo firewall-offline-cmd --zone=public --add-port=8083/tcp 
                fi



## SchemaRegistry Firewall
	# Schema registy on second worker (or first if there's only one)
	numWorkers=$(echo "$${workers//,/ }" | wc -w)
	if [ $numWorkers -le 1 ] ; then
		srWorker=$${workers%%,*}
	else
		srWorker=$(echo $workers | cut -d, -f2)
	fi

	echo "$srWorker" | grep -q -w "$THIS_HOST"
	if [ $? -eq 0 ] ; then
		sudo firewall-offline-cmd --zone=public --add-port=8081/tcp 
	fi

## Control Center Firewall
                ccWorker=$(echo $workers | cut -d, -f1)
		echo "$ccWorker" | grep -q -w "$THIS_HOST"
	        if [ $? -eq 0 ] ; then
        	        sudo firewall-offline-cmd --zone=public --add-port=9021/tcp 
	        fi

## Enable and Start firewall for changes to be effective.
systemctl enable firewalld
systemctl start firewalld

## File generated.  Will be used by other script. Reload of firewall needed to make above changes effective
## firewall-reload.sh 
touch /tmp/firewallportsadded



AMI_SBIN=/tmp/sbin
$AMI_SBIN/iscsi.sh
$AMI_SBIN/prep-cp-instance.sh
. $AMI_SBIN/prepare-disks.sh



## Run the steps to install the software, 
## then configure and start the services 
$AMI_SBIN/cp-install.sh 2> /tmp/cp-install.err 
$AMI_SBIN/cp-deploy.sh 2> /tmp/cp-deploy.err 


#1if [ -n "$CONNECTOR_URLS" ] ; then 
#1  for csrc in $${CONNECTOR_URLS//,/ } ; do 
#1    $AMI_SBIN/cp-retrieve-connect-jars.sh $csrc 2>&1 | tee -a /tmp/cp-retrieve-connect-jars.err 
#1  done 
#1fi

# Confluent Platform node deployment complete


set +x 
 
