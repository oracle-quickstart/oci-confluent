echo "Running broker.sh"

set -x 

echo "Configuring Kafka Broker..."

# Here's the install doc:
# https://docs.confluent.io/current/installation/installing_cp/rhel-centos.html#kafka

sed -i "s/^zookeeper\.connect=localhost\:2181/zookeeper\.connect=$zookeeperConnect/g" /etc/kafka/server.properties
#sed -i "s/^log.dirs=\/var\/lib\/kafka/log.dirs=\\$logDirs/g" /etc/kafka/server.properties

nodeIndex=`hostname | sed 's/broker-//'`
echo "$nodeIndex"
sed -i "s/^broker\.id=.*$/broker\.id=$nodeIndex/" /etc/kafka/server.properties

# wait for all zookeepers to be up and running
wait_for_zk_quorum

echo "Starting Kafka Broker service"
systemctl start confluent-kafka
