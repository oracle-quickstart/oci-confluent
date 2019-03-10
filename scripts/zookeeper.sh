echo "Running zookeeper.sh"

#######################################################
################# Configure ZooKeeper #################
#######################################################
echo "Configuring ZooKeeper..."

# 1. Navigate to the ZooKeeper properties file (/etc/kafka/zookeeper.properties) file and modify as shown.

################ nodes are hardcoded to three right now.  Come back and fix this later....

echo "tickTime=2000
dataDir=/var/lib/zookeeper/
clientPort=2181
initLimit=5
syncLimit=2
server.1=zookeeper-0:2888:3888
server.2=zookeeper-0:2888:3888
server.3=zookeeper-0:2888:3888
autopurge.snapRetainCount=3
autopurge.purgeInterval=24
" > /etc/kafka/zookeeper.properties
