#!/bin/bash
#用法：
#  nnbdc.sh -k|-t(可选参数)
#  当不加-k参数时，启动（或重启）
#  当加上-k参数时，停止（首先尝试优雅结束进程）
#  当加上-t参数时，向进程发送TERM信号，并立即返回
pid=`ps -ef|grep 'nnbdc-service.jar'|grep java|grep -v grep|cut -c 9-15`

#尝试优雅结束进程
if [ "$pid" != "" ] ; then
  kill -15 $pid
  echo '结束当前进程：'$pid
fi

if [ "$1" = "-t" ] ; then
  exit 0
fi

#等待进程优雅退出
pid=`ps -ef|grep 'nnbdc-service.jar'|grep java|grep -v grep|cut -c 9-15`
while [ "$pid" != "" ] ; do
  sleep 1s
  ((waited_time++))
  if [[ $waited_time -gt 20 ]]; then
    break
  fi
  echo "wait the process ["$pid"] to vanish ...("$waited_time"s)"
  pid=`ps -ef|grep 'nnbdc-service.jar'|grep java|grep -v grep|cut -c 9-15`
done

#强行杀掉现有进程
if [ "$pid" != "" ] ; then
  kill -9 $pid
  echo '杀掉当前进程：'$pid
fi

if [ "$1" = "-k" ] ; then
  exit 0
fi

/opt/nnbdc/waitPortToVanish 9090
nohup java -Djava.security.egd=file:/dev/./urandom -Xmx4096m -Xss228k -jar /opt/nnbdc/nnbdc-service.jar 1>/dev/null 2>&1 &

#tail -F /var/nnbdc/log/nnbdc-service.log
