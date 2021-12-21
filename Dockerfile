# FILE:  Dockerfile
#
# DESCR: Creates Alluxio Enteprise image with a pseudo distributed kerberized hadoop 2.7.4 cluster
#
# USAGE: docker build -t myalluxio/alluxio-secure-hadoop:hadoop-2.7.4 . 2>&1 | tee  ./build-log.txt
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
    vim rsyslog unzip glibc-devel initscripts mysql-connector-java \
    glibc-headers gcc-c++ make cmake git zlib-devel

# update libselinux. see https://github.com/sequenceiq/hadoop-docker/issues/14
RUN yum update -y libselinux

RUN echo 'alias ll="ls -alF"' >> /root/.bashrc

# Setup passwordless ssh
RUN    ssh-keygen -q -N "" -t dsa -f /etc/ssh/ssh_host_dsa_key \
    && ssh-keygen -q -N "" -t rsa -f /etc/ssh/ssh_host_rsa_key \
    && ssh-keygen -q -N "" -t rsa -f /root/.ssh/id_rsa \
    && cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys

# Install Java
# from https://lv.binarybabel.org/catalog/java/jdk8
RUN curl -L -b "oraclelicense=a" http://download.oracle.com/otn-pub/java/jdk/8u131-b11/d54c1d3a095b4ff2b6607d096fa80163/jdk-8u131-linux-x64.rpm -O
#COPY local_files/jdk-8u131-linux-x64.rpm /

RUN    rpm -i jdk-8u131-linux-x64.rpm \
    && rm jdk-8u131-linux-x64.rpm
ENV JAVA_HOME /usr/java/default
ENV PATH $PATH:$JAVA_HOME/bin
RUN rm /usr/bin/java && ln -s $JAVA_HOME/bin/java /usr/bin/java

RUN curl -L -b "oraclelicense=a" http://download.oracle.com/otn-pub/java/jce/8/jce_policy-8.zip -O \
    && unzip jce_policy-8.zip \
    && cp /UnlimitedJCEPolicyJDK8/local_policy.jar /UnlimitedJCEPolicyJDK8/US_export_policy.jar $JAVA_HOME/jre/lib/security \
    && rm -rf jce_policy-8.zip UnlimitedJCEPolicyJDK8

# Install Kerberos client
RUN    yum install krb5-libs krb5-workstation krb5-auth-dialog -y \
    && mkdir -p /var/log/kerberos \
    && touch /var/log/kerberos/kadmind.log

# Install Hadoop
ENV HADOOP_PREFIX /opt/hadoop
RUN curl https://archive.apache.org/dist/hadoop/core/hadoop-2.7.4/hadoop-2.7.4.tar.gz  | tar -xz -C /opt/
#COPY local_files/hadoop-2.7.4.tar.gz $HADOOP_PREFIX-2.7.4.tar.gz
#RUN tar -xzvf $HADOOP_PREFIX-2.7.4.tar.gz -C /opt/ cd /opt/
RUN    ln -s /opt/hadoop-2.7.4 /opt/hadoop \
    && chown root:root -R /opt/hadoop/ \
    && mkdir -p /etc/hadoop \
    && ln -s /opt/hadoop/etc/hadoop /etc/hadoop/conf \
    && echo "export HADOOP_HOME=/opt/hadoop" >> /etc/profile \
    && echo "export PATH=\$PATH:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin" >> /etc/profile

ENV HADOOP_COMMON_HOME $HADOOP_PREFIX
ENV HADOOP_HDFS_HOME $HADOOP_PREFIX
ENV HADOOP_MAPRED_HOME $HADOOP_PREFIX
ENV HADOOP_YARN_HOME $HADOOP_PREFIX
ENV HADOOP_CONF_DIR $HADOOP_PREFIX/etc/hadoop
ENV YARN_CONF_DIR $HADOOP_PREFIX/etc/hadoop
ENV NM_CONTAINER_EXECUTOR_PATH $HADOOP_PREFIX/bin/container-executor
ENV HADOOP_BIN_HOME $HADOOP_PREFIX/bin
ENV PATH $PATH:$HADOOP_BIN_HOME

