#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

log()  { printf '\033[1;34m→\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }

echo "Installing pipesplit..."
echo ""

# 1. PipeWire config
log "PipeWire sink config..."
mkdir -p ~/.config/pipewire/pipewire.conf.d
cp "$SCRIPT_DIR/pipesplit.conf" ~/.config/pipewire/pipewire.conf.d/pipesplit.conf
ok "~/.config/pipewire/pipewire.conf.d/pipesplit.conf"

# 2. Route config
log "Route config..."
mkdir -p ~/.config/pipesplit
if [[ -f ~/.config/pipesplit/routes.conf ]]; then
    ok "~/.config/pipesplit/routes.conf (exists, not overwriting)"
else
    cp "$SCRIPT_DIR/routes.conf" ~/.config/pipesplit/routes.conf
    ok "~/.config/pipesplit/routes.conf"
fi

# 3. Scripts
log "Scripts..."
mkdir -p ~/.local/bin
cp "$SCRIPT_DIR/pipesplit" ~/.local/bin/pipesplit
cp "$SCRIPT_DIR/pipesplit-router" ~/.local/bin/pipesplit-router
chmod +x ~/.local/bin/pipesplit ~/.local/bin/pipesplit-router
ok "~/.local/bin/pipesplit"
ok "~/.local/bin/pipesplit-router"

# 4. Systemd service
log "Systemd service..."
mkdir -p ~/.config/systemd/user
cp "$SCRIPT_DIR/pipesplit.service" ~/.config/systemd/user/pipesplit.service
systemctl --user daemon-reload
ok "~/.config/systemd/user/pipesplit.service"

# 5. Desktop launcher
log "Desktop launcher..."
mkdir -p ~/.local/share/applications
cp "$SCRIPT_DIR/pipesplit.desktop" ~/.local/share/applications/pipesplit.desktop
ok "~/.local/share/applications/pipesplit.desktop"

echo ""
ok "Installed!"
echo ""
echo "  Next steps:"
echo ""
echo "  1. systemctl --user restart pipewire"
echo "  2. systemctl --user enable --now pipesplit"
echo "  3. pipesplit connect"
echo ""
echo "  Edit app routes:  ~/.config/pipesplit/routes.conf"
echo "  Toggle output:    pipesplit toggle"
echo "  Check status:     pipesplit status"
