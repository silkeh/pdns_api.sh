# pdns_api.sh
A simple DNS hook that lets [`letsencrypt.sh`][le.sh] talk to the PowerDNS API.

# Usage
Add the settings for your PowerDNS API to
`/etc/letsencrypt.sh/config`, `/usr/local/etc/letsencrypt.sh/config`
or a `config` file next to `pdns_api.sh`:

```sh
HOST=ns0.example.com
PORT=8081
KEY=secret           # API key
VERSION=1            # API version, 0 for anything under PowerDNS 4.
SERVER=localhost     # Server for the API to use, usually `localhost`
WAIT=300             # Optional, for when slaves are slow
```

Configure it as a DNS hook, by adding the following to your `letsencrypt.sh` config:

```sh
CHALLENGETYPE="dns-01"
HOOK="./pdns_api.sh"
HOOK_CHAIN="yes"
```

[le.sh]: https://github.com/lukas2511/letsencrypt.sh
