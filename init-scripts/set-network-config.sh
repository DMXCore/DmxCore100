#!/usr/bin/env bash
#
# Increases specific kernel tunables ONLY if the new value would be an improvement
# (i.e. never decreases the current setting)
#

set -u
set -e

# ──────────────────────────────────────────────────────────────────────────────
# Target values (these are the MINIMUM values we want to enforce)
# ──────────────────────────────────────────────────────────────────────────────

readonly WANT_IGMP_MAX_MEMBERSHIPS=400
readonly WANT_MAX_USER_NAMESPACES=10000
readonly WANT_RMEM_MAX=5000000
readonly WANT_WMEM_MAX=5000000

# ──────────────────────────────────────────────────────────────────────────────
# Helper functions
# ──────────────────────────────────────────────────────────────────────────────

die() {
    echo "ERROR: $*" >&2
    exit 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root (sudo)"
    fi
}

get_current() {
    local key="$1"
    local val

    if [[ $key == /proc/* ]]; then
        if [[ -r "$key" ]]; then
            val=$(<"$key") || die "Cannot read $key"
        else
            die "File not readable: $key"
        fi
    else
        # sysctl -n may return nothing or error → we handle it
        val=$(sysctl -n "$key" 2>/dev/null) || val=""
        if [[ -z "$val" ]]; then
            die "Cannot read sysctl value for $key"
        fi
    fi

    # Remove any trailing whitespace/newline just in case
    echo "${val#"${val%%[![:space:]]*}"}" | tr -d '[:space:]'
}

update_if_better() {
    local key="$1"
    local want="$2"
    local current
    local msg

    current=$(get_current "$key")

    # Compare numerically
    if (( current < want )); then
        msg="Updating $key : $current  →  $want"
        echo "$msg"

        if [[ $key == /proc/* ]]; then
            echo "$want" > "$key" || die "Failed to write to $key"
        else
            # Use sysctl -w (temporary, until reboot)
            sysctl -w "$key=$want" >/dev/null || die "sysctl -w failed for $key"
            # Optional: also print confirmation of new value
            # new=$(sysctl -n "$key" 2>/dev/null || echo "?")
            # echo "  → actually set to: $new"
        fi
    else
        echo "Keeping $key = $current  (already ≥ $want)"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Main logic
# ──────────────────────────────────────────────────────────────────────────────

check_root

echo "Checking and applying minimum required kernel tunings..."
echo

update_if_better "/proc/sys/net/ipv4/igmp_max_memberships"  "$WANT_IGMP_MAX_MEMBERSHIPS"
update_if_better "user.max_user_namespaces"                 "$WANT_MAX_USER_NAMESPACES"
update_if_better "net.core.rmem_max"                        "$WANT_RMEM_MAX"
update_if_better "net.core.wmem_max"                        "$WANT_WMEM_MAX"

echo
echo "Done. The following values are now at least as requested:"
echo "──────────────────────────────────────────────────────────────"
sysctl -n user.max_user_namespaces          | awk '{printf "user.max_user_namespaces     = %10s\n", $1}'
sysctl -n net.core.rmem_max                 | awk '{printf "net.core.rmem_max            = %10s\n", $1}'
sysctl -n net.core.wmem_max                 | awk '{printf "net.core.wmem_max            = %10s\n", $1}'
cat /proc/sys/net/ipv4/igmp_max_memberships | awk '{printf "net.ipv4.igmp_max_memberships = %10s\n", $1}'
echo "──────────────────────────────────────────────────────────────"

exit 0
