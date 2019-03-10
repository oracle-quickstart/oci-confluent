echo "Running connect.sh"

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
################# Install Kafka Connect ###############
#######################################################
echo "Installing Kafka Connect..."
