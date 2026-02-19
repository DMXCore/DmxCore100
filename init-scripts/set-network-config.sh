#!/usr/bin/env bash
#
# Increases specific kernel tunables ONLY if the new value is higher than current.
# Optionally makes the minimum values persistent via /etc/sysctl.d/
#

set -u
set -e

# Target MINIMUM values we want to enforce
readonly WANT_IGMP_MAX_MEMBERSHIPS=400
readonly WANT_MAX_USER_NAMESPACES=10000
readonly WANT_RMEM_MAX=5000000
readonly WANT_WMEM_MAX=5000000

die() { echo "ERROR: $*" >&2; exit 1; }

check_root() {
    [[ $EUID -eq 0 ]] || die "This script must be run as root (sudo)"
}

get_current() {
    local key="$1" val
    if [[ $key == /proc/* ]]; then
        [[ -r "$key" ]] || die "Cannot read $key"
        val=$(<"$key")
    else
        val=$(sysctl -n "$key" 2>/dev/null) || die "Cannot read $key"
    fi
    echo "${val//[[:space:]]/}"   # trim whitespace
}

update_if_better() {
    local key="$1" want="$2" current msg
    current=$(get_current "$key")
    if (( current < want )); then
        echo "Updating $key: $current → $want"
        if [[ $key == /proc/* ]]; then
            echo "$want" > "$key" || die "Write failed: $key"
        else
            sysctl -w "$key=$want" >/dev/null || {
                echo "Warning: sysctl -w $key=$want failed (kernel may reject this value)"
            }
        fi
    else
        echo "Keeping $key = $current (already ≥ $want)"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────

check_root

echo "Checking and applying minimum kernel tunings..."
echo

update_if_better "/proc/sys/net/ipv4/igmp_max_memberships" "$WANT_IGMP_MAX_MEMBERSHIPS"
update_if_better "user.max_user_namespaces"                "$WANT_MAX_USER_NAMESPACES"
update_if_better "net.core.rmem_max"                       "$WANT_RMEM_MAX"
update_if_better "net.core.wmem_max"                       "$WANT_WMEM_MAX"

echo
echo "Current values after changes:"
sysctl -n user.max_user_namespaces          | awk '{printf "%-28s = %s\n" ,"user.max_user_namespaces"     ,$0}'
sysctl -n net.core.rmem_max                 | awk '{printf "%-28s = %s\n" ,"net.core.rmem_max"            ,$0}'
sysctl -n net.core.wmem_max                 | awk '{printf "%-28s = %s\n" ,"net.core.wmem_max"            ,$0}'
cat /proc/sys/net/ipv4/igmp_max_memberships | awk '{printf "%-28s = %s\n" ,"net.ipv4.igmp_max_memberships",$0}'

# ──────────────────────────────────────────────────────────────────────────────
# Persistence (only if values are actually usable)
# ──────────────────────────────────────────────────────────────────────────────

PERSIST_FILE="/etc/sysctl.d/99-custom-minimums.conf"

echo
echo "Make these MINIMUM values persistent across reboots?"
echo "This will create/overwrite $PERSIST_FILE (only keys that can be set higher are included)"
echo -n " (y/N): "
read -r answer < /dev/tty

if [[ "${answer^^}" =~ ^(Y|YES)$ ]]; then
    echo "# Minimum enforced kernel tunables (only applied if kernel accepts ≥ current)" | sudo tee "$PERSIST_FILE" >/dev/null

    # Only write keys that are actually settable / higher
    current_igmp=$(get_current "/proc/sys/net/ipv4/igmp_max_memberships")
    [[ $current_igmp -lt $WANT_IGMP_MAX_MEMBERSHIPS ]] && \
        echo "net.ipv4.igmp_max_memberships = $WANT_IGMP_MAX_MEMBERSHIPS" | sudo tee -a "$PERSIST_FILE" >/dev/null

    current_ns=$(get_current "user.max_user_namespaces")
    [[ $current_ns -lt $WANT_MAX_USER_NAMESPACES ]] && \
        echo "user.max_user_namespaces = $WANT_MAX_USER_NAMESPACES" | sudo tee -a "$PERSIST_FILE" >/dev/null

    current_rmem=$(get_current "net.core.rmem_max")
    [[ $current_rmem -lt $WANT_RMEM_MAX ]] && \
        echo "net.core.rmem_max = $WANT_RMEM_MAX" | sudo tee -a "$PERSIST_FILE" >/dev/null

    current_wmem=$(get_current "net.core.wmem_max")
    [[ $current_wmem -lt $WANT_WMEM_MAX ]] && \
        echo "net.core.wmem_max = $WANT_WMEM_MAX" | sudo tee -a "$PERSIST_FILE" >/dev/null

    if [[ -s "$PERSIST_FILE" ]]; then
        echo "→ Written to $PERSIST_FILE (only applicable settings)"
        echo "Applying now (individual sysctl -w)..."
        local failed=0
        sysctl -q -w user.max_user_namespaces="$WANT_MAX_USER_NAMESPACES"      2>/dev/null || ((failed++))
        sysctl -q -w net.core.rmem_max="$WANT_RMEM_MAX"                        2>/dev/null || ((failed++))
        sysctl -q -w net.core.wmem_max="$WANT_WMEM_MAX"                        2>/dev/null || ((failed++))
        sysctl -q -w net.ipv4.igmp_max_memberships="$WANT_IGMP_MAX_MEMBERSHIPS" 2>/dev/null || ((failed++))
        (( failed == 0 )) && echo "All settings applied successfully." \
                          || echo "Warning: $failed setting(s) could not be applied (kernel rejected value)."
    else
        echo "No settings need persistence (all already ≥ desired or rejected by kernel)."
        sudo rm -f "$PERSIST_FILE" 2>/dev/null
    fi
else
    echo "Skipped — changes remain temporary (until reboot)."
fi

exit 0
