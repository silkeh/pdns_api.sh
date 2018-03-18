#!/bin/bash

_TEST "V1 Wildcard"
_SUBTEST "Deploy"
_RUN 'deploy_challenge example.com _ t1 *.example.com _ t2' \
'PATCH http://hostname:8000/api/v1/servers/servername/zones/example.com.' \
'{
  "rrsets": [
    {
      "name": "_acme-challenge.example.com.",
      "type": "TXT",
      "ttl": 1,
      "records": [
        {
          "content": "\"t2\"",
          "disabled": false,
          "set-ptr": false
        },
        {
          "content": "\"t1\"",
          "disabled": false,
          "set-ptr": false
        }
      ],
      "changetype": "REPLACE"
    }
  ]
}'

_SUBTEST "Clean"
_RUN 'clean_challenge example.com _ t1 *.example.com _ t2' \
'PATCH http://hostname:8000/api/v1/servers/servername/zones/example.com.' \
'{
  "rrsets": [
    {
      "name": "_acme-challenge.example.com.",
      "type": "TXT",
      "changetype": "DELETE"
    }
  ]
}'
