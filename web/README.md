# ZLT X28 router dashboard

This package builds a self-contained Linux/ARM64 HTTP service and embeds its
static mobile interface into the binary. It has no third-party Go dependencies.

## Build and deployment

From the repository root:

```sh
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -trimpath -buildvcs=false -ldflags='-s -w' -o build/zlt-web-linux-arm64 ./web
```

The Mac app build copies that binary and `awg/zlt-web.init` into its router
payload. The existing Provisioner serves the payload over the local network;
`ZLTApp/Resources/router/install.sh` installs it to `/data/zltx28/bin`, creates
the password file once, enables the procd service, and starts it.

The dashboard listens on TCP 8080 and only accepts source addresses in
`192.168.70.0/24`. Its default URL is `http://192.168.70.1:8080`.

## Authentication

On first install the binary creates a 192-bit random hexadecimal password at
`/data/zltx28/web/password`, mode 0600 in a mode-0700 directory. The Mac
Provisioner reads it over the already-installed SSH key and prints it in the
setup log. Re-running setup preserves the password. The browser exchanges it
for a random in-memory session cookie; sessions last 12 hours and are cleared
on service restart. Login attempts are rate-limited per client IP.

The dashboard is local HTTP, not TLS. It must remain on the trusted router LAN;
do not forward port 8080 or expose it to the internet. The server rejects
clients outside the configured LAN CIDR and checks same-origin POST requests.
Only explicit VPN operations are exposed; request data is never passed to a
shell.

## API

- `GET /api/status`: both engine states, saved configs and current exit IP.
- `POST /api/vpn`: `awg|sb` and `on|off|restart`.
- `POST /api/select`: select a named saved config or sing-box link.
- `POST /api/import`: upload an AmneziaWG `.conf` or paste proxy links.
- `POST /api/remove`: move a saved config aside or use the sing-box trash path.
- `POST /api/test` and `POST /api/test-one`: run the router's existing sing-box tests.

Proxy URI parsing supports VLESS, VMess, Trojan, Shadowsocks, Hysteria2 and
SOCKS5. Link tests reuse the existing `vpn sb testall` command.

## Tests

`go test ./...` exercises the URI parsers. The dashboard CI workflow also
cross-compiles the static binary for linux/arm64 and syntax-checks the router
installer and init script.
