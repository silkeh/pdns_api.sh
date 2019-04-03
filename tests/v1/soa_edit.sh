#!/bin/bash

_TEST "V1 SOA-EDIT"
_SUBTEST "Retrieve"
_RUN 'soa_edit example.com' \
     'GET http://hostname:8000/api/v1/servers/servername/zones/example.com' \
     'Current values:' \
     'SOA-EDIT:' \
     'SOA-EDIT-API:'

_SUBTEST "Set one"
_RUN 'soa_edit example.com INCREMENT-WEEKS' \
'GET http://hostname:8000/api/v1/servers/servername/zones/example.com' \
'Setting:' \
'SOA-EDIT: INCREMENT-WEEKS' \
'SOA-EDIT-API: DEFAULT' \
'PUT http://hostname:8000/api/v1/servers/servername/zones/example.com' \
'{
  "soa_edit":"INCREMENT-WEEKS",
  "soa_edit_api":"DEFAULT",
  "kind":""
 }'

_SUBTEST "Set both"
_RUN 'soa_edit example.com INCREMENT-WEEKS SOA-EDIT' \
'GET http://hostname:8000/api/v1/servers/servername/zones/example.com' \
'Setting:' \
'SOA-EDIT: INCREMENT-WEEKS' \
'SOA-EDIT-API: SOA-EDIT' \
'PUT http://hostname:8000/api/v1/servers/servername/zones/example.com' \
'{
  "soa_edit":"INCREMENT-WEEKS",
  "soa_edit_api":"SOA-EDIT",
  "kind":""
 }'
