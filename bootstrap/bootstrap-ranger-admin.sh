#!/bin/bash
set -xe

yum -y install bc

mkdir -p /etc/ssl/certs/ranger

if [ ! -f /etc/ssl/certs/ranger/rangeradmin.jceks ]; then

     # Generate the Ranger Admin HTTPS/SSL server's keystore and certificate
     keytool -genkey -keyalg RSA -alias rangeradmin \
       -keystore /etc/ssl/certs/ranger/ranger-admin-keystore.jks \
       -keypass 'changeme123' -storepass 'changeme123' \
       -validity 360 -keysize 2048 \
       -dname "CN=Alluxio-Ranger, OU=Alluxio, L=San Mateo, ST=CA, C=US"
     
     keytool -export -keystore /etc/ssl/certs/ranger/ranger-admin-keystore.jks \
       -alias rangeradmin -file /etc/ssl/certs/ranger/rangeradmin.cer -storepass 'changeme123'
     
     # Generate the client (plugin) keystore and certificate
     keytool -genkey -keyalg RSA -alias alluxio-plugin \
       -keystore /etc/ssl/certs/ranger/ranger-plugin-keystore.jks \
       -keypass 'changeme123' -storepass 'changeme123' \
       -validity 360 -keysize 2048 \
       -dname "CN=Alluxio-Ranger, OU=Alluxio, L=San Mateo, ST=CA, C=US"
     
     keytool -export -keystore /etc/ssl/certs/ranger/ranger-plugin-keystore.jks \
       -alias alluxio-plugin -file /etc/ssl/certs/ranger/alluxio-plugin.cer -storepass 'changeme123'
     
     # Cross import the certificates (create truststores)
     keytool -import -noprompt -file /etc/ssl/certs/ranger/alluxio-plugin.cer \
             -alias alluxio-plugin \
             -keystore /etc/ssl/certs/ranger/ranger-admin-truststore.jks -storepass 'changeme123'
     
     keytool -import -noprompt -file /etc/ssl/certs/ranger/rangeradmin.cer \
        -alias rangeradmin \
             -keystore /etc/ssl/certs/ranger/ranger-plugin-truststore.jks -storepass 'changeme123'
     
     # Credentials file creation - one file containing credentials for both key and truststore
     # TODO: verify that rangeradmin.jceks is NOT actually used
     java -cp "/opt/ranger_admin/cred/lib/*" \
       org.apache.ranger.credentialapi.buildks create sslKeyStore -value 'changeme123' \
       -provider jceks://file/etc/ssl/certs/ranger/rangeradmin.jceks
     
     java -cp "/opt/ranger_admin/cred/lib/*" \
       org.apache.ranger.credentialapi.buildks create sslTrustStore -value 'changeme123' \
       -provider jceks://file/etc/ssl/certs/ranger/rangeradmin.jceks

    # Credentials file creation - one file containing credentials for both key and truststore
    # alluxio-plugin.jceks is used by ranger-plugin which downloads the policy.
    # In our case, the ranger-plugin sits in alluxio master process, and alluxio-plugin.jceks is
    # configured in ${ALLUXIO_HOME}/conf/ranger-hdfs-policymgr-ssl.xml
    # MAKE SURE the mode of alluxio-plugin.jceks is 400 and the user that starts alluxio master
    # process is the owner of alluxio-plugin.jceks.
    java -cp "/opt/ranger_admin/cred/lib/*" \
       org.apache.ranger.credentialapi.buildks create sslKeyStore -value 'changeme123' \
       -provider jceks://file/etc/ssl/certs/ranger/alluxio-plugin.jceks
     
     java -cp "/opt/ranger_admin/cred/lib/*" \
       org.apache.ranger.credentialapi.buildks create sslTrustStore -value 'changeme123' \
       -provider jceks://file/etc/ssl/certs/ranger/alluxio-plugin.jceks
fi

# For Ranger configuraiton in kerberized environment, see
# https://cwiki.apache.org/confluence/display/RANGER/Ranger+installation+in+Kerberized++Environment
# for details

# Install Kerberos client
#
yum install krb5-libs krb5-workstation krb5-auth-dialog -y \
    && mkdir -p /var/log/kerberos \
    && touch /var/log/kerberos/kadmind.log

# Define Kerberos settings
#
KRB_REALM=EXAMPLE.COM
KERBEROS_ADMIN=admin/admin
KERBEROS_ADMIN_PASSWORD=admin
KERBEROS_ROOT_USER_PASSWORD=changeme123
KEYTAB_DIR=/etc/security/keytabs
RANGER_ADMIN_SERVER_FQDN=ranger-admin.docker.com
     
# Create principals and keytabs
#
if [ -d ${KEYTAB_DIR} ] && [ -f ${KEYTAB_DIR}/ranger-admin.service.keytab ]; then
  echo "- File ${KEYTAB_DIR}/ranger-admin.service.keytab exists, skipping create kerberos principals step"
else 
  echo "- Creating kerberos principals for ranger services"

  # save cwd and cd to $KEYTAB_DIR
  pushd ${KEYTAB_DIR}

  # following principals are configured in ${RANGER_HOME}/install.properties

  # HTTP/_HOST@REALM is used for SPNEGO: alluxio ranger-plugin's principle acts as a client, and HTTP/_HOST@REALM acts as a server;
  # HTTP/_HOST@REALM authenticates client principle in KDC, and on success, it sends cookie back to client as a authentication verification.
  # This principal is configured in install.properties: "spnego_principal=..." & "spnego_keytab=..."
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey -maxrenewlife 7d +allow_renewable HTTP/${RANGER_ADMIN_SERVER_FQDN}@${KRB_REALM}"
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k spnego-ranger.service.keytab HTTP/${RANGER_ADMIN_SERVER_FQDN}"
  chmod 400 spnego-ranger.service.keytab

  # rangeradmin/_HOST@REALM is used as the ranger-admin service principal. This principal is configured in install.properties: "admin_principal=..." & "admin_keytab=..."
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey -maxrenewlife 7d +allow_renewable rangeradmin/${RANGER_ADMIN_SERVER_FQDN}@${KRB_REALM}"
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k rangeradmin.service.keytab rangeradmin/${RANGER_ADMIN_SERVER_FQDN}"
  chmod 400 rangeradmin.service.keytab

  # cd back to previously cwd
  popd
fi

# Run Ranger Admin setup script
./setup.sh

# change keytab owners to ranger, which is created by setup.sh
chown ranger:ranger ${KEYTAB_DIR}/spnego-ranger.service.keytab
chown ranger:ranger ${KEYTAB_DIR}/rangeradmin.service.keytab

# Start the Ranger Admin server
ranger-admin start

# Enable debug log for ranger and hadoop
# Find useful logs in ${RANGER_ADMIN_HOME}/ews/logs/*.log.
echo "log4j.logger.org.apache.ranger=debug,xa_log_appender" >> ${RANGER_ADMIN_HOME}/ews/webapp/WEB-INF/log4j.properties
echo "log4j.logger.org.apache.hadoop=debug,xa_log_appender" >> ${RANGER_ADMIN_HOME}/ews/webapp/WEB-INF/log4j.properties

tail -f logfile 

