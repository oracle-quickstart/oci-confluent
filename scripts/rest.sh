echo "Running rest.sh"

echo "Got the parameters:"
echo adminUsername \'$adminUsername\'
echo adminPassword \'$adminPassword\'
echo version \'$version\'
echo services \'$services\'

#######################################################
################# Turn Off the Firewall ###############
#######################################################
echo "Turning off the Firewall..."
service firewalld stop
chkconfig firewalld off

#######################################################
################ Install the REST Proxy  ##############
#######################################################
echo "Installing Kafka Connect..."
