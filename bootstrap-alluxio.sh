#!/bin/bash
# SCRIPT: bootstrap-alluxio.sh (/bootstrap.sh)
#
# DESCR:  Initialize Alluxio environment
#

#
# ALLUXIO
#

# wait for the hadoop container's bootstrap script to procced
# because it sets the root kerberos user's password which is needed here
sleep 10

echo "export ALLUXIO_HOME=/opt/alluxio" >> /etc/profile
echo "export PATH=\$PATH:\$ALLUXIO_HOME/bin" >> /etc/profile
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

                        echo " ### CONTENTS of /opt/"
                fi
                cd $ORIG_PWD
        fi
fi

# Copy Alluxio license files
if [ -f /tmp/config_files/alluxio/alluxio-enterprise-license.json ]; then
        cp /tmp/config_files/alluxio/alluxio-enterprise-license.json $ALLUXIO_HOME/license.json
fi

# Create an alluxio user, for testing purposes
useradd alluxio-user1
sleep 2
kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -pw ${KERBEROS_ROOT_USER_PASSWORD} alluxio-user1@${KRB_REALM}"
sleep 2
kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -pw ${KERBEROS_ROOT_USER_PASSWORD} alluxio-user1@${KRB_REALM}"

# Configure  kerberos client
cp -f /tmp/config_files/kdc/krb5.conf /etc/krb5.conf
sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" /etc/krb5.conf
sed -i "s/example.com/${DOMAIN_REALM}/g" /etc/krb5.conf

# Create kerberos principals
kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey alluxio/$(hostname -f)@${KRB_REALM}"
kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k ${KEYTAB_DIR}/alluxio.service.keytab alluxio/$(hostname -f)@${KRB_REALM}"
chmod 400 ${KEYTAB_DIR}/alluxio.service.keytab

# Acquire Kerberos ticket
kinit -kt ${KEYTAB_DIR}/alluxio.service.keytab alluxio/$(hostname -f)@${KRB_REALM}

# Configure the alluxio-site.properties file
cp /tmp/config_files/alluxio/alluxio-site.properties $ALLUXIO_HOME/conf/alluxio-site.properties

sed -i "s/NAMENODE/${NAMENODE}/g" $ALLUXIO_HOME/conf/alluxio-site.properties
sed -i "s/FQDN/${FQDN}/g" $ALLUXIO_HOME/conf/alluxio-site.properties
sed -i "s/EXAMPLE.COM/${KRB_REALM}/g" $ALLUXIO_HOME/conf/alluxio-site.properties


# Format the master node journal
$ALLUXIO_HOME/bin/alluxio formatJournal

# Start the master node daemons
$ALLUXIO_HOME/bin/alluxio-start.sh master
$ALLUXIO_HOME/bin/alluxio-start.sh job_master
$ALLUXIO_HOME/bin/alluxio-start.sh proxy

# Format the worker node ramdisk
#$ALLUXIO_HOME/bin/alluxio formatWorker

$ALLUXIO_HOME/bin/alluxio-start.sh worker 
$ALLUXIO_HOME/bin/alluxio-start.sh job_worker


#
# Wait forever
#

if [[ $1 == "-bash" ]]; then
  /bin/bash
else
  tail -f $ALLUXIO_HOME/logs/master.log
fi

# end of script

