echo "Running connect.sh"

echo "Configuring Confluent Connect..."

# Update properties for Kafka Connect
connectDistributedConfig="/etc/kafka/connect-distributed.properties"
connectPluginDirectory="/usr/share/java/kc-plugins"
mkdir -p $connectPluginDirectory
sed -i "s/^plugin\.path=\/usr\/share\/java/plugin\.path=\/usr\/share\/java,$connectPluginDirectory/g" $connectDistributedConfig
sed -i "s/^bootstrap.servers=localhost\:9092/bootstrap.servers=$brokerConnect/g" $connectDistributedConfig
sed -i "s/^key\.converter=org\.apache\.kafka\.connect\.json\.JsonConverter/key\.converter=io\.confluent\.connect\.avro\.AvroConverter/g" $connectDistributedConfig
sed -i "s/^value\.converter=org\.apache\.kafka\.connect\.json\.JsonConverter/value\.converter=io\.confluent\.connect\.avro\.AvroConverter/g" $connectDistributedConfig
echo "key.converter.schema.registry.url=http://$schemaRegistryConnect" >> $connectDistributedConfig
echo "value.converter.schema.registry.url=http://$schemaRegistryConnect" >> $connectDistributedConfig


if [ $edition = "Enterprise" ]; then
  # Interceptor setup
  echo "consumer.interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor" >>  $connectDistributedConfig
  echo "producer.interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor" >>  $connectDistributedConfig
fi

for f in /etc/schema-registry/connect-*.properties ; do
  sed -i "s/^bootstrap.servers=localhost\:9092/bootstrap.servers=$brokerConnect/g" $f
  sed -i "s/^key\.converter\.schema\.registry\.url=http\:\/\/localhost\:8081/key\.converter\.schema\.registry\.url=http\:\/\/$schemaRegistryConnect/g" $f
  sed -i "s/^value\.converter\.schema\.registry\.url=http\:\/\/localhost\:8081/value\.converter\.schema\.registry\.url=http\:\/\/$schemaRegistryConnect/g" $f
done

sed -i "s/^bootstrap\.servers=localhost\:9092/bootstrap\.servers=$brokerConnect/g" /etc/kafka/consumer.properties
sed -i "s/^bootstrap\.servers=localhost\:9092/bootstrap\.servers=$brokerConnect/g" /etc/kafka/producer.properties


# wait for all zookeepers to be up and running
wait_for_zk_quorum
# wait for all brokers to be up and running
wait_for_brokers
# wait for schema registry to be up and running
wait_for_schema_registry

echo "Starting Kafka Connect service"
systemctl enable confluent-zookeeper
systemctl start confluent-kafka-connect