ENV KRB_REALM EXAMPLE.COM
ENV DOMAIN_REALM example.com
ENV KERBEROS_ADMIN admin/admin
ENV KERBEROS_ADMIN_PASSWORD admin
ENV KERBEROS_ROOT_USER_PASSWORD changeme123
ENV KEYTAB_DIR /etc/security/keytabs
ENV FQDN hadoop.com

ADD config_files/hadoop/* $HADOOP_PREFIX/etc/hadoop/
RUN    mkdir $HADOOP_PREFIX/nm-local-dirs \
    && mkdir $HADOOP_PREFIX/nm-log-dirs \
    && mv $HADOOP_PREFIX/etc/hadoop/keystore.jks $HADOOP_PREFIX/lib/keystore.jks

# Download hadoop source code to build some binaries natively
# for this, protobuf is needed
RUN curl -L https://github.com/google/protobuf/releases/download/v2.5.0/protobuf-2.5.0.tar.gz | tar -xz -C /tmp/
#COPY local_files/protobuf-2.5.0.tar.gz /tmp/protobuf-2.5.0.tar.gz
#RUN tar -xzf /tmp/protobuf-2.5.0.tar.gz -C /tmp/

RUN    cd /tmp/protobuf-2.5.0 \
    && ./configure \
    && make \
    && make install
ENV HADOOP_PROTOC_PATH /usr/local/bin/protoc

RUN curl -L https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.5.0/apache-maven-3.5.0-bin.tar.gz | tar -xz -C /usr/local
#COPY local_files/apache-maven-3.5.0-bin.tar.gz /tmp/apache-maven-3.5.0-bin.tar.gz
#RUN tar -xzf /tmp/apache-maven-3.5.0-bin.tar.gz -C /usr/local

RUN cd /usr/local && ln -s ./apache-maven-3.5.0/ maven
ENV PATH $PATH:/usr/local/maven/bin

RUN curl -L https://archive.apache.org/dist/hadoop/common/hadoop-2.7.4/hadoop-2.7.4-src.tar.gz  | tar -xz -C /tmp
#COPY local_files/hadoop-2.7.4-src.tar.gz /tmp/hadoop-2.7.4-src.tar.gz
#RUN tar -xzf /tmp/hadoop-2.7.4-src.tar.gz -C /tmp

# Build native hadoop-common libs to remove warnings because of 64 bit OS
RUN    mv $HADOOP_PREFIX/lib/native $HADOOP_PREFIX/lib/native.orig \
    && mkdir -p $HADOOP_PREFIX/lib/native/ \
    && cd /tmp/hadoop-2.7.4-src/hadoop-common-project/hadoop-common \
    && mvn compile -Pnative \
    && cp target/native/target/usr/local/lib/libhadoop.a $HADOOP_PREFIX/lib/native/ \
    && cp target/native/target/usr/local/lib/libhadoop.so.1.0.0 $HADOOP_PREFIX/lib/native/
# build container-executor binary
RUN    cd /tmp/hadoop-2.7.4-src/hadoop-yarn-project/hadoop-yarn/hadoop-yarn-server/hadoop-yarn-server-nodemanager \
    && mvn compile -Pnative \
    && cp target/native/target/usr/local/bin/container-executor $HADOOP_PREFIX/bin/ \
    && chmod 6050 $HADOOP_PREFIX/bin/container-executor \
    && rm -rf /tmp/hadoop-2.7.4-src && rm -rf ~/.m2

ADD config_files/ssh/ssh_config /root/.ssh/config
RUN    chmod 600 /root/.ssh/config \
    && chown root:root /root/.ssh/config

# Install Hive and Hive metastore
#
ENV HIVE_HOME /opt/hive
ENV HIVE_CONF_DIR /etc/hive/conf

# Create a hive user
RUN    groupadd --gid 1020 hadoop \
    && useradd -d /opt/hive --no-create-home --uid 1020 --gid hadoop hive \
    && echo $NON_ROOT_PASSWORD | passwd hive --stdin

# Download and install the Hive binaries
RUN curl https://archive.apache.org/dist/hive/hive-2.1.0/apache-hive-2.1.0-bin.tar.gz | tar xvz -C /opt/ \
    && ln -s /opt/apache-hive-*bin $HIVE_HOME \
    && chown -R hive:hadoop $HIVE_HOME \
    && chmod -R g+rw $HIVE_HOME \
    && mkdir -p /etc/hive \
    && ln -s $HIVE_HOME/conf $HIVE_CONF_DIR \
    && echo "export HIVE_HOME=$HIVE_HOME" >> /etc/profile \
    && echo "export HIVE_CONF_DIR=$HIVE_CONF_DIR" >> /etc/profile \
    && echo "export PATH=\$PATH:\$HIVE_HOME/bin" >> /etc/profile

# Install the Hive conf files
ADD config_files/hive/hive-env.sh $HIVE_CONF_DIR/hive-env.sh
ADD config_files/hive/hive-site.xml $HIVE_CONF_DIR/hive-site.xml

# Install MySQL client binaries (so hive setup can use mysql command line)
# Note: MySQL jar file is in: /usr/share/java/mysql-connector-java.jar
# Note: After installing client, use command: mysql --host=mysql --user=root --password=changeme123
RUN    curl http://repo.mysql.com/yum/mysql-5.7-community/el/7/x86_64/mysql57-community-release-el7-7.noarch.rpm -O \
    && rpm -ivh mysql57-community-release-el7-7.noarch.rpm \
    && rm mysql57-community-release-el7-7.noarch.rpm \
    && yum -y install mysql

#
# Download and install the Alluxio release
#

# Create an alluxio user
RUN useradd -d /opt/alluxio --no-create-home --uid 1000 --gid root alluxio \
    && echo $NON_ROOT_PASSWORD | passwd alluxio --stdin

# Install the alluxio binaries
RUN    curl https://downloads.alluxio.io/protected/files/alluxio-enterprise-trial.tar.gz -O \
    && tar xzvf alluxio-enterprise-trial.tar.gz -C /opt \
    && ln -s /opt/alluxio-enterprise-* /opt/alluxio \
    && rm alluxio-enterprise-trial.tar.gz \
    && echo "export ALLUXIO_HOME=/opt/alluxio" >> /etc/profile \
    && echo "export PATH=\$PATH:\$ALLUXIO_HOME/bin" >> /etc/profile 

# Install default alluxio config files
ADD config_files/alluxio/alluxio-site.properties /opt/alluxio/conf/alluxio-site.properties
ADD config_files/hadoop/core-site.xml /opt/alluxio/conf/core-site.xml
ADD config_files/hadoop/hdfs-site.xml /opt/alluxio/conf/hdfs-site.xml

# Change the owner of the alluxio files
RUN chown -R alluxio:root /opt/alluxio/

# Workingaround docker.io build error
RUN ls -la $HADOOP_PREFIX/etc/hadoop/*-env.sh \
    && chmod +x $HADOOP_PREFIX/etc/hadoop/*-env.sh \
    && ls -la $HADOOP_PREFIX/etc/hadoop/*-env.sh

# Fix the 254 error code
RUN sed  -i "/^[^#]*UsePAM/ s/.*/#&/"  /etc/ssh/sshd_config \
    && echo "UsePAM no" >> /etc/ssh/sshd_config \
    && echo "Port 2122" >> /etc/ssh/sshd_config

# Hdfs ports
EXPOSE 50010 50020 50070 50075 50090 8020 9000
# Mapred ports
EXPOSE 10020 19888
# Yarn ports
EXPOSE 8030 8031 8032 8033 8040 8042 8088
# Other ports
EXPOSE 49707 2122

