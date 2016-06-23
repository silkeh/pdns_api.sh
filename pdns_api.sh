#!/bin/sh

# Copyright 2016 - Silke Hofstra
#
# Licensed under the EUPL, Version 1.1 or -- as soon they will be approved by
# the European Commission -- subsequent versions of the EUPL (the "Licence");
# You may not use this work except in compliance with the Licence.
# You may obtain a copy of the Licence at:
#
# https://joinup.ec.europa.eu/software/page/eupl
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the Licence is distributed on an "AS IS" basis,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
# express or implied.
# See the Licence for the specific language governing
# permissions and limitations under the Licence.
#

# Local directory
DIR="$(dirname "${0}")"

# Check for config in various locations
# From letsencrypt.sh
if [[ -z "${CONFIG:-}" ]]; then
  for check_config in "/etc/letsencrypt.sh" "/usr/local/etc/letsencrypt.sh" "${PWD}" "${DIR}"; do
    if [[ -f "${check_config}/config" ]]; then
      CONFIG="${check_config}/config"
      break
    fi
  done
fi

# Load configuration
. "$CONFIG"

## Functions
# API request
request () {
  # Do the request
  res=$(curl -sS --request PATCH --header "$headers" --data "$data" "$url")

  # Debug output
  if [[ "$DEBUG" ]]; then
    echo "Data: $data"
    echo "Response: $res"
  fi

  # Abort on failed request
  if [[ "$?" -gt 0 ]]; then
    echo "Request to API failed."
    exit 1
  elif [[ $res = *"error"* ]]; then
    echo "API error: $res"
    exit 1
  fi
}

setup() {
  # Domain and token from arguments
  domain="${1}"
  token="${2}"

  # Create the zone name from the arguments
  IFS='.' read -a domain_array <<< "$domain"
  zone="${domain_array[*]: -2:1}.${domain_array[*]: -1:1}"

  # Record name
  name="_acme-challenge.$domain"

  # URL to post to
  url="/servers/$SERVER/zones/$zone"

  # Header with the api key
  headers="X-API-Key: $KEY"

  # Some version incompatibilities
  if [[ $VERSION -ge 1 ]]; then
    name="$name."
    url="/api/v${VERSION}${url}"
  else
    extra_data=",\"name\": \"${name}\", \"type\": \"TXT\", \"ttl\": 1"
  fi

  # Add the host and port to the url
  url="http://${HOST}:${PORT}${url}"
}

deploy() {
  # Create the JSON string
  data='{
    "rrsets": [{
      "name": "'${name}'",
      "type": "TXT",
      "ttl": 1,
      "records": [{
        "content": "\"'${token}'\"",
        "disabled": false,
        "set-ptr": false
        '${extra_data}'
      }],
      "changetype": "REPLACE"
    }]
  }'

  # Do the request
  request
}

clean() {
  # Create the JSON string
  data='{"rrsets":[{"name":"'${name}'","type":"TXT","changetype":"DELETE"}]}'

  # Do the request
  request
}

# Loop through arguments per 3
for ((i=2; i<=$#; i=i+3)); do
  t=$(($i + 2))
  setup "${!i}" "${!t}"

  # Debug output
  if [[ "$DEBUG" ]]; then
    echo "Name:  $name"
    echo "Token: $token"
  fi

  # Deploy a token
  if [[ "$1" = "deploy_challenge" ]]; then
    deploy
  fi

  # Remove a token
  if [[ "$1" = "clean_challenge" ]]; then
    clean
  fi

  # Other actions are not implemented but will not cause an error
done

# Wait the requested amount of seconds when deployed
if [[ "$1" = "deploy_challenge" ]] && [[ ! -z "$WAIT" ]]; then
  if [[ "$DEBUG" ]]; then
    echo "Waiting for $WAIT seconds"
  fi

  sleep "$WAIT"
fi

exit 0
