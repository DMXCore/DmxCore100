#!/usr/bin/env bash
#
# DMXCore100 minimum kernel tunings
# Applies higher values temporarily + always creates persistent config in /etc/sysctl.d/
#

set -u
set -e

# Desired minimum values
IGMP=400
NS=10000
RMEM=5000000
WMEM=5000000

die() { echo "ERROR: $*" >&2; exit 1; }

check_root() {
    [[ $EUID -eq 0 ]] || die "This script must be run as root (sudo)"
}

get_current() {
    local key="$1" val
    if [[ $key == /proc/* ]]; then
        val=$(cat "$key" 2>/dev/null) || die "Cannot read $key"
    else
        val=$(sysctl -n "$key" 2>/dev/null) || die "Cannot read $key"
    fi
    echo "${val//[[:space:]]/}"
}

set_if_higher() {
    local key="$1" want="$2" current
    current=$(get_current "$key")
    if (( current < want )); then
        echo "Setting $key: $current → $want"
        if [[ $key == /proc/* ]]; then
            echo "$want" > "$key" || die "Failed writing to $key"
        else
            sysctl -w "$key=$want" >/dev/null 2>&1 || echo "  (sysctl -w failed – kernel may reject)"
        fi
    else
        echo "$key already ≥ $want ($current)"
    fi
}

# ────────────────────────────────────────────────

check_root

echo "Applying DMXCore100 minimum tunings..."
echo

set_if_higher "/proc/sys/net/ipv4/igmp_max_memberships" "$IGMP"
set_if_higher "user.max_user_namespaces"                "$NS"
set_if_higher "net.core.rmem_max"                       "$RMEM"
set_if_higher "net.core.wmem_max"                       "$WMEM"

echo
echo "Current values:"
printf "  %-28s = %s\n" "net.ipv4.igmp_max_memberships" "$(get_current "/proc/sys/net/ipv4/igmp_max_memberships")"
printf "  %-28s = %s\n" "user.max_user_namespaces"      "$(get_current "user.max_user_namespaces")"
printf "  %-28s = %s\n" "net.core.rmem_max"             "$(get_current "net.core.rmem_max")"
printf "  %-28s = %s\n" "net.core.wmem_max"             "$(get_current "net.core.wmem_max")"

# ────────────────────────────────────────────────
# Always create persistent file
# ────────────────────────────────────────────────

CONF="/etc/sysctl.d/99-dmxcore100.conf"

echo
echo "Creating persistent config → $CONF"
cat << EOF | tee "$CONF"
# DMXCore100 minimum kernel tunings
# (kernel will ignore / warn if value is invalid or lower than allowed)

net.ipv4.igmp_max_memberships = $IGMP
user.max_user_namespaces      = $NS
net.core.rmem_max             = $RMEM
net.core.wmem_max             = $WMEM
EOF

echo "Applying persistent settings now (sysctl --system)..."
if sysctl --system >/dev/null 2>&1; then
    echo "Success – settings loaded."
else
    echo "Some warnings/errors during sysctl --system (see below)."
    echo "Individual apply attempt:"
    sysctl -w net.ipv4.igmp_max_memberships="$IGMP"     2>&1 | grep -v "setting key" || true
    sysctl -w user.max_user_namespaces="$NS"            2>&1 | grep -v "setting key" || true
    sysctl -w net.core.rmem_max="$RMEM"                 2>&1 | grep -v "setting key" || true
    sysctl -w net.core.wmem_max="$WMEM"                 2>&1 | grep -v "setting key" || true
fi

echo
echo "Done. Changes are active now and should survive reboot."
echo "(If any value didn't apply, the kernel rejected it – check dmesg or kernel logs.)"

exit 0
