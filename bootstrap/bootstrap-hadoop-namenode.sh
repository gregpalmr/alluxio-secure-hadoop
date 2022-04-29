#!/bin/bash
# SCRIPT: bootstrap-hadoop-namenode.sh (/bootstrap.sh)
#
# DESCR:  Initialize Hadoop Namenode environment
#

#
# HADOOP NAMENODE
#

grep HADOOP_HOME /etc/profile
if [ "$?" != 0 ];then
	echo "export HADOOP_HOME=/opt/hadoop" >> /etc/profile
	echo "export PATH=\$PATH:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin" >> /etc/profile
fi
source /etc/profile

# Create SSL certs for Hadoop Namenode HTTPS services
keys_dir=/etc/ssl/certs # This is a common volume shared across hadoop and alluxio containers
if [ ! -d /etc/ssl/certs ]; then
     mkdir -p $keys_dir
fi

if [ -f /etc/ssl/certs/hadoop-client-truststore.jks ]; then
     echo "- File /etc/ssl/certs/hadoop-client-truststore.jks exists, skipping create SSL cert files step"
else
     echo "- Creating SSL cert files"
     old_pwd=`pwd`; cd $keys_dir

     store_password="changeme123"

     # For the namenode, generate the keystore and certificate
     keytool -genkey -keyalg RSA \
       -keypass $store_password -storepass $store_password  \
       -validity 360 -keysize 2048 \
       -alias ${HADOOP_NAMENODE_FQDN} \
       -dname "CN=${HADOOP_NAMENODE_FQDN}, OU=Alluxio, L=San Mateo, ST=CA, C=US" \
       -keystore hadoop-${HADOOP_NAMENODE_FQDN}-keystore.jks

     # For the datanode1, generate the keystore and certificate
     keytool -genkey -keyalg RSA \
       -keypass $store_password -storepass $store_password  \
       -validity 360 -keysize 2048 \
       -alias ${HADOOP_DATANODE1_FQDN} \
       -dname "CN=${HADOOP_DATANODE1_FQDN}, OU=Alluxio, L=San Mateo, ST=CA, C=US" \
       -keystore hadoop-${HADOOP_DATANODE1_FQDN}-keystore.jks

     # Export the namenode certificate's public key to a certificate file
     keytool -export -rfc -storepass $store_password \
       -alias ${HADOOP_NAMENODE_FQDN} \
       -keystore hadoop-${HADOOP_NAMENODE_FQDN}-keystore.jks \
       -file hadoop-${HADOOP_NAMENODE_FQDN}.cert 

     # Export the datanode1 certificate's public key to a certificate file
     keytool -export -rfc -storepass $store_password \
       -alias ${HADOOP_DATANODE1_FQDN} \
       -keystore hadoop-${HADOOP_DATANODE1_FQDN}-keystore.jks \
       -file hadoop-${HADOOP_DATANODE1_FQDN}.cert 

     # Import the namenode certificate to a truststore file
     keytool -import -noprompt -storepass $store_password \
       -alias ${HADOOP_NAMENODE_FQDN} \
       -file  hadoop-${HADOOP_NAMENODE_FQDN}.cert \
       -keystore hadoop-${HADOOP_NAMENODE_FQDN}-truststore.jks 

     # Import the datanode certificate to a truststore file
     keytool -import -noprompt -storepass $store_password \
       -alias ${HADOOP_DATANODE1_FQDN} \
       -file  hadoop-${HADOOP_DATANODE1_FQDN}.cert \
       -keystore hadoop-${HADOOP_DATANODE1_FQDN}-truststore.jks 

     # Create a single client truststore file that contains the public key from all the certificates
     keytool -import -noprompt -storepass $store_password \
       -alias ${HADOOP_NAMENODE_FQDN} \
       -file  hadoop-${HADOOP_NAMENODE_FQDN}.cert \
       -keystore hadoop-client-truststore.jks 

     keytool -import -noprompt -storepass $store_password \
       -alias ${HADOOP_DATANODE1_FQDN} \
       -file  hadoop-${HADOOP_DATANODE1_FQDN}.cert \
       -keystore hadoop-client-truststore.jks 

     # Set permissions and ownership on the keys
     #chown -R $YARN_USER:hadoop /etc/ssl/certs
     chmod 755 /etc/ssl/certs
     chmod 440 ${HADOOP_NAMENODE_FQDN}-keystore.jks  
     chmod 440 ${HADOOP_NAMENODE_FQDN}.cert  
     chmod 440 ${HADOOP_NAMENODE_FQDN}-truststore.jks 
     chmod 440 ${HADOOP_DATANODE1_FQDN}-keystore.jks 
     chmod 440 ${HADOOP_DATANODE1_FQDN}.cert 
     chmod 440 ${HADOOP_DATANODE1_FQDN}-truststore.jks 
     chmod 444 hadoop-client-truststore.jks

     # List the contents of the trustore file
     #echo "- Key contents of file: $keys_dir/hadoop-client-truststore.jks"
     #keytool -list -v -keystore hadoop-client-truststore.jks -storepass $store_password

     cd $old_pwd
