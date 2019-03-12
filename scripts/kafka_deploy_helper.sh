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

echo "Setting SchemaRegistry Connection String..."
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

# function to check if all zookeepers are running or else wait 
wait_for_zk_quorum() {
  command="/usr/bin/kafka-topics --list --zookeeper ${zookeeperConnect} &> /dev/null"
  counter=60
  sleepTime=5s
  eval "$command"
  while [ $? -ne 0  -a  $counter -gt 0 ] ; do
    sleep $sleepTime
    counter=$((counter-1))
    echo $counter
    eval "$command"
  done
  [ $counter -le 0 ] && return 1

  return 0
}


# function to check if all brokers are running or else wait
wait_for_brokers() {
  command="runningBrokers=$( echo "ls /brokers/ids" | /usr/bin/zookeeper-shell ${zookeeperConnect%%,*} | grep -v "zk\:" |  grep '^\[' | tr -d "[:punct:]" | wc -w )"
  # We don't need all brokers to be up, we just need a few, say 5, if the cluster is much larger
  local targetBrokers=$brokerNodeCount
  [ $targetBrokers -gt 5 ] && targetBrokers=5
  eval "$command"
  while [ ${runningBrokers:-0} -lt $targetBrokers -a $counter -gt 0 ] ; do
    sleep $sleepTime
    counter=$((counter-1))
    echo $counter
    eval "$command"
  done

  [ $counter -le 0 ] && return 1

  return 0
}

# function to check if schema registry is running or else wait
wait_for_schema_registry() {
  command="wget http://${schemaRegistryConnect}/ &> /dev/null"
  counter=60
  sleepTime=5s
  eval "$command"
  while [ $? -ne 0  -a  $counter -gt 0 ] ; do
    sleep $sleepTime
    counter=$((counter-1))
    echo $counter
    eval "$command"
  done
  [ $counter -le 0 ] && return 1

  return 0
}

