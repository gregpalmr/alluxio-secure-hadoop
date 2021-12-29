#!/bin/bash
# SCRIPT: bootstrap-hadoop.sh (/bootstrap.sh)
#
# DESCR:  Initialize Hadoop environment
#

#
# HADOOP 
#

grep HADOOP_HOME /etc/profile
if [ "$?" != 0 ];then
	echo "export HADOOP_HOME=/opt/hadoop" >> /etc/profile
	echo "export PATH=\$PATH:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin" >> /etc/profile
fi
source /etc/profile

# Turn HDFS client Debug mode on (uncomment these if you want to debug ssl or kerberos)
#echo "export HADOOP_OPTS=\"$HADOOP_OPTS -Djavax.net.debug=ssl\"" >> $HADOOP_HOME/etc/hadoop/hadoop-env.sh
echo "export HADOOP_OPTS=\"$HADOOP_OPTS -Dsun.security.krb5.debug=true\"" >> $HADOOP_HOME/etc/hadoop/hadoop-env.sh
#echo "export HIVE_OPTS=\"$HIVE_OPTS -Djavax.net.debug=ssl\"" >> $HADOOP_HOME/etc/hive/conf/hive-env.sh
echo "export HIVE_OPTS=\"$HIVE_OPTS -Dsun.security.krb5.debug=true\"" >> $HADOOP_HOME/etc/hive/conf/hive-env.sh

