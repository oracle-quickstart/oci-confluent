echo "Running zookeeper.sh"

echo "Configuring ZooKeeper..."

# Here's the install doc:
# https://docs.confluent.io/current/installation/installing_cp/rhel-centos.html#zk

# 1. Navigate to the ZooKeeper properties file (/etc/kafka/zookeeper.properties) file and modify as shown.

################ nodes are hardcoded to three right now.  Come back and fix this later....

cp /etc/kafka/zookeeper.properties /etc/kafka/zookeeper.properties.bak

echo "tickTime=2000
dataDir=/var/lib/zookeeper/
clientPort=2181
initLimit=5
syncLimit=2
server.1=zookeeper-0:2888:3888
server.2=zookeeper-1:2888:3888
server.3=zookeeper-2:2888:3888
autopurge.snapRetainCount=3
autopurge.purgeInterval=24
" > /etc/kafka/zookeeper.properties

nodeIndex=`hostname | sed 's/zookeeper-//'`
echo "'$nodeIndex'" > /var/lib/zookeeper/myid

# unclear if any of this is needed...
chown cp-kafka /var/lib/zookeeper/myid
chgrp confluent /var/lib/zookeeper/myid
chmod 666 /var/lib/zookeeper/myid

# this came from a suggestion in the logs...
chown cp-kafka:confluent /var/log/confluent
chmod u+wx,g+wx,o= /var/log/confluent

echo "Starting ZooKeeper..."
systemctl start confluent-zookeeper
