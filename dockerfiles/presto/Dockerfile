FROM ahanaio/prestodb-sandbox:0.276

LABEL maintainer="Saiguang saiguang@alluxio.com"

RUN yum clean all; \
    rpm --rebuilddb; \
    yum install -y tar; \
    rm -rf /var/cache/yum

RUN mkdir -p /tmp/local_files; \
    export ALLUXIO_HOME=/opt/alluxio； \
    if [ ! -f /tmp/local_files/alluxio-enterprise-trial.tar.gz ]; then \
        curl https://downloads.alluxio.io/protected/files/alluxio-enterprise-trial.tar.gz \
             -o /tmp/local_files/alluxio-enterprise-trial.tar.gz; \
    fi \
    && tar xzvf /tmp/local_files/alluxio-enterprise-trial.tar.gz -C /opt \
    && rm -f /tmp/local_files/alluxio-enterprise-trial.tar.gz \
    && ln -s /opt/alluxio-enterprise-* $ALLUXIO_HOME \
    && rm -f $PRESTO_HOME/plugin/hive-hadoop2/alluxio* ; \
    CLIENT_JAR=$(ls $ALLUXIO_HOME/client/alluxio-enterprise-*-client.jar) \
    && cp $CLIENT_JAR $PRESTO_HOME/plugin/hive-hadoop2 \
    && rm -rf /tmp/local_files

