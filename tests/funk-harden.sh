#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
script="$root/system/funk-harden"
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/funk-harden-test.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT

fail() {
    printf 'funk-harden test: %s\n' "$*" >&2
    exit 1
}

# Sourcing exposes the pure renderer and status checker without crossing the
# helper's root boundary or touching the live PF ruleset.
# shellcheck source=../system/funk-harden
source "$script"

fixture_ifconfig() {
    [ "$1" = en6 ]
}

physical_interfaces() {
    printf '%s\n' en0 en6
}

# The sourced helper reads these variables indirectly through its functions.
# shellcheck disable=SC2034
ifconfig=fixture_ifconfig

expected_travel='set skip on lo0
set block-policy drop
pass out all keep state
pass in quick on en0 proto udp from any port 67 to any port 68
pass in quick on en0 proto udp to 224.0.0.251 port 5353
pass in quick on en0 inet6 proto udp to ff02::fb port 5353
pass in quick on en0 inet6 proto udp from fe80::/10 port 547 to any port 546
pass in quick on en0 inet6 proto icmp6 icmp6-type { neighbrsol neighbradv routeradv routersol echoreq echorep toobig timex unreach }
block in quick on en0 all
pass in quick on en6 proto udp from any port 67 to any port 68
pass in quick on en6 proto udp to 224.0.0.251 port 5353
pass in quick on en6 inet6 proto udp to ff02::fb port 5353
pass in quick on en6 inet6 proto udp from fe80::/10 port 547 to any port 546
pass in quick on en6 inet6 proto icmp6 icmp6-type { neighbrsol neighbradv routeradv routersol echoreq echorep toobig timex unreach }
block in quick on en6 all'

travel_rules=$(render_rules travel)
[ "$travel_rules" = "$expected_travel" ] \
    || fail "travel rendering changed"
[ "$(render_rules travel)" = "$travel_rules" ] \
    || fail "travel rendering is not idempotent"

home_rules=$(render_rules home)
[ "$(render_rules home)" = "$home_rules" ] \
    || fail "home rendering is not idempotent"
home_allow='pass in quick on en6 inet from 192.168.50.0/24 to any'
[ "$(printf '%s\n' "$home_rules" | grep -Fc "$home_allow")" -eq 1 ] \
    || fail "home rendering does not contain exactly one trusted-subnet rule"
allow_line=$(line_number "$home_rules" "$home_allow")
block_line=$(block_line_number "$home_rules" en6)
[ -n "$allow_line" ] && [ -n "$block_line" ] && [ "$allow_line" -lt "$block_line" ] \
    || fail "the home allow rule does not precede the en6 quick block"
printf '%s\n' "$home_rules" | grep -F 'block in quick on en0 all' >/dev/null \
    || fail "home rendering stopped blocking an unrelated physical interface"
if printf '%s\n' "$home_rules" \
    | grep -F 'pass in quick on en0 inet from 192.168.50.0/24 to any' >/dev/null; then
    fail "home rendering trusted the subnet on an unrelated interface"
fi

active_rules=$test_dir/active.pf
posture_file=$test_dir/posture
normalized_travel_rules=$(printf '%s\n' "$travel_rules" \
    | sed 's/^block in quick /block drop in quick /')
normalized_home_rules=$(printf '%s\n' "$home_rules" \
    | sed -e 's/^block in quick /block drop in quick /' \
        -e '/^pass in quick on en6 inet from 192[.]168[.]50[.]0\/24 to any$/s/$/ flags S\/SA keep state/')
pfctl_fixture() {
    # shellcheck disable=SC2154
    case "$*" in
        '-s info')
            printf 'Status: Enabled\n'
            ;;
        "-a $anchor -sr")
            cat "$active_rules"
            ;;
        *)
            return 64
            ;;
    esac
}
# shellcheck disable=SC2034
pfctl=pfctl_fixture

printf 'travel\n' > "$posture_file"
printf '%s\n' "$normalized_travel_rules" > "$active_rules"
travel_status=$(status)
[ "$(status)" = "$travel_status" ] || fail "travel status is not idempotent"
printf '%s\n' "$travel_status" | grep -F 'Posture marker: travel' >/dev/null \
    || fail "travel status omitted its posture"
printf '%s\n' "$travel_status" | grep -F 'Home interface: en6' >/dev/null \
    || fail "travel status omitted the home interface"
printf '%s\n' "$travel_status" | grep -F 'Trusted IPv4 subnet: 192.168.50.0/24' >/dev/null \
    || fail "travel status omitted the trusted subnet"
printf '%s\n' "$travel_status" | grep -F '  en6: blocked inbound' >/dev/null \
    || fail "travel status did not report en6 as blocked"

printf 'home\n' > "$posture_file"
printf '%s\n' "$normalized_home_rules" > "$active_rules"
home_status=$(status)
[ "$(status)" = "$home_status" ] || fail "home status is not idempotent"
printf '%s\n' "$home_status" \
    | grep -F '  en6: permits inbound IPv4 from 192.168.50.0/24; otherwise blocked' >/dev/null \
    || fail "home status omitted the trusted en6 rule"
printf '%s\n' "$home_status" | grep -F '  en0: blocked inbound' >/dev/null \
    || fail "home status did not report an unrelated interface as blocked"

printf '%s\n' "$normalized_travel_rules" > "$active_rules"
if status >/dev/null 2>&1; then
    fail "status accepted travel rules with a home posture marker"
fi

bad_home_rules=$(printf '%s\n' "$home_rules" | /usr/bin/awk '
    /pass in quick on en6 inet from 192[.]168[.]50[.]0\/24 to any/ { allow=$0; next }
    { print }
    /block in quick on en6 all/ { print allow }
')
if (validate_expected_policy home "$bad_home_rules") >/dev/null 2>&1; then
    fail "validation accepted a home allow rule after the quick block"
fi

# shellcheck disable=SC2034
home_ipv4_subnet=192.168.0.0/16
if (validate_home_policy) >/dev/null 2>&1; then
    fail "validation accepted an unexpected trusted subnet"
fi

grep -F 'status|travel|home' "$root/libexec/funk-harden-client" >/dev/null \
    || fail "the client does not expose the home action"
grep -F '%s home' "$root/system/install-hardening-root" >/dev/null \
    || fail "the installer does not grant the narrow home action"
grep -F 'travel|boot)' "$script" >/dev/null \
    || fail "boot no longer selects the travel posture"

printf 'funk-harden tests passed\n'
