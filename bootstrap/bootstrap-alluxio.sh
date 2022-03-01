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

echo 'export PS1="\u $ "' >> /etc/profile

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
                echo " ### Installing custom Alluxio tarball: /tmp/alluxio-install/$ALLUXIO_TARBALL" | tee -a /opt/alluxio/logs/master.log

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

# Copy Alluxio license files
if [ -f /tmp/config_files/alluxio/alluxio-enterprise-license.json ]; then
        cp /tmp/config_files/alluxio/alluxio-enterprise-license.json $ALLUXIO_HOME/license.json
fi

# Create SSL certs for
keys_dir=/etc/ssl/certs # This is a common volume shared across hadoop and alluxio containers
if [ ! -d /etc/ssl/certs ]; then

     mkdir -p $keys_dir
fi

if [ ! -f /etc/ssl/certs/hadoop.jceks ]; then

     old_pwd=`pwd`; cd $keys_dir

     store_password="changeme123"

     # For each Alluxio node, generate the Alluxio keystore and certificate
     keytool -genkey -keyalg RSA -alias $HADOOP_FQDN \
       -keystore alluxio-keystore-$HADOOP_FQDN.jks \
       -keypass $store_password  -storepass $store_password  \
       -validity 360 -keysize 2048 \
       -dname "CN=$HADOOP_FQDN, OU=Alluxio, L=San Mateo, ST=CA, C=US"

     # Export the certificate's public key to a certificate file
     keytool -export -keystore alluxio-keystore-$HADOOP_FQDN.jks \
       -alias $HADOOP_FQDN -rfc -file alluxio-$HADOOP_FQDN.cert -storepass $store_password

     # Import the certificate to a truststore file
     keytool -import -noprompt -alias $HADOOP_FQDN -file alluxio-$HADOOP_FQDN.cert \
       -keystore alluxio-truststore-$HADOOP_FQDN.jks -storepass $store_password

     # Add the certificate's public key to the all inclusive truststore file 
     keytool -import -noprompt -file alluxio-$HADOOP_FQDN.cert \
        -alias $HADOOP_FQDN \
        -keystore hadoop-alluxio-truststore.jks -storepass $store_password

     # Set permissions and ownership on the keys
     chmod 755 /etc/ssl/certs
     chmod 440 alluxio-keystore-$HADOOP_FQDN.jks
     chmod 440 alluxio-truststore-$HADOOP_FQDN.jks
     chmod 440 cert
     chmod 444 hadoop-alluxio-truststore.jks

     # List the contents of the trustore file
     echo " Key contents of file: $keys_dir/hadoop-alluxio-truststore.jks"
     keytool -list -v -keystore hadoop-alluxio-truststore.jks -storepass $store_password

     cd $old_pwd
fi

# Update the HDFS config files
cp /tmp/config_files/hadoop/core-site.xml $HADOOP_HOME/etc/hadoop/core-site.xml
cp /tmp/config_files/hadoop/hdfs-site.xml $HADOOP_HOME/etc/hadoop/hdfs-site.xml
cp /tmp/config_files/hadoop/ssl-server.xml $HADOOP_HOME/etc/hadoop/ssl-server.xml
cp /tmp/config_files/hadoop/ssl-client.xml $HADOOP_HOME/etc/hadoop/ssl-client.xml

sed -i "s/HOSTNAME/${HADOOP_FQDN}/g" $HADOOP_HOME/etc/hadoop/core-site.xml
sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" $HADOOP_HOME/etc/hadoop/core-site.xml
sed -i "s#/etc/security/keytabs#${KEYTAB_DIR}#g" $HADOOP_HOME/etc/hadoop/core-site.xml

sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" $HADOOP_HOME/etc/hadoop/hdfs-site.xml
sed -i "s/HOSTNAME/${HADOOP_FQDN}/g" $HADOOP_HOME/etc/hadoop/hdfs-site.xml
sed -i "s#/etc/security/keytabs#${KEYTAB_DIR}#g" $HADOOP_HOME/etc/hadoop/hdfs-site.xml

sed -i "s/HOSTNAME/${HADOOP_FQDN}/g" $HADOOP_HOME/etc/hadoop/ssl-server.xml
sed -i "s/HOSTNAME/${HADOOP_FQDN}/g" $HADOOP_HOME/etc/hadoop/ssl-client.xml

# Copy the Hadoop config files to Alluxio
cp $HADOOP_HOME/etc/hadoop/core-site.xml $ALLUXIO_HOME/conf/core-site.xml
cp $HADOOP_HOME/etc/hadoop/hdfs-site.xml $ALLUXIO_HOME/conf/hdfs-site.xml
cp $HADOOP_HOME/etc/hadoop/ssl-server.xml $ALLUXIO_HOME/conf/ssl-server.xml
cp $HADOOP_HOME/etc/hadoop/ssl-client.xml $ALLUXIO_HOME/conf/ssl-client.xml

# Configure kerberos client
cp -f /tmp/config_files/kdc/krb5.conf /etc/krb5.conf
sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" /etc/krb5.conf
sed -i "s/example.com/${DOMAIN_REALM}/g" /etc/krb5.conf

# Create kerberos principals
kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey alluxio/$(hostname -f)@${KRB_REALM}"
kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k alluxio.service.keytab alluxio/$(hostname -f)@${KRB_REALM}"
chown alluxio:root alluxio.service.keytab
chmod 400 alluxio.service.keytab
mv alluxio.service.keytab ${KEYTAB_DIR}/

# Create a kerberos principal for the test Alluxio user
kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -pw ${NON_ROOT_PASSWORD} user1@${KRB_REALM}"

# Configure the alluxio-site.properties file
cp /tmp/config_files/alluxio/alluxio-site.properties $ALLUXIO_HOME/conf/alluxio-site.properties

sed -i "s/NAMENODE/${NAMENODE}/g" $ALLUXIO_HOME/conf/alluxio-site.properties
sed -i "s/FQDN/${FQDN}/g" $ALLUXIO_HOME/conf/alluxio-site.properties
sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" $ALLUXIO_HOME/conf/alluxio-site.properties

# Configure the alluxio-env.sh file
cp /tmp/config_files/alluxio/alluxio-env.sh $ALLUXIO_HOME/conf/alluxio-env.sh

# Turn on Alluxio Debug mode (un-comment these if you want to debug ssl or kerberos)
#echo "export ALLUXIO_JAVA_OPTS=\"$ALLUXIO_JAVA_OPTS -Djavax.net.debug=ssl\"" >> $ALLUXIO_HOME/conf/alluxio-env.sh
#echo "export ALLUXIO_JAVA_OPTS=\"$ALLUXIO_JAVA_OPTS -Dsun.security.krb5.debug=true\"" >> $ALLUXIO_HOME/conf/alluxio-env.sh

# Make alluxio user owner of files
chown -R alluxio:root /opt/alluxio/

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

