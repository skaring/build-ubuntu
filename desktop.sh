#!/usr/bin/env bash
# Apply desktop preferences. Idempotent. Needs a running GNOME session (not SSH / a bare TTY).
# Plain GNOME settings live in desktop.gsettings; the rest is below.
# Usage: ./desktop.sh [--dry-run]   (--dry-run / -n: print what would be done, change nothing)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"

for arg in "$@"; do
    case $arg in
        -n|--dry-run) DRY_RUN=1; export DRY_RUN ;;
        -h|--help) sed -n '2,4p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg (see --help)" >&2; exit 1 ;;
    esac
done

# add_custom_keybinding <id> <name> <command> <binding>: create/update a GNOME custom shortcut and
# append it to the list of custom shortcuts (keeps any others you have added by hand).
add_custom_keybinding() {
    local id=$1 name=$2 cmd=$3 binding=$4
    if dry; then would "add custom shortcut \"$name\": $binding -> $cmd"; return 0; fi
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

if dry; then
    echo "DRY RUN: no settings will be changed. (Assumes the ghostty and ksnip steps have run by then.)"
elif [[ -z ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then
    echo "No desktop session (DBUS_SESSION_BUS_ADDRESS unset); run this from a terminal in your GNOME session." >&2
    exit 1
fi

# GNOME settings from desktop.gsettings
while read -r schema key value || [[ -n ${schema:-} ]]; do
    [[ -z ${schema:-} || $schema == \#* ]] && continue
    run gsettings set "$schema" "$key" "$value"
done < "$DIR/desktop.gsettings"

# Default terminal: Ghostty (read by xdg-terminal-exec, which GNOME uses for terminals it launches).
if dry || [[ -e /usr/share/applications/com.mitchellh.ghostty.desktop ]]; then
    echo 'com.mitchellh.ghostty.desktop' | write_file ~/.config/xdg-terminals.list
else
    warn "Ghostty is not installed; default terminal unchanged (run ./install.sh ghostty first)."
fi

# Dock: hide it by disabling the Ubuntu Dock extension.
if gnome-extensions list 2>/dev/null | grep -qx 'ubuntu-dock@ubuntu.com'; then
    run gnome-extensions disable ubuntu-dock@ubuntu.com || warn "could not disable the Ubuntu Dock extension"
fi

# Screenshot with annotation: Super+Shift+S -> ksnip, rectangular area.
if dry || command -v ksnip >/dev/null 2>&1; then
    add_custom_keybinding ksnip "Screenshot (ksnip)" "ksnip -r" "<Super><Shift>s"
else
    warn "ksnip is not installed; Super+Shift+S not bound (run ./install.sh ksnip first)."
fi

# No audible bell in terminals. Ptyxis (Ubuntu's stock terminal) has its own setting; skip if it is not installed.
if gsettings list-schemas | grep -qx 'org.gnome.Ptyxis'; then
    run gsettings set org.gnome.Ptyxis audible-bell false
fi
# Ghostty: turn off the audio and system beep explicitly (title/attention cues stay, they are silent).
append_once ~/.config/ghostty/config.ghostty '# >>> build-ubuntu: no audible bell >>>' <<'GHOSTTY'
# >>> build-ubuntu: no audible bell >>>
bell-features = no-audio,no-system,attention,title
# <<< build-ubuntu: no audible bell <<<
GHOSTTY

# Default browser (Vivaldi) is set by the `vivaldi` step in install.sh.
if dry; then echo "Dry run finished: no settings were changed."; else echo "Desktop preferences applied."; fi
