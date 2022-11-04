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
     java -cp "/opt/ranger_admin/cred/lib/*" \
       org.apache.ranger.credentialapi.buildks create sslKeyStore -value 'changeme123' \
       -provider jceks://file/etc/ssl/certs/ranger/rangeradmin.jceks
     
     java -cp "/opt/ranger_admin/cred/lib/*" \
       org.apache.ranger.credentialapi.buildks create sslTrustStore -value 'changeme123' \
       -provider jceks://file/etc/ssl/certs/ranger/rangeradmin.jceks

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

  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey -maxrenewlife 7d +allow_renewable HTTP/${RANGER_ADMIN_SERVER_FQDN}@${KRB_REALM}"
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "addprinc -randkey -maxrenewlife 7d +allow_renewable rangeradmin/${RANGER_ADMIN_SERVER_FQDN}@${KRB_REALM}"

  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k spnego-ranger.service.keytab HTTP/${RANGER_ADMIN_SERVER_FQDN}"
  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} -q "xst -k rangeradmin.service.keytab rangeradmin/${RANGER_ADMIN_SERVER_FQDN}"

  chmod 400 spnego-ranger.service.keytab
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

tail -f logfile 

