#!/usr/bin/env bash
#
# DMXCore100 minimum kernel tunings
# Applies higher values temporarily if needed.
# Updates persistent config only if necessary, preserving existing settings.
#

set -u
set -e

# Desired minimum values (as associative array)
declare -A wants
wants["net.ipv4.igmp_max_memberships"]=400
wants["user.max_user_namespaces"]=10000
wants["net.core.rmem_max"]=5000000
wants["net.core.wmem_max"]=5000000

die() { echo "ERROR: $*" >&2; exit 1; }

check_root() {
    [[ $EUID -eq 0 ]] || die "This script must be run as root (sudo)"
}

get_current() {
    local key="$1"
    val=$(sysctl -n "$key" 2>/dev/null) || die "Cannot read sysctl key: $key"
    echo "${val//[[:space:]]/}"  # trim whitespace
}

set_if_higher() {
    local key="$1" current
    current=$(get_current "$key")
    if (( current < wants[key] )); then
        echo "Setting $key: $current → ${wants[$key]}"
        sysctl -w "$key=${wants[$key]}" >/dev/null 2>&1 || echo "  (sysctl -w failed – kernel may reject)"
        return 0  # needs persistence
    else
        echo "$key already ≥ ${wants[$key]} ($current)"
        return 1  # no need
    fi
}

# ────────────────────────────────────────────────

check_root

echo "Applying DMXCore100 minimum tunings..."
echo

needed=()
for key in "${!wants[@]}"; do
    if set_if_higher "$key"; then
        needed+=("$key")
    fi
done

echo
echo "Current values:"
for key in "${!wants[@]}"; do
    printf "  %-28s = %s\n" "$key" "$(get_current "$key")"
done

# ────────────────────────────────────────────────
# Persistent config (only update if needed, preserve existing)
# ────────────────────────────────────────────────

PERSIST_FILE="/etc/sysctl.d/99-dmxcore100.conf"

if [ ${#needed[@]} -gt 0 ]; then
    # Read existing if file exists
    declare -A existing
    if [ -f "$PERSIST_FILE" ]; then
        while read -r line; do
            line="${line%%#*}"  # remove comment
            if [[ $line =~ ^[[:space:]]*([a-z0-9._-]+)[[:space:]]*=[[:space:]]*([0-9]+)[[:space:]]*$ ]]; then
                k="${BASH_REMATCH[1]}"
                v="${BASH_REMATCH[2]}"
                existing["$k"]="$v"
            fi
        done < "$PERSIST_FILE"
    fi

    # Add/update the needed ones
    for need in "${needed[@]}"; do
        existing["$need"]="${wants[$need]}"
    done

    # Write back (create/overwrite with all current entries)
    {
        echo "# DMXCore100 minimum kernel tunings"
        echo "# (only sets values where needed to enforce minimums)"
        for k in $(printf '%s\n' "${!existing[@]}" | sort); do  # sorted for consistency
            echo "$k = ${existing[$k]}"
        done
    } > "$PERSIST_FILE"

    echo
    echo "Updated persistent config → $PERSIST_FILE"

    # Apply immediately
    echo "Applying persistent settings now (sysctl --system)..."
    if sysctl --system >/dev/null 2>&1; then
        echo "Success – settings loaded."
    else
        echo "Some warnings/errors during sysctl --system."
        echo "Individual apply attempt:"
        for key in "${needed[@]}"; do
            sysctl -w "$key=${wants[$key]}" 2>&1 || true
        done
    fi
else
    echo
    echo "No persistence changes needed (all values already meet or exceed minimums)."
fi

echo
echo "Done. Changes (if any) are active now and should survive reboot."

exit 0
