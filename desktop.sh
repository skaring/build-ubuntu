#!/usr/bin/env bash
# Apply desktop preferences. Idempotent. Needs a running GNOME session (not SSH / a bare TTY).
# Plain GNOME settings live in desktop.gsettings; the rest is below.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
warn() { echo "warning: $*" >&2; }

# add_custom_keybinding <id> <name> <command> <binding>: create/update a GNOME custom shortcut and
# append it to the list of custom shortcuts (keeps any others you have added by hand).
add_custom_keybinding() {
    local id=$1 name=$2 cmd=$3 binding=$4
    local key=org.gnome.settings-daemon.plugins.media-keys
    local path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/$id/"
    local list; list="$(gsettings get "$key" custom-keybindings)"
    if [[ $list != *"'$path'"* ]]; then
        if [[ $list == '@as []' || $list == '[]' ]]; then list="['$path']"; else list="${list%]}, '$path']"; fi
        gsettings set "$key" custom-keybindings "$list"
    fi
    gsettings set "$key.custom-keybinding:$path" name "$name"
    gsettings set "$key.custom-keybinding:$path" command "$cmd"
    gsettings set "$key.custom-keybinding:$path" binding "$binding"
}

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

# Screenshot with annotation: Super+Shift+S -> ksnip, rectangular area.
if command -v ksnip >/dev/null 2>&1; then
    add_custom_keybinding ksnip "Screenshot (ksnip)" "ksnip -r" "<Super><Shift>s"
else
    warn "ksnip is not installed; Super+Shift+S not bound (run ./install.sh ksnip first)."
fi

# No audible bell in terminals. Ptyxis (Ubuntu's stock terminal) has its own setting; skip if it is not installed.
if gsettings list-schemas | grep -qx 'org.gnome.Ptyxis'; then
    gsettings set org.gnome.Ptyxis audible-bell false
fi
# Ghostty: turn off the audio and system beep explicitly (title/attention cues stay, they are silent).
ghostty_cfg=~/.config/ghostty/config.ghostty
mkdir -p ~/.config/ghostty
if ! grep -qxF '# >>> build-ubuntu: no audible bell >>>' "$ghostty_cfg" 2>/dev/null; then
    cat >> "$ghostty_cfg" <<'GHOSTTY'
# >>> build-ubuntu: no audible bell >>>
bell-features = no-audio,no-system,attention,title
# <<< build-ubuntu: no audible bell <<<
GHOSTTY
fi

# Default browser (Vivaldi) is set by the `vivaldi` step in install.sh.
echo "Desktop preferences applied."
