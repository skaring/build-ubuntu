#!/usr/bin/env bash
# OPTIONAL corporate/work setup: Microsoft Edge, Intune (Company Portal), Microsoft Defender for
# Endpoint. Only for a device that needs company resources. NOT part of install.sh or bootstrap.sh
# -- run this yourself, deliberately, never as part of the personal setup.
# Usage: ./corporate.sh [--dry-run] [step ...]
# Steps: intune defender   (default: both)
#   intune   - Microsoft Edge + Intune Company Portal, via Microsoft's official installer script
#              (Edge is a hard requirement of Company Portal sign-in, so it installs both).
#   defender - Microsoft Defender for Endpoint (mdatp). Installs and configures the agent; final
#              onboarding needs a tenant-specific package from your org's admin portal (see below
#              and TODO.md) and cannot be scripted.
# --dry-run (-n): print what would be done and change nothing (no sudo, no downloads, no prompts).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -r $DIR/lib.sh ]] || { echo "lib.sh not found next to corporate.sh; run from a git checkout (see bootstrap.sh)." >&2; exit 1; }
# shellcheck source=lib.sh
source "$DIR/lib.sh"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

export DEBIAN_FRONTEND=noninteractive
APT=(sudo apt-get install -y)

step_intune() {
    # Official Microsoft installer for Ubuntu/RHEL: adds the Edge and Intune Portal apt repos and
    # installs both. Idempotent (designed for repeated runs); re-run to update.
    # Source, reviewed before wiring this in: https://github.com/microsoft/shell-intune-samples
    # ("Linux/Intune Installer/installer.sh", fetched via Microsoft's fwlink below). No corporate
    # credentials needed to install; it self-elevates with sudo and verifies public Microsoft GPG
    # keys. It does touch /etc/apt/sources.list.d (adds Edge/Intune repos, tidies old ones).
    log "Microsoft Edge + Intune Company Portal (official Microsoft installer)"
    local url='https://go.microsoft.com/fwlink/?linkid=2358529'
    if dry; then
        would "download $url"
        would "sudo bash installer.sh   # adds Edge + Intune Portal apt repos, installs both"
        return 0
    fi
    local script; script="$(mktemp -d)/installer.sh"
    curl -fsSL "$url" -o "$script"
    chmod +x "$script"
    sudo "$script"
}

step_defender() {
    # Microsoft's own apt repo, per https://learn.microsoft.com/defender-endpoint/linux-install-manually
    # (Ubuntu/Debian section). DEFENDER_CHANNEL defaults to "prod"; Microsoft also offers
    # insiders-fast/insiders-slow, not used here.
    log "Microsoft Defender for Endpoint (mdatp)"
    local channel="${DEFENDER_CHANNEL:-prod}"
    local listfile=/etc/apt/sources.list.d/microsoft-prod.list
    local keyfile=/usr/share/keyrings/microsoft-prod.gpg
    local version; version="$(. /etc/os-release; echo "$VERSION_ID")"

    run "${APT[@]}" curl libplist-utils gnupg apt-transport-https

    if dry; then
        would "curl https://packages.microsoft.com/config/ubuntu/$version/$channel.list -> $listfile"
        would "curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -> $keyfile"
        would "sudo apt-get update"
    elif [[ ! -f $listfile ]]; then
        local tmp; tmp="$(mktemp)"
        curl -fsSL "https://packages.microsoft.com/config/ubuntu/$version/$channel.list" -o "$tmp" \
            || { echo "error: no Defender repo published for Ubuntu $version (channel $channel)" >&2; rm -f "$tmp"; return 1; }
        sudo mv "$tmp" "$listfile"
        curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo_write "$keyfile"
        sudo chmod o+r "$keyfile"
        run sudo apt-get update
    fi
    run "${APT[@]}" mdatp

    dry && return 0
    cat <<'EOF'

Defender is installed but NOT onboarded: that needs a package generated for YOUR organization's
tenant, which cannot be scripted. See the "Microsoft Defender for Endpoint" section of TODO.md.
EOF
}

# --- main ---------------------------------------------------------------------------------
STEPS=()
for arg in "$@"; do
    case $arg in
        -n|--dry-run) DRY_RUN=1; export DRY_RUN ;;
        -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "Unknown option: $arg (see --help)" >&2; exit 1 ;;
        *) STEPS+=("$arg") ;;
    esac
done
[[ ${#STEPS[@]} -gt 0 ]] || STEPS=(intune defender)

for s in "${STEPS[@]}"; do
    declare -F "step_$s" >/dev/null || { echo "Unknown step: $s (see --help)" >&2; exit 1; }
done

[[ $EUID -ne 0 ]] || { echo "Run as your normal user, not root (sudo is used where needed)." >&2; exit 1; }

if dry; then
    echo "DRY RUN: nothing will be changed. Steps: ${STEPS[*]}"
else
    sudo -v
    while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
    trap 'kill $! 2>/dev/null || true' EXIT
fi

for s in "${STEPS[@]}"; do
    "step_$s"
done

if dry; then log "Dry run finished: nothing was changed."; else log "Done: ${STEPS[*]}"; fi
