#!/bin/bash

_TEST "V1 Single"
_SUBTEST "Deploy"
_RUN 'deploy_challenge host1.example.com unused1 token1' \
'PATCH http://hostname:8000/api/v1/servers/servername/zones/example.com.' \
'{
  "rrsets": [
    {
      "name": "_acme-challenge.host1.example.com.",
      "type": "TXT",
      "ttl": 1,
      "records": [
        {
          "content": "\"token1\"",
          "disabled": false,
          "set-ptr": false
        }
      ],
      "changetype": "REPLACE"
    }
  ]
}'

_SUBTEST "Clean"
_RUN 'clean_challenge host1.example.com unused1 token1' \
'PATCH http://hostname:8000/api/v1/servers/servername/zones/example.com.' \
'{
  "rrsets": [
    {
      "name": "_acme-challenge.host1.example.com.",
      "type": "TXT",
      "changetype": "DELETE"
    }
  ]
}'
