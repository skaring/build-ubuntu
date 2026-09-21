#!/usr/bin/env bash
# Apply desktop preferences. Idempotent. Needs a running GNOME session (not SSH / a bare TTY).
# Plain GNOME settings live in desktop.gsettings; the rest is below.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
warn() { echo "warning: $*" >&2; }

[[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] \
    || { echo "No desktop session (DBUS_SESSION_BUS_ADDRESS unset); run this from a terminal in your GNOME session." >&2; exit 1; }

# GNOME settings from desktop.gsettings
while read -r schema key value || [[ -n ${schema:-} ]]; do
    [[ -z ${schema:-} || $schema == \#* ]] && continue
    gsettings set "$schema" "$key" "$value"
done < "$DIR/desktop.gsettings"

# Default terminal: Ghostty (read by xdg-terminal-exec, which GNOME uses for terminals it launches).
if [[ -e /usr/share/applications/com.mitchellh.ghostty.desktop ]]; then
    mkdir -p ~/.config
    echo 'com.mitchellh.ghostty.desktop' > ~/.config/xdg-terminals.list
else
    warn "Ghostty is not installed; default terminal unchanged (run ./install.sh ghostty first)."
fi

# Dock: hide it by disabling the Ubuntu Dock extension.
if gnome-extensions list 2>/dev/null | grep -qx 'ubuntu-dock@ubuntu.com'; then
    gnome-extensions disable ubuntu-dock@ubuntu.com || warn "could not disable the Ubuntu Dock extension"
fi

# Default browser (Vivaldi) is set by the `vivaldi` step in install.sh.
echo "Desktop preferences applied."
