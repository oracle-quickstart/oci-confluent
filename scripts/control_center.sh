set -x 

echo "Configuring Control Center..."

# Here's the install doc:
# https://docs.confluent.io/current/installation/installing_cp/rhel-centos.html#kafka

controlCenterConfig="/etc/confluent-control-center/control-center-production.properties"
sed -i "s/^bootstrap.servers=localhost\:9092/bootstrap.servers=$brokerConnect/g" $controlCenterConfig
sed -i "s/^zookeeper\.connect=localhost\:2181/zookeeper\.connect=$zookeeperConnect/g" $controlCenterConfig
#sed -i "s/^bootstrap.servers=PLAINTEXT\:\/\/localhost\:9092/bootstrap.servers=$brokerConnect/g" $restConfig
## confluent.license=<your-confluent-license>


#sed -i "s/^kafkastore\.connection\.url=localhost\:2181/kafkastore\.connection\.url=$zookeeperConnect/g" $controlCenterConfig
#echo "kafkastore.zk.session.timeout.ms=300000" >> $controlCenterConfig
#echo "kafkastore.init.timeout.ms=300000" >> $controlCenterConfig

# wait for all zookeepers to be up and running
wait_for_zk_quorum
# wait for all brokers to be up and running
wait_for_brokers

echo "Starting Control Center service"
systemctl enable confluent-control-center
systemctl start confluent-control-center

