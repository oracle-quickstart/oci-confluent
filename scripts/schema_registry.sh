set -x 

echo "Configuring Schema Registry..."

# Here's the install doc:
# https://docs.confluent.io/current/installation/installing_cp/rhel-centos.html#kafka

schemaRegistryConfig="/etc/schema-registry/schema-registry.properties"
sed -i "s/^kafkastore\.connection\.url=localhost\:2181/kafkastore\.connection\.url=$zookeeperConnect/g" $schemaRegistryConfig
echo "kafkastore.zk.session.timeout.ms=300000" >> $schemaRegistryConfig
echo "kafkastore.init.timeout.ms=300000" >> $schemaRegistryConfig

# wait for all zookeepers to be up and running
wait_for_zk_quorum
# wait for all brokers to be up and running
wait_for_brokers

echo "Starting Schema Registry service"
systemctl start confluent-schema-registry

