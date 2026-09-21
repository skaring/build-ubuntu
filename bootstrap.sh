#!/usr/bin/env bash
# One-liner entry point for a fresh machine: installs git, clones this repo, runs install.sh.
#   bash <(wget -qO- https://raw.githubusercontent.com/skaring/build-ubuntu/main/bootstrap.sh) [step ...]
set -euo pipefail

REPO="${REPO:-https://github.com/skaring/build-ubuntu.git}"
DEST="${DEST:-$HOME/build-ubuntu}"

[[ $EUID -ne 0 ]] || { echo "Run as your normal user, not root." >&2; exit 1; }

sudo -v
sudo apt-get update
sudo apt-get install -y git ca-certificates

if [[ -d $DEST/.git ]]; then
    git -C "$DEST" pull --ff-only
else
    git clone "$REPO" "$DEST"
fi

exec "$DEST/install.sh" "$@"
