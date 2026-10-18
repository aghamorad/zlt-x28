#!/bin/bash
# Puts the sing-box build the app ships into build/sing-box.gz.
#
# It is not committed: it is a 30 MB gzip of an 86 MB upstream binary, and it is
# the same file SagerNet publishes, so the repo points at the release instead of
# carrying a copy. The hash below is the musl build that was run on the router;
# the release workflow checks it too, so a changed upstream asset stops a release
# instead of silently shipping something untested.
set -euo pipefail

VERSION="1.14.3"
SHA256="beefed1a2ca95c6bd1719c2177af1009e9bef215294f71a7e187b66cbafc85e0"
URL="https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-linux-arm64-musl.tar.gz"

cd "$(dirname "$0")"
mkdir -p build

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Downloading sing-box ${VERSION} (linux-arm64-musl)…"
curl -fsSL -o "$WORK/sb.tar.gz" "$URL"
tar -xzf "$WORK/sb.tar.gz" -C "$WORK"
BIN="$WORK/sing-box-${VERSION}-linux-arm64-musl/sing-box"

ACTUAL="$(shasum -a 256 "$BIN" | cut -d' ' -f1)"
if [ "$ACTUAL" != "$SHA256" ]; then
    echo "The downloaded sing-box is not the build this app was tested with." >&2
    echo "  expected $SHA256" >&2
    echo "  got      $ACTUAL" >&2
    exit 1
fi

gzip -9 -c "$BIN" > build/sing-box.gz
echo "Wrote build/sing-box.gz ($(du -h build/sing-box.gz | cut -f1))"
