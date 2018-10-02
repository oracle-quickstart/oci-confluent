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
sudo echo "search public0.cfvcn.oraclevcn.com public1.cfvcn.oraclevcn.com public2.cfvcn.oraclevcn.com" > /etc/resolv.conf
sudo echo "nameserver 169.254.169.254" >> /etc/resolv.conf




AMI_SBIN=/tmp/sbin
$AMI_SBIN/iscsi.sh
$AMI_SBIN/prep-cp-instance.sh
. $AMI_SBIN/prepare-disks.sh

touch /tmp/boot.sh.tpl.complete

echo "boot.sh.tpl setup complete"


## TODO - Add logic to install custom connectors
#1if [ -n "$CONNECTOR_URLS" ] ; then 
#1  for csrc in $${CONNECTOR_URLS//,/ } ; do 
#1    $AMI_SBIN/cp-retrieve-connect-jars.sh $csrc 2>&1 | tee -a /tmp/cp-retrieve-connect-jars.err 
#1  done 
#1fi

# Confluent Platform node deployment complete


set +x 
 
