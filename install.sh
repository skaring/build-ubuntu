#!/usr/bin/env bash
# Unattended setup for a fresh Ubuntu 26.04 desktop. Idempotent: safe to re-run.
# Software list: see ~/software.txt. Usage: ./install.sh [step ...]
# Steps: base claude vivaldi ghostty bitwarden yubikey herdr  (default: all, in that order)
set -euo pipefail

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q '^install ok installed'; }

[[ $EUID -ne 0 ]] || { echo "Run as your normal user, not root (sudo is used where needed)." >&2; exit 1; }

# Ask for the sudo password once and keep the ticket alive until we exit.
sudo -v
while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
trap 'kill $! 2>/dev/null || true' EXIT

export DEBIAN_FRONTEND=noninteractive
APT=(sudo apt-get install -y)

step_base() {
    log "Base packages"
    sudo apt-get update
    "${APT[@]}" curl ca-certificates gnupg git

    # Claude Code and Herdr install into ~/.local/bin.
    local line='export PATH="$HOME/.local/bin:$PATH"'
    grep -qxF "$line" ~/.bashrc || echo "$line" >> ~/.bashrc
    export PATH="$HOME/.local/bin:$PATH"
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
    local tmp; tmp="$(mktemp -d)"
    curl -fsSL 'https://vault.bitwarden.com/download/?app=desktop&platform=linux&variant=deb' \
        -o "$tmp/bitwarden.deb"
    "${APT[@]}" "$tmp/bitwarden.deb"
    rm -rf "$tmp"
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

STEPS=("$@")
[[ ${#STEPS[@]} -gt 0 ]] || STEPS=(base claude vivaldi ghostty bitwarden yubikey herdr)

for s in "${STEPS[@]}"; do
    declare -F "step_$s" >/dev/null || { echo "Unknown step: $s" >&2; exit 1; }
    "step_$s"
done

log "Done: ${STEPS[*]}"
