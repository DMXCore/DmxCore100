#!/usr/bin/env bash
#
# DMXCore100 setup script:
#   - Applies minimum kernel tunings (temporary + persistent)
#   - Connects dmxcore100 snap to: alsa, hardware-observer, network-control
#

set -u -e

# ────────────────────────────────────────────────
# Desired minimum kernel values
# ────────────────────────────────────────────────

declare -A targets=(
  ["net.ipv4.igmp_max_memberships"]=400
  ["user.max_user_namespaces"]=10000
  ["net.core.rmem_max"]=5000000
  ["net.core.wmem_max"]=5000000
)

# ────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────

die() { echo "ERROR: $*" >&2; exit 1; }

check_root() {
    [[ $EUID -eq 0 ]] || die "This script must be run as root (sudo)"
}

get_current() {
    local key="$1"
    local val
    val=$(sysctl -n "$key" 2>/dev/null | tr -d ' \t\r\n')
    [[ -n "$val" ]] || die "Cannot read sysctl: $key"
    echo "$val"
}

# ────────────────────────────────────────────────
# Kernel tunings part
# ────────────────────────────────────────────────

check_root

echo "Applying DMXCore100 minimum kernel tunings..."
echo

needs_update=()

for key in "${!targets[@]}"; do
    cur=$(get_current "$key")
    want=${targets[$key]}
    if (( cur < want )); then
        echo "  Updating $key: $cur → $want"
        sysctl -w "$key=$want" >/dev/null 2>&1 || echo "    (warning: sysctl -w failed – kernel may reject this value)"
        needs_update+=("$key=$want")
    else
        echo "  $key OK: $cur ≥ $want"
    fi
done

# Persistent config (only add entries that were actually needed / lower)
PERSIST_FILE="/etc/sysctl.d/99-dmxcore100.conf"

if (( ${#needs_update[@]} > 0 )); then
    echo
    echo "Updating persistent config → $PERSIST_FILE (adding only needed entries)"

    declare -A conf_values
    if [[ -f "$PERSIST_FILE" ]]; then
        while IFS= read -r line; do
            [[ $line =~ ^[[:blank:]]*# ]] && continue
            if [[ $line =~ ^[[:blank:]]*([a-zA-Z0-9._-]+)[[:blank:]]*=[[:blank:]]*([0-9]+)[[:blank:]]*$ ]]; then
                k="${BASH_REMATCH[1]}"
                v="${BASH_REMATCH[2]}"
                conf_values["$k"]="$v"
            fi
        done < "$PERSIST_FILE"
    fi

    # Add the ones we just raised
    for entry in "${needs_update[@]}"; do
        k=${entry%%=*} v=${entry#*=}
        conf_values["$k"]="$v"
    done

    # Write sorted
    {
        echo "# DMXCore100 minimum kernel tunings (last updated $(date '+%Y-%m-%d %H:%M:%S'))"
        for k in $(printf '%s\n' "${!conf_values[@]}" | sort); do
            echo "$k = ${conf_values[$k]}"
        done
    } | tee "$PERSIST_FILE" >/dev/null

    echo "Applying persistent settings..."
    sysctl --system >/dev/null 2>&1 && echo "  OK" || echo "  Some values may not apply immediately (check dmesg/syslog)"
else
    echo "No kernel tuning changes needed."
fi

# ────────────────────────────────────────────────
# Snap interface connections for dmxcore100
# ────────────────────────────────────────────────

echo
echo "Configuring snap interfaces for dmxcore100..."

SNAP_NAME="dmxcore100"

# Check if snap is installed
if ! snap list "$SNAP_NAME" &>/dev/null; then
    echo "Warning: Snap '$SNAP_NAME' is not installed → skipping interface connections."
    echo "         Install it first with:   sudo snap install $SNAP_NAME"
else
    declare -a interfaces=("alsa" "hardware-observe" "network-control")

    for iface in "${interfaces[@]}"; do
        # Check if already connected (plug side)
        if snap connections "$SNAP_NAME" | grep -q "^${iface}[[:space:]]\+${SNAP_NAME}:${iface}[[:space:]]\+"; then
            echo "  $SNAP_NAME:$iface already connected"
        else
            echo "  Connecting $SNAP_NAME:$iface ..."
            if sudo snap connect "$SNAP_NAME:$iface" 2>/dev/null; then
                echo "    → success"
            else
                echo "    → failed (may require manual approval, not supported, or snap confinement issue)"
                echo "      Try manually: sudo snap connect $SNAP_NAME:$iface"
            fi
        fi
    done
fi

echo
echo "Done."
echo "Kernel changes (if any) are active and persistent."
echo "Snap interfaces for dmxcore100 should now be connected (check with: snap connections $SNAP_NAME)"

exit 0
