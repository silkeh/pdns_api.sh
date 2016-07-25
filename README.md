# pdns_api.sh
A simple DNS hook that lets [`letsencrypt.sh`][le.sh] talk to the PowerDNS API.

# Usage
Add the settings for your PowerDNS API to
`/etc/letsencrypt.sh/config`, `/usr/local/etc/letsencrypt.sh/config`
or a `config` file next to `pdns_api.sh`:

```sh
HOST=ns0.example.com
PORT=8081            # Optional. Defaults to 8081
KEY=secret           # API key
SERVER=localhost     # Optional. Server for the API to use, usually `localhost`
VERSION=1            # Optional. API version, 0 for anything under PowerDNS 4
WAIT=300             # Optional. Delay for when slaves are slow
```

Configure it as a DNS hook, by adding the following to your `letsencrypt.sh` config:

```sh
CHALLENGETYPE="dns-01"
HOOK="./pdns_api.sh"
HOOK_CHAIN="yes"
```

Nested zones and subdomains are supported.
These zones should be detected automatically,
but can be overridden by creating a file called `zones.txt` in
`/etc/letsencrypt.sh/`, `/usr/local/etc/letsencrypt.sh/` or next to `pdns_api.sh` with the zones:

```
test.example.domain.tld
example.domain.tld
test.domain.tld
```

These zones can be added in any order.

[le.sh]: https://github.com/lukas2511/letsencrypt.sh
