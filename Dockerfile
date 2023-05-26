# FILE:  Dockerfile
#
# DESCR: Creates Alluxio Enteprise image with a pseudo distributed kerberized hadoop 2.10.1 cluster
#
# USAGE: docker build -t myalluxio/alluxio-secure-hadoop:hadoop-2.10.1 . 2>&1 | tee  ./build-log.txt
#    OR: docker build --no-cache -t myalluxio/alluxio-secure-hadoop:hadoop-2.10.1 . 2>&1 | tee  ./build-log.txt
#

FROM centos:centos7
MAINTAINER gregpalmr

USER root

# Password to use for various users, including root user
ENV ROOT_PASSWORD=changeme123
ENV NON_ROOT_PASSWORD=changeme123

# Change root password
RUN echo $ROOT_PASSWORD | passwd root --stdin

# Copy any local tarballs into the container (Not Required)
RUN mkdir /tmp/local_files
COPY README.md local_files* /tmp/local_files/

# Install required packages (include openjdk 1.8)
RUN yum clean all; \
    rpm --rebuilddb; \
    yum install -y curl which tar sudo openssh-server openssh-clients rsync \ 
        net-tools vim rsyslog unzip glibc-devel initscripts \
        glibc-headers gcc-c++ make cmake git zlib-devel \
        mysql-connector-java java-1.8.0-openjdk

# update libselinux. see https://github.com/sequenceiq/hadoop-docker/issues/14
RUN yum update -y libselinux

RUN echo 'alias ll="ls -alF"' >> /root/.bashrc

# Setup passwordless ssh
RUN    ssh-keygen -q -N "" -t dsa -f /etc/ssh/ssh_host_dsa_key \
    && ssh-keygen -q -N "" -t rsa -f /etc/ssh/ssh_host_rsa_key \
    && ssh-keygen -q -N "" -t rsa -f /root/.ssh/id_rsa \
    && /bin/cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys

# Create Java Environment
RUN if [ ! -d /usr/lib/jvm/java-1.8.*-openjdk-1.8.*.x86_64 ]; then \
       echo " ERROR - Unable to create Java environment because Java directory not found at '/usr/lib/jvm/java-1.8.*-openjdk-1.8.*.x86_64'. Skipping."; \
    else \
      java_dir=$(ls /usr/lib/jvm/ | grep java-1\.8\.); \
      export JAVA_HOME=/usr/lib/jvm/${java_dir}/jre; \
      echo "#### Java Environment ####" >> /etc/profile.d/java-env.sh; \
      echo "export JAVA_HOME=$JAVA_HOME" >> /etc/profile.d/java-env.sh; \
      echo "export PATH=\$PATH:\$JAVA_HOME/bin" >> /etc/profile.d/java-env.sh; \
    fi 

# Enable Java JCE Policy for OpenJDK
RUN source /etc/profile.d/java-env.sh && \
    if [ ! -d $JAVA_HOME/jre/lib/security ]; then \
       echo " ERROR - OpenJDK is not installed, can't configure JCE Policy. Skipping. "; \
    else \
       sed -i "/crypto.policy=/d" $JAVA_HOME/jre/lib/security/java.security; \
       echo "crypto.policy=unlimited" >> $JAVA_HOME/jre/lib/security/java.security; \
    fi 

# Install Kerberos client
RUN yum install krb5-libs krb5-workstation krb5-auth-dialog -y \
    && mkdir -p /var/log/kerberos \
    && touch /var/log/kerberos/kadmind.log

# Define Kerberos settings
#
ENV KRB_REALM EXAMPLE.COM
ENV DOMAIN_REALM example.com
ENV KERBEROS_ADMIN admin/admin
ENV KERBEROS_ADMIN_PASSWORD admin
ENV KERBEROS_ROOT_USER_PASSWORD changeme123
ENV KEYTAB_DIR /etc/security/keytabs
ENV FQDN hadoop.com

# Install MySQL client binaries (so hive setup can use mysql command line)
#
#    Note: MySQL jar file is in: /usr/share/java/mysql-connector-java.jar
#    Note: After installing client, use command: mysql --host=mysql --user=root --password=changeme123
RUN  if [ ! -f /tmp/local_files/mysql-community-client-5.7.37-1.el7.x86_64.rpm ]; then \
            mysql_download_location="https://downloads.mysql.com/archives/get/p/23/file"; \
            rpm_files="mysql-community-common-5.7.37-1.el7.x86_64.rpm mysql-community-libs-5.7.37-1.el7.x86_64.rpm mysql-community-client-5.7.37-1.el7.x86_64.rpm"; \
            for rpm_file in `echo ${rpm_files}`; do \
              curl -sSL ${mysql_download_location}/${rpm_file} -o /tmp/local_files/${rpm_file}; \
              rpm -Uvh /tmp/local_files/${rpm_file}; \
            done \
     fi \
     && rm -f /tmp/local_files/mysql*.rpm 

