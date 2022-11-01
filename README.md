# alluxio-secure-hadoop
Test Alluxio Enterprise with Apache Hadoop 2.10.1 in secure mode

This repo contains docker compose artifacts that build and launch a small Alluxio cluster that runs against a secure Hadoop environment with Kerberos enabled and SSL connections enforced. It also deploys an example of using secure client access methods including:
- Alluxio command line interface (CLI)
- Hiveserver2 (via beeline)
- MapReduce2/YARN
- Spark 

Since Alluxio supports a Prometheus sink for metrics, it also deploys:

- Prometheus server 
- Grafana server 

### Table of Contents  
[Setup](#setup)  
[Start the containers](#start_containers)  
[Test secure access to Alluxio](#use_alluxio)  
[Use Hive with Alluxio](#use_hive)  
[Use MapReduce2/YARN with Alluxio](#use_yarn)  
[Use Spark with Alluxio](#use_spark)  
[Use Prometheus to monitor Alluxio](#use_prometheus)  
[Use Grafana to monitor Alluxio](#use_grafana)  

<a name="setup"/></a>
### &#x1F536; Setup

#### Step 1. Install docker and docker-compose

#### MAC:

See: https://docs.docker.com/desktop/mac/install/

Note: The default docker resources will not be adequate. You must increase them to:

     - CPUs:   8
     - Memory: 8 GB
     - Swap:   2 GB
     - Disk Image Size: 150 GB

#### LINUX:

Disable SELinux, update /etc/selinux/config file and run following command

     sudo setenforce 0

Add new group "docker"

     sudo groupadd docker

Add your user to the docker group

     sudo usermod -a -G docker ec2-user

     or

     sudo usermod -a -G docker centos

Install needed tools

     sudo yum -y install docker git 

Increase the ulimit in /etc/sysconfig/docker

     echo "nofile=1024000:1024000" | sudo tee -a /etc/sysconfig/docker
     sudo service docker start

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

#### Step 2. Clone this repo:

     git clone https://github.com/gregpalmr/alluxio-secure-hadoop

     cd alluxio-secure-hadoop

#### Step 3. Copy your Alluxio Enterprise license file

If you don't already have an Alluxio Enterprise license file, contact your Alluxio salesperson at sales@alluxio.com.  Copy your license file to the alluxio staging directory:

     cp ~/Downloads/alluxio-enterprise-license.json config_files/alluxio/

#### Step 4. (Optional) Install your own Alluxio release

If you want to test your own Alluxio release, instead of using the release bundled with the docker image, follow these steps:

a. Copy your Alluxio tarball file (.tar.gz) to a directory accessible by the docker-compose utility.

b. Modify the docker-compose.yml file, and add a new entry to the "volumes:" section for the alluxio-master and alluxio-worker services. The purpose is to "mount" your tarball file as a volume and the target mount point must be in "/tmp/alluxio-install/". For example:

     volumes:
       - ~/Downloads/alluxio-enterprise-2.7.0-SNAPSHOT-bin.tar.gz:/tmp/alluxio-install/alluxio-enterprise-2.7.0-SNAPSHOT-bin.tar.gz 

c. Add an environment variable identifying the tarball file name. For example:

     environment:
       ALLUXIO_TARBALL: alluxio-enterprise-2.7.0-SNAPSHOT-bin.tar.gz 

#### Step 5. Build the docker image

The Dockerfile script is setup to copy tarballs and zip files from the local_files directory, if they exist. If they do not exist, the Dockerfile will use the curl command to download the tarballs and zip files from various locations, which takes some time. If you would like to save time while building the Docker image, you can pre-load the various tarballs with these commands:

     mkdir -p local_files && cd local_files

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

Build the docker image used for Presto.

     docker build -f dockerfiles/presto/Dockerfile -t myalluxio/presto:0.276 . 2>&1 | tee ./build-log.txt

Or, if you want to build from scratch, without previously built image layers.

     docker build --no-cache -f dockerfiles/presto/Dockerfile -t myalluxio/presto:0.276 . 2>&1 | tee ./build-log.txt


Note: if you run out of Docker volume space, run this command:

     docker volume prune

<a name="start_containers"/></a>
### &#x1F536; Start the KDC, Hadoop and Alluxio containers

#### Step 1. Remove volumes

Remove any existing volumes for these containers

     docker volume rm alluxio-secure-hadoop_hdfs_storage

     docker volume rm alluxio-secure-hadoop_kdc_storage

     docker volume rm alluxio-secure-hadoop_keystore

     docker volume rm alluxio-secure-hadoop_keytabs

     docker volume rm alluxio-secure-hadoop_mysql_data

#### Step 2. Start the containers

Use the docker-compose command to start the kdc, mysql, hadoop and alluxio containers.

     docker-compose up -d

#### Step 3. View log file output

You can see the log output of the Alluxio containers using this command:

     docker logs -f alluxio-master
     docker logs -f alluxio-worker1

You can see the log output of the Hadoop containers using this command:

     docker logs -f hadoop-namenode
     docker logs -f hadoop-datanode1

You can see the log output of the Kerberos kdc container using this command:

     docker logs -f kdc

#### Step 4. Stop the containers

When finished working with the containers, you can stop them with the commands:

     docker-compose down

If you are done testing and do not intend to spin up the docker images again, remove the disk volumes with the commands:

     docker volume rm alluxio-secure-hadoop_hdfs_storage

     docker volume rm alluxio-secure-hadoop_kdc_storage

     docker volume rm alluxio-secure-hadoop_keystore

     docker volume rm alluxio-secure-hadoop_keytabs

     docker volume rm alluxio-secure-hadoop_mysql_data

     docker volume rm alluxio-secure-prometheus_data

<a name="use_alluxio"/></a>
### &#x1F536; Use Alluxio with the secure Hadoop environment 

#### Step 1. Open a command shell

Open a command shell into the Alluxio container and execute the /etc/profile script.

     docker exec -it alluxio-master bash

     source /etc/profile

#### Step 2. Become the test Alluxio user:

     su - user1

#### Step 3. Destroy any previous Kerberos ticket.

     kdestroy

#### Step 4. Attempt to read the Alluxio virtual filesystem.

     alluxio fs ls /user/

     < you will see a "authentication failed" error >

#### Step 5. Acquire a Kerberos ticket.

     kinit

     < enter the user's kerberos password: it defaults to "changeme123" >

Show the valid Kerberos ticket:

     klist

#### Step 6. Attempt to read the Alluxio virtual filesystem again.

     alluxio fs ls /user/

     < you will see the contents of the /user HDFS directory >

The above commands show how Alluxio implements client to Alluxio (or northbound) Kerberos authentication, using the Alluxio properties configured in the /opt/alluxio/conf/alluxio-site.properties file, like this:

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

And has the following Alluxio properties setup in the /opt/alluxio/conf/alluxio-site.properties file:

     # Root UFS properties
     alluxio.master.mount.table.root.ufs=hdfs://hadoop-namenode.docker.com:9000/
     alluxio.master.mount.table.root.option.alluxio.underfs.hdfs.configuration=/opt/hadoop/etc/hadoop/core-site.xml:/opt/hadoop/etc/hadoop/hdfs-site.xml:/opt/hadoop/etc/ssl-client.xml
     alluxio.master.mount.table.root.option.alluxio.underfs.version=2.7
     alluxio.master.mount.table.root.option.alluxio.underfs.hdfs.remote=true
     
     # Root UFS Kerberos properties
     alluxio.master.mount.table.root.option.alluxio.security.underfs.hdfs.kerberos.client.principal=alluxio@EXAMPLE.COM
     alluxio.master.mount.table.root.option.alluxio.security.underfs.hdfs.kerberos.client.keytab.file=/etc/security/keytabs/alluxio.headless.keytab
     alluxio.master.mount.table.root.option.alluxio.security.underfs.hdfs.impersonation.enabled=true

#### Step 7. Copy a file to the user's home directory:

     alluxio fs copyFromLocal /etc/system-release /user/user1/

#### Step 8. List the files in the user's home directory:

     alluxio fs ls /user/user1/

     hdfs dfs -ls /user/user1/


<a name="use_hive"/></a>
### &#x1F536; Use Hive with the Alluxio virtual filesystem

#### Step 1. Setup a test data file in Alluxio and HDFS

As a test user, create a small test data file

     docker exec -it alluxio-master bash

     su - user1

     echo changeme123 | kinit

     echo "1,Jane Doe,jdoe@email.com,555-1234"               > alluxio_table.csv
     echo "2,Frank Sinclair,fsinclair@email.com,555-4321"   >> alluxio_table.csv
     echo "3,Iris Culpepper,icullpepper@email.com,555-3354" >> alluxio_table.csv

Create a directory in HDFS and upload the data file

     alluxio fs mkdir /user/user1/alluxio_table/

     alluxio fs copyFromLocal alluxio_table.csv /user/user1/alluxio_table/

     alluxio fs cat /user/user1/alluxio_table/alluxio_table.csv

#### Step 2. Test Hive with the Alluxio virtual filesystem

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

<a name="use_yarn"/></a>
### &#x1F536; Use MapReduce2/YARN with the Alluxio virtual filesystem

#### Step 1. Run an example wordcount MapReduce job

a. Start a shell session as the test user user1.

     docker exec -it alluxio-master bash

     su - user1

b. Acquire a Kerberos ticket, if needed

   echo changeme123 | kinit

c. Launch a MapReduce2 on YARN job

Launch the example wordcount mapreduce job against the CSV file created in the Hive step above.

     yarn jar \
          $HADOOP_HOME/share/hadoop/mapreduce/hadoop-mapreduce-examples-*.jar \
          wordcount \
          alluxio://alluxio-master:19998/user/user1/alluxio_table/alluxio_table.csv \
          alluxio://alluxio-master:19998/user/user1/wordcount_results

View the results of the word count job:

     alluxio fs cat /user/user1/wordcount_results/part000

<a name="use_spark"/></a>
### &#x1F536; Use Spark with the Alluxio virtual filesystem

#### Step 1. Run a Spark SQL command against a Hive table

a. Start a shell session as the test user user1.

     docker exec -it hadoop-namenode bash

     su - user1

b. Acquire a Kerberos ticket, if needed

   echo changeme123 | kinit

c. Start a spark-shell session

Start the spark shell and configure the hive metastore URI.

     spark-shell \
          --conf spark.hadoop.hive.metastore.uris=thrift://hadoop-namenode:9083

d. Run Spark SQL commands to see the Hive databases and tables

     scala> spark.sharedState.externalCatalog.listDatabases
            spark.sharedState.externalCatalog.listTables("alluxio_test_db")

e. Run a Spark SQL command that queries the Hive table

    scala>  val sqlContext = new org.apache.spark.sql.hive.HiveContext(sc)
            val result = sqlContext.sql("FROM alluxio_test_db.alluxio_table2 SELECT *")
            result.show()

#### Step 2. Run a Spark job that reads from Alluxio directly

In the previous step, Spark SQL was used to access the Hive metastore and hive data stored in HDFS via Alluxio. In this step, use Spark/Scala commands to read from the Alluxio/HDFS files without Hive.

a. If needed, run substeps a, b and c from Step 1 above.

b. Run a Spark/Scala command to access the CSV file in HDFS via the Alluxio filesystem

Continuing as the test user from Step 1, run a spark job with the commands:

     spark-shell 

     scala> val df = spark.read.csv("alluxio:///user/user1/alluxio_table/alluxio_table.csv")
            df.printSchema()

c. Run a Spark/Scala command to access the CSV file from Alluxio via the Alluxio S3 API.

Continuing as the test user from Step 1, run a spark job with the commands:

     spark-shell 

     scala> import org.apache.spark.sql.SparkSession

            val sparkMaster="spark://hadoop-namenode:7077"
            val alluxioS3Endpoint="http://alluxio-master:39999/api/v1/s3"

	       val spark = SparkSession.builder().appName(" Scala Alluxio S3 Example").config("spark.serializer", "org.apache.spark.serializer.KryoSerializer").master(sparkMaster).getOrCreate()

            val sc=spark.sparkContext
            sc.hadoopConfiguration.set("fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
            sc.hadoopConfiguration.set("fs.s3a.endpoint", alluxioS3Endpoint)
            sc.hadoopConfiguration.set("fs.s3a.access.key", "user1")
            sc.hadoopConfiguration.set("fs.s3a.secret.key", "[SECRET_KEY]")
            sc.hadoopConfiguration.set("fs.s3a.path.style.access", "true")
            sc.hadoopConfiguration.set("fs.s3a.connection.ssl.enabled","false") 
            
            sc.textFile("""s3a://user/user1/alluxio_table/alluxio_table.csv""").collect()

<a name="use_prometheus"/></a>
### &#x1F536; Use Prometheus to monitor the Alluxio virtual filesystem

#### Step 1. Access the Prometheus Web console

The Prometheus web console is available on port number 9000. So you can use the following URL to access it:

     http://localhost:9000

#### Step 2. TBD

<a name="use_grafana"/></a>
### &#x1F536; Use Grafana to monitor the Alluxio virtual filesystem

#### Step 1. Access the Grafana  Web console

The Grafana  web console is available on port number 3000. So you can use the following URL to access it:

     http://localhost:3000

#### Step 2. TBD

---

KNOWN ISSUES:

     None at this time.


---

Please direct questions and comments to greg.palmer@alluxio.com

<a name="use_presto"/></a>
### &#x1F536; Use Presto to query the Alluxio virtual filesystem


#### Step X. Delete managed table

1. Use SQL to delete the managed table
2. Check on Alluxio and HDFS that data files are deleted successfully accordingly

----
     TBA
----
