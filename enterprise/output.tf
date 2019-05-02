
data "oci_identity_tenancy" "tenancy" {
    #Required
    tenancy_id = "${var.tenancy_ocid}"
}

variable "topic_name" { default="demo-oci-os-sink" }


output "Port Test -  Broker" {
  value = "  telnet ${oci_core_instance.broker.*.private_ip[0]} 9092   \n			"
}

output "Port Test -  Zookeeper" {
  value = "telnet ${oci_core_instance.zookeeper.*.private_ip[0]} 2181"
}


output "Port Test -  Schema Registry" {
  value = "telnet ${oci_core_instance.schema_registry.*.private_ip[0]} 8081   \n                       curl http://${oci_core_instance.schema_registry.*.private_ip[0]}:8081/"
}

output "Port Test -  Connect" {
  value = "telnet ${oci_core_instance.connect.*.private_ip[0]} 8083   \n                       curl http://${oci_core_instance.connect.*.private_ip[0]}:8083/connectors"
}

output "Port Test -  REST" {
  value = "telnet ${oci_core_instance.rest.*.private_ip[0]} 8082   \n                       curl http://${oci_core_instance.rest.*.private_ip[0]}:8082/topics"
}

output "Port Test -  Control Center" {
  value = "telnet ${oci_core_instance.control_center.*.public_ip[0]} 9021   \n                       http://${oci_core_instance.control_center.*.public_ip[0]}:9021/"
}

output "Deployment Testing: " {
value = <<END

Create a bucket in OCI Object Storage in the same region where Kafka is deployed. Bucket name:  kafka_sink_object_storage_bucket


Create a topic 
Run the below command on one of the broker node: 
	ssh opc@${oci_core_instance.broker.*.private_ip[0]} 
	[opc@broker-0 opc]# /usr/bin/kafka-topics --zookeeper ${oci_core_instance.zookeeper.*.private_ip[0]}:2181 --create --topic ${var.topic_name} --partitions 1 --replication-factor 3


Run the below commands on kafka connect node:


ssh opc@<connect ip address>
export RPURL=http://${oci_core_instance.rest.*.private_ip[0]}:8082

[opc@connect-0 log]# for i in {1..10} ;  do echo $i; curl -X POST -H "Content-Type: application/vnd.kafka.avro.v2+json"       -H "Accept: application/vnd.kafka.v2+json"       --data '{"key_schema": "{\"name\":\"user_id\"  ,\"type\": \"int\"   }", "value_schema": "{\"type\": \"record\", \"name\": \"User\", \"fields\": [{\"name\": \"name\", \"type\": \"string\"}]}", "records": [{"key" : 1 , "value": {"name": "testUser"}}]}'       $RPURL/topics/${var.topic_name} ;   done;
 

Configure credentials to access OCI Object Storage and restart Kafka Connect
 

 
export CONNECTURL=http://${oci_core_instance.connect.*.private_ip[0]}:8083
 
curl -i -X POST -H "Accept:application/json"  -H  "Content-Type:application/json" $CONNECTURL/connectors/   -d '{
"name": "ociossink",
"config": {
   "connector.class": "io.confluent.connect.s3.S3SinkConnector",
   "tasks.max": "1",
   "topics": "${var.topic_name}",
   "s3.region": "${var.region}",
   "s3.bucket.name": "kafka_sink_object_storage_bucket",
   "s3.part.size": "5242880",
   "flush.size": "3",
   "storage.class": "io.confluent.connect.s3.storage.S3Storage",
   "store.url": "${data.oci_identity_tenancy.tenancy.name}.compat.objectstorage.${var.region}.oraclecloud.com",
   "key.converter": "io.confluent.connect.avro.AvroConverter",
   "value.converter": "io.confluent.connect.avro.AvroConverter",
   "key.converter.schemas.enable": "true",
   "value.converter.schemas.enable": "true",
   "key.converter.schema.registry.url": "http://${oci_core_instance.schema_registry.*.private_ip[0]}:8081",
   "value.converter.schema.registry.url": "http://${oci_core_instance.schema_registry.*.private_ip[0]}:8081",
   "format.class": "io.confluent.connect.s3.format.json.JsonFormat",
   "schema.generator.class": "io.confluent.connect.storage.hive.schema.DefaultSchemaGenerator",
   "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
   "schema.compatibility": "NONE"
   }
}'
 
 

END
}


