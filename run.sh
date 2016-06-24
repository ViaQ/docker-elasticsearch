#!/bin/bash

set -x
set -e

PORT=9200
HOST=localhost
LOG_FILE=elasticsearch_connect_log.txt
RETRY_COUNT=30      # how many times
RETRY_INTERVAL=1    # how often (in sec)

retry=${RETRY_COUNT}
max_time=$(( RETRY_COUNT * RETRY_INTERVAL ))    # should be integer
timeouted=false

if [ -z "$CLUSTER_NAME" ] ; then
    echo CLUSTER_NAME not set - using viaq
    export CLUSTER_NAME=viaq
fi
mkdir -p /elasticsearch/$CLUSTER_NAME
if [ -n "$USE_SEARCHGUARD" ] ; then
    ln -s /etc/elasticsearch/keys/searchguard.key /elasticsearch/$CLUSTER_NAME/searchguard_node_key.key
fi

# the amount of RAM allocated should be half of available instance RAM.
# ref. https://www.elastic.co/guide/en/elasticsearch/guide/current/heap-sizing.html#_give_half_your_memory_to_lucene
regex='^([[:digit:]]+)([GgMm])$'
if [[ "${INSTANCE_RAM}" =~ $regex ]]; then
	num=${BASH_REMATCH[1]}
	unit=${BASH_REMATCH[2]}
	if [[ $unit =~ [Gg] ]]; then
		((num = num * 1024)) # enables math to work out for odd gigs
	fi
	if [[ $num -lt 512 ]]; then
		echo "INSTANCE_RAM set to ${INSTANCE_RAM} but must be at least 512M"
		exit 1
	fi
	ES_JAVA_OPTS="${ES_JAVA_OPTS} -Xms256M -Xmx$(($num/2))m"
else
	echo "INSTANCE_RAM env var is invalid: ${INSTANCE_RAM}"
	exit 1
fi

# Wait for Elasticsearch port to be opened. Fail on timeout or if response from Elasticsearch is unexpected.
wait_for_port_open() {
    rm -f ${LOG_FILE}
    echo -n "Checking if Elasticsearch is ready on ${HOST}:${PORT} "
    while ! curl -i -s --max-time ${max_time} -o ${LOG_FILE} ${HOST}:${PORT} && [ ${timeouted} == false ]
    do
        echo -n "."
        sleep ${RETRY_INTERVAL}
        (( retry -= 1 ))
        if (( retry == 0 )) ; then
            timeouted=true
        fi
    done

    # Test for response code 200 in Elasticsearch output. This can be sensitive to Elasticsearch version.
    if [ -f ${LOG_FILE} ] && grep -q "HTTP/1.1 200 OK" ${LOG_FILE} ; then
        echo "- connection successful"
        cat ${LOG_FILE}
    else
        if [ ${timeouted} == true ] ; then
            echo -n "[timeout] "
        fi
        cat ${LOG_FILE}
        echo "failed"
        exit 1
    fi
}

add_index_template() {
    wait_for_port_open
    # Make sure cluster is stable enough for index templates being pushed in.
    curl -v -X GET "http://${HOST}:${PORT}/_cluster/health?wait_for_status=yellow&timeout=${max_time}s"
    curl -v -X PUT -d@/usr/share/elasticsearch/config/com.redhat.viaq-template.json http://${HOST}:${PORT}/_template/viaq
}

add_index_template &

/usr/share/elasticsearch/bin/elasticsearch
