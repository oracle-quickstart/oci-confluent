echo "Running rest.sh"

echo "Configuring REST Proxy..."

# Here's the install doc:
# https://docs.confluent.io/current/installation/installing_cp/rhel-centos.html#crest-long

restConfig="/etc/kafka-rest/kafka-rest.properties"
sed -i "s/^#zookeeper\.connect=localhost\:2181/zookeeper\.connect=$zookeeperConnect/g" $restConfig
sed -i "s/^bootstrap.servers=PLAINTEXT\:\/\/localhost\:9092/bootstrap.servers=$brokerConnect/g" $restConfig
sed -i "s/^#schema\.registry\.url=http\:\/\/localhost\:8081/schema.registry.url=http\:\/\/$schemaRegistryConnect/g" $restConfig

nodeIndex=`hostname | sed 's/rest-//'`
sed -i "s/^#id=kafka-rest-test-server/id=kafka-rest-${nodeIndex}/g" $restConfig 

#systemctl start confluent-kafka-rest
