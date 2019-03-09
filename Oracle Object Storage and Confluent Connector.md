## This document describes how to integrate Confluent Kafka with Oracle Object Storage using Kafka Connect S3 connector.

## Prerequisites
1. This assumes you already have an Oracle Cloud Infrastructure account.  If not, to create a Oracle Cloud Infrastructure tenant.  See [Signing Up for Oracle Cloud Infrastructure.](https://docs.cloud.oracle.com/iaas/Content/GSG/Tasks/signingup.htm)

2. Create an [Amazon S3 Compatibility API key.](https://docs.cloud.oracle.com/iaas/Content/Identity/Tasks/managingcredentials.htm#Working2) An Amazon S3 Compatibility API key consists of an Access Key/Secret Key pair.

3. Identify your Object Storage Namespace, which is basically your tenancy name, since we will need it.   You can find it in OCI console, see screenshot below.  

![](../images/tenant1.PNG)

4. Identify the Oracle Cloud Infrastructure region which you plan to use. eg:  us-phoenix-1,  us-ashburn-1, etc.  


5. The API endpoint (store.url) to be used in Connect S3 connector configuration to access Oracle Object Storage will depend on the values of region and namespace (Step3 and Step4 above).

    API Endpoints:

    https://<object_storage_namespace>.compat.objectstorage.us-phoenix-1.oraclecloud.com
    https://<object_storage_namespace>.compat.objectstorage.us-ashburn-1.oraclecloud.com
    https://<object_storage_namespace>.compat.objectstorage.eu-frankfurt-1.oraclecloud.com
    https://<object_storage_namespace>.compat.objectstorage.uk-london-1.oraclecloud.com

    **Replace <object_storage_namespace> with value from  Step3 above.**  


6. Create a bucket in Orace Object Storage using OCI console.  **eg: kafka_sink_object_storage_bucket**

![](../images/create_bucket.PNG)



## Modifying your application (eg: Confluent Kafka) to access Object Storage
1. Assuming you already have confluent platform installed on OCI using this Github repo.  Let's create a topic using Confluent Control Center UI or command line or REST API.   **example: kafka_oci_object_storage_test.**

![](../images/create_topic.PNG)

2. Produce a few messages using JSON with the value '{ "foo": "bar" }' to the topic created above.
I am using the REST API, so you can run it from anywhere as far as confluent worker nodes (cf-worker-1) are reachable.

Example:

    ssh -i ~/.ssh/id_rsa opc@<ip address or cf-worker-1>
    for i in {1..10} ;  do echo $i; curl -X POST -H "Content-Type: application/vnd.kafka.json.v1+json"  --data '{"records":[{"value":{"foo":"bar"}}]}' http://cf-worker-1:8082/topics/kafka_oci_object_storage_test ;   done;


3. Gracefully stop the connect-distributed daemon using the below command. Run this on all Confluent worker nodes.(example: cf-worker-1):

    ssh -i ~/.ssh/id_rsa opc@<ip address or cf-worker-1>

    ps -efw | grep "org.apache.kafka.connect.cli.ConnectDistributed" | grep -v "grep " |  gawk '{ print $2 }' | xargs sudo kill -15

4. Update connect-distributed.properties to use JsonConverter and schemas.enable set to false on all worker nodes.  In my example, I am using JSON messages and hence the below change is needed, since by default, it comes configured with AvroConverter  

On each of the Confluent Worker Nodes (example: cf-worker-<n>):

    vim /opt/confluent/etc/kafka/connect-distributed.properties

Make sure, the config files contains the below lines

    key.converter=org.apache.kafka.connect.json.JsonConverter
    # key.converter=io.confluent.connect.avro.AvroConverter
    value.converter=org.apache.kafka.connect.json.JsonConverter
    # value.converter=io.confluent.connect.avro.AvroConverter
    # Converter-specific settings can be passed in by prefixing the Converter's setting with the converter we want to apply
    # it to
    # key.converter.schemas.enable=true
    key.converter.schemas.enable=false
    # value.converter.schemas.enable=true
    value.converter.schemas.enable=false


5. Configure Confluent worker nodes with credentials to access Object Storage ans start Kafka connect daemon.  The keys below are labelled as AWS_xxxxx,  but its values needs to be set with the keys generated in prerequisites Step2 on OCI console.

Do the steps on each of the Confluent Worker Nodes (example: cf-worker-<n>):

    ssh -i ~/.ssh/id_rsa opc@cf-worker-1  

    sudo AWS_ACCESS_KEY_ID=<replace with your OCI Object storage access key> \
    AWS_SECRET_ACCESS_KEY=<replace with your OCI Object storage secret key> \
    /opt/confluent/bin/connect-distributed -daemon /opt/confluent/etc/kafka/connect-distributed.properties


6. Load the Confluent Connect S3 Sink connector with configuration to access Oracle Object Storage. 

Note: We are setting the below parameters with OCI specific values (**not AWS values**):

    "s3.region": "us-phoenix-1"  (**Replace with value from Prerequisite Step4**).
    "store.url": "intmahesht.compat.objectstorage.us-phoenix-1.oraclecloud.com"   (**Replace with value from Prerequisite Step5**).

Similarly replace the below with the values which apply for your implementation:

    "topics": "kafka_oci_object_storage_test"
    "s3.bucket.name": "kafka_sink_object_storage_bucket"

 I am using the REST API, so you can run it from anywhere as far as confluent worker nodes (cf-worker-1) are reachable.
 Command to run:

    curl -i -X POST -H "Accept:application/json"  -H  "Content-Type:application/json" http://cf-worker-1:8083/connectors/   -d '{
     "name": "s3-sink-oci-obj-storage",
     "config": {
       "connector.class": "io.confluent.connect.s3.S3SinkConnector",
       "tasks.max": "1",
       "topics": "kafka_oci_object_storage_test",
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
Go to OCI Console and navigate to Object Storage:  

    For us-phoenix-1:   [https://console.us-phoenix-1.oraclecloud.com](https://console.us-phoenix-1.oraclecloud.com)

Bucket View:

![](../images/bucket_content.PNG)

Object Content:

![](../images/object_content.PNG)



## Troubleshooting
To view the logs, go here on worker nodes (cf-worker-<n>)

    less /opt/confluent/logs/connectDistributed.out



## References:
* Oracle Object Storage Amazon S3 Compatibility API Documentation: [https://docs.cloud.oracle.com/iaas/Content/Object/Tasks/s3compatibleapi.htm](https://docs.cloud.oracle.com/iaas/Content/Object/Tasks/s3compatibleapi.htm)

* Confluent Kafka Connect S3 Documentation: [https://docs.confluent.io/current/connect/kafka-connect-s3/index.html](https://docs.confluent.io/current/connect/kafka-connect-s3/index.html)
