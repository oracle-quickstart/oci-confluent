

# iscsiadm discovery/login
# this can loop over various ip's but needs to only attempt disks that actually
# do/will exist by using some $numdisks var.
success=1
while [[ $success -eq 1 ]]; do
  iqn=$(iscsiadm -m discovery -t sendtargets -p 169.254.2.2:3260 | awk '{print $2}')
  if  [[ $iqn != iqn.* ]] ;
  then
    echo "Error: unexpected iqn value: $iqn"
    sleep 10s
    continue
  else
    echo "Success for iqn: $iqn"
    success=0
  fi
done
iscsiadm -m node -o update -T $iqn -n node.startup -v automatic
iscsiadm -m node -T $iqn -p 169.254.2.2:3260 -l

# mdadm raid possible here, currently hard coded to use sdb

mkdir /data
mount -t ext4 -o noatime /dev/sdb /data
UUID=$(lsblk -no UUID /dev/sdb)
echo "UUID=$UUID   /data    ext4   defaults,noatime,_netdev,nofail,discard,barrier=0 0 1" | sudo tee -a /etc/fstab
