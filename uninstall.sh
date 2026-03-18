#!/usr/bin/env bash
set -euo pipefail

log()  { printf '\033[1;34m→\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }

echo "Uninstalling pipesplit..."
echo ""

# Stop and disable service
log "Stopping service..."
systemctl --user disable --now pipesplit.service 2>/dev/null && ok "Service stopped" || warn "Service was not running"

# Remove files
log "Removing files..."
rm -f ~/.local/bin/pipesplit ~/.local/bin/pipesplit-router
rm -f ~/.config/systemd/user/pipesplit.service
rm -f ~/.config/pipewire/pipewire.conf.d/pipesplit.conf
rm -f ~/.local/share/applications/pipesplit.desktop
systemctl --user daemon-reload 2>/dev/null || true

echo ""
ok "Uninstalled!"
echo ""
echo "  Kept (remove manually if you want):"
echo "    ~/.config/pipesplit/routes.conf"
echo ""
echo "  Restart PipeWire to remove virtual sinks:"
echo "    systemctl --user restart pipewire"
