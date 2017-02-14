#!/bin/bash

set -euxo pipefail

HOST=${HOST:-localhost}
PORT=${PORT:-9200}
ES_REST_BASEURL=http://${HOST}:$PORT
LOG_FILE=elasticsearch_connect_log.txt
RETRY_COUNT=300		# how many times
RETRY_INTERVAL=1	# how often (in sec)

retry=$RETRY_COUNT
max_time=$(( RETRY_COUNT * RETRY_INTERVAL ))	# should be integer
timeouted=false

if [ -z "${CLUSTER_NAME:-}" ] ; then
    echo CLUSTER_NAME not set - using viaq
    export CLUSTER_NAME=viaq
fi
mkdir -p /elasticsearch/$CLUSTER_NAME

ADMIN_AUTH=
if [ "${USE_SEARCHGUARD:-}" = true ] ; then
    ES_REST_BASEURL=https://${HOST}:$PORT
    ADMIN_AUTH="-u kirk:kirk -k"
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
    echo "INSTANCE_RAM env var is invalid: ${INSTANCE_RAM:-}"
    exit 1
fi

# Wait for Elasticsearch port to be opened. Fail on timeout or if response from Elasticsearch is unexpected.
wait_for_port_open() {
    rm -f ${LOG_FILE}
    echo -n "Checking if Elasticsearch is ready on ${ES_REST_BASEURL}"
    while ! curl -i -s --max-time ${max_time} -o ${LOG_FILE} $ADMIN_AUTH ${ES_REST_BASEURL} && [ ${timeouted} == false ]
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

verify_or_add_index_templates() {
    wait_for_port_open
    # Try to wait for cluster become more stable before index template being pushed in.
    # Give up on timeout and continue...
    curl -v -X GET $ADMIN_AUTH "${ES_REST_BASEURL}/_cluster/health?wait_for_status=yellow&timeout=${max_time}s"

    for template_file in $ES_CONF/index_templates/*.json
    do
        template=`basename $template_file`
        # Check if index template already exists
        response_code=$(curl -v -X HEAD \
            -w '%{response_code}' $ADMIN_AUTH \
            ${ES_REST_BASEURL}/_template/$template)
        if [ $response_code == "200" ]; then
            echo "Index template '$template' already present in ES cluster"
        else
            echo "Create index template '$template'"
            curl -v -X PUT -d@$template_file $ADMIN_AUTH ${ES_REST_BASEURL}/_template/$template
        fi
    done
}

init_sg() {
    sleep 15
    cd $ES_HOME
    bash plugins/search-guard-2/tools/sgadmin.sh \
        -cd plugins/search-guard-2/sgconfig/ \
        -ks plugins/search-guard-2/sgconfig/node-0-keystore.jks \
        -ts plugins/search-guard-2/sgconfig/truststore.jks \
        -i .searchguard \
        -nhnv
}

do_initial_tasks() {
    if [ "${USE_SEARCHGUARD:-}" = true ] ; then
        init_sg
    fi
    wait_for_port_open
    verify_or_add_index_templates
}

do_initial_tasks &

exec $ES_HOME/bin/elasticsearch --security.manager.enabled=false --path.conf=$ES_CONF/
