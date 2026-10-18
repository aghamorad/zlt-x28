# Third-party components

The app bundle ships these pieces built by others. Each keeps its own licence.

## sing-box 1.14.3 — GPL-3.0

`Contents/Resources/router/sing-box.gz` is the upstream `linux-arm64-musl` build,
unmodified except for gzip compression. It is the VPN engine the Links page drives.

- Source: <https://github.com/SagerNet/sing-box/tree/v1.14.3>
- Licence: GNU General Public License v3.0 — <https://github.com/SagerNet/sing-box/blob/v1.14.3/LICENSE>
- SHA-256 of the uncompressed binary:
  `beefed1a2ca95c6bd1719c2177af1009e9bef215294f71a7e187b66cbafc85e0`

Because this is a GPL-3.0 binary, the release that contains it is a distribution of
GPL-3.0 code. The complete corresponding source is the upstream tag linked above, and
the build is reproducible with `./fetch-payload.sh` — same input, same binary.

## AmneziaWG (amneziawg-go, awgctl) — MIT

`Contents/Resources/router/amneziawg-go` and `awgctl` are arm64 Linux builds of
AmneziaWG, a WireGuard fork with obfuscation, derived from WireGuard LLC's MIT-licensed
code. They are exec'd as separate processes.

- Source: <https://github.com/amnezia-vpn/amneziawg-go>
- Licence: MIT (WireGuard LLC)

## Not bundled

The app contains no other third-party libraries. It is SwiftUI and Foundation, compiled
by `swiftc`; `uapipush` and `dotbridge` are small Go helpers written for this project.
