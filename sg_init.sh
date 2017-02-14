#!/bin/bash

set -euxo pipefail

# ----------------------------------------------
# This script installs Search Guard plugins, starts Elasticsearch and finishes
# initialization of Search Guard plugin. It needs to be executed only once. You
# can then shutdown Elasticsearch and start it again and all will be set as needed.
#
# The following env variables are set to enable smooth testing in Travis, you might
# want to tweak them accordingly if testing locally.
# ----------------------------------------------

export IS_ES_SECURED=${IS_ES_SECURED:-true}
export ES_VER=${ES_VER:-2.4.4}
export SG_VER=${SG_VER:-2.4.4.10}
export SG_SSL_VER=${SG_SSL_VER:-2.4.4.19}
export TMP_DIR=${TMP_DIR:-/tmp}
export ES_HOME=${ES_HOME:-$TMP_DIR/elasticsearch}
export ES_CONF=${ES_CONF:-./tests/conf}


if [ "${IS_ES_SECURED:-}" = true ] ; then

    # ----------------------------------------------
    # Install SSL plugin
    # See: <https://github.com/floragunncom/search-guard-ssl-docs/blob/master/installation.md>

    [[ -d ${ES_HOME}/bin/plugin/search-guard-ssl ]] && rm -rf ${ES_HOME}/bin/plugin/search-guard-ssl
    ${ES_HOME}/bin/plugin install -b com.floragunn/search-guard-ssl/${SG_SSL_VER}

    # ----------------------------------------------
    # Follow Quickstart tutorial
    # See: <https://github.com/floragunncom/search-guard-ssl-docs/blob/master/quickstart.md>
    # Use PKI scripts: <https://github.com/floragunncom/search-guard-ssl-docs/blob/master/quickstart.md#using-the-example-pki-scripts>

    ACTUAL_DIR=`pwd`
    [[ -d ${TMP_DIR} ]] || mkdir ${TMP_DIR}
    cd ${TMP_DIR}
    [[ -d ${TMP_DIR}/search-guard-ssl ]] && rm -rf ${TMP_DIR}/search-guard-ssl
    git clone https://github.com/floragunncom/search-guard-ssl.git -b v${SG_SSL_VER}
    cd search-guard-ssl/example-pki-scripts/
    ./example.sh
    # for the searchguard.ssl.transport.keystore
    mkdir transport
    # have to move these because gen_node_cert_no_oid.sh will overwrite them
    for nn in 0 1 2 ; do mv node-${nn}* transport ; done
    # the searchguard.ssl.http certs cannot use this oid due to bugs in python and openssl
    sed 's/,oid:1.2.3.4.5.5//g' gen_node_cert.sh > gen_node_cert_no_oid.sh
    chmod +x gen_node_cert_no_oid.sh
    # create http certs/trusts for nodes
    for nn in 0 1 2 ; do ./gen_node_cert_no_oid.sh $nn changeit capass ; done
    ls -alrtF
    cd ${ACTUAL_DIR}

    cp ${TMP_DIR}/search-guard-ssl/example-pki-scripts/truststore.jks ${ES_CONF}/truststore.jks
    cp ${TMP_DIR}/search-guard-ssl/example-pki-scripts/transport/node-0-keystore.jks ${ES_CONF}/transport-node-0-keystore.jks
    cp ${TMP_DIR}/search-guard-ssl/example-pki-scripts/node-0-keystore.jks ${ES_CONF}/http-node-0-keystore.jks

    # ----------------------------------------------
    # Install Search Guard plugin
    # See: <https://github.com/floragunncom/search-guard/#installation>

    [[ -d ${ES_HOME}/bin/plugin/search-guard-2 ]] && rm -rf ${ES_HOME}/bin/plugin/search-guard-2
    ${ES_HOME}/bin/plugin install -b com.floragunn/search-guard-2/${SG_VER}

    # ----------------------------------------------
    # Make sure sgadmin tool is executable
    cd ${ES_HOME}/plugins/search-guard-2/tools
    chmod u+x *.sh
    # sgadmin.sh uses the inter-node transport, not http
    cp ${TMP_DIR}/search-guard-ssl/example-pki-scripts/truststore.jks ${ES_HOME}/plugins/search-guard-2/sgconfig/truststore.jks
    cp ${TMP_DIR}/search-guard-ssl/example-pki-scripts/transport/node-0-keystore.jks ${ES_HOME}/plugins/search-guard-2/sgconfig/transport-node-0-keystore.jks
    cd ${ACTUAL_DIR}

    cp ${ES_CONF}/sg_*.yml ${ES_HOME}/plugins/search-guard-2/sgconfig
fi

# $SG_SETUP_ONLY is undocumented for now.
if [ "${SG_SETUP_ONLY:-}" = true ] ; then
    exit 0
fi

# ----------------------------------------------
# Start elasticsearch
${ES_HOME}/bin/elasticsearch -d --security.manager.enabled=false --path.conf=${ES_CONF}/
sleep 15
tail ${ES_HOME}/logs/elasticsearch.log


if [ "${IS_ES_SECURED:-}" = true ] ; then

    cd ${ES_HOME}
    plugins/search-guard-2/tools/sgadmin.sh \
      -cd plugins/search-guard-2/sgconfig/ \
      -ks plugins/search-guard-2/sgconfig/transport-node-0-keystore.jks \
      -ts plugins/search-guard-2/sgconfig/truststore.jks \
      -nhnv

    # plugins/search-guard-2/tools/hash.sh -p mycleartextpassword

    cd ${ACTUAL_DIR}

    # ----------------------------------------------
    # Make some curl requests to ES node.
    # See: <https://github.com/floragunncom/search-guard/blob/master/demo/searchguard_init.sh>

    # User kirk is an admin.
    curl -sS --insecure -u kirk:kirk 'https://localhost:9200/'
    curl -sS --insecure -u kirk:kirk 'https://localhost:9200/_searchguard/sslinfo?pretty'
    curl -sS --insecure -u kirk:kirk 'https://localhost:9200/_cluster/health?pretty'

    curl -vs -u kirk:kirk 'https://localhost:9200/_cluster/health?pretty' \
      --cacert ${TMP_DIR}/search-guard-ssl/example-pki-scripts/ca/chain-ca.pem

    curl -vs 'https://localhost:9200/_cluster/health?pretty' \
      --cacert ${TMP_DIR}/search-guard-ssl/example-pki-scripts/ca/chain-ca.pem \
      --cert ${TMP_DIR}/search-guard-ssl/example-pki-scripts/kirk.crt.pem \
      --key  ${TMP_DIR}/search-guard-ssl/example-pki-scripts/kirk.key.pem

    # User spock is NOT an admin
    curl -sS --insecure -u kirk:kirk 'https://localhost:9200/'
    echo This request should be rejected \(403\)
    curl -sS --insecure -u spock:spock 'https://localhost:9200/_cluster/health?pretty'

else

    curl -sS 'http://localhost:9200/'
    curl -sS 'http://localhost:9200/_cluster/health?pretty'

fi
