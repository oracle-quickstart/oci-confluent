echo "Running zookeeper.sh"

echo "Configuring ZooKeeper..."

# Here's the install doc:
# https://docs.confluent.io/current/installation/installing_cp/rhel-centos.html#zk

# 1. Navigate to the ZooKeeper properties file (/etc/kafka/zookeeper.properties) file and modify as shown.

echo "tickTime=2000
dataDir=/var/lib/zookeeper/
clientPort=2181
initLimit=5
syncLimit=2
" > /etc/kafka/zookeeper.properties

# Update zookeeper.properties with zookeeper node info
for index in `seq 0 $((zookeeperNodeCount-1))` ; do echo "server.${index}=zookeeper-${index}:2888:3888" >> /etc/kafka/zookeeper.properties  ; done ;

echo "autopurge.snapRetainCount=3
autopurge.purgeInterval=24
" >> /etc/kafka/zookeeper.properties


# Update zookeeper.properties with zookeeper node info
#for index in `seq 0 $((zookeeperNodeCount-1))` ; do echo "server.${index}=zookeeper-${index}:2888:3888" >> /tmp/zk.txt  ; done ;


nodeIndex=`hostname | sed 's/zookeeper-//'`
echo "$nodeIndex" > /var/lib/zookeeper/myid

###### unclear if any of this is needed... try to remove....
chown cp-kafka /var/lib/zookeeper/myid
chgrp confluent /var/lib/zookeeper/myid
chmod 666 /var/lib/zookeeper/myid

###### this came from a suggestion in the logs... check if needed and maybe remove....
chown cp-kafka:confluent /var/log/confluent
chmod u+wx,g+wx,o= /var/log/confluent

echo "Starting ZooKeeper..."
systemctl start confluent-zookeeper
