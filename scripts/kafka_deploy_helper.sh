echo "Setting common variables needed by multiple nodes"

set -x 

echo "Got the parameters:"
echo version \'$version\'
echo edition \'$edition\'
echo zookeeperNodeCount \'$zookeeperNodeCount\'
echo brokerNodeCount \'$brokerNodeCount\'
echo schemaRegistryNodeCount \'$schemaRegistryNodeCount\'


echo "Setting Zookeeper Connection Strings..."

zookeeperConnect=""
zookeeperHostPrefix="zookeeper-"
for i in `seq 0 $((zookeeperNodeCount-1))` 
do 
  if [ -z "$zookeeperConnect" ] ; then
    zookeeperConnect="$zookeeperHostPrefix${i}:2181"
  else
    zookeeperConnect="$zookeeperConnect,$zookeeperHostPrefix${i}:2181"
  fi
done
echo "zookeeperConnect=$zookeeperConnect"

echo "Setting Broker Connection Strings..."

brokerConnect=""
brokerHostPrefix="broker-"
for i in `seq 0 $((brokerNodeCount-1))`
do
  if [ -z "$brokerConnect" ] ; then
    brokerConnect="$brokerHostPrefix${i}:9092"
  else
    brokerConnect="$brokerConnect,$brokerHostPrefix${i}:9092"
  fi
done
echo "brokerConnect=$brokerConnect"

schemaRegistryConnect=""
schemaRegistryHostPrefix="schema-registry-"
for i in `seq 0 $((schemaRegistryNodeCount-1))`
do
  if [ -z "$schemaRegistryConnect" ] ; then
    schemaRegistryConnect="$schemaRegistryHostPrefix${i}:8081"
  else
    schemaRegistryConnect="$schemaRegistryConnect,$schemaRegistryHostPrefix${i}:8081"
  fi
done
echo "schemaRegistryConnect=$schemaRegistryConnect"


