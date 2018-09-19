#!/bin/bash

set -x


while [ ! -f /tmp/firewallportsadded ] ; do 
	sleep 20;
done;

sudo firewall-cmd --reload 
sudo firewall-cmd --runtime-to-permanent


set +x

