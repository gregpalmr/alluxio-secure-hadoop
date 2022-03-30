# alluxio-secure-hadoop
Test Alluxio Enterprise with Apache Hadoop 2.10.1 in secure mode

This repo contains docker compose artifacts that build and launch a small Alluxio cluster that runs against a secure Hadoop environment with Kerberos enabled and SSL connections enforced.


## Usage:

### Step 1. Install docker and docker-compose

#### MAC:

See: https://docs.docker.com/desktop/mac/install/

Note: The default docker resources will not be adequate. You must increase them to:

     - CPUs:   8
     - Memory: 8 GB
     - Swap:   2 GB
     - Disk Image Size: 150 GB

#### LINUX:

Install the docker package

     sudo yum -y install docker

Increase the ulimit in /etc/sysconfig/docker

     sudo echo "nofile=1024000:1024000" >> /etc/sysconfig/docker
     sudo service docker start

Add your user to the docker group

     sudo usermod -a -G docker ec2-user

     or

     sudo usermod -a -G docker centos

Logout and back in to get new group membershiop

     exit

     ssh ...

Install the docker-compose package

     Red Hat EL 7.x

          DOCKER_COMPOSE_VERSION="1.23.2"

     Red Hat EL 8.x

          DOCKER_COMPOSE_VERSION="1.27.0"

     sudo  curl -L https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose

     sudo chmod +x /usr/local/bin/docker-compose

### Step 2. Clone this repo:

     git clone https://github.com/gregpalmr/alluxio-secure-hadoop

     cd alluxio-secure-hadoop

### Step 3. Copy your Alluxio Enterprise license file

If you don't already have an Alluxio Enterprise license file, contact your Alluxio salesperson at sales@alluxio.com.  Copy your license file to the alluxio staging directory:

     cp ~/Downloads/alluxio-enterprise-license.json config_files/alluxio/

### Step 4. (Optional) Install your own Alluxio release

If you want to test your own Alluxio release, instead of using the release bundled with the docker image, follow these steps:

a. Copy your Alluxio tarball file (.tar.gz) to a directory accessible by the docker-compose utility.

b. Modify the docker-compose.yml file, to "mount" that file as a volume. The target mount point must be in "/tmp/alluxio-install/". For example:

     volumes:
       - ~/Downloads/alluxio-enterprise-2.7.0-SNAPSHOT-bin.tar.gz:/tmp/alluxio-install/alluxio-enterprise-2.7.0-SNAPSHOT-bin.tar.gz 

c. Add an environment variable identifying the tarball file name. For example:

     environment:
       ALLUXIO_TARBALL: alluxio-enterprise-2.7.0-SNAPSHOT-bin.tar.gz 

### Step 5. Build the docker image

The Dockerfile script is setup to copy tarballs and zip files from the local_files directory, if they exist. If they do not exist, the Dockerfile will use the curl command to download the tarballs and zip files from various locations, which takes some time. If you would like to save time while building the Docker image, you can pre-load the various tarballs with these commands:

     mkdir -p local_files && cd local_files

     curl -v -j -k -L -H "Cookie: oraclelicense=accept-securebackup-cookie" http://download.oracle.com/otn-pub/java/jdk/8u131-b11/d54c1d3a095b4ff2b6607d096fa80163/jdk-8u131-linux-x64.rpm -O
     curl -v -j -k -L -H "Cookie: oraclelicense=accept-securebackup-cookie" http://download.oracle.com/otn-pub/java/jce/8/jce_policy-8.zip -O
     curl -L https://archive.apache.org/dist/hadoop/core/hadoop-2.10.1/hadoop-2.10.1.tar.gz -O
     curl -L https://archive.apache.org/dist/hadoop/core/hadoop-2.10.1/hadoop-2.10.1-src.tar.gz -O
     curl -L https://github.com/google/protobuf/releases/download/v2.5.0/protobuf-2.5.0.tar.gz -O
     curl -L https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.5.0/apache-maven-3.5.0-bin.tar.gz -O
     curl -L http://repo.mysql.com/yum/mysql-5.7-community/el/7/x86_64/mysql57-community-release-el7-7.noarch.rpm -O
     curl -L https://archive.apache.org/dist/hive/hive-2.3.8/apache-hive-2.3.8-bin.tar.gz -O
     curl -L https://downloads.alluxio.io/protected/files/alluxio-enterprise-trial.tar.gz -O

     cd ..

