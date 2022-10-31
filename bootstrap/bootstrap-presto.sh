#!/bin/bash

echo "hahahahahahahaha"

# Install Kerberos client
#
yum install krb5-libs krb5-workstation krb5-auth-dialog -y \
    && mkdir -p /var/log/kerberos \
    && touch /var/log/kerberos/kadmind.log

# Define Kerberos settings
#
KRB_REALM=EXAMPLE.COM
DOMAIN_REALM=example.com
KERBEROS_ADMIN=admin/admin
KERBEROS_ADMIN_PASSWORD=admin
KERBEROS_ROOT_USER_PASSWORD=changeme123
KEYTAB_DIR=/etc/security/keytabs
FQDN=hadoop.com
PRESTO_SERVER_FQDN=presto-server.docker.com


kadmin \
-p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} \
-q "addprinc -randkey -maxrenewlife 7d +allow_renewable presto/${PRESTO_SERVER_FQDN}@${KRB_REALM}"

kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} \
-q "xst -k presto.service.keytab presto/${HADOOP_NAMENODE_FQDN}"

chmod 400 ${KEYTAB_DIR}/presto.service.keytab


# Wait forever
#
if [[ $1 == "-bash" ]]; then
  /bin/bash
else
  tail -f $ALLUXIO_HOME/logs/master.log
fi