# installing libraries if any - (resource urls added comma separated to the ACP system variable)
cd $HADOOP_HOME/share/hadoop/common ; for cp in ${ACP//,/ }; do  echo == $cp; curl -LO $cp ; done; cd -

# Configure kerberos client
cp -f /tmp/config_files/kdc/krb5.conf /etc/krb5.conf
sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" /etc/krb5.conf
sed -i "s/example.com/${DOMAIN_REALM}/g" /etc/krb5.conf

# update config files
sed -i "s/HOSTNAME/${HADOOP_FQDN}/g" $HADOOP_HOME/etc/hadoop/core-site.xml
sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" $HADOOP_HOME/etc/hadoop/core-site.xml
sed -i "s#/etc/security/keytabs#${KEYTAB_DIR}#g" $HADOOP_HOME/etc/hadoop/core-site.xml

sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" $HADOOP_HOME/etc/hadoop/hdfs-site.xml
sed -i "s/HOSTNAME/${HADOOP_FQDN}/g" $HADOOP_HOME/etc/hadoop/hdfs-site.xml
sed -i "s#/etc/security/keytabs#${KEYTAB_DIR}#g" $HADOOP_HOME/etc/hadoop/hdfs-site.xml

sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" $HADOOP_HOME/etc/hadoop/yarn-site.xml
sed -i "s/HOSTNAME/${HADOOP_FQDN}/g" $HADOOP_HOME/etc/hadoop/yarn-site.xml
sed -i "s#/etc/security/keytabs#${KEYTAB_DIR}#g" $HADOOP_HOME/etc/hadoop/yarn-site.xml

sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" $HADOOP_HOME/etc/hadoop/mapred-site.xml
sed -i "s/HOSTNAME/${HADOOP_FQDN}/g" $HADOOP_HOME/etc/hadoop/mapred-site.xml
sed -i "s#/etc/security/keytabs#${KEYTAB_DIR}#g" $HADOOP_HOME/etc/hadoop/mapred-site.xml

sed -i "s#/opt/hadoop/bin/container-executor#${NM_CONTAINER_EXECUTOR_PATH}#g" $HADOOP_HOME/etc/hadoop/yarn-site.xml

# Create kerberos principals and keytabs
kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -pw ${KERBEROS_ROOT_USER_PASSWORD} root@${KRB_REALM}"
kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey nn/$(hostname -f)@${KRB_REALM}"
kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey dn/$(hostname -f)@${KRB_REALM}"
kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey HTTP/$(hostname -f)@${KRB_REALM}"
kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey jhs/$(hostname -f)@${KRB_REALM}"
kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey yarn/$(hostname -f)@${KRB_REALM}"
kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey rm/$(hostname -f)@${KRB_REALM}"
kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey nm/$(hostname -f)@${KRB_REALM}"
kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey hive/$(hostname -f)@${KRB_REALM}"

kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k nn.service.keytab nn/$(hostname -f)"
kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k dn.service.keytab dn/$(hostname -f)"
kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k spnego.service.keytab HTTP/$(hostname -f)"
kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k jhs.service.keytab jhs/$(hostname -f)"
kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k yarn.service.keytab yarn/$(hostname -f)"
kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k rm.service.keytab rm/$(hostname -f)"
kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k nm.service.keytab nm/$(hostname -f)"
kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k hive.service.keytab hive/$(hostname -f)"

mkdir -p ${KEYTAB_DIR}
mv nn.service.keytab ${KEYTAB_DIR}
mv dn.service.keytab ${KEYTAB_DIR}
mv spnego.service.keytab ${KEYTAB_DIR}
mv jhs.service.keytab ${KEYTAB_DIR}
mv yarn.service.keytab ${KEYTAB_DIR}
mv rm.service.keytab ${KEYTAB_DIR}
mv nm.service.keytab ${KEYTAB_DIR}
mv hive.service.keytab ${KEYTAB_DIR}
chmod 400 ${KEYTAB_DIR}/nn.service.keytab
chmod 400 ${KEYTAB_DIR}/dn.service.keytab
chmod 400 ${KEYTAB_DIR}/spnego.service.keytab
chmod 400 ${KEYTAB_DIR}/jhs.service.keytab
chmod 400 ${KEYTAB_DIR}/yarn.service.keytab
chmod 400 ${KEYTAB_DIR}/rm.service.keytab
chmod 400 ${KEYTAB_DIR}/nm.service.keytab
chown hive:root ${KEYTAB_DIR}/hive.service.keytab
chmod 400 ${KEYTAB_DIR}/hive.service.keytab

# Format the namenode
$HADOOP_HOME/bin/hdfs namenode -format

# Start the sshd daemon so start-dfs.sh can passwordless ssh
nohup /usr/sbin/sshd -D >/dev/null 2>&1 &

#
# Setup Hive
#

# Save a copy of the Alluxio client jar file, referenced in hive-env.sh
CLIENT_JAR=$(ls $ALLUXIO_HOME/client/alluxio-enterprise-*-client.jar)
CLIENT_JAR=$(basename $CLIENT_JAR)
echo
echo " ### Setting up Alluxio client environment in /etc/alluxio/alluxio-site.properties and /opt/alluxio/client/$CLIENT_JAR"
cp $ALLUXIO_HOME/client/$CLIENT_JAR /tmp/
cp $ALLUXIO_HOME/conf/alluxio-site.properties.client-only /tmp/
rm -rf /opt/alluxio-enterprise* /opt/alluxio
mkdir -p $ALLUXIO_HOME/client
mv /tmp/$CLIENT_JAR $ALLUXIO_HOME/client/
mkdir -p $ALLUXIO_HOME/conf
mv /tmp/alluxio-site.properties.client-only $ALLUXIO_HOME/conf/alluxio-site.properties

# Remove the duplicate log4j jar file
rm -f $HIVE_HOME/lib/log4j-slf4j-impl-2.6.2.jar

# Copy the mysql jdbc jar file to the hive lib dir
cp /usr/share/java/mysql-connector-java.jar $HIVE_HOME/lib/

# Create the hive metastore database in mysql
cat <<EOT > /tmp/mysql_commands.sql
 CREATE DATABASE hive_metastore;
 USE hive_metastore;
 CREATE USER 'hiveuser'@'%' IDENTIFIED BY '$NON_ROOT_PASSWORD';
 GRANT ALL ON hive_metastore.* TO 'hiveuser'@'%' WITH GRANT OPTION;
 FLUSH PRIVILEGES;
EOT

sleep 3 

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

echo && echo " ### Creating the hive_metastore "
mysql --host=mysql \
  --user=root --password=$NON_ROOT_PASSWORD < /tmp/mysql_commands.sql
rm /tmp/mysql_commands.sql

# Create the Hive metastore schema in mysql
su - hive -c " . /etc/profile && $HIVE_HOME/bin/schematool -dbType mysql -initSchema"

#mysql --host=mysql \
#  --user=hiveuser --password=$NON_ROOT_PASSWORD \
#  --database=hive_metastore < \
#  $HIVE_HOME/scripts/metastore/upgrade/mysql/hive-schema-2.1.0.mysql.sql


#
# Start the hadoop daemons
#
$HADOOP_HOME/etc/hadoop/hadoop-env.sh
echo && echo " ### Starting HDFS daemons"
$HADOOP_HOME/sbin/start-dfs.sh
echo && echo " ### Starting YARN daemons"
$HADOOP_HOME/sbin/start-yarn.sh
echo && echo " ### Starting MapReduce Job History Server  daemon"
$HADOOP_HOME/sbin/mr-jobhistory-daemon.sh start historyserver
sleep 5

# Make some HDFS directories - add the sticky bit to /tmp and /user
echo changeme123 | kinit
hdfs dfs -mkdir -p /tmp
hdfs dfs -chmod 1777 /tmp
hdfs dfs -mkdir -p /user
hdfs dfs -chmod 1777 /user
hdfs dfs -mkdir -p /user/hive/warehouse
hdfs dfs -chown -R hive:hadoop /user/hive
hdfs dfs -chmod 1777 /user/hive/warehouse
hdfs dfs -mkdir /user/user1
hdfs dfs -chown user1 /user/user1

# Start Hive metastore and hiveserver2 (log file will be in /tmp/hive/hive.log)
su - hive -c " . /etc/profile && kinit -kt /etc/security/keytabs/hive.service.keytab hive/hadoop.docker.com@EXAMPLE.COM"

echo &&  echo " ### Starting Hive Metastore"
#su - hive -c " . /etc/profile && nohup $HIVE_HOME/bin/hive --service metastore  >/dev/null 2>&1 &"
su - hive -c " . /etc/profile && nohup $HIVE_HOME/bin/hive --service metastore  > ./metastore-nohup.out 2>&1 &"

echo && echo " ### Starting Hiveserver2"
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
  tail -f /opt/hadoop-*/logs/hadoop-root-namenode-hadoop.out
fi

# end of script
