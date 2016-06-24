#!/bin/bash

set -ex

rpm --import https://packages.elastic.co/GPG-KEY-elasticsearch
case ${ES_VER:-1.5.2} in
    1.*) DISABLEREPO="--disablerepo elasticsearch-2.x" ;;
esac
yum install -y --setopt=tsflags=nodocs $DISABLEREPO \
  java-1.8.0-openjdk-headless \
  elasticsearch
yum clean all

# need these so elasticsearch doesn't reject its config while installing plugins
export SERVICE_DNS=placeholder
export CLUSTER_NAME=placeholder

mkdir -p ${HOME}
ln -s /usr/share/elasticsearch /usr/share/java/elasticsearch
if [ -n "$USE_SEARCHGUARD" ] ; then
    /usr/share/elasticsearch/bin/plugin -i com.floragunn/search-guard/0.5
fi
if [ -n "$USE_OPENSHIFT_PLUGIN" ] ; then
    /usr/share/elasticsearch/bin/plugin -i io.fabric8.elasticsearch/openshift-elasticsearch-plugin/0.6
fi
if [ -n "$USE_KUBERNETES_PLUGIN" ] ; then
    /usr/share/elasticsearch/bin/plugin -i io.fabric8/elasticsearch-cloud-kubernetes/1.3.0
fi
mkdir /elasticsearch
chmod -R og+w /usr/share/java/elasticsearch ${HOME} /elasticsearch
