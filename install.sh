#!/usr/bin/env bash
# Unattended setup for a fresh Ubuntu 26.04 desktop. Idempotent: safe to re-run.
# Software list: see software.txt in this repo. Usage: ./install.sh [step ...]
# Steps: base shell claude vivaldi ghostty bitwarden obsidian ksnip yubikey herdr desktop  (default: all, in that order)
set -euo pipefail

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q '^install ok installed'; }

# git_identity <config-key> <preset-value> <prompt>: set a global git option unless already set.
# Reads from /dev/tty so it also works when the script itself is piped in; skips if there is no TTY.
git_identity() {
    local key=$1 value=$2 prompt=$3
    git config --global "$key" >/dev/null && return 0
    if [[ -z $value ]]; then
        if { : </dev/tty; } 2>/dev/null; then
            read -r -p "$prompt: " value </dev/tty || true
        fi
    fi
    if [[ -n $value ]]; then
        git config --global "$key" "$value"
    else
        echo "warning: $key not set (no value given). Set it later with: git config --global $key ..." >&2
    fi
}

[[ $EUID -ne 0 ]] || { echo "Run as your normal user, not root (sudo is used where needed)." >&2; exit 1; }

# Ask for the sudo password once and keep the ticket alive until we exit.
sudo -v
while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
trap 'kill $! 2>/dev/null || true' EXIT

export DEBIAN_FRONTEND=noninteractive
APT=(sudo apt-get install -y)

# install_deb <name> <url>...: download the first URL that works and install it through apt
# (so dpkg tracks it and dependencies are resolved).
install_deb() {
    local name=$1 url tmp; shift
    tmp="$(mktemp -d)"
    for url in "$@"; do
        echo "downloading $url"
        if curl -fsSL --retry 2 "$url" -o "$tmp/$name.deb"; then
            "${APT[@]}" "$tmp/$name.deb"
            rm -rf "$tmp"
            return 0
        fi
        echo "download failed, trying the next candidate" >&2
    done
    rm -rf "$tmp"
    echo "error: no working download for $name" >&2
    return 1
}

step_base() {
    log "Base packages"
    sudo apt-get update
    "${APT[@]}" curl ca-certificates gnupg git

    # Git identity: only if not already set. Uses GIT_NAME / GIT_EMAIL if given, otherwise asks.
    git_identity user.name "${GIT_NAME:-}" "Git user.name"
    git_identity user.email "${GIT_EMAIL:-}" "Git user.email"

    # Claude Code and Herdr install into ~/.local/bin.
    local line='export PATH="$HOME/.local/bin:$PATH"'
    grep -qxF "$line" ~/.bashrc || echo "$line" >> ~/.bashrc
    export PATH="$HOME/.local/bin:$PATH"
}

step_shell() {
    # zoxide (smarter cd: `z`) and fzf (fuzzy finder). fzf's shell integration rebinds Ctrl-R
    # (history), Ctrl-T (files) and Alt-C (cd), so it replaces bash's default Ctrl-R search.
    log "Shell tools (zoxide, fzf)"
    "${APT[@]}" zoxide fzf
    local marker='# >>> build-ubuntu: zoxide + fzf >>>'
    if ! grep -qxF "$marker" ~/.bashrc; then
        cat >> ~/.bashrc <<'BASHRC'

# >>> build-ubuntu: zoxide + fzf >>>
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"
command -v fzf >/dev/null 2>&1 && eval "$(fzf --bash)"
# <<< build-ubuntu: zoxide + fzf <<<
BASHRC
    fi
}

step_claude() {
    log "Claude Code"
    if have claude; then echo "already installed ($(command -v claude))"; return; fi
    curl -fsSL https://claude.ai/install.sh | bash
}