Then, build the docker image used for the Hadoop instances and the Alluxio instance.

     docker build -t myalluxio/alluxio-secure-hadoop:hadoop-2.10.1 . 2>&1 | tee  ./build-log.txt

Or, if you want to build from scratch, without previously built image layers.

     docker build --no-cache -t myalluxio/alluxio-secure-hadoop:hadoop-2.10.1 . 2>&1 | tee  ./build-log.txt

Note: if you run out of Docker volume space, run this command:

     docker volume prune

### Step 6. Start the kdc, hadoop and alluxio containers

a. Remove any existing volumes for these containers

     docker volume rm alluxio-secure-hadoop_hdfs_storage

     docker volume rm alluxio-secure-hadoop_kdc_storage

     docker volume rm alluxio-secure-hadoop_keytabs

     docker volume rm alluxio-secure-hadoop_mysql_data

b. Use the docker-compose command to start the kdc, mysql, hadoop and alluxio containers.

     docker-compose up -d

c. You can see the log output of the Alluxio containers using this command:

     docker logs -f alluxio-master
     docker logs -f alluxio-worker1

d. You can see the log output of the Hadoop containers using this command:

     docker logs -f hadoop-namenode
     docker logs -f hadoop-datanode

e. You can see the log output of the Kerberos kdc container using this command:

     docker logs -f kdc

f. When finished working with the containers, you can stop them with the commands:

     docker-compose down

g. If you are done testing and do not intend to spin up the docker images again, remove the disk volumes with the commands:

     docker volume rm alluxio-secure-hadoop_hdfs_storage

     docker volume rm alluxio-secure-hadoop_kdc_storage

     docker volume rm alluxio-secure-hadoop_keytabs

     docker volume rm alluxio-secure-hadoop_mysql_data

### Step 7. Test Alluxio access to the secure Hadoop environment 

a. Open a command shell into the Alluxio container and execute the /etc/profile script.

     docker exec -it alluxio-master bash

     source /etc/profile

b. Become the test Alluxio user:

     su - user1

c. Destroy any previous Kerberos ticket.

     kdestroy

d. Attempt to read the Alluxio virtual filesystem.

     alluxio fs ls /user/

     < you will see a "authentication failed" error >

e. Acquire a Kerberos ticket.

     kinit

     < enter the user's kerberos password: it defaults to "changeme123" >

f. Show the valid Kerberos ticket:

     klist

g. Attempt to read the Alluxio virtual filesystem again.

     alluxio fs ls /user/

     < you will see the contents of the /user HDFS directory >

h. The above commands show how Alluxio implements client to Alluxio (or northbound) Kerberos authentication, using the Alluxio properties configured in the /opt/alluxio/conf/alluxio-site.properties file, like this:

     # Setup client-side (northbound) Kerberos authentication
     alluxio.security.authentication.type=KERBEROS
     alluxio.security.authorization.permission.enabled=true
     alluxio.security.kerberos.server.principal=alluxio/alluxio-master.docker.com@EXAMPLE.COM
     alluxio.security.kerberos.server.keytab.file=/etc/security/keytabs/alluxio.alluxio-master.docker.com.keytab
     alluxio.security.kerberos.auth.to.local=RULE:[1:$1@$0](alluxio.*@.*EXAMPLE.COM)s/.*/alluxio/ RULE:[1:$1@$0](A.*@EXAMPLE.COM)s/A([0-9]*)@.*/a$1/ DEFAULT

The above commands also show how Alluxio accesses the Kerberos and TLS enabled Hadoop environment, that has the following HDFS properties configured in the /etc/hadoop/conf/hdfs-site.xml file:

     dfs.encrypt.data.transfer           = true
     dfs.encrypt.data.transfer.algorithm = 3des
     dfs.http.policy set                 = HTTPS_ONLY
     hadoop.security.authorization       = true
     hadoop.security.authentication      = kerberos

