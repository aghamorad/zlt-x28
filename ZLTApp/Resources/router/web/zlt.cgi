#!/bin/sh
# ZLT X28 web app — the small API behind /zlt/
#
# Served by the router's own web server (uhttpd) and reachable only from the
# home Wi-Fi, exactly like the stock admin page. It runs /usr/bin/vpn, so every
# action here is the same action the Mac app takes.
#
# No password is asked for: the stock panel already trusts anyone on the LAN to
# reach its login page, and this page only does what the Mac app does. It cannot
# change the SIM, the APN, the Wi-Fi, or the firmware.

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export LC_ALL=C

QS="${QUERY_STRING:-}"

param() {
    printf '%s' "$QS" | tr '&' '\n' | sed -n "s/^$1=//p" | head -n 1
}

# Percent-decode the little we accept (names are letters, digits, - and _).
urldecode() {
    printf '%b' "$(printf '%s' "$1" | sed 's/+/ /g; s/%/\\x/g')"
}

header() {
    printf 'Content-Type: application/json; charset=utf-8\r\n'
    printf 'Cache-Control: no-store\r\n'
    printf 'Connection: close\r\n\r\n'
}

# Escape a string for a JSON value. Busybox tr/sed only.
esc() {
    printf '%s' "$1" | tr '\n\r\t' '   ' | sed 's/\\/\\\\/g; s/"/\\"/g'
}

reply() {   # reply <ok:true|false> <message>
    header
    printf '{"ok":%s,"say":"%s"}\n' "$1" "$(esc "$2")"
}

fail() { reply false "$1"; }

valid_name() {
    case "$1" in
        ""|-|*[!A-Za-z0-9_-]*) return 1 ;;
    esac
    return 0
}

awg_is_on() {
    /usr/bin/vpn awg status 2>/dev/null | grep -q 'default dev awg0'
}

sb_is_on() {
    /usr/bin/vpn sb status quick 2>/dev/null | grep -q '^daemon *: *running'
}

awg_active() {
    /usr/bin/vpn awg status 2>/dev/null | sed -n 's/^config *: *//p' | head -n 1
}

sb_active() {
    /usr/bin/vpn sb status quick 2>/dev/null | sed -n 's/^link *: *//p' | head -n 1
}

status_json() {
    on=0; awg_is_on && on=1
    sb=0; sb_is_on && sb=1
    sp=0; /usr/bin/vpn awg status 2>/dev/null | grep -q '^split *: *on' && sp=1
    kl=0; /usr/bin/vpn awg status 2>/dev/null | grep -q '^kill *: *on' && kl=1
    active=$(awg_active)
    sblink=$(sb_active)
    exitip=$(/usr/bin/vpn awg status 2>/dev/null | sed -n 's/^exit IP *: *//p' | head -n 1)
    [ -n "$exitip" ] || exitip="—"

    confs=""
    for f in /etc/amneziawg/awg0.conf.*; do
        [ -f "$f" ] || continue
        n=${f##*.}
        [ "$n" = current ] && continue
        case "$n" in disabled-*|*.disabled-*) continue ;; esac
        ep=$(awk -F' *= *' 'tolower($1)=="endpoint" {print $2; exit}' "$f")
        [ -n "$ep" ] || ep="no address in this file"
        confs="$confs{\"name\":\"$(esc "$n")\",\"endpoint\":\"$(esc "$ep")\"},"
    done

    links=""
    /usr/bin/vpn sb list 2>/dev/null | while read -r n; do
        [ -n "$n" ] || continue
        printf '{"name":"%s"},' "$(esc "$n")"
    done > /tmp/zlt-web-links.$$
    links=$(cat /tmp/zlt-web-links.$$ 2>/dev/null)
    rm -f /tmp/zlt-web-links.$$

    header
    printf '{"awg":{"on":%s,"config":"%s","exit":"%s"},' "$on" "$(esc "$active")" "$(esc "$exitip")"
    printf '"sb":{"on":%s,"link":"%s"},' "$sb" "$(esc "$sblink")"
    printf '"split":%s,"kill":%s,' "$sp" "$kl"
    printf '"configs":[%s],"links":[%s]}\n' "${confs%,}" "${links%,}"
}

ACT=$(param act)

