echo "Running ksql.sh"

echo "Configuring Confluent KSQL..."

# Update properties for Kafka KSQL
ksqlConfig="/etc/ksql/ksql-server.properties"
host=`hostname`
sed -i "s/^bootstrap.servers=localhost\:9092/bootstrap.servers=$brokerConnect/g" $ksqlConfig
sed -i "s/^listeners=http\:\/\/localhost\:8088/listeners=http\:\/\/$host\:8088/g" $ksqlConfig



# wait for all zookeepers to be up and running
wait_for_zk_quorum
# wait for all brokers to be up and running
wait_for_brokers

echo "Starting Kafka KSQL service"
systemctl enable confluent-ksql
systemctl start confluent-ksql