fi

## Turn on HDFS client Debug mode (uncomment these if you want to debug ssl or kerberos)
#echo "export HADOOP_OPTS=\"$HADOOP_OPTS -Djavax.net.debug=ssl\"" >> $HADOOP_HOME/etc/hadoop/hadoop-env.sh
#echo "export HADOOP_OPTS=\"$HADOOP_OPTS -Dsun.security.krb5.debug=true\"" >> $HADOOP_HOME/etc/hadoop/hadoop-env.sh

## Turn on Hive Debug mode (uncomment these if you want to debug ssl or kerberos)
#echo "export HIVE_OPTS=\"$HIVE_OPTS -Djavax.net.debug=ssl\"" >> /opt/hive/conf/hive-env.sh
#echo "export HIVE_OPTS=\"$HIVE_OPTS -Dsun.security.krb5.debug=true\"" >> /opt/hive/conf/hive-env.sh

# Installing libraries if any - (resource urls added comma separated to the ACP system variable)
cd $HADOOP_HOME/share/hadoop/common ; for cp in ${ACP//,/ }; do  echo == $cp; curl -LO $cp ; done; cd -

# Configure kerberos client
cp -f /tmp/config_files/kdc/krb5.conf /etc/krb5.conf
sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" /etc/krb5.conf
sed -i "s/example.com/${DOMAIN_REALM}/g" /etc/krb5.conf

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

sed -i "s/HADOOP_NAMENODE_FQDN/${HADOOP_NAMENODE_FQDN}/g" $HADOOP_HOME/etc/hadoop/ssl-server.xml

# Create kerberos principals and keytabs (if not already created)
if [ -d ${KEYTAB_DIR} ] && [ -f ${KEYTAB_DIR}/nn.service.keytab ]; then
  echo "- File ${KEYTAB_DIR}/nn.service.keytab exists, skipping create kerberos principals step"
else 
  echo "- Creating kerberos principals "

  mkdir -p ${KEYTAB_DIR}
  old_dir=`pwd`; cd ${KEYTAB_DIR}

  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -pw ${KERBEROS_ROOT_USER_PASSWORD} root@${KRB_REALM}"
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey -maxrenewlife 7d +allow_renewable nn/${HADOOP_NAMENODE_FQDN}@${KRB_REALM}"
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey -maxrenewlife 7d +allow_renewable host/${HADOOP_NAMENODE_FQDN}@${KRB_REALM}"
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey -maxrenewlife 7d +allow_renewable dn/${HADOOP_DATANODE1_FQDN}@${KRB_REALM}"
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey -maxrenewlife 7d +allow_renewable host/${HADOOP_DATANODE1_FQDN}@${KRB_REALM}"
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey -maxrenewlife 7d +allow_renewable HTTP/${HADOOP_NAMENODE_FQDN}@${KRB_REALM}"
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey -maxrenewlife 7d +allow_renewable HTTP/${HADOOP_DATANODE1_FQDN}@${KRB_REALM}"
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey -maxrenewlife 7d +allow_renewable jhs/${HADOOP_NAMENODE_FQDN}@${KRB_REALM}"
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey -maxrenewlife 7d +allow_renewable yarn/${HADOOP_NAMENODE_FQDN}@${KRB_REALM}"
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey -maxrenewlife 7d +allow_renewable yarn/${HADOOP_DATANODE1_FQDN}@${KRB_REALM}"
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey -maxrenewlife 7d +allow_renewable rm/${HADOOP_NAMENODE_FQDN}@${KRB_REALM}"
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey -maxrenewlife 7d +allow_renewable nm/${HADOOP_DATANODE1_FQDN}@${KRB_REALM}"
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey -maxrenewlife 7d +allow_renewable hive/${HADOOP_NAMENODE_FQDN}@${KRB_REALM}"

  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k nn.service.keytab nn/${HADOOP_NAMENODE_FQDN}"
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k nn.service.keytab host/${HADOOP_NAMENODE_FQDN}"
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k dn.service.keytab dn/${HADOOP_DATANODE1_FQDN}"
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k dn.service.keytab host/${HADOOP_DATANODE1_FQDN}"
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k spnego.service.keytab HTTP/${HADOOP_NAMENODE_FQDN}"
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k spnego.service.keytab HTTP/${HADOOP_DATANODE1_FQDN}"
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k jhs.service.keytab jhs/${HADOOP_NAMENODE_FQDN}"
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k yarn.service.keytab yarn/${HADOOP_NAMENODE_FQDN}"
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k yarn.service.keytab yarn/${HADOOP_DATANODE1_FQDN}"
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k rm.service.keytab rm/${HADOOP_NAMENODE_FQDN}"
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k nm.service.keytab nm/${HADOOP_DATANODE1_FQDN}"
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k hive.service.keytab hive/${HADOOP_NAMENODE_FQDN}"

  chmod 400 ${KEYTAB_DIR}/nn.service.keytab
  chmod 400 ${KEYTAB_DIR}/dn.service.keytab
  chmod 400 ${KEYTAB_DIR}/spnego.service.keytab
  chmod 400 ${KEYTAB_DIR}/jhs.service.keytab
  chmod 400 ${KEYTAB_DIR}/yarn.service.keytab
  chmod 400 ${KEYTAB_DIR}/rm.service.keytab
  chmod 400 ${KEYTAB_DIR}/nm.service.keytab
  chown hive:root ${KEYTAB_DIR}/hive.service.keytab
  chmod 400 ${KEYTAB_DIR}/hive.service.keytab

  cd $old_dir
fi

# Format the namenode
if [ ! -d $HADOOP_HOME/data/namenode/current ]; then
  echo "- Formatting the HDFS namenode "
  $HADOOP_HOME/bin/hdfs namenode -format
fi

# Start the sshd daemon so start-dfs.sh can passwordless ssh
nohup /usr/sbin/sshd -D >/dev/null 2>&1 &

# Add Alluxio environment 
grep ALLUXIO_HOME /etc/profile
if [ "$?" != 0 ]; then
     echo "export ALLUXIO_HOME=/opt/alluxio" >> /etc/profile
     echo "export PATH=\$PATH:\$ALLUXIO_HOME/bin" >> /etc/profile
fi

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

#
# Setup Hive
#

# Copy hive config files
cp -f /tmp/config_files/hive/* /opt/hive/conf/

# Save a copy of the Alluxio client jar file, referenced in hive-env.sh
CLIENT_JAR=$(ls $ALLUXIO_HOME/client/alluxio-enterprise-*-client.jar)
CLIENT_JAR=$(basename $CLIENT_JAR)
echo
echo "- Setting up Alluxio client environment in /etc/alluxio/alluxio-site.properties and /opt/alluxio/client/$CLIENT_JAR"
cp $ALLUXIO_HOME/client/$CLIENT_JAR /tmp/
cp /tmp/config_files/alluxio/alluxio-site.properties.client-only /tmp/
rm -rf /opt/alluxio-enterprise* /opt/alluxio
mkdir -p $ALLUXIO_HOME/client
mv /tmp/$CLIENT_JAR $ALLUXIO_HOME/client/
mkdir -p $ALLUXIO_HOME/conf
mv /tmp/alluxio-site.properties.client-only $ALLUXIO_HOME/conf/alluxio-site.properties

# Remove the duplicate log4j jar file
if [ -f $HIVE_HOME/lib/log4j-slf4j-impl-2.6.2.jar ]; then
  rm -f $HIVE_HOME/lib/log4j-slf4j-impl-2.6.2.jar
fi

# Copy the mysql jdbc jar file to the hive lib dir
if [ ! -f $HIVE_HOME/lib/java/mysql-connector-java.jar ]; then
  cp /usr/share/java/mysql-connector-java.jar $HIVE_HOME/lib/
fi

# Create the hive metastore database in mysql
cat <<EOT > /tmp/mysql_commands.sql
 CREATE DATABASE hive_metastore;
 USE hive_metastore;
 CREATE USER 'hiveuser'@'%' IDENTIFIED BY '$NON_ROOT_PASSWORD';
 GRANT ALL ON hive_metastore.* TO 'hiveuser'@'%' WITH GRANT OPTION;
 FLUSH PRIVILEGES;
EOT

# Wait for mysql to become available
max_tries=10
i=0
while true
do
  i=$((i+1))

  mysql --host=mysql --user=root --password=$NON_ROOT_PASSWORD -e '\q'  >/dev/null 2>&1

  if [ "$?" == 0 ]; then
    break
  fi

  if [ $i -gt 10 ]; then
    echo " ERROR: Cannot connect to MySQL server on mysql.docker.com after 10 attempts"
    break
  fi

  sleep 3
done

result=$(mysql --host=mysql --user=root --password=$NON_ROOT_PASSWORD -e "show databases;" | grep hive_metastore)
if [ "$result" != "" ];then
  echo "- Skipping create hive_metastore, already exists "
else
  echo "- Creating the hive_metastore "

  mysql --host=mysql \
    --user=root --password=$NON_ROOT_PASSWORD < /tmp/mysql_commands.sql

  # Create the Hive metastore schema in mysql
  su - hive -c " . /etc/profile && $HIVE_HOME/bin/schematool -dbType mysql -initSchema"
fi

rm /tmp/mysql_commands.sql

#
# Start the hadoop namenode daemons
#
source /etc/profile

$HADOOP_HOME/etc/hadoop/hadoop-env.sh
 
# Temporary fix for: DatanodeProtocol: this service is only accessible by dn/hadoop-namenode.docker.com@EXAMPLE.COM
#echo "sun.security.krb5.disableReferrals=true" >> /usr/java/default/jre/lib/security/java.security

echo
echo "- Starting namenode daemon"
nohup $HADOOP_HOME/bin/hdfs --config $HADOOP_CONF_DIR namenode > /var/log/hadoop-namenode.log 2>&1 &

echo "- Starting YARN Resource Manager daemon"
nohup $HADOOP_HOME/bin/yarn --config $HADOOP_CONF_DIR resourcemanager > /var/log/yarn-resourcemanager.log 2>&1 &

echo "- Starting MapReduce Job History Server daemon"
nohup $HADOOP_HOME/sbin/mr-jobhistory-daemon.sh start historyserver > /var/log/mapreduce-historyserver.log 2>&1 &

sleep 5

# Make some HDFS directories - add the sticky bit to /tmp and /user
echo changeme123 | kinit
hdfs dfs -ls /user/hive/warehouse > /dev/null 2>&1
if [ $? == 0 ]; then
  echo "- Skipping Create HDFS directories (they already exist)"
else
  echo "- Creating HDFS directories (/tmp /user /user/hive etc.)"
  hdfs dfs -mkdir -p /tmp
  hdfs dfs -chmod 1777 /tmp
  hdfs dfs -mkdir -p /user
  hdfs dfs -chmod 1777 /user
  hdfs dfs -mkdir -p /user/hive/warehouse
  hdfs dfs -chown -R hive:hadoop /user/hive
  hdfs dfs -chmod 1777 /user/hive/warehouse
  hdfs dfs -mkdir /user/user1
  hdfs dfs -chown user1 /user/user1
  hdfs dfs -mkdir -p /user/spark
  hdfs dfs -chown spark:root /user/spark
fi

# Start Hive metastore and hiveserver2 (log file will be in /tmp/hive/hive.log)
su - hive -c " . /etc/profile && kinit -kt /etc/security/keytabs/hive.service.keytab hive/${THIS_FQDN}@EXAMPLE.COM"

echo "- Starting Hive Metastore"
#su - hive -c " . /etc/profile && nohup $HIVE_HOME/bin/hive --service metastore  >/dev/null 2>&1 &"
su - hive -c " . /etc/profile && nohup $HIVE_HOME/bin/hive --service metastore  > ./metastore-nohup.out 2>&1 &"

echo "- Starting Hiveserver2"
sleep 3
#su - hive -c " . /etc/profile && nohup $HIVE_HOME/bin/hive --service hiveserver2  >/dev/null 2>&1 &"
su - hive -c " . /etc/profile && nohup $HIVE_HOME/bin/hive --service hiveserver2  > ./hiveserver2-nohup.out 2>&1 &"

echo
echo

#
# Wait forever
#

if [[ $1 == "-bash" ]]; then
  /bin/bash
else
  tail -f /var/log/hadoop-namenode.log
fi

# end of script
