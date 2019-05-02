echo "Running broker.sh"

set -x

echo "Configuring Kafka Broker..."

# Here's the install doc:
# https://docs.confluent.io/current/installation/installing_cp/rhel-centos.html#kafka

brokerConfig="/etc/kafka/server.properties"
sed -i "s/^zookeeper\.connect=localhost\:2181/zookeeper\.connect=$zookeeperConnect/g" $brokerConfig
sed -i "s/^log.dirs=\/var\/lib\/kafka/log.dirs=\\$logDirs\/kafka/g" $brokerConfig

nodeIndex=`hostname | sed 's/broker-//'`
echo "$nodeIndex"
sed -i "s/^broker\.id=.*$/broker\.id=$nodeIndex/" $brokerConfig


if [ $edition = "Enterprise" ]; then
  ##################### Confluent Metrics Reporter #######################
  # Confluent Control Center and Confluent Auto Data Balancer integration
  #
  # Uncomment the following lines to publish monitoring data for
  # Confluent Control Center and Confluent Auto Data Balancer
  # If you are using a dedicated metrics cluster, also adjust the settings
  # to point to your metrics Kafka cluster.
  sed -i "s/^#metric\.reporters=io\.confluent\.metrics\.reporter\.ConfluentMetricsReporter/metric\.reporters=io\.confluent\.metrics\.reporter\.ConfluentMetricsReporter/g" $brokerConfig
  sed -i "s/^#confluent\.metrics\.reporter\.bootstrap\.servers=localhost\:9092/confluent\.metrics\.reporter\.bootstrap\.servers=$brokerConnect/g" $brokerConfig
  #
  # Uncomment the following line if the metrics cluster has a single broker
  # confluent.metrics.reporter.topic.replicas=1
fi

# create/chown directory set above
mkdir -p $logDirs/kafka
chown cp-kafka:confluent $logDirs/kafka

# wait for all zookeepers to be up and running
wait_for_zk_quorum

echo "Starting Kafka Broker service"
systemctl enable confluent-zookeeper
systemctl start confluent-kafka
