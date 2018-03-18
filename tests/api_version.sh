#!/bin/bash

export PDNS_VERSION=

_TEST "API version detection"
_SUBTEST "Deploy"
_RUN 'deploy_challenge' \
'GET http://hostname:8000/api'

_SUBTEST "Clean"
_RUN 'clean_challenge' \
'GET http://hostname:8000/api'