# Install Hadoop
#
ARG DOCKER_HADOOP_PREFIX=/opt/hadoop
RUN export HADOOP_PREFIX=$DOCKER_HADOOP_PREFIX \
    && echo " ------------------- Using HADOOP_PREFIX=$HADOOP_PREFIX" \
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
    && chmod go-wx $HADOOP_HOME/bin/container-executor $HADOOP_HOME/bin/test-container-executor \
    && chmod ugo+s $HADOOP_HOME/bin/container-executor $HADOOP_HOME/bin/test-container-executor \
    && mkdir -p /etc/hadoop \
    && ln -s $HADOOP_HOME/etc/hadoop /etc/hadoop/conf \
    && echo "#### Hadoop Environment ####" >> /etc/profile \
    && echo "export HADOOP_HOME=$HADOOP_HOME" >> /etc/profile \
    && echo "export HADOOP_CONF_DIR=$HADOOP_CONF_DIR" >> /etc/profile \
    && echo "export PATH=\$PATH:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin" >> /etc/profile \
    && mkdir -p $HADOOP_HOME/data/nodemanager/local-dirs \
    && mkdir -p $HADOOP_HOME/data/nodemanager/log-dirs

ADD config_files/hadoop/* $DOCKER_HADOOP_PREFIX/etc/hadoop/
RUN mv $DOCKER_HADOOP_PREFIX/etc/hadoop/keystore.jks $DOCKER_HADOOP_PREFIX/lib/keystore.jks

#ENV HADOOP_COMMON_HOME $HADOOP_PREFIX
#ENV HADOOP_HDFS_HOME $HADOOP_PREFIX
#ENV HADOOP_MAPRED_HOME $HADOOP_PREFIX
#ENV HADOOP_YARN_HOME $HADOOP_PREFIX
#ENV HADOOP_CONF_DIR $HADOOP_PREFIX/etc/hadoop
#ENV YARN_CONF_DIR $HADOOP_PREFIX/etc/hadoop
#ENV NM_CONTAINER_EXECUTOR_PATH $HADOOP_PREFIX/bin/container-executor
#ENV HADOOP_BIN_HOME $HADOOP_PREFIX/bin
#ENV PATH $PATH:$HADOOP_BIN_HOME

# To compile Hadoop source, protobuf is needed
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

# Download hadoop source code to build some binaries natively
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
#    && mv $DOCKER_HADOOP_PREFIX/lib/native $DOCKER_HADOOP_PREFIX/lib/native.orig \
#    && mkdir -p $DOCKER_HADOOP_PREFIX/lib/native/ \
#    && cd /tmp/hadoop-${HADOOP_VERNO}-src/hadoop-common-project/hadoop-common \
#    && mvn compile -Pnative \
#    && /bin/cp target/native/target/usr/local/lib/libhadoop.a $DOCKER_HADOOP_PREFIX/lib/native/ \
#    && /bin/cp target/native/target/usr/local/lib/libhadoop.so.1.0.0 $DOCKER_HADOOP_PREFIX/lib/native/

# Build container-executor binary
#RUN export HADOOP_VERNO=2.10.1 \
#    && \ 
#    && cd /tmp/hadoop-${HADOOP_VERNO}-src/hadoop-yarn-project/hadoop-yarn/hadoop-yarn-server/hadoop-yarn-server-nodemanager \
#    && mvn compile -Pnative \
#    && /bin/cp target/native/target/usr/local/bin/container-executor $DOCKER_HADOOP_PREFIX/bin/ \
#    && chmod 6050 $DOCKER_HADOOP_PREFIX/bin/container-executor \
#    && rm -rf /tmp/hadoop-${HADOOP_VERNO}-src && rm rm -rf ~/.m2

# Setup ssh for root user
#
ADD config_files/ssh/ssh_config /root/.ssh/config
RUN    chmod 600 /root/.ssh/config \
    && chown root:root /root/.ssh/config

# Install Hive and Hive metastore
#
ARG DOCKER_HIVE_HOME=/opt/hive
RUN export HIVE_HOME=$DOCKER_HIVE_HOME && export HIVE_CONF_DIR=/etc/hive/conf \
    && useradd -d $HIVE_HOME --no-create-home --uid 1002 --gid root hive \
    && echo $NON_ROOT_PASSWORD | passwd hive --stdin \
    && export HIVE_VERNO="2.3.8" \
    && \
    if [ ! -f /tmp/local_files/apache-hive-${HIVE_VERNO}-bin.tar.gz ]; then \
        curl https://archive.apache.org/dist/hive/hive-${HIVE_VERNO}/apache-hive-${HIVE_VERNO}-bin.tar.gz \
             -o /tmp/local_files/apache-hive-${HIVE_VERNO}-bin.tar.gz; \ 
    fi \
    && tar xvzf /tmp/local_files/apache-hive-${HIVE_VERNO}-bin.tar.gz -C /opt/ \
    && rm -f /tmp/local_files/apache-hive-${HIVE_VERNO}-bin.tar.gz \
    && ln -s /opt/apache-hive-${HIVE_VERNO}-bin $HIVE_HOME \
    && /bin/cp /usr/share/java/mysql-connector-java.jar $HIVE_HOME/lib/ \
    && chown -R hive:root $HIVE_HOME/ \
    && chmod -R g+rw $HIVE_HOME/ \
    && mkdir -p /etc/hive \
    && ln -s $HIVE_HOME/conf $HIVE_CONF_DIR \
    && echo "#### Hive Environment ####" >> /etc/profile \
    && echo "export HIVE_HOME=$HIVE_HOME" >> /etc/profile \
    && echo "export HIVE_CONF_DIR=$HIVE_CONF_DIR" >> /etc/profile \
    && echo "export PATH=\$PATH:\$HIVE_HOME/bin" >> /etc/profile

# Install the Hive conf files (hive-env.sh, hive-site.xml, hive-log4j2.propreties)
ADD config_files/hive/* $DOCKER_HIVE_HOME/conf/

#
# Install Spark (must be installed after hive)
ARG DOCKER_SPARK_HOME=/opt/spark
RUN echo "Installing Spark" \
    && \
    if true ; then \
      export SPARK_HOME=$DOCKER_SPARK_HOME; \
      export SPARK_CONF_DIR=/etc/spark/conf; \
      useradd -d $DOCKER_SPARK_HOME --no-create-home --uid 1003 --gid root spark; \
      echo $NON_ROOT_PASSWORD | passwd spark --stdin; \
      export SPARK_VERNO="2.3.2"; \
      export SPARK_HADOOP_VERNO="2.7"; \
      if [ ! -f /tmp/local_files/spark-${SPARK_VERNO}-bin-hadoop${SPARK_HADOOP_VERNO}.tgz ]; then \
          echo curl https://archive.apache.org/dist/spark/spark-${SPARK_VERNO}/spark-${SPARK_VERNO}-bin-hadoop${SPARK_HADOOP_VERNO}.tgz -o /tmp/local_files/spark-${SPARK_VERNO}-bin-hadoop${SPARK_HADOOP_VERNO}.tgz; \
          curl https://archive.apache.org/dist/spark/spark-${SPARK_VERNO}/spark-${SPARK_VERNO}-bin-hadoop${SPARK_HADOOP_VERNO}.tgz -o /tmp/local_files/spark-${SPARK_VERNO}-bin-hadoop${SPARK_HADOOP_VERNO}.tgz; \
      fi; \
      echo tar xvzf /tmp/local_files/spark-${SPARK_VERNO}-bin-hadoop${SPARK_HADOOP_VERNO}.tgz -C /opt/; \
      tar xvzf /tmp/local_files/spark-${SPARK_VERNO}-bin-hadoop${SPARK_HADOOP_VERNO}.tgz -C /opt/; \
      rm -f /tmp/local_files/spark-${SPARK_VERNO}-bin-hadoop${SPARK_HADOOP_VERNO}.tgz; \
      ln -s /opt/spark-${SPARK_VERNO}-bin-hadoop${SPARK_HADOOP_VERNO} /opt/spark; \
      if [ ! `grep spark /etc/profile` ]; then \
        echo "### Spark Environment ###" >> /etc/profile; \
        echo "export SPARK_HOME=$DOCKER_SPARK_HOME" >> /etc/profile; \
        echo "export SPARK_CONF_DIR=$SPARK_CONF_DIR" >> /etc/profile; \
        echo "export PATH=\$PATH:\$SPARK_HOME/bin:\$SPARK_HOME/sbin" >> /etc/profile; \
      fi; \
      source /etc/profile; \
      mkdir -p /etc/spark; \
      ln -s $DOCKER_SPARK_HOME/conf /etc/spark/conf; \
      /bin/cp $DOCKER_HIVE_HOME/conf/hive-site.xml $SPARK_CONF_DIR/; \
  fi

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
#    && mv $DOCKER_HADOOP_PREFIX/lib/native $DOCKER_HADOOP_PREFIX/lib/native.orig \
#    && mkdir -p $DOCKER_HADOOP_PREFIX/lib/native/ \
#    && cd /tmp/hadoop-${HADOOP_VERNO}-src/hadoop-common-project/hadoop-common \
#    && mvn compile -Pnative \
#    && /bin/cp target/native/target/usr/local/lib/libhadoop.a $DOCKER_HADOOP_PREFIX/lib/native/ \
#    && /bin/cp target/native/target/usr/local/lib/libhadoop.so.1.0.0 $DOCKER_HADOOP_PREFIX/lib/native/

# Build container-executor binary
#RUN export HADOOP_VERNO=2.10.1 \
#    && \ 
#    && cd /tmp/hadoop-${HADOOP_VERNO}-src/hadoop-yarn-project/hadoop-yarn/hadoop-yarn-server/hadoop-yarn-server-nodemanager \
#    && mvn compile -Pnative \
#    && /bin/cp target/native/target/usr/local/bin/container-executor $DOCKER_HADOOP_PREFIX/bin/ \
#    && chmod 6050 $DOCKER_HADOOP_PREFIX/bin/container-executor \
#    && rm -rf /tmp/hadoop-${HADOOP_VERNO}-src && rm rm -rf ~/.m2

ADD config_files/ssh/ssh_config /root/.ssh/config
RUN    chmod 600 /root/.ssh/config \
    && chown root:root /root/.ssh/config


#
# Install Alluxio 
#

# Create an alluxio user (to run the Alluxio daemons)
RUN useradd -d /opt/alluxio --no-create-home --uid 1000 --gid root alluxio \
    && echo $NON_ROOT_PASSWORD | passwd alluxio --stdin

# Create an Alluxio test user
RUN groupadd --gid 1001 user1 \
    && useradd --uid 1001 --gid user1 user1 \
    && echo $NON_ROOT_PASSWORD | passwd user1 --stdin

# Install the alluxio binaries
ARG DOCKER_ALLUXIO_HOME=/opt/alluxio
RUN export ALLUXIO_HOME=$DOCKER_ALLUXIO_HOME \
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
ADD config_files/alluxio/alluxio-site.properties $DOCKER_ALLUXIO_HOME/conf/alluxio-site.properties
ADD config_files/alluxio/alluxio-site.properties.client-only $DOCKER_ALLUXIO_HOME/conf/alluxio-site.properties.client-only
ADD config_files/hadoop/core-site.xml $DOCKER_ALLUXIO_HOME/conf/core-site.xml
ADD config_files/hadoop/hdfs-site.xml $DOCKER_ALLUXIO_HOME/conf/hdfs-site.xml

# Change the owner of the alluxio files
RUN chown -R alluxio:root $DOCKER_ALLUXIO_HOME

#
# Install Spark
ARG DOCKER_SPARK_HOME=/opt/spark
RUN echo "Installing Spark" \
    && \
    if true ; then \
      export SPARK_HOME=$DOCKER_SPARK_HOME; \
      export SPARK_CONF_DIR=/etc/spark/conf; \
      useradd -d $SPARK_HOME --no-create-home --uid 1003 --gid root spark; \
      echo $NON_ROOT_PASSWORD | passwd spark --stdin; \
      export SPARK_VERNO="2.3.2"; \
      export SPARK_HADOOP_VERNO="2.7"; \
      if [ ! -f /tmp/local_files/spark-${SPARK_VERNO}-bin-hadoop${SPARK_HADOOP_VERNO}.tgz ]; then \
          echo curl https://archive.apache.org/dist/spark/spark-${SPARK_VERNO}/spark-${SPARK_VERNO}-bin-hadoop${SPARK_HADOOP_VERNO}.tgz -o /tmp/local_files/spark-${SPARK_VERNO}-bin-hadoop${SPARK_HADOOP_VERNO}.tgz; \
          curl https://archive.apache.org/dist/spark/spark-${SPARK_VERNO}/spark-${SPARK_VERNO}-bin-hadoop${SPARK_HADOOP_VERNO}.tgz -o /tmp/local_files/spark-${SPARK_VERNO}-bin-hadoop${SPARK_HADOOP_VERNO}.tgz; \
      fi; \
      echo tar xvzf /tmp/local_files/spark-${SPARK_VERNO}-bin-hadoop${SPARK_HADOOP_VERNO}.tgz -C /opt/; \
      tar xvzf /tmp/local_files/spark-${SPARK_VERNO}-bin-hadoop${SPARK_HADOOP_VERNO}.tgz -C /opt/; \
      rm -f /tmp/local_files/spark-${SPARK_VERNO}-bin-hadoop${SPARK_HADOOP_VERNO}.tgz; \
      ln -s /opt/spark-${SPARK_VERNO}-bin-hadoop${SPARK_HADOOP_VERNO} /opt/spark; \
      if [ ! `grep spark /etc/profile` ]; then \
        echo "### Spark Environment ###" >> /etc/profile; \
        echo "export SPARK_HOME=$SPARK_HOME" >> /etc/profile; \
        echo "export SPARK_CONF_DIR=$SPARK_CONF_DIR" >> /etc/profile; \
        echo "export PATH=\$PATH:\$SPARK_HOME/bin:\$SPARK_HOME/sbin" >> /etc/profile; \
      fi; \
      source /etc/profile; \
      mkdir -p /etc/spark; \
      ln -s $SPARK_HOME/conf /etc/spark/conf; \
      /bin/cp $DOCKER_HIVE_HOME/conf/hive-site.xml $SPARK_CONF_DIR/; \
      CLIENT_JAR=$(ls $ALLUXIO_HOME/client/alluxio-enterprise-*-client.jar); \
      CLIENT_JAR=$(basename $CLIENT_JAR); \
      echo "spark.master                  spark://hadoop-namenode:7077" > $SPARK_CONF_DIR/spark-defaults.conf; \ 
      echo "spark.driver.memory           512m"                       >> $SPARK_CONF_DIR/spark-defaults.conf; \
      echo "spark.driver.extraClassPath   /opt/alluxio/client/$CLIENT_JAR" >> $SPARK_CONF_DIR/spark-defaults.conf; \
      echo "spark.executor.extraClassPath /opt/alluxio/client/$CLIENT_JAR" >> $SPARK_CONF_DIR/spark-defaults.conf; \
      echo "spark.yarn.access.hadoopFileSystems=alluxio://alluxio-master:19998" >> $SPARK_CONF_DIR/spark-defaults.conf; \ 
      hadoop_classpath=$(hadoop classpath); \
      echo "HADOOP_CONF_DIR=$HADOOP_CONF_DIR"        > /etc/spark/conf/spark-env.sh; \
      echo "YARN_CONF_DIR=$HADOOP_CONF_DIR"         >> /etc/spark/conf/spark-env.sh; \
      echo "JAVA_HOME=$JAVA_HOME"                   >> /etc/spark/conf/spark-env.sh; \
      echo "SPARK_CONF_DIR=$SPARK_CONF_DIR"         >> /etc/spark/conf/spark-env.sh; \
      echo "SPARK_DIST_CLASSPATH=$hadoop_classpath" >> /etc/spark/conf/spark-env.sh; \
      chown -R spark:root /opt/spark-${SPARK_VERNO}-bin-hadoop${SPARK_HADOOP_VERNO}; \
      chown -R spark:root /etc/spark; \
    fi

# Workingaround docker.io build error
RUN ls -la $DOCKER_HADOOP_PREFIX/etc/hadoop/*-env.sh \
    && chmod +x $DOCKER_HADOOP_PREFIX/etc/hadoop/*-env.sh \
    && ls -la $DOCKER_HADOOP_PREFIX/etc/hadoop/*-env.sh

# Fix the 254 error code
RUN sed  -i "/^[^#]*UsePAM/ s/.*/#&/"  /etc/ssh/sshd_config \
    && echo "UsePAM no" >> /etc/ssh/sshd_config \
    && echo "Port 2122" >> /etc/ssh/sshd_config

# Clean up /tmp/local_files directory
RUN rm -rf /tmp/local_files

# Hdfs ports
EXPOSE 50010 50020 50070 50075 50090 8020 9000
# Mapred ports
EXPOSE 10020 19888
# Yarn ports
EXPOSE 8030 8031 8032 8033 8040 8042 8088
# Alluxio Ports
EXPOSE 19999 19998 30000
# Other ports
EXPOSE 49707 2122

