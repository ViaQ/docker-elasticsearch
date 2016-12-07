#!/bin/sh

set -x
set -o errexit
prefix=${PREFIX:-${1:-viaq/}}
version=${VERSION:-${2:-latest}}
use_sg=
if [ "${USE_SEARCHGUARD:-}" = true ] ; then
    use_sg="--build-arg=USE_SEARCHGUARD=true"
fi
docker build -f Dockerfile-1.x -t "${prefix}elasticsearch:1.5.2" .
docker build $use_sg -t "${prefix}elasticsearch:${ES_VER:-2.4.2}" .
tagoutput=`docker tag "${prefix}elasticsearch:${ES_VER:-2.4.2}" "${prefix}elasticsearch:$version" 2>&1 || :`
case "$tagoutput" in
*"is already set to image"*) echo "tagged" ;;
"") echo "tagged" ;;
*) echo "Error tagging image $tagoutput" ; exit 1 ;;
esac

if [ -n "${PUSH:-$3}" ]; then
	docker push "${prefix}elasticsearch:${version}"
fi
