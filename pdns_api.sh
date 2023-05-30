#!/usr/bin/env bash

# Copyright 2016-2021 - Silke Hofstra and contributors
#
# Licensed under the EUPL
#
# You may not use this work except in compliance with the Licence.
# You may obtain a copy of the Licence at:
#
# https://joinup.ec.europa.eu/collection/eupl
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

# Config directories
CONFIG_DIRS="/etc/dehydrated /usr/local/etc/dehydrated"

# Show an error/warning
error() { echo "Error: $*" >&2; }
warn() { echo "Warning: $*" >&2; }
fatalerror() { error "$*"; exit 1; }

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
    for check_config in ${CONFIG_DIRS} "${PWD}" "${DIR}"; do
      if [[ -f "${check_config}/config" ]]; then
        CONFIG="${check_config}/config"
        break
      fi
    done
  fi

  # Check if config was set
  if [[ -z "${CONFIG:-}" ]]; then
    # Warn about missing config
    warn "No config file found, using default config!"
  elif [[ -f "${CONFIG}" ]]; then
    # shellcheck disable=SC1090
    . "${CONFIG}"
  fi

  if [[ -n "${CONFIG_D:-}" ]]; then
    if [[ ! -d "${CONFIG_D}" ]]; then
      fatalerror "The path ${CONFIG_D} specified for CONFIG_D does not point to a directory."
    fi

    # Allow globbing
    if [[ -n "${ZSH_VERSION:-}" ]]
    then
      set +o noglob
      setopt null_glob
    else
      set +f
      shopt -s nullglob
    fi

    for check_config_d in "${CONFIG_D}"/*.sh; do
      if [[ -f "${check_config_d}" ]] && [[ -r "${check_config_d}" ]]; then
        echo "# INFO: Using additional config file ${check_config_d}"
        # shellcheck disable=SC1090
        . "${check_config_d}"
      else
        fatalerror "Specified additional config ${check_config_d} is not readable or not a file at all."
      fi
    done

    # Disable globbing
    if [[ -n "${ZSH_VERSION:-}" ]]
    then
      set -o noglob
      setopt no_null_glob
    else
      set -f
      shopt -u nullglob
    fi
  fi

  # Check required settings
  [[ -n "${PDNS_HOST:-}" ]] || fatalerror "PDNS_HOST setting is required."
  [[ -n "${PDNS_KEY:-}" ]]  || fatalerror "PDNS_KEY setting is required."

  # Check optional settings
  [[ -n "${PDNS_PORT:-}" ]] || PDNS_PORT=8081
  # Check if PDNS_CURL_OPTS is unset
  [[ -n "${PDNS_CURL_OPTS+empty}" ]] || PDNS_CURL_OPTS=${CURL_OPTS:-}
}

# Load the zones from file
load_zones() {
  # Check for zones.txt in various locations
  if [[ -z "${PDNS_ZONES_TXT:-}" ]]; then
    for check_zones in ${CONFIG_DIRS} "${PWD}" "${DIR}"; do
      if [[ -f "${check_zones}/zones.txt" ]]; then
        PDNS_ZONES_TXT="${check_zones}/zones.txt"
        break
      fi
    done
  fi

  # Load zones
  all_zones=()
  if [[ -n "${PDNS_ZONES_TXT:-}" ]] && [[ -f "${PDNS_ZONES_TXT}" ]]; then
    mapfile -t all_zones < "${PDNS_ZONES_TXT}"
  fi
}

# API request
request() {
  # Request parameters
  local method url data
  method="$1"
  url="$2"
  data="$3"
  error=false

  # Perform the request
  # This is wrappend in an if to avoid the exit on error
  # shellcheck disable=SC2086
  if ! res="$(curl ${PDNS_CURL_OPTS:-} -sSfL --stderr - --request "${method}" --header "${content_header}" --header "${api_header}" --data "${data}" "${url}")"; then
    error=true
  fi

  # Debug output
  debug "# Request"
  debug "Method: ${method}"
  debug "URL: ${url}"
  debug "Data: ${data}"
  debug "Response: ${res}"

  # Abort on failed request
  if [[ "${res}" = *"error"* ]] || [[ "${error}" = true ]]; then
    fatalerror "API error: ${res}"
  fi
}

# Setup of connection settings
setup() {
  # Header values
  api_header="X-API-Key: ${PDNS_KEY}"
  content_header="Content-Type: application/json"

  # Set the URL to the host if it is a URL,
  # otherwise create it from the host and port.
  if [[ "${PDNS_HOST}" == http://* || "${PDNS_HOST}" == https://* ]]; then
    url="${PDNS_HOST}"
  else
    url="http://${PDNS_HOST}:${PDNS_PORT}"
  fi

  # Detect the version
  if [[ -z "${PDNS_VERSION:-}" ]]; then
    request "GET" "${url}/api" ""
    PDNS_VERSION="$(<<< "${res}" get_json_int_value version)"
  fi

  # Fallback to version 0
  if [[ -z "${PDNS_VERSION}" ]]; then
    PDNS_VERSION=0
  fi

  # Some version incompatibilities
  if [[ "${PDNS_VERSION}" -ge 1 ]]; then
    url="${url}/api/v${PDNS_VERSION}"
  fi

  # Detect the server
  if [[ -z "${PDNS_SERVER:-}" ]]; then
    request "GET" "${url}/servers" ""
    PDNS_SERVER="$(<<< "${res}" get_json_string_value id)"
  fi

  # Fallback to localhost
  if [[ -z "${PDNS_SERVER}" ]]; then
    PDNS_SERVER="localhost"
  fi

  # Zone endpoint on the API
  url="${url}/servers/${PDNS_SERVER}/zones"

  # Get a zone list from the API if none was set
  if [[ ${#all_zones[@]} -eq 0 ]]; then
    request "GET" "${url}" ""
    mapfile -t all_zones < <(<<< "${res//, /$',\n'}" get_json_string_value name)
  fi

  # Strip trailing dots from zones
  all_zones=("${all_zones[@]//$'.\n'/ }")
  all_zones=("${all_zones[@]%.}")

  # Sort zones to list most specific first
  mapfile -t all_zones < <(printf '%s\n' "${all_zones[@]}" | rev | sort | rev)

  # Set suffix in case of CNAME redirection
  if [[ -n "${PDNS_SUFFIX:-}" ]]; then
      suffix=".${PDNS_SUFFIX}"
  else
      suffix=""
  fi

  # Debug setup result
  debug "# Setup"
  debug "API version: ${PDNS_VERSION}"
  debug "PDNS server: ${PDNS_SERVER}"
  debug "Zones: $(printf '%s ' "${all_zones[@]}")"
  debug "Suffix: \"${suffix}\""
}

setup_domain() {
  # Domain and token from arguments
  domain="$1"
  token="$2"
  zone=""

  # Record name
  name="_acme-challenge.${domain}${suffix}"

  # Read name parts into array
  IFS='.' read -ra name_array <<< "${name}"

  # Find zone name, cut off subdomains until match
  for check_zone in "${all_zones[@]}"; do
    for (( j=${#name_array[@]}-1; j>=0; j-- )); do
      if [[ "${check_zone}" = "$(join . "${name_array[@]:j}")" ]]; then
        zone="${check_zone}"
        break 2
      fi
    done
  done

  # Fallback to creating zone from arguments
  if [[ -z "${zone}" ]]; then
    zone="${name_array[*]: -2:1}.${name_array[*]: -1:1}"
    warn "zone not found, using '${zone}'"
  fi

  # Some version incompatibilities
  if [[ "${PDNS_VERSION}" -ge 1 ]]; then
    name="${name}."
    zone="${zone}."
    extra_data=""
  else
    extra_data=",\"name\": \"${name}\", \"type\": \"TXT\", \"ttl\": 1"
  fi
}

get_records() {
  IFS=" " read -ra tokens <<< "${token}"

  for i in "${!tokens[@]}"; do
    [[ $i -ne 0 ]] && echo -n ","

    echo -n '{
    "content": "\"'"${tokens[$i]}"'\"",
    "disabled": false,
    "set-ptr": false
    '"${extra_data}"'
    }'
  done
}

deploy_rrset() {
  echo -n '{
    "name": "'"${name}"'",
    "type": "TXT",
    "ttl": 1,
    "records": ['"$(get_records)"'],
    "changetype": "REPLACE"
  }'
}

clean_rrset() {
  echo '{"name":"'"${name}"'","type":"TXT","changetype":"DELETE"}'
}

soa_edit() {
  # Show help
  if [[ $# -eq 0 ]]; then
    echo "Usage: pdns_api.sh soa_edit <zone> [SOA-EDIT] [SOA-EDIT-API]"
    exit 1
  fi

  # Get current values for zone
  request "GET" "${url}/$1" ""

  # Set variables
  if [[ $# -le 1 ]]; then
    soa_edit=$(<<< "${res}" get_json_string_value soa_edit)
    soa_edit_api=$(<<< "${res}" get_json_string_value soa_edit_api)

    echo "Current values:"
  else
    soa_edit="$2"
    if [[ $# -eq 3 ]]; then
      soa_edit_api="$3"
    else
      soa_edit_api="DEFAULT"
    fi

    echo "Setting:"
  fi

  # Display values
  echo "SOA-EDIT:     ${soa_edit}"
  echo "SOA-EDIT-API: ${soa_edit_api}"

  # Update values
  if [[ $# -ge 2 ]]; then
    request "PUT" "${url}/${1}" '{
      "soa_edit":"'"${soa_edit}"'",
      "soa_edit_api":"'"${soa_edit_api}"'",
      "kind":"'"$(<<< "${res}" get_json_string_value kind)"'"
    }'
  fi
}

exit_hook() {
  if [[ -n "${PDNS_EXIT_HOOK:-}" ]]; then
    exec ${PDNS_EXIT_HOOK}
  fi
}

deploy_cert() {
  if [[ -n "${PDNS_DEPLOY_CERT_HOOK:-}" ]]; then
    exec ${PDNS_DEPLOY_CERT_HOOK}
  fi
}

main() {
  # Set hook
  hook="$1"

  # Ignore unknown hooks
  if [[ ! "${hook}" =~ ^(deploy_challenge|clean_challenge|soa_edit|exit_hook|deploy_cert)$ ]]; then
    exit 0
  fi

  # Main setup
  load_config
  load_zones
  setup
  declare -A requests

  # Debug output
  debug "# Main"
  debug "Bash: ${BASH_VERSION}"
  debug "Args: $*"
  debug "Hook: ${hook}"

  # Interface for SOA-EDIT
  if [[ "${hook}" = "soa_edit" ]]; then
    shift
    soa_edit "$@"
    exit 0
  fi

  # Interface for exit_hook
  if [[ "${hook}" = "exit_hook" ]]; then
    shift
    exit_hook "$@"
    exit 0
  fi

  # Interface for deploy_cert
  if [[ "${hook}" = "deploy_cert" ]]; then
    deploy_cert "$@"
    exit 0
  fi

  declare -A domains
  # Loop through arguments per 3
  for ((i=2; i<=$#; i=i+3)); do
    t=$((i + 2))
    _domain="${!i}"
    _token="${!t}"

    if [[ "${_domain}" == "*."* ]]; then
      debug "Domain ${_domain} is a wildcard domain, ACME challenge will be for domain apex (${_domain:2})"
      _domain="${_domain:2}"
    fi

    domains[${_domain}]="${_token} ${domains[${_domain}]:-}"
  done

  # Loop through unique domains
  for domain in "${!domains[@]}"; do
    # Setup for this domain
    req=""
    t=${domains[${domain}]}
    setup_domain "${domain}" "${t}"

    # Debug output
    debug "# Domain"
    debug "Name:  ${name}"
    debug "Token: ${token}"
    debug "Zone:  ${zone}"

    # Add comma
    if [[ ${requests[${zone}]+x} ]]; then
      req="${requests[${zone}]},"
    fi

    # Deploy a token
    if [[ "${hook}" = "deploy_challenge" ]]; then
      requests[${zone}]="${req}$(deploy_rrset)"
    fi

    # Remove a token
    if [[ "${hook}" = "clean_challenge" ]]; then
      requests[${zone}]="${req}$(clean_rrset)"
    fi

    # Other actions are not implemented but will not cause an error
  done

  # Perform requests
  for zone in "${!requests[@]}"; do
    request "PATCH" "${url}/${zone}" '{"rrsets": ['"${requests[${zone}]}"']}'
    if [[ -z "${PDNS_NO_NOTIFY:-}" ]]; then
      request "PUT" "${url}/${zone}/notify" ''
    fi
  done

  # Wait the requested amount of seconds when deployed
  if [[ "${hook}" = "deploy_challenge" ]] && [[ -n "${PDNS_WAIT:-}" ]]; then
    debug "Waiting for ${PDNS_WAIT} seconds"

    sleep "${PDNS_WAIT}"
  fi
}

main "$@"
