# pdns_api.sh
[![Build Status](https://travis-ci.com/silkeh/pdns_api.sh.svg?branch=master)](https://travis-ci.com/silkeh/pdns_api.sh)

A simple DNS hook that lets [Dehydrated][] talk to the PowerDNS API.

# Usage
## Configuration
Add the settings for your PowerDNS API to Dehydrated's `config`
(in `/etc/dehydrated` or `/usr/local/etc/dehydrated`),
or a `config` file next to `pdns_api.sh`:

```sh
PDNS_HOST=ns0.example.com # API Host. Can also be a URL, eg: http://ns0.example.com:8081
PDNS_PORT=8081            # Optional. Defaults to 8081
PDNS_KEY=secret           # API key
PDNS_SERVER=localhost     # Optional. Server for the API to use, usually `localhost`
PDNS_VERSION=1            # Optional. API version, 0 for anything under PowerDNS 4
PDNS_WAIT=300             # Optional. Delay for when slaves are slow
PDNS_ZONES_TXT=zones.txt  # Optional. File containing zones to use (see below).
PDNS_NO_NOTIFY=yes        # Optional. Disable sending a notification after updating the zone.
PDNS_SUFFIX=v.example.com # Optional. When using a dedicated validation zone via CNAME redirection
PDNS_CURL_OPTS="-k"       # Optional. Pass some options to curl
                          #   CURL_OPTS variable will be used if PDNS_CURL_OPTS undefined
                          #   To ignore CURL_OPTS you could set PDNS_CURL_OPTS to empty string
```

Configure the DNS hook by adding the following to your Dehydrated config:

```sh
CHALLENGETYPE="dns-01"
HOOK="./pdns_api.sh"
HOOK_CHAIN="yes"
```

Nested zones and subdomains are supported.
These zones should be detected automatically,
but can be overridden by creating a file called `zones.txt` in
`/etc/dehydrated`, `/usr/local/etc/dehydrated`
or next to `pdns_api.sh` with the zones:

```
test.example.domain.tld
example.domain.tld
test.domain.tld
```

These zones can be added in any order.

## Incrementing the zone's serial
PowerDNS can automatically increment the serial in the SOA record with the [SOA-EDIT][] metadata entry.
`pdns_api.sh` can show and edit this entry.
Usage:

```sh
pdns_api.sh soa_edit <zone> [soa-edit] [soa-edit-api]
```

## Hook chaining

`pdns_api.sh` has limited support for chaining hooks.
This can be used to, for example, reload your webserver or execute your own script.

Note that arguments passed to `pdns_api.sh` are not passed to the hook, and complex scripting is not supported.
Extend the [example hook] with a call to `pdns_api.sh "$@"` for anything more complex than reloading service or calling a script.

The hooks are available for `deploy_cert` and `exit_hook`, for example:

```
PDNS_DEPLOY_CERT_HOOK="/bin/systemctl reload nginx"
PDNS_EXIT_HOOK="/usr/local/bin/my-dehydrated-script.sh"
```

[dehydrated]:   https://github.com/dehydrated-io/dehydrated
[example hook]: https://github.com/dehydrated-io/dehydrated/blob/master/docs/examples/hook.sh
[SOA-EDIT]:     https://doc.powerdns.com/authoritative/dnssec/operational.html#soa-edit-ensure-signature-freshness-on-slaves
