
echo "Running disks.sh"
echo "Number of disks brokerDiskCount: $brokerDiskCount"

# iscsiadm discovery/login
# loop over various ip's but needs to only attempt disks that actually
# do/will exist.
for n in `seq 2 $((brokerDiskCount+1))`; do
  echo "Disk $((n-2)), attempting iscsi discovery/login of 169.254.2.$n ..."
  success=1
  while [[ $success -eq 1 ]]; do
    iqn=$(iscsiadm -m discovery -t sendtargets -p 169.254.2.$n:3260 | awk '{print $2}')
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
  iscsiadm -m node -T $iqn -p 169.254.2.$n:3260 -l
done

if [ $brokerDiskCount -gt 1 ] ;
then
  echo "More than 1 volume, RAIDing..."
  device="/dev/md0"
  # use **all** iscsi disks to build raid, there's a short race between
  # iscsiadm retuning and the disk symlinks being created
  sleep 4s
  disks=$(ls /dev/disk/by-path/ip-169.254*)
  echo "Block disks found: $disks"
  mdadm --create --verbose --force --run $device --level=0 \
    --raid-devices=$brokerDiskCount \
    $disks
else
  device="/dev/sdb"
fi

mke2fs -F -t ext4 -b 4096 -E lazy_itable_init=1 -O sparse_super,dir_index,extent,has_journal,uninit_bg -m1 $device

logDirs="/data"
mkdir -p $logDirs
mount -t ext4 -o noatime $device $logDirs
UUID=$(lsblk -no UUID $device)
echo "UUID=$UUID   $logDirs    ext4   defaults,noatime,_netdev,nofail,discard,barrier=0 0 1" | sudo tee -a /etc/fstab
