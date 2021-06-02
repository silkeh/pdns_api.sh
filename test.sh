#!/usr/bin/env bash

# Copyright 2016-2018 - Silke Hofstra and contributors
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
set -euo pipefail

# Settings for the test
export DEBUG=
export CONFIG="/dev/null"

# Override commands
export PATH="tests:$PATH"

# Go to correct directory
cd "$(dirname "$0")"

# Show bash version
echo "Testing using Bash ${BASH_VERSION}"

# Failure count
FAILURES=0

# Test utilities
_TEST() {
  echo -e "${1}"
}
_SUBTEST() {
  echo -n " + ${1} "
}
_COLOR() {
  c="$1"
  shift
  echo -e "\\u001B[${c}m$*\\u001B[0m"
}
_PASS() {
  echo -e "\\t[$(_COLOR 32 PASS)]"
}
_FAIL() {
  echo -e "\\t[$(_COLOR 31 FAIL)]"
  FAILURES=$((FAILURES+1))
}
_EXP() {
  echo -e "$(_COLOR 33 EXPECTED)\\n"\
    "$1\\n" \
    "$(_COLOR 33 GOT)\\n" \
    "$2\\n" \
    "---"
}
_MATCH() {
  out="$1"
  shift
  mat="$*"
  _out="${out//[[:space:]]/}"
  _mat="${mat//[[:space:]]/}"

  if [ "$_out" = "$_mat" ]; then
    _PASS
  else
    _FAIL
    if [[ -n "${VERBOSE:-}" ]]; then
      _EXP "$mat" "$out"
    fi
  fi
}
_RUN() {
  if [[ -n "${SKIP_ALL:-}" ]]; then
    _SKIP
    return
  fi

  IFS=" " read -ra args <<< "$1"

  out=$(./pdns_api.sh "${args[@]}" 2>&1)
  shift
  _MATCH "$out" "$@"
}
_SKIP() {
   echo -e "\\t[$(_COLOR 34 SKIPPED)]"
}
_SKIP_ALL() {
  export SKIP_ALL=1
}
_RELOAD_CONFIG() {
  source tests/config
  if [[ $# -gt 0 ]]; then
    export PDNS_VERSION="$1"
  fi
  export SKIP_ALL=
}

# Run all tests
if [ $# -eq 0 ]; then
  # Run the tests in the tests folder
  for test in tests/*.sh; do
    _RELOAD_CONFIG
    # shellcheck source=/dev/null
    source "${test}"
  done

  # Run the tests for API versions
  for version in {1..1}; do
    echo "=> API version ${version}"
    for test in "tests/v${version}"/*.sh; do
      _RELOAD_CONFIG "${version}"
      # shellcheck source=/dev/null
      source "${test}"
    done
  done
else
  # Run the given tests
  for test in "$@"; do
    _RELOAD_CONFIG
    # shellcheck source=/dev/null
    source "${test}"
  done
fi

echo "Tests complete: ${FAILURES} failures."

exit ${FAILURES}
