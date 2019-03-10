echo "Running zookeeper.sh"

#######################################################
################# Configure ZooKeeper #################
#######################################################
echo "Configuring ZooKeeper..."

# 1. Navigate to the ZooKeeper properties file (/etc/kafka/zookeeper.properties) file and modify as shown.

echo "tickTime=2000
dataDir=/var/lib/zookeeper/
clientPort=2181
initLimit=5
syncLimit=2
server.1=zoo1:2888:3888
server.2=zoo2:2888:3888
server.3=zoo3:2888:3888
autopurge.snapRetainCount=3
autopurge.purgeInterval=24
" > /etc/kafka/zookeeper.properties
