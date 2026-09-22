#!/usr/bin/env bash
# Unattended setup for a fresh Ubuntu 26.04 desktop. Idempotent: safe to re-run.
# Software list: see software.txt in this repo.
# Usage: ./install.sh [--dry-run] [step ...]
# Steps: base shell claude vivaldi ghostty bitwarden obsidian ksnip drawing yubikey herdr zed desktop  (default: all, in that order)
# --dry-run (-n): print what would be done and change nothing (no sudo, no downloads, no prompts).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -r $DIR/lib.sh ]] || { echo "lib.sh not found next to install.sh; run from a git checkout (see bootstrap.sh)." >&2; exit 1; }
# shellcheck source=lib.sh
source "$DIR/lib.sh"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q '^install ok installed'; }

export DEBIAN_FRONTEND=noninteractive
APT=(sudo apt-get install -y)

# git_identity <config-key> <preset-value> <prompt>: set a global git option unless already set.
# Reads from /dev/tty so it also works when the script itself is piped in; skips if there is no TTY.
git_identity() {
    local key=$1 value=$2 prompt=$3
    if have git && git config --global "$key" >/dev/null 2>&1; then
        if dry; then would "git $key is already \"$(git config --global "$key")\"; keeping it"; fi
        return 0
    fi
    if dry; then
        if [[ -n $value ]]; then would "git config --global $key \"$value\" (from the environment)"
        else would "ask for git $key (\"$prompt\") and set it"; fi
        return 0
    fi
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

# install_deb <name> <url>...: download the first URL that works and install it through apt
# (so dpkg tracks it and dependencies are resolved).
install_deb() {
    local name=$1 url tmp; shift
    if dry; then
        would "download the first working of: $*"
        would "${APT[*]} <downloaded $name.deb>"
        return 0
    fi
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
    run sudo apt-get update
    run "${APT[@]}" curl ca-certificates gnupg git

    # Git identity: only if not already set. Uses GIT_NAME / GIT_EMAIL if given, otherwise asks.
    git_identity user.name "${GIT_NAME:-}" "Git user.name"
    git_identity user.email "${GIT_EMAIL:-}" "Git user.email"

    # Claude Code and Herdr install into ~/.local/bin.
    local line='export PATH="$HOME/.local/bin:$PATH"'
    printf '%s\n' "$line" | append_once ~/.bashrc "$line"
    export PATH="$HOME/.local/bin:$PATH"
}

step_shell() {
    # zoxide (smarter cd: `z`), fzf (fuzzy finder) and tmux. fzf's shell integration rebinds Ctrl-R
    # (history), Ctrl-T (files) and Alt-C (cd), so it replaces bash's default Ctrl-R search.
    log "Shell tools (zoxide, fzf, tmux, wl-clipboard)"
    run "${APT[@]}" zoxide fzf tmux wl-clipboard

    # tmux config: mouse support (click to select panes/windows, drag borders to resize, wheel to scroll).
    append_once ~/.config/tmux/tmux.conf '# >>> build-ubuntu: tmux >>>' <<'TMUX'
# >>> build-ubuntu: tmux >>>
set -g mouse on
# <<< build-ubuntu: tmux <<<
TMUX

    append_once ~/.bashrc '# >>> build-ubuntu: zoxide + fzf >>>' <<'BASHRC'

# >>> build-ubuntu: zoxide + fzf >>>
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"
command -v fzf >/dev/null 2>&1 && eval "$(fzf --bash)"
# <<< build-ubuntu: zoxide + fzf <<<
BASHRC
}

step_claude() {
    log "Claude Code"
    if have claude; then echo "already installed ($(command -v claude))"; return 0; fi
    if dry; then would "curl -fsSL https://claude.ai/install.sh | bash"; return 0; fi
    curl -fsSL https://claude.ai/install.sh | bash
}

step_vivaldi() {
    log "Vivaldi (official apt repo)"
    if ! installed vivaldi-stable; then
        run sudo install -d -m 0755 /etc/apt/keyrings
        run sudo curl -fsSL https://repo.vivaldi.com/archive/linux_signing_key.pub \
            -o /etc/apt/keyrings/vivaldi.asc
        sudo_write /etc/apt/sources.list.d/vivaldi.sources <<'EOF'
Types: deb
URIs: https://repo.vivaldi.com/archive/deb/
Suites: stable
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/vivaldi.asc
EOF
        # Stop the vivaldi package from adding its own duplicate apt source.
        sudo_write /etc/default/vivaldi <<'EOF'
repo_add_once="false"
repo_reenable_on_distupgrade="false"
EOF
        run sudo apt-get update
    fi
    run "${APT[@]}" vivaldi-stable

    # Default browser (Firefox stays installed as a fallback). Needs a desktop session; don't abort without one.
    run xdg-settings set default-web-browser vivaldi-stable.desktop \
        || echo "warning: could not set Vivaldi as default browser (no desktop session?). See TODO.md" >&2
}

step_ghostty() {
    log "Ghostty (Ubuntu archive)"
    run "${APT[@]}" ghostty
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
    if dry; then
        would "look up the newest amd64 .deb on https://github.com/obsidianmd/obsidian-releases/releases (no network in dry-run)"
        install_deb obsidian '<newest working release>'
        return 0
    fi
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
    run "${APT[@]}" ksnip
}

step_drawing() {
    # Lightweight GTK paint/image tool (GNOME's own "Drawing" app, Paint-style basics).
    log "Drawing (Ubuntu archive)"
    run "${APT[@]}" drawing
}

step_yubikey() {
    # Tooling only. Deliberately no libpam-u2f: enrolling keys for login/sudo can lock you out,
    # so that stays a manual, deliberate step.
    log "YubiKey support (ykman, FIDO2 tools, smartcard/GPG, Authenticator)"
    run "${APT[@]}" yubikey-manager fido2-tools pcscd scdaemon yubioath-desktop
}

step_zed() {
    log "Zed editor"
    if have zed; then echo "already installed ($(command -v zed))"; return 0; fi
    if dry; then would "curl -fsSL https://zed.dev/install.sh | sh"; return 0; fi
    curl -fsSL https://zed.dev/install.sh | sh
}

step_herdr() {
    log "Herdr"
    if have herdr || [[ -x "$HOME/.local/bin/herdr" ]]; then echo "already installed"; return 0; fi
    if dry; then would "curl -fsSL https://herdr.dev/install.sh | sh"; return 0; fi
    curl -fsSL https://herdr.dev/install.sh | sh
}

step_desktop() {
    # Needs a desktop session and the rest of this repo (desktop.sh). DRY_RUN is inherited.
    log "Desktop preferences"
    [[ -x $DIR/desktop.sh ]] || { echo "desktop.sh not found next to install.sh; run from a git checkout (see bootstrap.sh)." >&2; return 1; }
    "$DIR/desktop.sh"
}

# --- main ---------------------------------------------------------------------------------
STEPS=()
for arg in "$@"; do
    case $arg in
        -n|--dry-run) DRY_RUN=1; export DRY_RUN ;;
        -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "Unknown option: $arg (see --help)" >&2; exit 1 ;;
        *) STEPS+=("$arg") ;;
    esac
done
[[ ${#STEPS[@]} -gt 0 ]] || STEPS=(base shell claude vivaldi ghostty bitwarden obsidian ksnip drawing yubikey herdr zed desktop)

# Validate every step name before running anything.
for s in "${STEPS[@]}"; do
    declare -F "step_$s" >/dev/null || { echo "Unknown step: $s (see --help)" >&2; exit 1; }
done

[[ $EUID -ne 0 ]] || { echo "Run as your normal user, not root (sudo is used where needed)." >&2; exit 1; }

if dry; then
    echo "DRY RUN: nothing will be changed. Steps: ${STEPS[*]}"
else
    # Ask for the sudo password once and keep the ticket alive until we exit.
    sudo -v
    while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
    trap 'kill $! 2>/dev/null || true' EXIT
fi

for s in "${STEPS[@]}"; do
    "step_$s"
done

if dry; then log "Dry run finished: nothing was changed."; else log "Done: ${STEPS[*]}"; fi
