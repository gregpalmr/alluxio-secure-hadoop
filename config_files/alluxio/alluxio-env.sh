# FILE: alluxio-env.sh
#

ALLUXIO_JAVA_OPTS+=" -Djavax.net.ssl.trustStore=/etc/ssl/certs/hadoop-alluxio-truststore.jks -Djavax.net.ssl.trustStorePassword=changeme123 "

# end of file
