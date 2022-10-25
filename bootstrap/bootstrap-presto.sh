#!/bin/bash

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
PRESTO_SERVER_FQDN=presto-server.docker.com

if [ -d ${KEYTAB_DIR} ] && [ -f ${KEYTAB_DIR}/presto.service.keytab ]; then
  echo "- File ${KEYTAB_DIR}/presto.service.keytab exists, skipping create kerberos principals step"
else 
  echo "- Creating kerberos principals for presto.service"

  # save cwd and cd to $KEYTAB_DIR
  pushd ${KEYTAB_DIR}

  kadmin \
  -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} \
  -q "addprinc -randkey -maxrenewlife 7d +allow_renewable presto/${PRESTO_SERVER_FQDN}@${KRB_REALM}"

  kadmin -p ${KERBEROS_ADMIN} -w ${KERBEROS_ADMIN_PASSWORD} \
  -q "xst -k presto.service.keytab presto/${PRESTO_SERVER_FQDN}"

  chmod 400 ${KEYTAB_DIR}/presto.service.keytab

  # cd back to previously cwd
  popd
fi


# start presto server
#
/bin/sh ./bin/launcher run

# wait forever
#
while true
do
  sleep 300
done