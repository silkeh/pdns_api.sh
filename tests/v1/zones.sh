#!/bin/bash

export PDNS_ZONES_TXT="/dev/null"

_TEST "V1 Zone index"
_SUBTEST "Deploy"
_RUN 'deploy_challenge' \
'GET http://hostname:8000/api/v1/servers/servername/zones'

_SUBTEST "Clean"
_RUN 'clean_challenge' \
'GET http://hostname:8000/api/v1/servers/servername/zones'
