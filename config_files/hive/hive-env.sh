export HADOOP_PID_DIR=${HADOOP_PID_DIR}
export HIVE_CONF_DIR=$HIVE_CONF_DIR

if [ "$SERVICE" = "cli" ]; then
   if [ -z "$DEBUG" ]; then
     export HADOOP_OPTS="$HADOOP_OPTS -XX:NewRatio=12 -Xms10m -XX:MaxHeapFreeRatio=40 -XX:MinHeapFreeRatio=15 -XX:+UseParNewGC -XX:-UseGCOverheadLimit"
   else
     export HADOOP_OPTS="$HADOOP_OPTS -XX:NewRatio=12 -Xms10m -XX:MaxHeapFreeRatio=40 -XX:MinHeapFreeRatio=15 -XX:-UseGCOverheadLimit"
   fi
fi

# Add share/hadoop/tools/lib/*.jar files to classpath (for aws s3 filesystem usage)
for f in $HADOOP_HOME/share/hadoop/tools/lib/*.jar
do
  if [ "$HADOOP_CLASSPATH" ]; then
    export HADOOP_CLASSPATH=$HADOOP_CLASSPATH:$f
  else
    export HADOOP_CLASSPATH=$f
  fi
done

export HADOOP_HEAPSIZE=1024
export HIVE_OPTS="-hiveconf mapreduce.map.memory.mb=1024 -hiveconf mapreduce.reduce.memory.mb=1024"
export HIVE_AUX_JARS_PATH=$ALLUXIO_HOME/client/alluxio-enterprise-*-client.jar,$ALLUXIO_HOME/conf/alluxio-site.properties

