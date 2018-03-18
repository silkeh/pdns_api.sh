#!/bin/bash

export PDNS_NO_NOTIFY=

_TEST "V1 Notify"
_SUBTEST "Deploy"
_RUN 'deploy_challenge example.com unused1 token1' \
'PATCH http://hostname:8000/api/v1/servers/servername/zones/example.com.' \
'{
  "rrsets": [
    {
      "name": "_acme-challenge.example.com.",
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
}' \
'PUT http://hostname:8000/api/v1/servers/servername/zones/example.com./notify'

_SUBTEST "Clean"
_RUN 'clean_challenge example.com unused1 token1' \
'PATCH http://hostname:8000/api/v1/servers/servername/zones/example.com.' \
'{
  "rrsets": [
    {
      "name": "_acme-challenge.example.com.",
      "type": "TXT",
      "changetype": "DELETE"
    }
  ]
}' \
'PUT http://hostname:8000/api/v1/servers/servername/zones/example.com./notify'
