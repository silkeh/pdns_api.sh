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

set -e
set -u
set -o pipefail

# Local directory
DIR="$(dirname "$0")"

# Show an error/warning
error() { echo "Error: $@" >&2; }
warn() { echo "Warning: $@" >&2; }
fatalerror() { error "$@"; exit 1; }

# Debug message
debug() { [[ -z "${DEBUG:-}" ]] || echo "$@"; }

# Join an array with a character
join() { local IFS="$1"; shift; echo "$*"; }

# Reverse a string
rev() {
  local str rev
  str="$(cat)"
  rev=""
  for (( i=${#str}-1; i>=0; i-- )); do rev="${rev}${str:$i:1}"; done
  echo "${rev}"
}

# Different sed version for different os types...
# From letsencrypt.sh
_sed() {
  if [[ "${OSTYPE}" = "Linux" ]]; then
    sed -r "${@}"
  else
    sed -E "${@}"
  fi
}

# Get string value from json dictionary
# From letsencrypt.sh
get_json_string_value() {
  local filter
  filter="$(printf 's/.*"%s": *"([^"]*)".*/\\1/p' "$1")"
  _sed -n "${filter}"
}

# Get integer value from json dictionary
get_json_int_value() {
  local filter
  filter="$(printf 's/.*"%s": *([^,}]*),*.*/\\1/p' "$1")"
  _sed -n "${filter}"
}

# Load the configuration and set default values
load_config() {
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

  # Default values
  PORT=8081

  # Check if config was set
  if [[ -z "${CONFIG:-}" ]]; then
    # Warn about missing config
    warn "No config file found, using default config!"
  elif [[ -f "${CONFIG}" ]]; then
    # Load configuration
    . "${CONFIG}"
  fi

  # Check required settings
  [[ -n "${HOST:-}" ]] || fatalerror "HOST setting is required."
  [[ -n "${KEY:-}" ]]  || fatalerror "KEY setting is required."
}

# Load the zones from file
load_zones() {
  # Check for zones.txt in various locations
  if [[ -z "${ZONES_TXT:-}" ]]; then
    for check_zones in "/etc/letsencrypt.sh" "/usr/local/etc/letsencrypt.sh" "${PWD}" "${DIR}"; do
      if [[ -f "${check_zones}/zones.txt" ]]; then
        ZONES_TXT="${check_zones}/zones.txt"
        break
      fi
    done
  fi

  # Load zones
  all_zones=""
  if [[ -n "${ZONES_TXT:-}" ]] && [[ -f "${ZONES_TXT}" ]]; then
    all_zones="$(cat "${ZONES_TXT}")"
  fi
}

# API request
request() {
  # Request parameters
  local method url data
  method="$1"
  url="$2"
  data="$3"

  # Do the request
  res="$(curl -sS --request "${method}" --header "${headers}" --data "${data}" "${url}")"

  # Debug output
  debug "Method: ${method}"
  debug "URL: ${url}"
  debug "Data: ${data}"
  debug "Response: ${res}"

  # Abort on failed request
  if [[ "${res}" = *"error"* ]] || [[ "${res}" = "Not Found" ]]; then
    error "API error: ${res}"
    exit 1
  fi
}

# Setup of connection settings
setup() {
  # Header with the api key
  headers="X-API-Key: ${KEY}"

  # Default port
  if [[ -z "${PORT:-}" ]]; then
    PORT=8081
  fi

  # Add the host and port to the url
  url="http://${HOST}:${PORT}"

  # Detect the version
  if [[ -z "${VERSION:-}" ]]; then
    request "GET" "${url}/api" ""
    VERSION="$(<<< "${res}" get_json_int_value version)"
  fi

  # Fallback to version 0
  if [[ -z "${VERSION}" ]]; then
    VERSION=0
  fi

  # Some version incompatibilities
  if [[ "${VERSION}" -ge 1 ]]; then
    url="${url}/api/v${VERSION}"
  fi

  # Detect the server
  if [[ -z "${SERVER:-}" ]]; then
    request "GET" "${url}/servers" ""
    SERVER="$(<<< "${res}" get_json_string_value id)"
  fi

  # Fallback to localhost
  if [[ -z "${SERVER}" ]]; then
    SERVER="localhost"
  fi

  # Zone endpoint on the API
  url="${url}/servers/${SERVER}/zones"

  # Get a zone list from the API is none was set
  if [[ -z "${all_zones}" ]]; then
    request "GET" "${url}" ""
    all_zones="$(<<< "${res//, /$',\n'}" get_json_string_value id)"
  fi

  # Strip trailing dots from zones
  all_zones="${all_zones//$'.\n'/ }"

  # Sort zones to list most specific first
  all_zones="$(<<< "${all_zones}" rev | sort | rev)"
}

setup_domain() {
  # Domain and token from arguments
  domain="$1"
  token="$2"
  zone=""

  # Read domain parts into array
  IFS='.' read -a domain_array <<< "${domain}"

  # Find zone name, cut off subdomains until match
  for check_zone in ${all_zones}; do
    for (( j=${#domain_array[@]}-1; j>=0; j-- )); do
      if [[ "${check_zone}" = "$(join . ${domain_array[@]:j})" ]]; then
        zone="${check_zone}"
        break 2
      fi
    done
  done

  # Fallback to creating zone from arguments
  if [[ -z "${zone}" ]]; then
    zone="${domain_array[*]: -2:1}.${domain_array[*]: -1:1}"
    warn "zone not found, using '${zone}'"
  fi

  # Record name
  name="_acme-challenge.${domain}"

  # Some version incompatibilities
  if [[ "${VERSION}" -ge 1 ]]; then
    name="${name}."
    zone="${zone}."
    extra_data=""
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
        '"${extra_data}"'
      }],
      "changetype": "REPLACE"
    }]
  }'

  # Do the request
  request "PATCH" "${url}/${zone}" "${data}"
}

clean() {
  # Create the JSON string
  data='{"rrsets":[{"name":"'${name}'","type":"TXT","changetype":"DELETE"}]}'

  # Do the request
  request PATCH "${url}/${zone}" "${data}"
}

main() {
  # Main setup
  load_config
  load_zones
  setup

  # Set hook
  hook="$1"

  # Deployment of a certificate
  if [[ "${hook}" = "deploy_cert" ]]; then
    exit 0
  fi

  # Unchanged certificate
  if [[ "${hook}" = "unchanged_cert" ]]; then
    exit 0
  fi

  # Loop through arguments per 3
  for ((i=2; i<=$#; i=i+3)); do
    # Setup for this domain
    t=$(($i + 2))
    setup_domain "${!i}" "${!t}"

    # Debug output
    debug "Hook:  ${hook}"
    debug "Name:  ${name}"
    debug "Token: ${token}"
    debug "Zone:  ${zone}"

    # Deploy a token
    if [[ "${hook}" = "deploy_challenge" ]]; then
      deploy
    fi

    # Remove a token
    if [[ "${hook}" = "clean_challenge" ]]; then
      clean
    fi

    # Other actions are not implemented but will not cause an error
  done

  # Wait the requested amount of seconds when deployed
  if [[ "${hook}" = "deploy_challenge" ]] && [[ -n "${WAIT:-}" ]]; then
    debug "Waiting for ${WAIT} seconds"

    sleep "${WAIT}"
  fi
}

main "$@"
