#!/bin/bash

set -euxo pipefail

rpm --import https://packages.elastic.co/GPG-KEY-elasticsearch
DISABLEREPO=
case ${ES_VER:-1.5.2} in
    1.*) DISABLEREPO="--disablerepo elasticsearch-2.x" ;;
esac
PKGS="java-1.8.0-openjdk-headless elasticsearch"
if [ "${USE_SEARCHGUARD:-}" = true ] ; then
    PKGS="$PKGS git openssl"
fi
yum install -y --setopt=tsflags=nodocs $DISABLEREPO $PKGS
yum clean all

# need these so elasticsearch doesn't reject its config while installing plugins
export SERVICE_DNS=placeholder
export CLUSTER_NAME=placeholder

mkdir -p $HOME
ln -s $ES_HOME /usr/share/java/elasticsearch
if [ -n "${USE_OPENSHIFT_PLUGIN:-}" ] ; then
    $ES_HOME/bin/plugin -i io.fabric8.elasticsearch/openshift-elasticsearch-plugin/$OSE_ES_VER
fi
if [ -n "${USE_KUBERNETES_PLUGIN:-}" ] ; then
    $ES_HOME/bin/plugin -i io.fabric8/elasticsearch-cloud-kubernetes/$ES_CLOUD_K8S_VER
fi
mkdir /elasticsearch
chmod -R og+w /usr/share/java/elasticsearch $HOME /elasticsearch
if [ "${USE_SEARCHGUARD:-}" = true ] ; then
    $HOME/sg_init.sh
    echo "" >> $ES_CONF/elasticsearch.yml
    cat $ES_CONF/searchguard.yml >> $ES_CONF/elasticsearch.yml
fi
