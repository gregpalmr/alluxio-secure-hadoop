# FILE:  Dockerfile
#
# DESCR: Creates Alluxio Enteprise image with a pseudo distributed kerberized hadoop 2.10.1 cluster
#
# USAGE: docker build -t myalluxio/alluxio-secure-hadoop:hadoop-2.10.1 . 2>&1 | tee  ./build-log.txt
#

FROM centos:centos7
MAINTAINER gregpalmr

USER root

# Password to use for various users, including root user
ENV ROOT_PASSWORD=changeme123
ENV NON_ROOT_PASSWORD=changeme123

# Change root password
RUN echo $ROOT_PASSWORD | passwd root --stdin

# Install required packages 
RUN yum clean all; \
    rpm --rebuilddb; \
    yum install -y curl which tar sudo openssh-server openssh-clients rsync \ 
        net-tools vim rsyslog unzip glibc-devel initscripts mysql-connector-java \
        glibc-headers gcc-c++ make cmake git zlib-devel

# update libselinux. see https://github.com/sequenceiq/hadoop-docker/issues/14
RUN yum update -y libselinux

RUN echo 'alias ll="ls -alF"' >> /root/.bashrc

# Setup passwordless ssh
RUN    ssh-keygen -q -N "" -t dsa -f /etc/ssh/ssh_host_dsa_key \
    && ssh-keygen -q -N "" -t rsa -f /etc/ssh/ssh_host_rsa_key \
    && ssh-keygen -q -N "" -t rsa -f /root/.ssh/id_rsa \
    && cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys

# Copy any local tarballs into the container (Not Required)
RUN mkdir /tmp/local_files
COPY README.md local_files* /tmp/local_files/

# Install Java
ARG THIS_JAVA_HOME=/usr/java/default
RUN if [ ! -f /tmp/local_files/jdk-8u131-linux-x64.rpm ]; then \
       curl -L -b "oraclelicense=a" http://download.oracle.com/otn-pub/java/jdk/8u131-b11/d54c1d3a095b4ff2b6607d096fa80163/jdk-8u131-linux-x64.rpm \
            -o /tmp/local_files/jdk-8u131-linux-x64.rpm; \
    fi \
    && rpm -i /tmp/local_files/jdk-8u131-linux-x64.rpm \
    && rm /tmp/local_files/jdk-8u131-linux-x64.rpm \
    && export JAVA_HOME=$THIS_JAVA_HOME \
    && echo "#### Java Environment ####" >> /etc/profile \
    && echo "export JAVA_HOME=$JAVA_HOME" >> /etc/profile \
    && echo "export PATH=\$PATH:\$JAVA_HOME/bin" >> /etc/profile \
    && rm /usr/bin/java; ln -s $JAVA_HOME/bin/java /usr/bin/java

# Install Java JCE Policy files
RUN if [ ! -f /tmp/local_files/jce_policy-8.zip ]; then \
        curl -L -b "oraclelicense=a" http://download.oracle.com/otn-pub/java/jce/8/jce_policy-8.zip -o /tmp/local_files/jce_policy-8.zip; \
    fi \
    && unzip /tmp/local_files/jce_policy-8.zip \
    && cp /UnlimitedJCEPolicyJDK8/local_policy.jar /UnlimitedJCEPolicyJDK8/US_export_policy.jar $THIS_JAVA_HOME/jre/lib/security \
    && rm -rf /tmp/local_files/jce_policy-8.zip UnlimitedJCEPolicyJDK8

# Install Kerberos client
RUN yum install krb5-libs krb5-workstation krb5-auth-dialog -y \
    && mkdir -p /var/log/kerberos \
    && touch /var/log/kerberos/kadmind.log

