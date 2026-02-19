# ──────────────────────────────────────────────────────────────────────────────
# Make persistent (optional)
# ──────────────────────────────────────────────────────────────────────────────

PERSIST_FILE="/etc/sysctl.d/99-custom-minimums.conf"

echo
echo "Make these minimum values persistent across reboots?"
echo "This will create/overwrite $PERSIST_FILE"
echo -n " (y/N): "
read -r answer

if [[ "${answer^^}" =~ ^(Y|YES)$ ]]; then
    cat << EOF | sudo tee "$PERSIST_FILE" >/dev/null
# Minimum required kernel tunables - enforced at boot

net.ipv4.igmp_max_memberships = $WANT_IGMP_MAX_MEMBERSHIPS
user.max_user_namespaces      = $WANT_MAX_USER_NAMESPACES
net.core.rmem_max             = $WANT_RMEM_MAX
net.core.wmem_max             = $WANT_WMEM_MAX
EOF

    echo "→ Written to $PERSIST_FILE"
    echo "Applying now..."
    sudo sysctl --system >/dev/null && echo "Done — settings should survive reboot." \
               || echo "Warning: sysctl --system had issues — check file syntax."
else
    echo "Skipped — changes are temporary only."
fi
