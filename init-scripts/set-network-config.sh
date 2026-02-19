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
        val=$(sysctl -n "$key" 2>/dev/null) || die "Cannot read sysctl key: $key"
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
            sysctl -w "$key=$want" >/dev/null 2>&1 || {
                echo "Warning: sysctl -w $key=$want failed (kernel may reject or already at limit)"
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
printf "%-28s = %s\n" "user.max_user_namespaces"     "$(sysctl -n user.max_user_namespaces     2>/dev/null || echo 'unknown')"
printf "%-28s = %s\n" "net.core.rmem_max"            "$(sysctl -n net.core.rmem_max            2>/dev/null || echo 'unknown')"
printf "%-28s = %s\n" "net.core.wmem_max"            "$(sysctl -n net.core.wmem_max            2>/dev/null || echo 'unknown')"
printf "%-28s = %s\n" "net.ipv4.igmp_max_memberships" "$(cat /proc/sys/net/ipv4/igmp_max_memberships 2>/dev/null || echo 'unknown')"

# ──────────────────────────────────────────────────────────────────────────────
# Persistence
# ──────────────────────────────────────────────────────────────────────────────

PERSIST_FILE="/etc/sysctl.d/99-dmxcore100.conf"

echo
echo "Make these MINIMUM values persistent across reboots?"
echo "This will create/overwrite $PERSIST_FILE (only keys where current < desired)"
echo -n " (y/N): "
read -r answer < /dev/tty

if [[ "${answer^^}" =~ ^(Y|YES)$ ]]; then
    echo "# Minimum enforced kernel tunables (applied only if kernel allows)" | sudo tee "$PERSIST_FILE" >/dev/null

    local_igmp=$(get_current "/proc/sys/net/ipv4/igmp_max_memberships")
    [[ $local_igmp -lt $WANT_IGMP_MAX_MEMBERSHIPS ]] && \
        echo "net.ipv4.igmp_max_memberships = $WANT_IGMP_MAX_MEMBERSHIPS" | sudo tee -a "$PERSIST_FILE" >/dev/null

    local_ns=$(get_current "user.max_user_namespaces")
    [[ $local_ns -lt $WANT_MAX_USER_NAMESPACES ]] && \
        echo "user.max_user_namespaces = $WANT_MAX_USER_NAMESPACES" | sudo tee -a "$PERSIST_FILE" >/dev/null

    local_rmem=$(get_current "net.core.rmem_max")
    [[ $local_rmem -lt $WANT_RMEM_MAX ]] && \
        echo "net.core.rmem_max = $WANT_RMEM_MAX" | sudo tee -a "$PERSIST_FILE" >/dev/null

    local_wmem=$(get_current "net.core.wmem_max")
    [[ $local_wmem -lt $WANT_WMEM_MAX ]] && \
        echo "net.core.wmem_max = $WANT_WMEM_MAX" | sudo tee -a "$PERSIST_FILE" >/dev/null

    if [[ -s "$PERSIST_FILE" ]]; then
        echo "→ Written to $PERSIST_FILE"
        echo "Applying now (individual sysctl -w)..."
        failed=0

        sysctl -q -w user.max_user_namespaces="$WANT_MAX_USER_NAMESPACES"      2>/dev/null || ((failed++))
        sysctl -q -w net.core.rmem_max="$WANT_RMEM_MAX"                        2>/dev/null || ((failed++))
        sysctl -q -w net.core.wmem_max="$WANT_WMEM_MAX"                        2>/dev/null || ((failed++))
        sysctl -q -w net.ipv4.igmp_max_memberships="$WANT_IGMP_MAX_MEMBERSHIPS" 2>/dev/null || ((failed++))

        if (( failed == 0 )); then
            echo "All settings applied successfully."
        else
            echo "Warning: $failed setting(s) could not be applied right now (kernel rejected value)."
            echo "They are still saved in $PERSIST_FILE — they may apply on next boot or after config reload."
        fi
    else
        echo "No settings need persistence (all already at or above desired)."
        sudo rm -f "$PERSIST_FILE" 2>/dev/null || true
    fi
else
    echo "Skipped — changes remain temporary (until reboot)."
fi

exit 0
