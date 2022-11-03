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
fi
     
# Run Ranger Admin setup script
./setup.sh

# Start the Ranger Admin server
ranger-admin start

tail -f logfile 

