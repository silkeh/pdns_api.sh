#!/bin/bash

export PDNS_EXIT_HOOK="/bin/echo exit hook test"
export PDNS_DEPLOY_CERT_HOOK="/bin/echo deploy cert test"

_TEST "Hooks"
_SUBTEST "exit"
_RUN 'exit_hook ERROR' \
     'exit hook test'

_SUBTEST "deploy"
_RUN 'deploy_cert DOMAIN KEYFILE CERTFILE FULLCHAINFILE CHAINFILE TIMESTAMP' \
     'deploy cert test'


export PDNS_EXIT_HOOK="/bin/false"
export PDNS_DEPLOY_CERT_HOOK="/bin/false"

_TEST "Hook errors"
_SUBTEST "exit"
_RUN 'exit_hook ERROR' \
     'exit=1'

_SUBTEST "deploy"
_RUN 'deploy_cert DOMAIN KEYFILE CERTFILE FULLCHAINFILE CHAINFILE TIMESTAMP' \
     'exit=1'


# These versions work fine, but the exit code is different.
# This results in a test failure that can be ignored.
if [[ "${BASH_VERSION}" < "4.4." ]]
then
    _SKIP_ALL
fi

export PDNS_EXIT_HOOK="/Foo3Xeiz"
export PDNS_DEPLOY_CERT_HOOK="/dah5Aiph"

_TEST "Hook invalid scripts"
_SUBTEST "exit"
_RUN 'exit_hook ERROR' \
     './pdns_api.sh: line 369: /Foo3Xeiz: No such file or directory' \
     'exit=127'

_SUBTEST "deploy"
_RUN 'deploy_cert DOMAIN KEYFILE CERTFILE FULLCHAINFILE CHAINFILE TIMESTAMP' \
     './pdns_api.sh: line 375: /dah5Aiph: No such file or directory' \
     'exit=127'
