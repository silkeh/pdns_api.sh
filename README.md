# pdns_api.sh
A simple DNS hook that lets [Dehydrated][] talk to the PowerDNS API.

# Usage
Add the settings for your PowerDNS API to Dehydrated's `config`
(in `/etc/dehydrated` or `/usr/local/etc/dehydrated`),
or a `config` file next to `pdns_api.sh`:

```sh
PDNS_HOST=ns0.example.com
PDNS_PORT=8081            # Optional. Defaults to 8081
PDNS_KEY=secret           # API key
PDNS_SERVER=localhost     # Optional. Server for the API to use, usually `localhost`
PDNS_VERSION=1            # Optional. API version, 0 for anything under PowerDNS 4
PDNS_WAIT=300             # Optional. Delay for when slaves are slow
PDNS_ZONES_TXT            # Optional. File containing zones to use (see below).
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

[dehydrated]: https://github.com/lukas2511/dehydrated
