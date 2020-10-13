
echo "Running install.sh"

echo "Got the parameters:"
echo version \'$version\'
echo edition \'$edition\'

echo "Installing Java..."
yum install -y java

echo "Installing redhat lsb"
yum install redhat-lsb -y
osVersion=`lsb_release -r | awk '{print $2}'`
osVersion=${osVersion%%.*}

echo "Installing Confluent..."

# Here's the install doc:
# https://docs.confluent.io/current/installation/installing_cp/rhel-centos.html#systemd-rhel-centos-install

# 2. Install the Confluent Platform public key. This key is used to sign packages in the YUM repository.
versionMajorPrefix=${version%.*}

rpm --import https://packages.confluent.io/rpm/${versionMajorPrefix}/archive.key

# 3. Navigate to /etc/yum.repos.d/ and create a file named confluent.repo with these contents.
# This adds the Confluent repository.
echo "[Confluent.dist]
name=Confluent repository (dist)
baseurl=https://packages.confluent.io/rpm/${versionMajorPrefix}/${osVersion}
gpgcheck=1
gpgkey=https://packages.confluent.io/rpm/${versionMajorPrefix}/archive.key
enabled=1

[Confluent]
name=Confluent repository
baseurl=https://packages.confluent.io/rpm/${versionMajorPrefix}
gpgcheck=1
gpgkey=https://packages.confluent.io/rpm/${versionMajorPrefix}/archive.key
enabled=1
" >  /etc/yum.repos.d/confluent.repo

# 4. Clear the YUM caches and install Confluent Platform.

# Commercial Version

# Confluent Platform using only Confluent Community components
yum clean all
if [ $edition = "Enterprise" ]; then
  package=`yum search confluent | grep "confluent-platform" | head -n 1 | gawk -F" " '{ print $1 }'`
  packageVersion=`sudo yum --showduplicates list $package | grep $version | gawk -F" " '{ print $2 }'`
  packageWithVersion=`echo $package | sed "s|.noarch|-${version}-1.noarch|g"`
  yum install -y $packageWithVersion
else
  package=`yum search confluent | grep "confluent-community-" | head -n 1 | gawk -F" " '{ print $1 }'`
  packageVersion=`sudo yum --showduplicates list $package | grep $version | gawk -F" " '{ print $2 }'`
  packageWithVersion=`echo $package | sed "s|.noarch|-${version}-1.noarch|g"`
  yum install -y $packageWithVersion
fi
