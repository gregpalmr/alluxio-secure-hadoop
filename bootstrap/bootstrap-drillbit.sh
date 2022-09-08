#!/bin/bash
# SCRIPT: bootstrap-drillbit.sh (/bootstrap.sh)
#
# DESCR:  Initialize Apache Drillbit server environment
#

#
# APACHE DRILL
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

# Copy the Hadoop config files to Alluxio
cp $HADOOP_HOME/etc/hadoop/core-site.xml $ALLUXIO_HOME/conf/core-site.xml
cp $HADOOP_HOME/etc/hadoop/hdfs-site.xml $ALLUXIO_HOME/conf/hdfs-site.xml
cp $HADOOP_HOME/etc/hadoop/ssl-server.xml $ALLUXIO_HOME/conf/ssl-server.xml
cp $HADOOP_HOME/etc/hadoop/ssl-client.xml $ALLUXIO_HOME/conf/ssl-client.xml

# Copy the Hadoop config files to Drill
cp $HADOOP_HOME/etc/hadoop/core-site.xml $DRILL_HOME/conf/core-site.xml
cp $HADOOP_HOME/etc/hadoop/hdfs-site.xml $DRILL_HOME/conf/hdfs-site.xml
cp $HADOOP_HOME/etc/hadoop/ssl-server.xml $DRILL_HOME/conf/ssl-server.xml
cp $HADOOP_HOME/etc/hadoop/ssl-client.xml $DRILL_HOME/conf/ssl-client.xml

# Add fs.alluxio.imp to Drill's core-site.xml
sed -i '/^\/configuration/i <property>\n    <name>fs.alluxio.impl</name>\n    <value>alluxio.hadoop.FileSystem<value>\n</property>' $DRILL_HOME/conf/core-site.xml

# Update Drill config override file
sed -i "s/DRILL_CLUSTER_ID/$DRILL_CLUSTER_ID/" $DRILL_HOME/conf/drill-override.conf
sed -i "s/DRILL_ZOOKEEPER_QUORUM/$DRILL_ZOOKEEPER_QUORUM/" $DRILL_HOME/conf/drill-override.conf

# Copy the Alluxio client jar file to the Drill classpath:
CLIENT_JAR=$(ls $ALLUXIO_HOME/client/alluxio-enterprise-*-client.jar); \
CLIENT_JAR=$(basename $CLIENT_JAR);
cp $ALLUXIO_HOME/client/$CLIENT_JAR $DRILL_HOME/jars/3rdparty/

# Configure kerberos client
cp -f /tmp/config_files/kdc/krb5.conf /etc/krb5.conf
sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" /etc/krb5.conf
sed -i "s/example.com/${DOMAIN_REALM}/g" /etc/krb5.conf

#
# Configure the alluxio-site.properties file
#
cp /tmp/config_files/alluxio/alluxio-site.properties $ALLUXIO_HOME/conf/alluxio-site.properties

sed -i "s/HADOOP_NAMENODE_FQDN/${HADOOP_NAMENODE_FQDN}/g" $ALLUXIO_HOME/conf/alluxio-site.properties
sed -i "s/THIS_FQDN/${THIS_FQDN}/g" $ALLUXIO_HOME/conf/alluxio-site.properties
sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" $ALLUXIO_HOME/conf/alluxio-site.properties

# Configure the alluxio-env.sh file
cp /tmp/config_files/alluxio/alluxio-env.sh $ALLUXIO_HOME/conf/alluxio-env.sh

# Make alluxio user owner of files
chown -R alluxio:root $ALLUXIO_HOME
chmod -R go+rw $ALLUXIO_HOME/logs/user

# Make drill user owner of files
chown -R drill $DRILL_HOME

#
# Start the drill service
#
if [[ $1 == "-bash" ]]; then
  /bin/bash
else
  #echo "`ulimit -a`"  2>&1
  echo "`date` - Starting drillbit on `hostname`"
  su - drill bash -c ". $DRILL_HOME/bin/drill-config.sh && $DRILL_HOME/bin/runbit drillbit"
fi

#
# Wait forever
#
sleep 5
tail -f /var/log/drill/drillbit.log

# end of script