step_vivaldi() {
    log "Vivaldi (official apt repo)"
    if ! installed vivaldi-stable; then
        sudo install -d -m 0755 /etc/apt/keyrings
        sudo curl -fsSL https://repo.vivaldi.com/archive/linux_signing_key.pub \
            -o /etc/apt/keyrings/vivaldi.asc
        sudo tee /etc/apt/sources.list.d/vivaldi.sources >/dev/null <<'EOF'
Types: deb
URIs: https://repo.vivaldi.com/archive/deb/
Suites: stable
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/vivaldi.asc
EOF
        # Stop the vivaldi package from adding its own duplicate apt source.
        sudo tee /etc/default/vivaldi >/dev/null <<'EOF'
repo_add_once="false"
repo_reenable_on_distupgrade="false"
EOF
        sudo apt-get update
    fi
    "${APT[@]}" vivaldi-stable

    # Default browser (Firefox stays installed as a fallback). Needs a desktop session; don't abort without one.
    xdg-settings set default-web-browser vivaldi-stable.desktop \
        || echo "warning: could not set Vivaldi as default browser (no desktop session?). See TODO.md" >&2
}

step_ghostty() {
    log "Ghostty (Ubuntu archive)"
    "${APT[@]}" ghostty
}

step_bitwarden() {
    # Bitwarden ships no apt repo. The .deb doesn't self-update; re-run this step to upgrade.
    # (.deb rather than snap so browser-extension integration works outside the snap sandbox.)
    log "Bitwarden desktop (.deb from bitwarden.com)"
    install_deb bitwarden 'https://vault.bitwarden.com/download/?app=desktop&platform=linux&variant=deb'
}

step_obsidian() {
    # No apt repo either. GitHub's newest release is sometimes Android-only or has a broken asset,
    # so try the newest few releases that have an amd64 .deb, newest first. Re-run to upgrade.
    log "Obsidian (.deb from GitHub releases)"
    local urls
    mapfile -t urls < <(curl -fsSL 'https://api.github.com/repos/obsidianmd/obsidian-releases/releases?per_page=15' \
        | grep -o '"browser_download_url": *"[^"]*_amd64\.deb"' | cut -d'"' -f4 | head -3)
    [[ ${#urls[@]} -gt 0 ]] || { echo "error: could not find an Obsidian .deb release" >&2; return 1; }
    install_deb obsidian "${urls[@]}"
}

step_ksnip() {
    # Screenshot + annotation (Greenshot-like). Works on GNOME Wayland via the desktop portal; Flameshot did not.
    # Hotkey (Super+Shift+S) is set by desktop.sh.
    log "ksnip (Ubuntu archive)"
    "${APT[@]}" ksnip
}

step_yubikey() {
    # Tooling only. Deliberately no libpam-u2f: enrolling keys for login/sudo can lock you out,
    # so that stays a manual, deliberate step.
    log "YubiKey support (ykman, FIDO2 tools, smartcard/GPG, Authenticator)"
    "${APT[@]}" yubikey-manager fido2-tools pcscd scdaemon yubioath-desktop
}

step_herdr() {
    log "Herdr"
    if have herdr || [[ -x "$HOME/.local/bin/herdr" ]]; then echo "already installed"; return; fi
    curl -fsSL https://herdr.dev/install.sh | sh
}

step_desktop() {
    # Needs a desktop session and the rest of this repo (desktop.sh), so use a checkout or bootstrap.sh.
    log "Desktop preferences"
    local dir; dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    [[ -x $dir/desktop.sh ]] || { echo "desktop.sh not found next to install.sh; run from a git checkout (see bootstrap.sh)." >&2; return 1; }
    "$dir/desktop.sh"
}

STEPS=("$@")
[[ ${#STEPS[@]} -gt 0 ]] || STEPS=(base shell claude vivaldi ghostty bitwarden obsidian ksnip yubikey herdr desktop)

for s in "${STEPS[@]}"; do
    declare -F "step_$s" >/dev/null || { echo "Unknown step: $s" >&2; exit 1; }
    "step_$s"
done

log "Done: ${STEPS[*]}"
