#!/bin/bash
#

echo $ZOO_MY_ID > /data/myid 

/apache-zookeeper-3.5.7-bin/bin/zkServer.sh start

# wait forever
while true
do
  sleep 300
done

# end of script
