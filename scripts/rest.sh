echo "Running rest.sh"

echo "Got the parameters:"
echo version \'$version\'
echo edition \'$edition\'

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
