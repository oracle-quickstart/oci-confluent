
echo "Running install.sh"

echo "Got the parameters:"
echo version \'$version\'
echo edition \'$edition\'

echo "Installing Java..."
yum install -y java

echo "Installing Confluent..."

# Here's the install doc:
# https://docs.confluent.io/current/installation/installing_cp/rhel-centos.html#systemd-rhel-centos-install

# 2. Install the Confluent Platform public key. This key is used to sign packages in the YUM repository.
rpm --import https://packages.confluent.io/rpm/5.1/archive.key

# 3. Navigate to /etc/yum.repos.d/ and create a file named confluent.repo with these contents.
# This adds the Confluent repository.
echo "[Confluent.dist]
name=Confluent repository (dist)
baseurl=https://packages.confluent.io/rpm/5.1/7
gpgcheck=1
gpgkey=https://packages.confluent.io/rpm/5.1/archive.key
enabled=1

[Confluent]
name=Confluent repository
baseurl=https://packages.confluent.io/rpm/5.1
gpgcheck=1
gpgkey=https://packages.confluent.io/rpm/5.1/archive.key
enabled=1
" >  /etc/yum.repos.d/confluent.repo

# 4. Clear the YUM caches and install Confluent Platform.

# Commercial Version
#sudo yum clean all && sudo yum install confluent-platform-2.11

# Confluent Platform using only Confluent Community components
yum clean all
yum install -y confluent-community-2.11
