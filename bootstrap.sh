#!/usr/bin/env bash
# One-liner entry point for a fresh machine: installs git, clones this repo, runs install.sh.
#   bash <(wget -qO- https://raw.githubusercontent.com/skaring/build-ubuntu/main/bootstrap.sh) [--dry-run] [step ...]
# --dry-run (-n): print what would be done and change nothing. The install plan itself can only be
# previewed if the repo is already cloned (and current); otherwise only the bootstrap actions are shown.
set -euo pipefail

REPO="${REPO:-https://github.com/skaring/build-ubuntu.git}"
DEST="${DEST:-$HOME/git/build-ubuntu}"

[[ $EUID -ne 0 ]] || { echo "Run as your normal user, not root." >&2; exit 1; }

DRY_RUN="${DRY_RUN:-0}"
for arg in "$@"; do
    case $arg in -n|--dry-run) DRY_RUN=1 ;; esac
done
export DRY_RUN

if [[ $DRY_RUN == 1 ]]; then
    echo "DRY RUN: nothing will be changed."
    echo "  [dry-run] sudo apt-get update && sudo apt-get install -y git ca-certificates"
    echo "  [dry-run] mkdir -p $(dirname "$DEST")"
    if [[ -d $DEST/.git ]]; then echo "  [dry-run] git -C $DEST pull --ff-only"
    else echo "  [dry-run] git clone $REPO $DEST"; fi
    if [[ -x $DEST/install.sh ]] && grep -q -- '--dry-run' "$DEST/install.sh"; then
        echo "  [dry-run] then run install.sh; its plan (from the existing checkout in $DEST):"
        exec "$DEST/install.sh" "$@"
    fi
    echo "  [dry-run] then run install.sh. Its plan can't be previewed yet: no up-to-date checkout in $DEST."
    echo "            After the clone, run: $DEST/install.sh --dry-run"
    exit 0
fi

sudo -v
sudo apt-get update
sudo apt-get install -y git ca-certificates

mkdir -p "$(dirname "$DEST")"
if [[ -d $DEST/.git ]]; then
    git -C "$DEST" pull --ff-only
else
    git clone "$REPO" "$DEST"
fi

exec "$DEST/install.sh" "$@"
