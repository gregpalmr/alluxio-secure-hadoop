# alluxio-secure-hadoop
Test Alluxio Enterprise with Apache Hadoop 2.7.4 in secure mode

This repo contains docker compose artifacts that build and launch a small Alluxio cluster that runs against a Hadoop environment with Kerberos enabled and SSL connections enforced (dfs.http.policy=HTTPS_ONLY)


## Usage:

### Step 1. Install docker and docker-compose

#### MAC:

See: https://docs.docker.com/desktop/mac/install/

#### LINUX:

Install the docker package

     sudo yum -y install docker

Increase the ulimit in /etc/sysconfig/docker

     sudo sed -i 's/nofile=32768:65536/nofile=1024000:1024000/' /etc/sysconfig/docker

     sudo service docker start

Add your user to the docker group

     sudo usermod -a -G docker ec2-user

Logout and back in to get new group membershiop

     exit

     ssh ...

Install the docker-compose package

     DOCKER_COMPOSE_VERSION="1.23.2"

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

Build the docker image used for the Hadoop instances and the Alluxio instance.

     docker build -t myalluxio/alluxio-secure-hadoop:2.7.4 .

### Step 6. Start the kdc, hadoop and alluxio containers

Use the docker-compose command to start the kdc, hadoop and alluxio containers.

     docker-compose up -d

You can see the log output of the Alluxio container using this command:

     docker logs -f alluxio

You can see the log output of the Hadoop container using this command:

     docker logs -f hadoop

You can see the log output of the Kerberos kdc container using this command:

     docker logs -f kdc

When finished working with the containers, you can stop them with the commands:

     docker-compose down

If you are done testing and do not intend to spin up the docker images again, remove the disk volumes with the commands:

     docker volume rm alluxio-secure-hadoop_keytabs  


#### Step 7. Test Alluxio access to the secure Hadoop environment 

Open a command shell into the Alluxio container.

     docker exec -it alluxio bash

Destroy any kerberos ticket that may be active

     kdestroy

Attempt to read the Alluxio virtual filesystem.

     alluxio fs ls /tmp

     < you will see a permission denied error >

Acquire a Kerberos ticket.

     kinit

     < enter the user's kerberos password: it defaults to "password" >

Show the valid Kerberos ticket:

     klist

Attempt to read the Alluxio virtual filesystem.

     alluxio fs ls /tmp

     < you will see the contents of the /tmp HDFS directory >

The above command shows Alluxio access the kerberized Hadoop environment that had the following HDFS properties configured:

      dfs.encrypt.data.transfer           = true
      dfs.encrypt.data.transfer.algorithm = 3des
      dfs.http.policy set                 = HTTPS_ONLY

---

KNOWN ISSUES:

- In the bootstrap-alluxio.sh script, the kadmin command to create the principal for the alluxio-user1 user, is erroring out with the message:

     kadmin: unable to get default realm
---

Please direct questions and comments to greg.palmer@alluxio.com
