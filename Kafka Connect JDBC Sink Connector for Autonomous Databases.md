# Kafka Connect JDBC Sink Connector for Oracle Autonomous Data Warehouse (ADW) or Autonomous Transaction Procesing (ATP) databases
You can use Kafka Connect JDBC Sink Connector to export data from Apache Kafka® topics to Oracle Autonomous Databases (ADW/ATP) or Oracle database. This document covers exporting to ADW/ATP. The jdbc-sink connector comes pre-loaded with Confluent Kafka Community and Enterprise edition.  

## Secure Connection to ADW/ATP using Wallet
Connections to ATP/ADW are made over the public Internet. To secure any connection to ATP/ADW, it requires 
client applications to uses certificate authentication and Secure Sockets Layer (SSL). 
This ensures that there is no unauthorized access to the ADW/ATP and that communications between the client 
and server are fully encrypted and cannot be intercepted or altered.

Certification authentication uses an encrypted key stored in a wallet on both the client (where the application
is running) and the server (where your database service on the ATP/ADW is running). 
The key on the client must match the key on the server to make a connection. 
A wallet contains a collection of files, including the key and other information needed to 
connect to your database service in the ADW/ATP. 
All communications between the client and the server are encrypted.

For more details, refer to ADW documentation: Connecting to Autonomous Data Warehouse
https://docs.oracle.com/en/cloud/paas/autonomous-data-warehouse-cloud/user/connect-data-warehouse.html#GUID-94719269-9218-4FAF-870E-6F0783E209FD



## Prerequisites
Given below are pre-requisities to configure Kafka

1. Download client credentials (Wallets) file from Oracle Cloud Infrastructure console. Detailed steps are available [here](https://docs.oracle.com/en/cloud/paas/autonomous-data-warehouse-cloud/user/connect-download-wallet.html#GUID-B06202D2-0597-41AA-9481-3B174F75D4B1)

2. Copy the wallet file to Kafka Connect nodes.  You can scp to the nodes from your local machine or upload the wallet file to OCI Object Storage, so it can be download to Kafka Connect nodes using [secure pre-authenticated request URL](https://docs.cloud.oracle.com/iaas/Content/Object/Tasks/usingpreauthenticatedrequests.htm)

    Example:
    
    wget https://objectstorage.us-phoenix-1.oraclecloud.com/p/hQUstt-JkH9n07EuXcdVk5FczNkM9bY0KOxTTCtjh_0/n/intmahesht/b/dbwallet/o/Wallet_ADW.zip

3. Configure sqlnet.ora and confluent-kafka-connect service to use Wallet file.

    On each Kafka Connect node:
    
        sudo su  
        wallet_unzipped_folder=/oracle_credentials_wallet
        mkdir -p $wallet_unzipped_folder
        unzip -u /Wallet_ADW.zip -d $wallet_unzipped_folder
        chown -R  cp-kafka-connect:confluent $wallet_unzipped_folder
        sed -i -E 's|DIRECTORY=".*"|DIRECTORY="/oracle_credentials_wallet"|g'  $wallet_unzipped_folder/sqlnet.ora
        vim  /usr/lib/systemd/system/confluent-kafka-connect.service
        Environment=TNS_ADMIN=/oracle_credentials_wallet



4. Download the latest JDBC thin drivers to Kafka Connect nodes from [here](https://www.oracle.com/technetwork/database/application-development/jdbc/downloads/jdbc-ucp-183-5013470.html).  Get the full Zipped JDBC Driver and Companion JARs. (ojdbc8-full.tar.gz).  The below example assumes I copied the zip file to OCI Object storage for easy download to all nodes. 

    On each Kafka Connect node:

        sudo su  
        cd /usr/share/java/kafka-connect-jdbc
        wget https://objectstorage.us-phoenix-1.oraclecloud.com/n/intmahesht/b/oracledrivers/o/ojdbc8-full.tar.gz
        tar xvzf ./ojdbc8-full.tar.gz
        cp ojdbc8-full/*.jar  ./
        chmod 644 *.jar
        rm -rf ojdbc8-full
        rm -rf ojdbc8-full.tar.gz


5. Restart Confluent Kafka Connect service 

    systemctl daemon-reload

    systemctl restart confluent-kafka-connect
    
    systemctl status confluent-kafka-connect



6. You can check logs here (/var/log/messages) for any error message during restart of confluent-kafka-connect service
 

## Configure and Load Kafka Connect JDBC Sink connector for ADW/ATP

1. Set a variable with Kafka Connect URL, example: 
    
    export CONNECTURL=http://connect-0:8083

2. Create the jdbc connection url using information from Wallet file, example: 

    "connection.url": "jdbc:oracle:thin:@adw_low?TNS_ADMIN=/oracle_credentials_wallet"

3. Identify the Kafka Topics which will be used as a source to write data to ADW/ATP, example:

    "topics": "adw-sink"

4. Identify the username and password to be used to connect to ADW/ATP, example 
    
    "connection.user": "HR",
    "connection.password": "Ora18abc!!",

5. Use the above information to create the Kafka Connect JDBC Sink Connector using Kafka REST API call.   The below config will auto create a table, if it doesn't exist already.

    export CONNECTURL=http://connect-0:8083
 
    curl -i -X POST -H "Accept:application/json"  -H  "Content-Type:application/json" $CONNECTURL/connectors/       -d '{
    "name": "dbsink-adw",
    "config": {
        "name": "dbsink-adw",
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "adw-sink",
        "connection.url": "jdbc:oracle:thin:@adw_low?TNS_ADMIN=/oracle_credentials_wallet",
        "connection.user": "HR",
        "connection.password": "Ora18abc!!",
        "auto.create": "true",
        "key.converter": "io.confluent.connect.avro.AvroConverter",
        "value.converter": "io.confluent.connect.avro.AvroConverter",
        "key.converter.schema.registry.url": "http://schema-registry-0:8081",
        "value.converter.schema.registry.url": "http://schema-registry-0:8081"
        }
    }' 

6. Using your preferred SQL tool,  run a query in your database to look for exported data. 