case "$ACT" in
    status|"")
        status_json
        ;;

    awg_on)
        out=$(/usr/bin/vpn awg on 2>&1)
        if awg_is_on; then reply true "$(printf '%s' "$out" | tail -n 2)";
        else fail "$(printf '%s' "$out" | tail -n 2)"; fi
        ;;
    awg_off)
        out=$(/usr/bin/vpn awg off 2>&1)
        if awg_is_on; then fail "The tunnel is still on. $(printf '%s' "$out" | tail -n 1)";
        else reply true "The VPN is off. Traffic goes straight out through the carrier."; fi
        ;;
    awg_use)
        name=$(urldecode "$(param name)")
        valid_name "$name" || { fail "That config name is not valid."; exit 0; }
        [ -f "/etc/amneziawg/awg0.conf.$name" ] || { fail "No config named $name."; exit 0; }
        was_on=0; awg_is_on && was_on=1
        out=$(/usr/bin/vpn awg use "$name" 2>&1)
        if [ "$was_on" = 1 ]; then out="$out; $(/usr/bin/vpn awg restart 2>&1 | tail -n 1)"; fi
        reply true "$(printf '%s' "$out" | tail -n 2)"
        ;;
    awg_rename)
        old=$(urldecode "$(param old)")
        new=$(urldecode "$(param new)")
        valid_name "$old" || { fail "The current config name is not valid."; exit 0; }
        valid_name "$new" || { fail "Use letters, digits, - or _ only."; exit 0; }
        [ -f "/etc/amneziawg/awg0.conf.$old" ] || { fail "No config named $old."; exit 0; }
        [ "$old" = "$new" ] && { reply true "$old kept its name."; exit 0; }
        [ ! -e "/etc/amneziawg/awg0.conf.$new" ] || { fail "There is already a config named $new."; exit 0; }
        if mv "/etc/amneziawg/awg0.conf.$old" "/etc/amneziawg/awg0.conf.$new" 2>/dev/null; then
            reply true "$old is now called $new."
        else
            fail "Could not rename $old."
        fi
        ;;
    awg_delete)
        name=$(urldecode "$(param name)")
        valid_name "$name" || { fail "That config name is not valid."; exit 0; }
        [ -f "/etc/amneziawg/awg0.conf.$name" ] || { fail "No config named $name."; exit 0; }
        if [ "$(awg_active)" = "$name" ]; then
            /usr/bin/vpn awg off >/dev/null 2>&1
            rm -f /etc/amneziawg/awg0.conf
        fi
        rm -f "/etc/amneziawg/awg0.conf.$name" /etc/amneziawg/awg0.conf."$name".disabled-*
        reply true "$name is deleted from the router."
        ;;
    split_on)
        out=$(timeout 40 /usr/bin/vpn split on 2>&1)
        reply true "$(printf '%s' "$out" | tail -n 1)"
        ;;
    split_off)
        out=$(/usr/bin/vpn split off 2>&1)
        reply true "$(printf '%s' "$out" | tail -n 1)"
        ;;
    kill_on)
        out=$(/usr/bin/vpn kill on 2>&1)
        reply true "$(printf '%s' "$out" | tail -n 1)"
        ;;
    kill_off)
        out=$(/usr/bin/vpn kill off 2>&1)
        reply true "$(printf '%s' "$out" | tail -n 1)"
        ;;
    sb_on)
        out=$(/usr/bin/vpn sb on 2>&1)
        if sb_is_on; then reply true "$(printf '%s' "$out" | tail -n 1)";
        else fail "$(printf '%s' "$out" | tail -n 2)"; fi
        ;;
    sb_off)
        out=$(/usr/bin/vpn sb off 2>&1)
        reply true "The link tunnel is off."
        ;;
    sb_use)
        name=$(urldecode "$(param name)")
        valid_name "$name" || { fail "That link name is not valid."; exit 0; }
        [ -f "/data/zltx28/singbox/links/$name.json" ] || { fail "No link named $name."; exit 0; }
        was_on=0; sb_is_on && was_on=1
        out=$(/usr/bin/vpn sb use "$name" 2>&1)
        if [ "$was_on" = 1 ]; then out="$out; $(/usr/bin/vpn sb restart 2>&1 | tail -n 1)"; fi
        reply true "$(printf '%s' "$out" | tail -n 1)"
        ;;
    sb_delete)
        name=$(urldecode "$(param name)")
        valid_name "$name" || { fail "That link name is not valid."; exit 0; }
        [ -f "/data/zltx28/singbox/links/$name.json" ] || { fail "No link named $name."; exit 0; }
        if [ "$(sb_active)" = "$name" ]; then
            /usr/bin/vpn sb off >/dev/null 2>&1
            rm -f /data/zltx28/singbox/active.json
            echo "-" > /data/zltx28/singbox/active_name
        fi
        rm -f "/data/zltx28/singbox/links/$name.json" \
              "/data/zltx28/singbox/links/$name.test.json" \
              "/data/zltx28/singbox/links/$name.link"
        rm -rf /data/zltx28/singbox/trash/"$name"-*
        reply true "$name is deleted from the router."
        ;;

    *)
        fail "Unknown action."
        ;;
esac