And has the following Alluxio properties setup in the /opt/alluxio/conf/alluxio-site.properties file"

     # Root UFS properties
     alluxio.master.mount.table.root.ufs=hdfs://hadoop-namenode.docker.com:9000/
     alluxio.master.mount.table.root.option.alluxio.underfs.hdfs.configuration=/opt/hadoop/etc/hadoop/core-site.xml:/opt/hadoop/etc/hadoop/hdfs-site.xml:/opt/hadoop/etc/ssl-client.xml
     alluxio.master.mount.table.root.option.alluxio.underfs.version=2.7
     alluxio.master.mount.table.root.option.alluxio.underfs.hdfs.remote=true
     
     # Root UFS Kerberos properties
     alluxio.master.mount.table.root.option.alluxio.security.underfs.hdfs.kerberos.client.principal=alluxio@EXAMPLE.COM
     alluxio.master.mount.table.root.option.alluxio.security.underfs.hdfs.kerberos.client.keytab.file=/etc/security/keytabs/alluxio.headless.keytab
     alluxio.master.mount.table.root.option.alluxio.security.underfs.hdfs.impersonation.enabled=true

i. Copy a file to the user's home directory:

     alluxio fs copyFromLocal /etc/system-release /user/user1/

j. List the files in the user's home directory:

     alluxio fs ls /user/user1/

     hdfs dfs -ls /user/user1/

### Step 8. Test Hive access to the Alluxio virtual filesystem

a. Setup a test data file in Alluxio and HDFS

As a test user, create a small test data file

     docker exec -it alluxio-master bash

     su - user1

     kinit
     < enter the user's kerberos password: it defaults to "changeme123" >

     echo "1,Jane Doe,jdoe@email.com,555-1234"               > alluxio_table.csv
     echo "2,Frank Sinclair,fsinclair@email.com,555-4321"   >> alluxio_table.csv
     echo "3,Iris Culpepper,icullpepper@email.com,555-3354" >> alluxio_table.csv

Create a directory in HDFS and upload the data file

     alluxio fs ls -f /user/user1/  # needed to avoid permissions error

     alluxio fs mkdir /user/user1/alluxio_table/

     alluxio fs copyFromLocal alluxio_table.csv /user/user1/alluxio_table/

     alluxio fs cat /user/user1/alluxio_table/alluxio_table.csv

b. Test Hive with the Alluxio virtual filesystem

Confirm that the user1 user has a valid kerberos ticket

     klist

Start a hive session using beeline

     beeline -u "jdbc:hive2://hadoop-namenode.docker.com:10000/default;principal=hive/_HOST@EXAMPLE.COM"

Create a table in Hive that points to the HDFS location

     CREATE DATABASE alluxio_test_db;

     USE alluxio_test_db;

     CREATE EXTERNAL TABLE alluxio_table1 (
          customer_id BIGINT,
          name STRING,
          email STRING,
          phone STRING ) 
     ROW FORMAT DELIMITED
     FIELDS TERMINATED BY ','
     LOCATION 'hdfs://hadoop-namenode.docker.com:9000/user/user1/alluxio_table';

     SELECT * FROM alluxio_table1;

Create a table in Hive that points to the Alluxio virtual filesystem 

     USE alluxio_test_db;

     CREATE EXTERNAL TABLE alluxio_table2 (
          customer_id BIGINT,
          name STRING,
          email STRING,
          phone STRING ) 
     ROW FORMAT DELIMITED
     FIELDS TERMINATED BY ','
     LOCATION 'alluxio://alluxio-master.docker.com:19998/user/user1/alluxio_table';

     SELECT * FROM alluxio_table2;

     SELECT * FROM alluxio_table2 WHERE NAME LIKE '%Frank%';

If you have any issues, you can inspect the Hiveserver2 log file using the commands:

     docker exec -it hadoop-namenode bash

     vi /tmp/hive/hive.log

     vi /opt/hive/hiveserver2-nohup.out

     vi /opt/hive/metastore-nohup.out

The Hiveserver2 and Hive metastore config files are in:

     /etc/hive/conf

The Hiveserver2 Alluxio config files are in:

     /etc/alluxio (soft link to /opt/alluxio/conf)

The Alluxio client jar file is in:

     /opt/alluxio/client

---

KNOWN ISSUES:

- Currently, the hdfs_storage volume is not persisting correctly, so you must remove all volumes before running "docker-compose up -d". See Step 6.a.

- In Step 8.a, a "permission denied" error will result if you don't first run this command (there is an open JIRA on it):

     alluxio fs ls -f /user/user1/  


---

Please direct questions and comments to greg.palmer@alluxio.com
