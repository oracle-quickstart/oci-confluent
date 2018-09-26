#!/bin/bash
## post-cloud-init-cluster-setup.sh script

set -x 

ssh_check () {
	if [ -z $user ]; then
		user="opc"
	fi
	echo -ne "Checking SSH as $user on $host [*"
        while [ "$sshchk" != "0" ]; do
		sshchk=`ssh -o StrictHostKeyChecking=no -q -i /home/opc/.ssh/id_rsa ${user}@${host} 'echo 0'`
                sleep 5
                echo -n "*"
        done;
	echo -ne "*] - DONE\n"
        unset sshchk user
}


THIS_FQDN=`hostname --fqdn`
THIS_HOST=${THIS_FQDN%%.*}



## Cleanup any exiting files just in case
if [ -f /home/opc/cphosts ]; then
        rm -f /home/opc/cphosts;
        rm -f /home/opc/brokers;
        rm -f /home/opc/zookeepers;
        rm -f /home/opc/workers;
fi

# First do some network & host discovery
domain="cfvcn.oraclevcn.com"

echo "Doing nslookup for Zookeeper nodes"
ct=1;
ZOOKEEPER_HOSTNAME_PREFIX="cf-zookeeper-"
if [ `cat /tmp/zookeepernodecount` -gt 0 ]; then
        while [ $ct -le `cat /tmp/zookeepernodecount` ]; do
                nslk=`nslookup $ZOOKEEPER_HOSTNAME_PREFIX${ct}`
                ns_ck=`echo -e $?`
                if [ $ns_ck = 0 ]; then
                        hname=`nslookup $ZOOKEEPER_HOSTNAME_PREFIX${ct} | grep Name | gawk '{print $2}'`
                        echo "$hname" >> /home/opc/cphosts;
                        echo "$hname" >> /home/opc/zookeepers;
                        ct=$((ct+1));
                else
                        # sleep 10 seconds and check again - infinite loop
                        echo "Sleeping for 10 secs and will check again for nslookup $ZOOKEEPER_HOSTNAME_PREFIX${ct}"
                        sleep 10
                fi
        done;
        echo "Found `cat /home/opc/zookeepers | wc -l` nodes";
        echo `cat /home/opc/zookeepers`;
else
        echo "no dedicated zooker nodes configured, use first 3 broker nodes as zookeeper nodes"
fi




BROKER_HOSTNAME_PREFIX="cf-broker-"
echo "Doing nslookup for Broker nodes"
ct=1;
if [ `cat /tmp/brokernodecount` -gt 0 ]; then
        while [ $ct -le `cat /tmp/brokernodecount` ]; do
                nslk=`nslookup $BROKER_HOSTNAME_PREFIX${ct}`
                ns_ck=`echo -e $?`
                if [ $ns_ck = 0 ]; then
                        hname=`nslookup $BROKER_HOSTNAME_PREFIX${ct} | grep Name | gawk '{print $2}'`
                        echo "$hname" >> /home/opc/brokers;
                        ct=$((ct+1));
                else
                        # sleep 10 seconds and check again - infinite loop
                        echo "Sleeping for 10 secs and will check again for nslookup $BROKER_HOSTNAME_PREFIX${ct}"
                        sleep 10
                fi
        done;
        echo "Found `cat /home/opc/brokers | wc -l` nodes";
        echo `cat /home/opc/brokers`;
else
        echo "no broker nodes configured, should not happen"
fi

if [ `cat /tmp/zookeepernodecount` -le 0 ]; then
	head -3 /home/opc/brokers > /home/opc/zookeepers
	cat /home/opc/zookeepers >> /home/opc/cphosts;
        cat /home/opc/brokers  >> /home/opc/cphosts;
else 
	cat /home/opc/brokers  >> /home/opc/cphosts;
fi






echo "Doing nslookup for Worker nodes"
ct=1;
WORKER_HOSTNAME_PREFIX="cf-worker-"
if [ `cat /tmp/workernodecount` -gt 0 ]; then
        while [ $ct -le `cat /tmp/workernodecount` ]; do
                nslk=`nslookup $WORKER_HOSTNAME_PREFIX${ct}`
                ns_ck=`echo -e $?`
                if [ $ns_ck = 0 ]; then
                        hname=`nslookup $WORKER_HOSTNAME_PREFIX${ct} | grep Name | gawk '{print $2}'`
                        echo "$hname" >> /home/opc/cphosts;
                        echo "$hname" >> /home/opc/workers;
                        ct=$((ct+1));
                else
                        # sleep 10 seconds and check again - infinite loop
                        echo "Sleeping for 10 secs and will check again for nslookup $WORKER_HOSTNAME_PREFIX${ct}"
                        sleep 10
                fi
        done;
        echo "Found `cat /home/opc/workers | wc -l` nodes";
        echo `cat /home/opc/workers`;
