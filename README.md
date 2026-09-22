# build-ubuntu

Unattended setup for a fresh Ubuntu 26.04 desktop. See `software.txt` for the software list.

## Run

From a regular terminal (sudo needs a TTY), on a fresh machine:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/skaring/build-ubuntu/main/bootstrap.sh)
```

Or from a checkout:

```bash
./install.sh                  # all steps
./install.sh vivaldi ksnip    # just one (or several) steps
./install.sh --dry-run        # preview: show what would be done, change nothing
```

`bootstrap.sh` installs git, clones this repo to `~/git/build-ubuntu` and runs `install.sh` (arguments are passed on).

Steps: `base shell claude vivaldi ghostty bitwarden obsidian ksnip drawing yubikey herdr zed desktop`. The script is idempotent; re-run it to upgrade
Bitwarden and Obsidian (their `.deb`s do not self-update).

## Dry run

Preview a run before doing it:

```bash
./install.sh --dry-run                # the whole plan
./install.sh --dry-run vivaldi        # just some steps (-n is short for --dry-run)
DRY_RUN=1 ./install.sh                # same thing via the environment
./desktop.sh --dry-run                # just the desktop preferences
bash <(wget -qO- https://raw.githubusercontent.com/skaring/build-ubuntu/main/bootstrap.sh) --dry-run
```

Every action is printed as `[dry-run] ...` instead of being performed. A dry run needs no `sudo`, asks no
questions, downloads nothing and writes nothing: no packages, apt sources, config files or GNOME settings are touched.

- **It still looks at the machine.** Read-only checks run for real, so the plan is accurate: steps whose software is
  already installed say so, and config blocks that are already present say "nothing to do".
- **Some things are described, not resolved.** The newest Obsidian release is only looked up in a real run (that needs
  the network), and the git name/email prompt is shown as "ask for ...".
- **`desktop` assumes the earlier steps have run.** The Ghostty terminal default and the ksnip shortcut depend on those
  programs being installed; the preview lists them as if they were, so on a machine where they are missing a real run of
  `desktop` alone would warn and skip them instead.
- **`bootstrap.sh --dry-run`** shows its own actions (install git, clone or pull). It can show the install plan only if an
  up-to-date checkout already exists in `~/git/build-ubuntu`; it never pulls or clones in a dry run, so that plan reflects
  the local checkout, which may be behind GitHub. Otherwise it tells you to clone and run `./install.sh --dry-run`.

## Desktop preferences

`./install.sh desktop` (or `./desktop.sh`; both accept `--dry-run`) applies GNOME preferences: 4 fixed workspaces, green (Yaru olive, dark)
theme, Ghostty as default terminal, Ubuntu Dock disabled, event sounds and terminal bell off (GNOME, Ptyxis, Ghostty), `Super+Shift+S` for ksnip area screenshots (copied to the clipboard automatically), `Super+1..4` to switch workspace and `Super+Shift+1..4` to move a window. Plain GNOME settings are listed in `desktop.gsettings`
(`<schema> <key> <value>` per line); anything else goes in `desktop.sh`. It needs a running desktop session, so run it
from a terminal on the desktop, not over SSH. Vivaldi as default browser is set by the `vivaldi` step.

## Corporate setup (optional)

`./corporate.sh` installs Microsoft Edge, Intune (Company Portal) and Microsoft Defender for Endpoint,
for a device that needs company resources. It is entirely separate: not called by `install.sh` or
`bootstrap.sh`, so a personal machine never gets it unless you run it yourself.

```bash
./corporate.sh                # both steps: intune, defender
./corporate.sh intune         # Edge + Company Portal only
./corporate.sh --dry-run      # preview
```

- `intune` runs Microsoft's own installer script (Edge is a hard requirement of Company Portal
  sign-in, so it installs both). After it finishes, open Company Portal and sign in with your work
  account to enroll.
- `defender` adds Microsoft's apt repo and installs `mdatp`. Final onboarding needs a package
  generated for your organization's tenant from its admin portal, which can't be scripted — see
  `TODO.md`.

## Notes

- No snaps: everything is installed via apt, an apt-installed `.deb`, or the vendor's install script.
- `lib.sh` holds the small helpers shared by `install.sh`, `desktop.sh` and `corporate.sh` (including the dry-run
  plumbing); keep the scripts together in one checkout.
- `TODO.md` lists the manual steps the script does not (or should not) do.
- Keep secrets out of this repo; it is meant to be public.
