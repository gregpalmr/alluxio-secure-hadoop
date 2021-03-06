#!/bin/bash
# SCRIPT: bootstrap-alluxio-worker.sh (/bootstrap.sh)
#
# DESCR:  Initialize Alluxio Worker environment
#

#
# ALLUXIO WORKER
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
                echo "- Installing custom Alluxio tarball: /tmp/alluxio-install/$ALLUXIO_TARBALL" | tee -a /opt/alluxio/logs/master.log

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
                fi
                cd $ORIG_PWD
        fi
fi

# Create SSL certs for Alluxio worker to worker TLS
keys_dir=/etc/ssl/certs # This is a common volume shared across alluxio containers
if [ ! -d /etc/ssl/certs ]; then
     mkdir -p $keys_dir
fi

if [ -f /etc/ssl/certs/alluxio-tls-${THIS_FQDN}-keystore.jks ]; then
     echo "- File /etc/ssl/certs/alluxio-tls-${THIS_FQDN}-keystore.jks exists, skipping create SSL cert files step."
else
     old_pwd=`pwd`; cd $keys_dir

     store_password="changeme123"

     # Generate self-signed keystore
     keytool -genkey -keyalg RSA \
       -keypass $store_password -storepass $store_password  \
       -validity 360 -keysize 2048 \
       -alias ${THIS_FQDN} \
       -dname "CN=${THIS_FQDN}, OU=Alluxio, L=San Mateo, ST=CA, C=US" \
       -keystore alluxio-tls-${THIS_FQDN}-keystore.jks

     # Export the certificate's public key to a certificate file
     keytool -export -rfc -storepass $store_password \
       -alias ${THIS_FQDN} \
       -keystore alluxio-tls-${THIS_FQDN}-keystore.jks \
       -file alluxio-tls-${THIS_FQDN}.cert

     # Import the certificate to a truststore file
     keytool -import -noprompt -storepass $store_password \
       -alias ${THIS_FQDN} \
       -file  alluxio-tls-${THIS_FQDN}.cert \
       -keystore alluxio-tls-${THIS_FQDN}-truststore.jks

     # Add the certificate's public key to the all inclusive truststore file 
     keytool -import -noprompt -storepass $store_password \
       -alias ${THIS_FQDN} \
       -file  alluxio-tls-${THIS_FQDN}.cert \
       -keystore alluxio-tls-client-truststore.jks

     # Set permissions and ownership on the keys
     chmod 755 /etc/ssl/certs
     chmod 400 alluxio-tls-${THIS_FQDN}-keystore.jks
     chmod 400 alluxio-tls-${THIS_FQDN}-truststore.jks
     chmod 400 alluxio-tls-${THIS_FQDN}.cert
     chmod 400 alluxio-tls-client-truststore.jks
     chown alluxio alluxio-tls-*

     # List the contents of the trustore file
     #echo "- Contents of truststore file: $keys_dir/alluxio-tls-client-truststore.jks"
     #keytool -list -v -keystore alluxio-tls-client-truststore.jks -storepass $store_password

     cd $old_pwd
fi

# Update the HDFS config files
cp /tmp/config_files/hadoop/core-site.xml $HADOOP_HOME/etc/hadoop/core-site.xml
cp /tmp/config_files/hadoop/hdfs-site.xml $HADOOP_HOME/etc/hadoop/hdfs-site.xml
cp /tmp/config_files/hadoop/ssl-server.xml $HADOOP_HOME/etc/hadoop/ssl-server.xml
cp /tmp/config_files/hadoop/ssl-client.xml $HADOOP_HOME/etc/hadoop/ssl-client.xml

sed -i "s/THIS_FQDN/${THIS_FQDN}/g" $HADOOP_HOME/etc/hadoop/core-site.xml
sed -i "s/HADOOP_NAMENODE_FQDN/${HADOOP_NAMENODE_FQDN}/g" $HADOOP_HOME/etc/hadoop/core-site.xml
sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" $HADOOP_HOME/etc/hadoop/core-site.xml
sed -i "s#/etc/security/keytabs#${KEYTAB_DIR}#g" $HADOOP_HOME/etc/hadoop/core-site.xml

