#!/bin/bash
# SCRIPT: bootstrap-hadoop-datanode.sh (/bootstrap.sh)
#
# DESCR:  Initialize Hadoop Datanode environment
#

#
# HADOOP DATANODE
#

grep HADOOP_HOME /etc/profile
if [ "$?" != 0 ];then
	echo "export HADOOP_HOME=/opt/hadoop" >> /etc/profile
	echo "export PATH=\$PATH:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin" >> /etc/profile
fi
source /etc/profile

## Turn on HDFS client Debug mode (uncomment these if you want to debug ssl or kerberos)
#echo "export HADOOP_OPTS=\"$HADOOP_OPTS -Djavax.net.debug=ssl\"" >> $HADOOP_HOME/etc/hadoop/hadoop-env.sh
#echo "export HADOOP_OPTS=\"$HADOOP_OPTS -Dsun.security.krb5.debug=true\"" >> $HADOOP_HOME/etc/hadoop/hadoop-env.sh

# Installing libraries if any - (resource urls added comma separated to the ACP system variable)
cd $HADOOP_HOME/share/hadoop/common ; for cp in ${ACP//,/ }; do  echo == $cp; curl -LO $cp ; done; cd -

# Configure kerberos client
cp -f /tmp/config_files/kdc/krb5.conf /etc/krb5.conf
sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" /etc/krb5.conf
sed -i "s/example.com/${DOMAIN_REALM}/g" /etc/krb5.conf

# copy the Hadoop config files
cp -f /tmp/config_files/hadoop/* $HADOOP_HOME/etc/hadoop/

# Update config files
sed -i "s/HADOOP_NAMENODE_FQDN/${HADOOP_NAMENODE_FQDN}/g" $HADOOP_HOME/etc/hadoop/core-site.xml
sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" $HADOOP_HOME/etc/hadoop/core-site.xml
sed -i "s#/etc/security/keytabs#${KEYTAB_DIR}#g" $HADOOP_HOME/etc/hadoop/core-site.xml

sed -i "s/THIS_FQDN/${THIS_FQDN}/g" $HADOOP_HOME/etc/hadoop/hdfs-site.xml
sed -i "s/HADOOP_NAMENODE_FQDN/${HADOOP_NAMENODE_FQDN}/g" $HADOOP_HOME/etc/hadoop/hdfs-site.xml
sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" $HADOOP_HOME/etc/hadoop/hdfs-site.xml
sed -i "s#/etc/security/keytabs#${KEYTAB_DIR}#g" $HADOOP_HOME/etc/hadoop/hdfs-site.xml

sed -i "s/HADOOP_NAMENODE_FQDN/${HADOOP_NAMENODE_FQDN}/g" $HADOOP_HOME/etc/hadoop/yarn-site.xml
sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" $HADOOP_HOME/etc/hadoop/yarn-site.xml
sed -i "s#/etc/security/keytabs#${KEYTAB_DIR}#g" $HADOOP_HOME/etc/hadoop/yarn-site.xml
sed -i "s#/opt/hadoop/bin/container-executor#${NM_CONTAINER_EXECUTOR_PATH}#g" $HADOOP_HOME/etc/hadoop/yarn-site.xml

sed -i "s/HADOOP_NAMENODE_FQDN/${HADOOP_NAMENODE_FQDN}/g" $HADOOP_HOME/etc/hadoop/mapred-site.xml
sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" $HADOOP_HOME/etc/hadoop/mapred-site.xml
sed -i "s#/etc/security/keytabs#${KEYTAB_DIR}#g" $HADOOP_HOME/etc/hadoop/mapred-site.xml
sed -i "s/ALLUXIO_MASTER_FQDN/${ALLUXIO_MASTER_FQDN}/g" $HADOOP_HOME/etc/hadoop/mapred-site.xml

sed -i "s/HADOOP_NAMENODE_FQDN/${HADOOP_NAMENODE_FQDN}/g" $HADOOP_HOME/etc/hadoop/ssl-server.xml

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

#
# Start the hadoop datanode daemons
#

# Wait for the namenode to create keytab files
sleep 15

source /etc/profile

$HADOOP_HOME/etc/hadoop/hadoop-env.sh

# Temporary fix for: DatanodeProtocol: this service is only accessible by dn/hadoop-namenode.docker.com@EXAMPLE.COM
#echo "sun.security.krb5.disableReferrals=true" >> /usr/java/default/jre/lib/security/java.security

echo "- Starting datanode daemon"
nohup $HADOOP_HOME/bin/hdfs --config $HADOOP_CONF_DIR datanode > /var/log/hadoop-datanode.log 2>&1 &

echo "- Starting YARN Node Manager daemon"
nohup $HADOOP_HOME/bin/yarn --config $HADOOP_CONF_DIR nodemanager > /var/log/yarn-nodemanager.log 2>&1 &

echo "- Starting Spark Worker"
su - spark bash -c "\$SPARK_HOME/sbin/start-slave.sh spark://hadoop-namenode:7077"

echo
echo

#
# Wait forever
#

if [[ $1 == "-bash" ]]; then
  /bin/bash
else
  #tail -f /opt/hadoop-*/logs/hadoop-root-datanode-hadoop.out
  tail -f /var/log/hadoop-datanode.log
fi

# end of script
