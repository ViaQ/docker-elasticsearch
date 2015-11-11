#!/bin/sh
set -o errexit

HOSTDIR=${HOSTDIR:-/var/lib/bitscout}
ESHOSTDIR=${ESHOSTDIR:-$HOSTDIR/elasticsearch}
if [ ! -d $ESHOSTDIR ] ; then
    sudo mkdir -p $ESHOSTDIR
    sudo chown -R $USER $ESHOSTDIR
    sudo chcon -Rt svirt_sandbox_file_t $ESHOSTDIR
fi

uid=`id -u`
id=`docker run -d -p 9200:9200 -p 9300:9300 -u $uid --name bitscout-elasticsearch -v $ESHOSTDIR:/elasticsearch bitscout/elasticsearch:latest`
echo $id
sleep 5
docker logs $id
