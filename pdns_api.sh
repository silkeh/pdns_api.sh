#!/usr/bin/env bash

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

# Check for zones.txt in various locations
if [[ -z "${ZONES_TXT:-}" ]]; then
  for check_zones in "/etc/letsencrypt.sh" "/usr/local/etc/letsencrypt.sh" "${PWD}" "${DIR}"; do
    if [[ -f "${check_zones}/zones.txt" ]]; then
      ZONES_TXT="${check_zones}/zones.txt"
      break
    fi
  done
fi

# Load configuration
. "$CONFIG"

# Load zones
if [[ -f $ZONES_TXT ]]; then
  all_zones="$(cat $ZONES_TXT)"
fi

## Functions

# Utility
function join { local IFS="${1}"; shift; echo "$*"; }

# Different sed version for different os types...
# From letsencrypt.sh
_sed() {
  if [[ "${OSTYPE}" = "Linux" ]]; then
    sed -r "${@}"
  else
    sed -E "${@}"
  fi
}

# API request
request() {
  # Request parameters
  req_method="${1}"
  req_url="${2}"
  req_data="${3}"

  # Do the request
  res=$(curl -sS --request "$req_method" --header "$headers" --data "$req_data" "$req_url")
  res_code=$?

  # Debug output
  if [[ "$DEBUG" ]]; then
    echo "Method: $req_method"
    echo "URL: $req_url"
    echo "Data: $req_data"
    echo "Response: $res"
  fi

  # Abort on failed request
  if [[ $res_code -gt 0 ]]; then
    >&2 echo "Request to API failed."
    exit 1
  elif [[ $res = *"error"* ]]; then
    >&2 echo "API error: $res"
    exit 1
  fi
}

# Setup of connection settings
setup() {
  # Zone endpoint on the API
  url="/servers/$SERVER/zones"

  # Header with the api key
  headers="X-API-Key: $KEY"

  # Some version incompatibilities
  if [[ $VERSION -ge 1 ]]; then
    url="/api/v${VERSION}${url}"
  fi

  # Add the host and port to the url
  url="http://${HOST}:${PORT}${url}"

  # Get a zone list from the API is none was set
  if [[ "$all_zones" = "" ]]; then
    request "GET" "${url}" ""
    all_zones=$(<<< "${res}" grep -o 'id":[^,]*,' | _sed -e 's/id": "|\.?",//g')
  fi

  # Sort zones to list most specific first
  all_zones=$(sort -r <<< "$all_zones")
}

setup_domain() {
  # Domain and token from arguments
  domain="${1}"
  token="${2}"
  zone=""

  # Read domain parts into array
  IFS='.' read -a domain_array <<< "$domain"

  # Find zone name, cut off subdomains until match
  for check_zone in $all_zones; do
    for (( j=${#domain_array[@]}-1; j>=0; j-- )); do
      if [[ "$check_zone" = "$(join . ${domain_array[@]:j})" ]]; then
        zone=$check_zone
        break 2
      fi
    done
  done

  # Fallback to creating zone from arguments
  if [[ "$zone" = "" ]]; then
    zone="${domain_array[*]: -2:1}.${domain_array[*]: -1:1}"
    >&2 echo "Warning: zone not found, using '$zone'"
  fi

  # Record name
  name="_acme-challenge.$domain"

  # Some version incompatibilities
  if [[ $VERSION -ge 1 ]]; then
    name="$name."
    zone="$zone."
  else
    extra_data=",\"name\": \"${name}\", \"type\": \"TXT\", \"ttl\": 1"
  fi
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
  request "PATCH" "${url}/${zone}" "$data"
}

clean() {
  # Create the JSON string
  data='{"rrsets":[{"name":"'${name}'","type":"TXT","changetype":"DELETE"}]}'

  # Do the request
  request "PATCH" "${url}/${zone}" "$data"
}

# Main setup
setup

# Set hook
hook="${1}"

# Loop through arguments per 3
for ((i=2; i<=$#; i=i+3)); do
  t=$(($i + 2))
  setup_domain "${!i}" "${!t}"

  # Debug output
  if [[ "$DEBUG" ]]; then
    echo "Hook:  $hook"
    echo "Name:  $name"
    echo "Token: $token"
    echo "Zone:  $zone"
  fi

  # Deploy a token
  if [[ "$hook" = "deploy_challenge" ]]; then
    deploy
  fi

  # Remove a token
  if [[ "$hook" = "clean_challenge" ]]; then
    clean
  fi

  # Other actions are not implemented but will not cause an error
done

# Wait the requested amount of seconds when deployed
if [[ "$hook" = "deploy_challenge" ]] && [[ ! -z "$WAIT" ]]; then
  if [[ "$DEBUG" ]]; then
    echo "Waiting for $WAIT seconds"
  fi

  sleep "$WAIT"
fi

exit 0