# Install Hadoop
#
ARG THIS_HADOOP_PREFIX=/opt/hadoop
RUN export HADOOP_PREFIX=$THIS_HADOOP_PREFIX \
    && export HADOOP_HOME=$HADOOP_PREFIX \
    && export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop \
    && export HADOOP_VERNO=2.10.1 \
    && \
    if [ ! -f /tmp/local_files/hadoop-${HADOOP_VERNO}.tar.gz ]; then \
        curl https://archive.apache.org/dist/hadoop/core/hadoop-${HADOOP_VERNO}/hadoop-${HADOOP_VERNO}.tar.gz -o /tmp/local_files/hadoop-${HADOOP_VERNO}.tar.gz; \ 
    fi \
    && tar -xzf /tmp/local_files/hadoop-${HADOOP_VERNO}.tar.gz -C /opt/ \
    && rm -f /tmp/local_files/hadoop-${HADOOP_VERNO}.tar.gz \
    && ln -s /opt/hadoop-${HADOOP_VERNO} $HADOOP_HOME \
    && chown root:root -R $HADOOP_HOME/ \
    && mkdir -p /etc/hadoop \
    && ln -s $HADOOP_HOME/etc/hadoop /etc/hadoop/conf \
    && echo "#### Hadoop Environment ####" >> /etc/profile \
    && echo "export HADOOP_HOME=$HADOOP_HOME" >> /etc/profile \
    && echo "export PATH=\$PATH:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin" >> /etc/profile \
    && mkdir -p $HADOOP_HOME/data/nodemanager/local-dirs \
    && mkdir -p $HADOOP_HOME/data/nodemanager/log-dirs

