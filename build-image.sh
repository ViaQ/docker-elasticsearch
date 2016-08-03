#!/bin/sh

set -x
set -o errexit
prefix=${PREFIX:-${1:-viaq/}}
version=${VERSION:-${2:-latest}}
docker build  -t "${prefix}elasticsearch:1.5.2" .
docker tag "${prefix}elasticsearch:1.5.2" "${prefix}elasticsearch:$version"
docker build -f Dockerfile-2.x -t "${prefix}elasticsearch:2.3.4" .

if [ -n "${PUSH:-$3}" ]; then
	docker push "${prefix}elasticsearch:${version}"
fi
