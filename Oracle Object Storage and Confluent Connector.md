# Oracle Object Storage and Confluent Connector

## Prerequisites
This assumes you already have an Oracle Cloud Infrastructure account.  If not, to create a Oracle Cloud Infrastructure tenant.  See [Signing Up for Oracle Cloud Infrastructure.](https://docs.cloud.oracle.com/iaas/Content/GSG/Tasks/signingup.htm)

Create an [Amazon S3 Compatibility API key.](https://docs.cloud.oracle.com/iaas/Content/Identity/Tasks/managingcredentials.htm#Working2) An Amazon S3 Compatibility API key consists of an Access Key/Secret Key pair.

Identify your Object Storage Namespace, which is basically your tenancy name, since we will need it.   You can find it in OCI console, see screenshot below.  

![](./images/object storage/01 - tenant.png)

Identify the Oracle Cloud Infrastructure region which you plan to use. eg:  us-phoenix-1,  us-ashburn-1, etc.  

The API endpoint (store.url) to be used in Connect S3 connector configuration to access Oracle Object Storage will depend on the values of region and namespace from the prerequisites.

Examples of API endpoints include:

    https://<object_storage_namespace>.compat.objectstorage.us-phoenix-1.oraclecloud.com
    https://<object_storage_namespace>.compat.objectstorage.us-ashburn-1.oraclecloud.com
    https://<object_storage_namespace>.compat.objectstorage.eu-frankfurt-1.oraclecloud.com
    https://<object_storage_namespace>.compat.objectstorage.uk-london-1.oraclecloud.com

Replace <object_storage_namespace> with value from the prerequisites.

Create a bucket in Oracle Object Storage using OCI console.  **eg: kafka_sink_object_storage_bucket**

![](./images/object%20storage/02%20-%20create%20bucket.png)

## Configure Confluent to Access Object Storage
Assuming you already have Confluent installed on OCI using this Github repo.  Let's create a topic from command line or using Confluent Control Center UI (Enterprise only).   **example: kafka-oci-object-storage-test**

![](./images/object%20storage/03%20-%20create%20topic.png)
    Login to a broker instance:  ssh opc@<broker_instance>
    sudo su 
    [root@broker-0 opc]# /usr/bin/kafka-topics --zookeeper zookeeper-0:2181 --create --topic kafka-oci-object-storage-test --partitions 1 --replication-factor 3


Produce a few messages using JSON with the value '{ "foo": "bar" }' to the topic created above.
I am using the REST API to publish 10 messages.

Example:
    
    ssh -i ~/.ssh/id_rsa opc@<ip address of rest instance>
    export RPURL=http://rest-0:8082
    for i in {1..10} ;  do echo $i; curl -X POST -H "Content-Type: application/vnd.kafka.json.v1+json"  --data '{"records":[{"value":{"foo":"bar"}}]}' $RPURL/topics/kafka-oci-object-storage-test ;   done;


Run this on all Confluent connect nodes.(example: connect-0, connect-1):


Update connect-distributed.properties to use JsonConverter and schemas.enable set to false on all connect nodes.  In my example, I am using JSON messages and hence the below change is needed, since by default, it comes configured with AvroConverter  


    vim /opt/confluent/etc/kafka/connect-distributed.properties

Make sure, the config files contains the below lines

    key.converter=org.apache.kafka.connect.json.JsonConverter
    value.converter=org.apache.kafka.connect.json.JsonConverter

and comment the below lines:  

    #key.converter=io.confluent.connect.avro.AvroConverter
    #value.converter=io.confluent.connect.avro.AvroConverter

Make sure, the config files contains the below lines:

    key.converter.schemas.enable=false
    value.converter.schemas.enable=false




Do the steps on each of the Confluent Connect Nodes :

    ssh -i ~/.ssh/id_rsa opc@<ip address or connect instance>
 
    
Update this file:  /usr/lib/systemd/system/confluent-kafka-connect.service to set environment variables for AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY.  The keys are labelled as AWS_xxxxx,  but its values needs to be set with the keys generated in OCI console.  

    User=cp-kafka-connect
    Group=confluent
    Environment=AWS_SECRET_ACCESS_KEY=<replace with your OCI Object storage secret key>
    Environment=AWS_ACCESS_KEY_ID=replace with your OCI Object storage access key>
    ....
    .... removed for brevity
    ....

Then run 

    sudo systemctl daemon-reload 
    sudo systemctl restart confluent-kafka-connect 

to apply new environments to confluent-kafka-connect 



Load the Confluent Connect S3 Sink connector with configuration to access Oracle Object Storage.

Note: We are setting the below parameters with OCI specific values (not AWS values):

    "s3.region": "us-phoenix-1"
    "store.url": "intmahesht.compat.objectstorage.us-phoenix-1.oraclecloud.com"

Replace the above with values from prerequisites above.

Similarly replace the below with the values which apply for your implementation:

    "topics": "kafka-oci-object-storage-test"
    "s3.bucket.name": "kafka_sink_object_storage_bucket"

 I am using the REST API, so you can run it from anywhere as far as confluent connect nodes are reachable. 
 Command to run:

    export CONNECTURL=http://connect-0:8083
    curl -i -X POST -H "Accept:application/json"  -H  "Content-Type:application/json" $CONNECTURL/connectors/   -d '{
     "name": "s3-sink-oci-obj-storage",
     "config": {
       "connector.class": "io.confluent.connect.s3.S3SinkConnector",
       "tasks.max": "1",
       "topics": "kafka-oci-object-storage-test",
       "s3.region": "us-phoenix-1",
       "s3.bucket.name": "kafka_sink_object_storage_bucket",
       "s3.part.size": "5242880",
       "flush.size": "3",
       "storage.class": "io.confluent.connect.s3.storage.S3Storage",
       "store.url": "intmahesht.compat.objectstorage.us-phoenix-1.oraclecloud.com",
       "format.class": "io.confluent.connect.s3.format.json.JsonFormat",
       "schema.generator.class": "io.confluent.connect.storage.hive.schema.DefaultSchemaGenerator",
       "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
       "schema.compatibility": "NONE"
       }
    }'


## View Bucket and Objects
Go to OCI Console and navigate to Object Storage.  For us-phoenix-1, go to https://console.us-phoenix-1.oraclecloud.com.

Bucket View:

![](./images/object%20storage/04%20-%20bucket%20content.png)

Object Content:

![](./images/object%20storage/05%20-%20object%20content.png)

## Troubleshooting
To view the logs, go here on connect nodes (connect-<n>)

    less /var/logs/messages

## References:
* Oracle Object Storage Amazon S3 Compatibility API Documentation: https://docs.cloud.oracle.com/iaas/Content/Object/Tasks/s3compatibleapi.htm
* Confluent Kafka Connect S3 Documentation: https://docs.confluent.io/current/connect/kafka-connect-s3

* REST API commands for Kafka Connect

    curl -i -X GET -H "Accept:application/json"  -H  "Content-Type:application/json"  http://connect-0:8083/connectors/
    curl -i -X DELETE -H "Accept:application/json"  -H  "Content-Type:application/json"  http://connect-0:8083/connectors/s3-sink-oci-obj-storage
    

