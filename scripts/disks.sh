
echo "Running disks.sh"

# iscsiadm discovery/login
# loop over various ip's but needs to only attempt disks that actually
# do/will exist.
if [ $brokerDiskCount -gt 0 ] ;
then
  echo "Number of disks brokerDiskCount: $brokerDiskCount"
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
else
  echo "Zero block volumes, not calling iscsiadm, brokerDiskCount: $brokerDiskCount"
fi

# not matter what we're mounting, we're placing data at the same path
logDirs="/data"
mkdir -p $logDirs

# choose between sdb or md0, $device unused if 0 disks
if [ $brokerDiskCount -gt 1 ] ;
then
  echo "More than 1 volume, RAIDing..."
  device="/dev/md0"
  # use **all** iscsi disks to build raid, there's a short race between
  # iscsiadm retuning and the disk symlinks being created, also mdadm
  # doesn't care about consistent device names
  sleep 4s
  disks=$(ls /dev/disk/by-path/ip-169.254*)
  echo "Block disks found: $disks"
  mdadm --create --verbose --force --run $device --level=0 \
    --raid-devices=$brokerDiskCount \
    $disks
else
  device="/dev/sdb"
fi

if [ $brokerDiskCount -gt 0 ] ;
then
  echo "Creating filesystem and mounting on /data..."
  mke2fs -F -t ext4 -b 4096 -E lazy_itable_init=1 -O sparse_super,dir_index,extent,has_journal,uninit_bg -m1 $device
  mount -t ext4 -o noatime $device $logDirs
  UUID=$(lsblk -no UUID $device)
  echo "UUID=$UUID   $logDirs    ext4   defaults,noatime,_netdev,nofail,discard,barrier=0 0 1" | sudo tee -a /etc/fstab
else
  echo "No filesystem to create, skipping"
fi
