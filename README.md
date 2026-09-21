# build-ubuntu

Unattended setup for a fresh Ubuntu 26.04 desktop. See `software.txt` for the software list.

## Run

From a regular terminal (sudo needs a TTY), on a fresh machine:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/skaring/build-ubuntu/main/install.sh)
```

Or from a checkout:

```bash
./install.sh            # all steps
./install.sh vivaldi    # just one (or several) steps
```

Steps: `base claude vivaldi ghostty bitwarden yubikey herdr`. The script is idempotent; re-run it to upgrade
Bitwarden (its `.deb` does not self-update).

## Notes

- No snaps: everything is installed via apt, an apt-installed `.deb`, or the vendor's install script.
- `install.sh` must stay a single self-contained file to work with the `wget` one-liner. If it is
  split up, switch the one-liner to `git clone` + run.
- Keep secrets out of this repo; it is meant to be public.
