#!/bin/bash
# SCRIPT: bootstrap-alluxio.sh (/bootstrap.sh)
#
# DESCR:  Initialize Alluxio environment
#

#
# ALLUXIO
#

# Wait for the hadoop container's bootstrap script to procced
# because it sets the root kerberos user's password which is needed here
sleep 10

grep ALLUXIO_HOME /etc/profile
if [ "$?" != 0 ]; then
	echo "export ALLUXIO_HOME=/opt/alluxio" >> /etc/profile
	echo "export PATH=\$PATH:\$ALLUXIO_HOME/bin" >> /etc/profile
fi
grep HADOOP_HOME /etc/profile
if [ "$?" != 0 ];then
        echo "export HADOOP_HOME=/opt/hadoop" >> /etc/profile
        echo "export PATH=\$PATH:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin" >> /etc/profile
fi
. /etc/profile

# If a new Alluxio install tarball was specified, install it
if [ "$ALLUXIO_TARBALL" != "" ]; then
        if [ ! -f /tmp/alluxio-install/$ALLUXIO_TARBALL ]; then
                echo " ERROR: Cannot install Alluxio tarball - file not found: /tmp/alluxio-install/$ALLUXIO_TARBALL" | tee -a /opt/alluxio/logs/master.log
        else
                echo " ### Installing Alluxio tarball: /tmp/alluxio-install/$ALLUXIO_TARBALL" | tee -a /opt/alluxio/logs/master.log

                ORIG_PWD=$(pwd) && cd /

                # Remove the soft link
                rm -f /opt/alluxio

                # Save the old release and install the new release
                orig_dir_name=$(ls /opt | grep alluxio-enterprise)
                if [ "$orig_dir_name" != "" ]; then
                        #mv /opt/$orig_dir_name /opt/${orig_dir_name}.orig
                        rm -rf /opt/$orig_dir_name

                        # Untar the new release to /opt/
                        tar zxf /tmp/alluxio-install/$ALLUXIO_TARBALL -C /opt/

                        # Recreate the soft link
                        #new_dir_name=$(echo $ALLUXIO_TARBALL | sed 's/-bin.tar.gz//')
                        new_dir_name=$(ls /opt | grep alluxio-enterprise | grep -v $orig_dir_name)
                        ln -s /opt/$new_dir_name /opt/alluxio
			chown -R alluxio:root /opt/alluxio/
                        echo " ### CONTENTS of /opt/"
                fi
                cd $ORIG_PWD
        fi
fi

# Update the HDFS config files
sed -i "s/HOSTNAME/${HADOOP_FQDN}/g" $HADOOP_HOME/etc/hadoop/core-site.xml
sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" $HADOOP_HOME/etc/hadoop/core-site.xml
sed -i "s#/etc/security/keytabs#${KEYTAB_DIR}#g" $HADOOP_HOME/etc/hadoop/core-site.xml

sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" $HADOOP_HOME/etc/hadoop/hdfs-site.xml
sed -i "s/HOSTNAME/${HADOOP_FQDN}/g" $HADOOP_HOME/etc/hadoop/hdfs-site.xml
sed -i "s#/etc/security/keytabs#${KEYTAB_DIR}#g" $HADOOP_HOME/etc/hadoop/hdfs-site.xml

# Copy Alluxio license files
if [ -f /tmp/config_files/alluxio/alluxio-enterprise-license.json ]; then
        cp /tmp/config_files/alluxio/alluxio-enterprise-license.json $ALLUXIO_HOME/license.json
fi

# Configure  kerberos client
cp -f /tmp/config_files/kdc/krb5.conf /etc/krb5.conf
sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" /etc/krb5.conf
sed -i "s/example.com/${DOMAIN_REALM}/g" /etc/krb5.conf

# Create kerberos principals
kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey alluxio/$(hostname -f)@${KRB_REALM}"
kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k alluxio.service.keytab alluxio/$(hostname -f)@${KRB_REALM}"
chown alluxio:root alluxio.service.keytab
chmod 400 alluxio.service.keytab
mv alluxio.service.keytab ${KEYTAB_DIR}/

# Create an alluxio user, for testing purposes
useradd alluxio-user1
kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -pw ${NON_ROOT_PASSWORD} alluxio-user1@${KRB_REALM}"

# Configure the alluxio-site.properties file
cp /tmp/config_files/alluxio/alluxio-site.properties $ALLUXIO_HOME/conf/alluxio-site.properties

sed -i "s/NAMENODE/${NAMENODE}/g" $ALLUXIO_HOME/conf/alluxio-site.properties
sed -i "s/FQDN/${FQDN}/g" $ALLUXIO_HOME/conf/alluxio-site.properties
sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" $ALLUXIO_HOME/conf/alluxio-site.properties

# Acquire Kerberos ticket for the alluxio user
su - alluxio bash -c "kinit -kt ${KEYTAB_DIR}/alluxio.service.keytab alluxio/$(hostname -f)@${KRB_REALM}"

# Format the master node journal
su - alluxio bash -c "$ALLUXIO_HOME/bin/alluxio formatJournal"

# Start the Alluxio master node daemons
su - alluxio bash -c "$ALLUXIO_HOME/bin/alluxio-start.sh master"
su - alluxio bash -c "$ALLUXIO_HOME/bin/alluxio-start.sh job_master"

# Format the worker node ramdisk
#$ALLUXIO_HOME/bin/alluxio formatWorker

# Start the alluxio worker daemons and proxy daemon
su - alluxio bash -c "$ALLUXIO_HOME/bin/alluxio-start.sh worker"
su - alluxio bash -c "$ALLUXIO_HOME/bin/alluxio-start.sh job_worker"
su - alluxio bash -c "$ALLUXIO_HOME/bin/alluxio-start.sh proxy"

#
# Wait forever
#

if [[ $1 == "-bash" ]]; then
  /bin/bash
else
  tail -f $ALLUXIO_HOME/logs/master.log
fi

# end of script

