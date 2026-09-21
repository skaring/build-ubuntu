# build-ubuntu

Unattended setup for a fresh Ubuntu 26.04 desktop. See `software.txt` for the software list.

## Run

From a regular terminal (sudo needs a TTY), on a fresh machine:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/skaring/build-ubuntu/main/bootstrap.sh)
```

Or from a checkout:

```bash
./install.sh            # all steps
./install.sh vivaldi    # just one (or several) steps
```

`bootstrap.sh` installs git, clones this repo to `~/build-ubuntu` and runs `install.sh` (arguments are passed on).

Steps: `base claude vivaldi ghostty bitwarden obsidian yubikey herdr desktop`. The script is idempotent; re-run it to upgrade
Bitwarden and Obsidian (their `.deb`s do not self-update).

## Desktop preferences

`./install.sh desktop` (or `./desktop.sh`) applies GNOME preferences: 4 fixed workspaces, green (Yaru olive, dark)
theme, Ghostty as default terminal, Ubuntu Dock disabled, `Super+1..4` to switch workspace and `Super+Shift+1..4` to move a window. Plain GNOME settings are listed in `desktop.gsettings`
(`<schema> <key> <value>` per line); anything else goes in `desktop.sh`. It needs a running desktop session, so run it
from a terminal on the desktop, not over SSH. Vivaldi as default browser is set by the `vivaldi` step.

## Notes

- No snaps: everything is installed via apt, an apt-installed `.deb`, or the vendor's install script.
- `TODO.md` lists the manual steps the script does not (or should not) do.
- Keep secrets out of this repo; it is meant to be public.
