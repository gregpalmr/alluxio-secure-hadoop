export HADOOP_PID_DIR=${HADOOP_PID_DIR}
export HIVE_CONF_DIR=$HIVE_CONF_DIR

if [ "$SERVICE" = "cli" ]; then
   if [ -z "$DEBUG" ]; then
     export HADOOP_OPTS="$HADOOP_OPTS -XX:NewRatio=12 -Xms10m -XX:MaxHeapFreeRatio=40 -XX:MinHeapFreeRatio=15 -XX:+UseParNewGC -XX:-UseGCOverheadLimit"
   else
     export HADOOP_OPTS="$HADOOP_OPTS -XX:NewRatio=12 -Xms10m -XX:MaxHeapFreeRatio=40 -XX:MinHeapFreeRatio=15 -XX:-UseGCOverheadLimit"
   fi
fi

export HADOOP_HEAPSIZE=1024
export HIVE_OPTS="-hiveconf mapreduce.map.memory.mb=1024 -hiveconf mapreduce.reduce.memory.mb=1024"
export HIVE_AUX_JARS_PATH=$ALLUXIO_HOME/client/alluxio-enterprise-*-client.jar

