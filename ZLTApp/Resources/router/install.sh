#!/bin/sh
# ZLT X28 — install the VPN engine on a rooted router.
# The app runs this on the router with its own download address as the argument:
#   sh /tmp/zlt-install.sh http://192.168.70.195:8137
#
# Nothing here is destructive: the current VPN config is never touched.
#
# The router's own filesystem (/overlay) is only 22.8 MB on the X28 and is shared
# with the firmware's own settings. The engine's four large programs go to /data
# instead (270 MB free) and are linked into /usr/bin, so everything that calls
# /usr/bin/<name> keeps working. Only the small shell scripts live in /usr/bin.

set -u

BASE=${1:-}
if [ -z "$BASE" ]; then
    echo "FAILED: no download address supplied"
    exit 1
fi

ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ]; then
    echo "FAILED: this router reports $ARCH, not aarch64"
    exit 1
fi

for tool in ip iptables awk; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "FAILED: $tool is missing from this firmware"
        exit 1
    fi
done

# Earlier versions of this installer left backups of its own files behind, which
# is what filled this router's tiny root filesystem. They are ours, not the
# firmware's, so they can go.
for old in /usr/bin/amneziawg-go.bak-zlt /usr/bin/awgctl.bak-zlt \
           /usr/bin/uapipush.bak-zlt /usr/bin/dotbridge.bak-zlt \
           /usr/bin/vpn.bak-zlt /usr/bin/vpn-keepalive.bak-zlt \
           /etc/init.d/amneziawg.bak-zlt; do
    [ -f "$old" ] && rm -f "$old"
done

PROGRAM_DIR=/data/zltx28/bin
if ! mkdir -p "$PROGRAM_DIR" 2>/dev/null || ! touch "$PROGRAM_DIR/.writable" 2>/dev/null; then
    echo "Note: /data is not writable, falling back to /usr/bin."
    PROGRAM_DIR=/usr/bin
fi
rm -f "$PROGRAM_DIR/.writable"
mkdir -p /etc/amneziawg /var/run/amneziawg /usr/bin /data/zltx28

free_kb() { df -k "$1" 2>/dev/null | awk 'NR==2 {print $4}'; }
NEED_KB=4096
HAVE_KB=$(free_kb "$PROGRAM_DIR")
if [ -n "$HAVE_KB" ] && [ "$HAVE_KB" -lt "$NEED_KB" ]; then
    echo "FAILED: not enough free space in $PROGRAM_DIR (${HAVE_KB} KB free)"
    exit 1
fi

TMP=/tmp/zlt-install.$$
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

fetch() {  # fetch <remote-name> <local-path>
    if command -v curl >/dev/null 2>&1; then
        curl -fsS --max-time 180 "$BASE/$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$2" "$BASE/$1"
    else
        echo "FAILED: neither curl nor wget is available"
        return 1
    fi
}

place() {  # place <remote-name> <destination> <mode>
    src=$TMP/$1
    if ! fetch "$1" "$src"; then
        echo "FAILED: could not download $1"
        return 1
    fi
    if [ ! -s "$src" ]; then
        echo "FAILED: $1 arrived empty"
        return 1
    fi
    if [ -f "$2" ] && cmp -s "$src" "$2"; then
        echo "already current: $2"
        chmod "$3" "$2" 2>/dev/null
        return 0
    fi
    tmp="$2.zlt-new"
    if ! cp "$src" "$tmp" 2>/dev/null; then
        echo "FAILED: could not write $2"
        return 1
    fi
    chmod "$3" "$tmp"
    mv -f "$tmp" "$2" || { echo "FAILED: could not replace $2"; return 1; }
    echo "installed $2  ($(wc -c < "$2" | tr -d ' ') bytes)"
}

link_program() {  # link_program <remote-name>
    name=$1
    if ! place "$name" "$PROGRAM_DIR/$name" 755; then
        return 1
    fi
    ln -sf "$PROGRAM_DIR/$name" /usr/bin/$name
    # A real file from an older install would shadow the link.
    [ -f /usr/bin/$name ] && [ ! -L /usr/bin/$name ] && rm -f /usr/bin/$name \
        && ln -sf "$PROGRAM_DIR/$name" /usr/bin/$name
    echo "linked /usr/bin/$name"
}

echo "Downloading the VPN engine…"
link_program amneziawg-go  || exit 1
link_program awgctl       || exit 1
link_program uapipush     || exit 1
link_program dotbridge    || exit 1
place vpn              /usr/bin/vpn              755 || exit 1
place vpn-keepalive    /usr/bin/vpn-keepalive    755 || exit 1
place amneziawg.init   /etc/init.d/amneziawg     755 || exit 1

# The link engine. 86 MB on disk, so it is streamed off the Mac already
# compressed and unpacked straight into place — /tmp on this router is RAM.
SB_VERSION=1.14.3
if [ -x "$PROGRAM_DIR/sing-box" ] && "$PROGRAM_DIR/sing-box" version 2>/dev/null \
        | grep -q "$SB_VERSION"; then
    echo "sing-box $SB_VERSION already installed"
else
    echo "Installing the link engine (sing-box $SB_VERSION, about 86 MB)…"
    if ! ( curl -fsS --max-time 600 "$BASE/sing-box.gz" | gunzip -c \
            > "$PROGRAM_DIR/sing-box.zlt-new" ); then
        echo "FAILED: could not download or unpack sing-box"
        rm -f "$PROGRAM_DIR/sing-box.zlt-new"
        exit 1
    fi
    chmod 755 "$PROGRAM_DIR/sing-box.zlt-new"
    "$PROGRAM_DIR/sing-box.zlt-new" version 2>/dev/null | head -1
    mv -f "$PROGRAM_DIR/sing-box.zlt-new" "$PROGRAM_DIR/sing-box" || \
        { echo "FAILED: could not replace sing-box"; exit 1; }
fi
ln -sf "$PROGRAM_DIR/sing-box" /usr/bin/sing-box
place singbox.init /etc/init.d/singbox 755 || exit 1
mkdir -p /data/zltx28/singbox/links /data/zltx28/singbox/trash

sync
echo "ZLT_INSTALL_OK"
