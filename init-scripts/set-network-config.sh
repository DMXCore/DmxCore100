#!/usr/bin/env bash
# DMXCore100 minimum kernel tunings - safe & idempotent

set -u -e

declare -A targets=(
  ["net.ipv4.igmp_max_memberships"]=400
  ["user.max_user_namespaces"]=10000
  ["net.core.rmem_max"]=5000000
  ["net.core.wmem_max"]=5000000
)

die() { echo "ERROR: $*"; exit 1; }
[[ $EUID -eq 0 ]] || die "Run with sudo"

get() {
  sysctl -n "$1" 2>/dev/null | tr -d ' \t\r\n'
}

needs_update=()

echo "Checking DMXCore100 tunings..."

for key in "${!targets[@]}"; do
  cur=$(get "$key")
  want=${targets[$key]}
  if [[ -z "$cur" ]]; then
    echo "  $key: cannot read current value"
    continue
  fi
  if (( cur < want )); then
    echo "  Updating $key: $cur → $want"
    sysctl -w "$key=$want" >/dev/null 2>&1 || echo "    (failed - kernel may reject)"
    needs_update+=("$key=$want")
  else
    echo "  $key OK: $cur ≥ $want"
  fi
done

conf="/etc/sysctl.d/99-dmxcore100.conf"

if (( ${#needs_update[@]} > 0 )); then
  echo
  echo "Updating persistent file $conf (adding only needed entries)"

  declare -A conf_values
  if [[ -f "$conf" ]]; then
    while IFS= read -r line; do
      [[ $line =~ ^# ]] && continue
      [[ $line =~ ^[[:blank:]]*([a-zA-Z0-9._]+)[[:blank:]]*=[[:blank:]]*([0-9]+) ]] || continue
      conf_values["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
    done < "$conf"
  fi

  for entry in "${needs_update[@]}"; do
    k=${entry%%=*} v=${entry#*=}
    conf_values["$k"]="$v"
  done

  {
    echo "# DMXCore100 minimum tunings (added $(date '+%Y-%m-%d'))"
    for k in $(printf '%s\n' "${!conf_values[@]}" | sort); do
      echo "$k = ${conf_values[$k]}"
    done
  } | tee "$conf" >/dev/null

  echo "Applying now..."
  sysctl --system >/dev/null 2>&1 && echo "OK" || echo "Some values may not apply (check sysctl output)"
else
  echo "No changes needed - all at or above minimums."
fi

echo "Done."