sed -i "s/THIS_FQDN/${THIS_FQDN}/g" $HADOOP_HOME/etc/hadoop/hdfs-site.xml
sed -i "s/HADOOP_NAMENODE_FQDN/${HADOOP_NAMENODE_FQDN}/g" $HADOOP_HOME/etc/hadoop/hdfs-site.xml
sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" $HADOOP_HOME/etc/hadoop/hdfs-site.xml
sed -i "s#/etc/security/keytabs#${KEYTAB_DIR}#g" $HADOOP_HOME/etc/hadoop/hdfs-site.xml

sed -i "s/HADOOP_NAMENODE_FQDN/${HADOOP_NAMENODE_FQDN}/g" $HADOOP_HOME/etc/hadoop/ssl-server.xml

# copy the Hadoop config files
cp -f /tmp/config_files/hadoop/* $HADOOP_HOME/etc/hadoop/

# Update config files
sed -i "s/THIS_FQDN/${THIS_FQDN}/g" $HADOOP_HOME/etc/hadoop/core-site.xml
sed -i "s/HADOOP_NAMENODE_FQDN/${HADOOP_NAMENODE_FQDN}/g" $HADOOP_HOME/etc/hadoop/core-site.xml
sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" $HADOOP_HOME/etc/hadoop/core-site.xml
sed -i "s#/etc/security/keytabs#${KEYTAB_DIR}#g" $HADOOP_HOME/etc/hadoop/core-site.xml

sed -i "s/THIS_FQDN/${THIS_FQDN}/g" $HADOOP_HOME/etc/hadoop/hdfs-site.xml
sed -i "s/HADOOP_NAMENODE_FQDN/${HADOOP_NAMENODE_FQDN}/g" $HADOOP_HOME/etc/hadoop/hdfs-site.xml
sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" $HADOOP_HOME/etc/hadoop/hdfs-site.xml
sed -i "s#/etc/security/keytabs#${KEYTAB_DIR}#g" $HADOOP_HOME/etc/hadoop/hdfs-site.xml

sed -i "s/THIS_FQDN/${THIS_FQDN}/g" $HADOOP_HOME/etc/hadoop/yarn-site.xml
sed -i "s/HADOOP_NAMENODE_FQDN/${HADOOP_NAMENODE_FQDN}/g" $HADOOP_HOME/etc/hadoop/yarn-site.xml
sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" $HADOOP_HOME/etc/hadoop/yarn-site.xml
sed -i "s#/etc/security/keytabs#${KEYTAB_DIR}#g" $HADOOP_HOME/etc/hadoop/yarn-site.xml
sed -i "s#/opt/hadoop/bin/container-executor#${NM_CONTAINER_EXECUTOR_PATH}#g" $HADOOP_HOME/etc/hadoop/yarn-site.xml

sed -i "s/THIS_FQDN/${THIS_FQDN}/g" $HADOOP_HOME/etc/hadoop/mapred-site.xml
sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" $HADOOP_HOME/etc/hadoop/mapred-site.xml
sed -i "s/HADOOP_NAMENODE_FQDN/${HADOOP_NAMENODE_FQDN}/g" $HADOOP_HOME/etc/hadoop/mapred-site.xml
sed -i "s#/etc/security/keytabs#${KEYTAB_DIR}#g" $HADOOP_HOME/etc/hadoop/mapred-site.xml
sed -i "s/ALLUXIO_MASTER_FQDN/${ALLUXIO_MASTER_FQDN}/g" $HADOOP_HOME/etc/hadoop/mapred-site.xml

sed -i "s/HADOOP_NAMENODE_FQDN/${HADOOP_NAMENODE_FQDN}/g" $HADOOP_HOME/etc/hadoop/ssl-server.xml

# Copy the Hadoop config files to Alluxio
cp $HADOOP_HOME/etc/hadoop/core-site.xml $ALLUXIO_HOME/conf/core-site.xml
cp $HADOOP_HOME/etc/hadoop/hdfs-site.xml $ALLUXIO_HOME/conf/hdfs-site.xml
cp $HADOOP_HOME/etc/hadoop/yarn-site.xml $ALLUXIO_HOME/conf/yarn-site.xml
cp $HADOOP_HOME/etc/hadoop/mapred-site.xml $ALLUXIO_HOME/conf/mapred-site.xml
cp $HADOOP_HOME/etc/hadoop/ssl-server.xml $ALLUXIO_HOME/conf/ssl-server.xml
cp $HADOOP_HOME/etc/hadoop/ssl-client.xml $ALLUXIO_HOME/conf/ssl-client.xml

# Configure kerberos client
cp -f /tmp/config_files/kdc/krb5.conf /etc/krb5.conf
sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" /etc/krb5.conf
sed -i "s/example.com/${DOMAIN_REALM}/g" /etc/krb5.conf

# Create kerberos principal for "northbound" kerberization
keytab_dir=${KEYTAB_DIR}  # This is a common volume shared across alluxio containers
if [ ! -d $keytab_dir ]; then
     mkdir -p $keytab_dir
fi

if [ -f $keytab_dir/alluxio.${THIS_FQDN}.keytab ]; then
     echo "- File $keytab_dir/alluxio.${THIS_FQDN}.keytab exists, skipping create keytab files step."
else
     old_pwd=`pwd`; cd $keytab_dir
     kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey alluxio/${THIS_FQDN}@${KRB_REALM}"
     kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k alluxio.${THIS_FQDN}.keytab alluxio/${THIS_FQDN}@${KRB_REALM}"

     chown alluxio:root alluxio.${THIS_FQDN}.keytab
     chmod 400          alluxio.${THIS_FQDN}.keytab
fi

#
# Configure the alluxio-site.properties file
#
cp /tmp/config_files/alluxio/alluxio-site.properties $ALLUXIO_HOME/conf/alluxio-site.properties

sed -i "s/HADOOP_NAMENODE_FQDN/${HADOOP_NAMENODE_FQDN}/g" $ALLUXIO_HOME/conf/alluxio-site.properties
sed -i "s/THIS_FQDN/${THIS_FQDN}/g" $ALLUXIO_HOME/conf/alluxio-site.properties
sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" $ALLUXIO_HOME/conf/alluxio-site.properties

# Configure the alluxio-env.sh file
cp /tmp/config_files/alluxio/alluxio-env.sh $ALLUXIO_HOME/conf/alluxio-env.sh

# Turn on Alluxio Debug mode (un-comment these if you want to debug ssl or kerberos)
#echo "export ALLUXIO_JAVA_OPTS=\"$ALLUXIO_JAVA_OPTS -Djavax.net.debug=ssl\"" >> $ALLUXIO_HOME/conf/alluxio-env.sh
#echo "export ALLUXIO_JAVA_OPTS=\"$ALLUXIO_JAVA_OPTS -Dsun.security.krb5.debug=true\"" >> $ALLUXIO_HOME/conf/alluxio-env.sh

# Make alluxio user owner of files
chown -R alluxio:root /opt/alluxio/
chmod -R go+rw /opt/alluxio/logs/user

# Acquire Kerberos ticket for the alluxio user
su - alluxio bash -c "kinit -kt ${KEYTAB_DIR}/alluxio.${THIS_FQDN}.keytab alluxio/${THIS_FQDN}@${KRB_REALM}"

# Format the worker node ramdisk
# echo "- Formatting Alluxio worker"
#$ALLUXIO_HOME/bin/alluxio formatWorker

# Start the alluxio worker daemons and proxy daemon
echo "- Starting Alluxio worker daemons (worker, job_worker, proxy)"
su - alluxio bash -c "$ALLUXIO_HOME/bin/alluxio-start.sh worker"
su - alluxio bash -c "$ALLUXIO_HOME/bin/alluxio-start.sh job_worker"
su - alluxio bash -c "$ALLUXIO_HOME/bin/alluxio-start.sh proxy"

#
# Wait forever
#

if [[ $1 == "-bash" ]]; then
  /bin/bash
else
  tail -f $ALLUXIO_HOME/logs/worker.log
fi

# end of script