ADD config_files/hadoop/* $THIS_HADOOP_PREFIX/etc/hadoop/
RUN mv $THIS_HADOOP_PREFIX/etc/hadoop/keystore.jks $THIS_HADOOP_PREFIX/lib/keystore.jks

#ENV HADOOP_COMMON_HOME $HADOOP_PREFIX
#ENV HADOOP_HDFS_HOME $HADOOP_PREFIX
#ENV HADOOP_MAPRED_HOME $HADOOP_PREFIX
#ENV HADOOP_YARN_HOME $HADOOP_PREFIX
#ENV HADOOP_CONF_DIR $HADOOP_PREFIX/etc/hadoop
#ENV YARN_CONF_DIR $HADOOP_PREFIX/etc/hadoop
#ENV NM_CONTAINER_EXECUTOR_PATH $HADOOP_PREFIX/bin/container-executor
#ENV HADOOP_BIN_HOME $HADOOP_PREFIX/bin
#ENV PATH $PATH:$HADOOP_BIN_HOME

ENV KRB_REALM EXAMPLE.COM
ENV DOMAIN_REALM example.com
ENV KERBEROS_ADMIN admin/admin
ENV KERBEROS_ADMIN_PASSWORD admin
ENV KERBEROS_ROOT_USER_PASSWORD changeme123
ENV KEYTAB_DIR /etc/security/keytabs
ENV FQDN hadoop.com

# Download hadoop source code to build some binaries natively
# for this, protobuf is needed
RUN if [ ! -f /tmp/local_files/protobuf-2.5.0.tar.gz ]; then \
        curl -L https://github.com/google/protobuf/releases/download/v2.5.0/protobuf-2.5.0.tar.gz -o /tmp/local_files/protobuf-2.5.0.tar.gz; \
    fi \
    && tar -xzf /tmp/local_files/protobuf-2.5.0.tar.gz -C /tmp/ \
    && rm -f /tmp/local_files/protobuf-2.5.0.tar.gz

#RUN    cd /tmp/protobuf-2.5.0 \
#    && ./configure \
#    && make \
#    && make install
#ENV HADOOP_PROTOC_PATH /usr/local/bin/protoc

RUN if [ ! -f /tmp/local_files/apache-maven-3.5.0-bin.tar.gz ]; then \
        curl -L https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.5.0/apache-maven-3.5.0-bin.tar.gz \
                -o /tmp/local_files/apache-maven-3.5.0-bin.tar.gz; \
    fi \
    && tar -xzf /tmp/local_files/apache-maven-3.5.0-bin.tar.gz -C /usr/local \
    && rm -f /tmp/local_files/apache-maven-3.5.0-bin.tar.gz \
    && cd /usr/local && ln -s ./apache-maven-3.5.0/ maven

ENV PATH $PATH:/usr/local/maven/bin

RUN export HADOOP_VERNO=2.10.1 \
    && \
    if [ ! -f /tmp/local_files/hadoop-${HADOOP_VERNO}-src.tar.gz ]; then \
        curl -L https://archive.apache.org/dist/hadoop/common/hadoop-${HADOOP_VERNO}/hadoop-${HADOOP_VERNO}-src.tar.gz \
               -o /tmp/local_files/hadoop-${HADOOP_VERNO}-src.tar.gz; \
    fi \
    && tar -xzf /tmp/local_files/hadoop-${HADOOP_VERNO}-src.tar.gz -C /tmp \
    && rm -f /tmp/local_files/hadoop-${HADOOP_VERNO}-src.tar.gz

# Build native hadoop-common libs to remove warnings because of 64 bit OS
#RUN export HADOOP_VERNO=2.10.1 \
#    && \ 
#    && mv $THIS_HADOOP_PREFIX/lib/native $THIS_HADOOP_PREFIX/lib/native.orig \
#    && mkdir -p $THIS_HADOOP_PREFIX/lib/native/ \
#    && cd /tmp/hadoop-${HADOOP_VERNO}-src/hadoop-common-project/hadoop-common \
#    && mvn compile -Pnative \
#    && cp target/native/target/usr/local/lib/libhadoop.a $THIS_HADOOP_PREFIX/lib/native/ \
#    && cp target/native/target/usr/local/lib/libhadoop.so.1.0.0 $THIS_HADOOP_PREFIX/lib/native/

# Build container-executor binary
#RUN export HADOOP_VERNO=2.10.1 \
#    && \ 
#    && cd /tmp/hadoop-${HADOOP_VERNO}-src/hadoop-yarn-project/hadoop-yarn/hadoop-yarn-server/hadoop-yarn-server-nodemanager \
#    && mvn compile -Pnative \
#    && cp target/native/target/usr/local/bin/container-executor $THIS_HADOOP_PREFIX/bin/ \
#    && chmod 6050 $THIS_HADOOP_PREFIX/bin/container-executor \
#    && rm -rf /tmp/hadoop-${HADOOP_VERNO}-src && rm rm -rf ~/.m2

ADD config_files/ssh/ssh_config /root/.ssh/config
RUN    chmod 600 /root/.ssh/config \
    && chown root:root /root/.ssh/config

# Install MySQL client binaries (so hive setup can use mysql command line)
#
#    Note: MySQL jar file is in: /usr/share/java/mysql-connector-java.jar
#    Note: After installing client, use command: mysql --host=mysql --user=root --password=changeme123
#RUN result=`yum list installed | grep ^mysql57` \
#    && \
#    if [ "$result" == "" ]; then \
#        if [ ! -f /tmp/local_files/mysql57-community-release-el7-7.noarch.rpm ]; then \
#            curl http://repo.mysql.com/yum/mysql-5.7-community/el/7/x86_64/mysql57-community-release-el7-7.noarch.rpm \
#                  -o /tmp/local_files/mysql57-community-release-el7-7.noarch.rpm; \
#        fi \
#        && rpm -ivh /tmp/local_files/mysql57-community-release-el7-7.noarch.rpm \
#        && rm /tmp/local_files/mysql57-community-release-el7-7.noarch.rpm \
#        && yum -y install mysql \
#    fi
RUN if [ ! -f /tmp/local_files/mysql57-community-release-el7-7.noarch.rpm ]; then \
            curl http://repo.mysql.com/yum/mysql-5.7-community/el/7/x86_64/mysql57-community-release-el7-7.noarch.rpm \
                  -o /tmp/local_files/mysql57-community-release-el7-7.noarch.rpm; \
     fi \
     && rpm -ivh /tmp/local_files/mysql57-community-release-el7-7.noarch.rpm \
     && rm /tmp/local_files/mysql57-community-release-el7-7.noarch.rpm 

# Install Hive and Hive metastore
#

# Create a Hive user
RUN useradd -d /opt/hive --no-create-home --uid 1002 --gid root hive \
    && echo $NON_ROOT_PASSWORD | passwd hive --stdin

# Download and install the Hive binaries 
ARG THIS_HIVE_HOME=/opt/hive
RUN export HIVE_HOME=$THIS_HIVE_HOME && export HIVE_CONF_DIR=/etc/hive/conf \
    && export HIVE_VERNO="2.3.8" \
    && \
    if [ ! -f /tmp/local_files/apache-hive-${HIVE_VERNO}-bin.tar.gz ]; then \
        curl https://archive.apache.org/dist/hive/hive-${HIVE_VERNO}/apache-hive-${HIVE_VERNO}-bin.tar.gz \
             -o /tmp/local_files/apache-hive-${HIVE_VERNO}-bin.tar.gz; \ 
    fi \
    && tar xvzf /tmp/local_files/apache-hive-${HIVE_VERNO}-bin.tar.gz -C /opt/ \
    && rm -f /tmp/local_files/apache-hive-${HIVE_VERNO}-bin.tar.gz \
    && ln -s /opt/apache-hive-${HIVE_VERNO}-bin $HIVE_HOME \
    && cp /usr/share/java/mysql-connector-java.jar $HIVE_HOME/lib/ \
    && chown -R hive:root $HIVE_HOME/ \
    && chmod -R g+rw $HIVE_HOME/ \
    && mkdir -p /etc/hive \
    && ln -s $HIVE_HOME/conf $HIVE_CONF_DIR \
    && echo "#### Hive Environment ####" >> /etc/profile \
    && echo "export HIVE_HOME=$HIVE_HOME" >> /etc/profile \
    && echo "export HIVE_CONF_DIR=$HIVE_CONF_DIR" >> /etc/profile \
    && echo "export PATH=\$PATH:\$HIVE_HOME/bin" >> /etc/profile

# Install the Hive conf files (hive-env.sh, hive-site.xml, hive-log4j2.propreties)
ADD config_files/hive/* $THIS_HIVE_HOME/conf/

#
# Download and install the Alluxio release
#

# Create an alluxio user (to run the Alluxio daemons)
RUN useradd -d /opt/alluxio --no-create-home --uid 1000 --gid root alluxio \
    && echo $NON_ROOT_PASSWORD | passwd alluxio --stdin

# Create an Alluxio test user
RUN groupadd --gid 1001 user1 \
    && useradd --uid 1001 --gid user1 user1 \
    && echo $NON_ROOT_PASSWORD | passwd user1 --stdin

# Install the alluxio binaries
ARG THIS_ALLUXIO_HOME=/opt/alluxio
RUN export ALLUXIO_HOME=$THIS_ALLUXIO_HOME \
    && \
    if [ ! -f /tmp/local_files/alluxio-enterprise-trial.tar.gz ]; then \
        curl https://downloads.alluxio.io/protected/files/alluxio-enterprise-trial.tar.gz \
             -o /tmp/local_files/alluxio-enterprise-trial.tar.gz; \
    fi \
    && tar xzvf /tmp/local_files/alluxio-enterprise-trial.tar.gz -C /opt \
    && rm -f /tmp/local_files/alluxio-enterprise-trial.tar.gz \
    && ln -s /opt/alluxio-enterprise-* $ALLUXIO_HOME \
    && ln -s $ALLUXIO_HOME/conf /etc/alluxio \
    && echo "#### Alluxio Environment ####" >> /etc/profile \
    && echo "export ALLUXIO_HOME=/opt/alluxio" >> /etc/profile \
    && echo "export PATH=\$PATH:\$ALLUXIO_HOME/bin" >> /etc/profile 

# Install default alluxio config files
ADD config_files/alluxio/alluxio-site.properties $THIS_ALLUXIO_HOME/conf/alluxio-site.properties
ADD config_files/alluxio/alluxio-site.properties.client-only $THIS_ALLUXIO_HOME/conf/alluxio-site.properties.client-only
ADD config_files/hadoop/core-site.xml $THIS_ALLUXIO_HOME/conf/core-site.xml
ADD config_files/hadoop/hdfs-site.xml $THIS_ALLUXIO_HOME/conf/hdfs-site.xml

# Change the owner of the alluxio files
RUN chown -R alluxio:root $THIS_ALLUXIO_HOME

# Workingaround docker.io build error
RUN ls -la $THIS_HADOOP_PREFIX/etc/hadoop/*-env.sh \
    && chmod +x $THIS_HADOOP_PREFIX/etc/hadoop/*-env.sh \
    && ls -la $THIS_HADOOP_PREFIX/etc/hadoop/*-env.sh

# Fix the 254 error code
RUN sed  -i "/^[^#]*UsePAM/ s/.*/#&/"  /etc/ssh/sshd_config \
    && echo "UsePAM no" >> /etc/ssh/sshd_config \
    && echo "Port 2122" >> /etc/ssh/sshd_config

RUN rm -rf /tmp/local_files

# Hdfs ports
EXPOSE 50010 50020 50070 50075 50090 8020 9000
# Mapred ports
EXPOSE 10020 19888
# Yarn ports
EXPOSE 8030 8031 8032 8033 8040 8042 8088
# Other ports
EXPOSE 49707 2122