else
        echo "no dedicated  worker nodes configured, use broker nodes as workers "
        cp /home/opc/brokers /home/opc/workers
fi



### Firewall setup based on node type
## Get hostname ready in variables 
cphosts=$(awk '{print $1}' /home/opc/cphosts)
if [ -n "cphosts" ] ; then
        cphosts=`echo $cphosts`                  # convert <\n> to ' '
fi
cphosts=${cphosts// /,}

bhosts=$(awk '{print $1}' /home/opc/brokers)
if [ -n "bhosts" ] ; then
	brokers=`echo $bhosts`			# convert <\n> to ' '
fi
brokers=${brokers// /,}

zkhosts=$(awk '{print $1}' /home/opc/zookeepers)
if [ -n "$zkhosts" ] ; then
	zknodes=`echo $zkhosts`			# convert <\n> to ' '
fi
zknodes=${zknodes// /,}		# not really necessary ... but safe

	# external workers
whosts=$(awk '{print $1}' /home/opc/workers)
if [ -n "whosts" ] ; then
	workers=`echo $whosts`			# convert <\n> to ' '
fi
workers=${workers// /,}

if [ -z "${zknodes}"  -o  -z "${brokers}" ] ; then
	echo "Insufficient specification for Confluent Platform cluster ... terminating script" >> $LOG
	exit 1
fi


localmachine=false
counter=1
zkcount=`cat /home/opc/zookeepers | wc -l`
for host in `cat /home/opc/cphosts | gawk -F '.' '{print $1}'`; do
	echo -e "\tConfiguring $host for deployment."
	ssh_check
	echo $THIS_HOST | grep -q -w "$host"
        if [ $? -eq 0 ] ; then
		localmachine=true
	else 
		localmachine=false
	fi

	if [ "$localmachine" = true  ] ; then
		echo "Files already exist on $host, since this script runs on $host"
	else
		echo -e "Copying Setup Scripts...\n"
        	## Copy Setup scripts
        	scp -o BatchMode=yes -o StrictHostkeyChecking=no -i /home/opc/.ssh/id_rsa /home/opc/cphosts opc@$host:~/
        	scp -o BatchMode=yes -o StrictHostkeyChecking=no -i /home/opc/.ssh/id_rsa /home/opc/zookeepers opc@$host:~/
        	scp -o BatchMode=yes -o StrictHostkeyChecking=no -i /home/opc/.ssh/id_rsa /home/opc/brokers opc@$host:~/
        	scp -o BatchMode=yes -o StrictHostkeyChecking=no -i /home/opc/.ssh/id_rsa /home/opc/workers opc@$host:~/
	fi


## Broker Firewall
        echo "$brokers" | grep -q -w "$host"
        if [ $? -eq 0 ] ; then
		if [ "$localmachine" = true  ] ; then
			sudo firewall-offline-cmd --zone=public --add-port=9092/tcp
		else
	        	ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i /home/opc/.ssh/id_rsa opc@$host 'sudo firewall-offline-cmd --zone=public --add-port=9092/tcp' 
		fi
        fi



## Zookeeper Firewall
	echo "$zknodes" | grep -q -w "$host"
	if [ $? -eq 0 ] ; then
		if [ "$localmachine" = true  ] ; then
			sudo firewall-offline-cmd --zone=public --add-port=2181/tcp
			sudo firewall-offline-cmd --zone=public --add-port=2888/tcp
			sudo firewall-offline-cmd --zone=public --add-port=3888/tcp
		else
                        ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i /home/opc/.ssh/id_rsa opc@$host 'sudo firewall-offline-cmd --zone=public --add-port=2181/tcp'
			ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i /home/opc/.ssh/id_rsa opc@$host 'sudo firewall-offline-cmd --zone=public --add-port=2888/tcp'
			ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i /home/opc/.ssh/id_rsa opc@$host 'sudo firewall-offline-cmd --zone=public --add-port=3888/tcp'
                fi
	fi

## REST Proxy Firewall
		
        echo "$workers" | grep -q -w "$host"
        if [ $? -eq 0 ] ; then
		if [ "$localmachine" = true  ] ; then
			sudo firewall-offline-cmd --zone=public --add-port=8082/tcp
		else
                        ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i /home/opc/.ssh/id_rsa opc@$host 'sudo firewall-offline-cmd --zone=public --add-port=8082/tcp' 
                fi
	fi


	## Kafka Connect REST API
	numWorkers=$(echo "${workers//,/ }" | wc -w)
	wconnect=$workers
	# Remember that Connect won't run on worker0 if we have more than 1 worker
	#if [ $numWorkers -gt 1 ] ; then
	#	wconnect=${wconnect##*,}
	#fi
        echo "$wconnect" | grep -q -w "$host"
        if [ $? -eq 0 ] ; then
		if [ "$localmachine" = true  ] ; then
			sudo firewall-offline-cmd --zone=public --add-port=8083/tcp
		else
			ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i /home/opc/.ssh/id_rsa opc@$host 'sudo firewall-offline-cmd --zone=public --add-port=8083/tcp' 
		fi
        fi



	## SchemaRegistry Firewall
	# Schema registy on second worker (or first if there's only one)
	numWorkers=$(echo "${workers//,/ }" | wc -w)
	if [ $numWorkers -le 1 ] ; then
		srWorker=${workers%%,*}
	else
		srWorker=$(echo $workers | cut -d, -f2)
	fi

	echo "$srWorker" | grep -q -w "$host"
	if [ $? -eq 0 ] ; then
		if [ "$localmachine" = true  ] ; then
			sudo firewall-offline-cmd --zone=public --add-port=8081/tcp
		else
			ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i /home/opc/.ssh/id_rsa opc@$host 'sudo firewall-offline-cmd --zone=public --add-port=8081/tcp' 
		fi
	fi

	## Control Center Firewall
        ccWorker=$(echo $workers | cut -d, -f1)
	echo "$ccWorker" | grep -q -w "$host"
	if [ $? -eq 0 ] ; then
		if [ "$localmachine" = true  ] ; then
			sudo firewall-offline-cmd --zone=public --add-port=9021/tcp
		else
                	ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i /home/opc/.ssh/id_rsa opc@$host 'sudo firewall-offline-cmd --zone=public --add-port=9021/tcp' 
		fi
	fi

	## Enable and Start firewall for changes to be effective.
	if [ "$localmachine" = true  ] ; then
		sudo systemctl enable firewalld
		sudo systemctl start firewalld
		sudo firewall-cmd --reload
		sudo firewall-cmd --runtime-to-permanent
	else
		ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i /home/opc/.ssh/id_rsa opc@$host "sudo systemctl enable firewalld"
		ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i /home/opc/.ssh/id_rsa opc@$host "sudo systemctl start firewalld"
		ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i /home/opc/.ssh/id_rsa opc@$host "sudo firewall-cmd --reload"
		ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i /home/opc/.ssh/id_rsa opc@$host "sudo firewall-cmd --runtime-to-permanent"
	fi




	AMI_SBIN=/tmp/sbin

	## Run the steps to install the software, 
	## then configure and start the services 
	if [ "$localmachine" = true  ] ; then
		sudo $AMI_SBIN/cp-install.sh 2> /tmp/cp-install.err
	else
		ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i /home/opc/.ssh/id_rsa opc@$host "sudo $AMI_SBIN/cp-install.sh 2> /tmp/cp-install.err"
	fi
	if [ $? -eq 0 ] ; then
	echo "cp-install.sh complete on host: $host"


		zkStartOnly=0
		if [ $counter -le $zkcount ] ; then
			zkStartOnly=1
			## for starting only zookeeper service
			if [ "$localmachine" = true  ] ; then
				sudo $AMI_SBIN/cp-deploy.sh $zkStartOnly 2> /tmp/cp-deploy.zk.err
			else
				ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i /home/opc/.ssh/id_rsa opc@$host "sudo $AMI_SBIN/cp-deploy.sh $zkStartOnly 2> /tmp/cp-deploy.zk.err"
			fi
		else
			## for starting non-zookeeper services 
			if [ "$localmachine" = true  ] ; then
				sudo $AMI_SBIN/cp-deploy.sh $zkStartOnly 2> /tmp/cp-deploy.err
			else
				ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i /home/opc/.ssh/id_rsa opc@$host "sudo $AMI_SBIN/cp-deploy.sh $zkStartOnly 2> /tmp/cp-deploy.err"
			fi
		fi
			if [ $? -eq 0 ] ; then
                		echo "cp-deploy.sh complete on host: $host"
        		else
                		echo "cp-deploy.sh failed on host: $host"
				exit 1
        		fi

	else
		echo "cp-install.sh failed on host: $host"
		exit 1
	fi

	## Create topics required by workers and start worker services
	echo "$workers" | grep -q -w "$host"
	if [ $? -eq 0 ] ; then
		if [ "$localmachine" = true  ] ; then
			sudo $AMI_SBIN/start-worker-services.sh 2> /tmp/start-worker-services.err
		else
			ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i /home/opc/.ssh/id_rsa opc@$host "sudo $AMI_SBIN/start-worker-services.sh 2> /tmp/start-worker-services.err"
		fi
	fi
	counter=$((counter+1))

done; 

# Todo to support custom connectors
#1if [ -n "$CONNECTOR_URLS" ] ; then 
#1  for csrc in ${CONNECTOR_URLS//,/ } ; do 
#1    $AMI_SBIN/cp-retrieve-connect-jars.sh $csrc 2>&1 | tee -a /tmp/cp-retrieve-connect-jars.err 
#1  done 
#1fi



set +x 
 
