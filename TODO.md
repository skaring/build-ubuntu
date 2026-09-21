# TODO: manual tasks after `install.sh`

Things the script deliberately does not do (need a human, a physical key, or carry lock-out risk).
Tick them off as you go; add new ones as they come up.

## Accounts & sign-in
- [ ] Sign in to Claude Code: run `claude` and log in.
- [ ] Sign in to Bitwarden desktop (and the Vivaldi extension).

## SSH & GitHub
- [ ] Generate a key: `ssh-keygen -t ed25519 -C "fredrik.skaring@gmail.com"`, then add the `.pub`
      at https://github.com/settings/keys and test with `ssh -T git@github.com`.
- [ ] Optional: hardware-backed key instead: `ssh-keygen -t ed25519-sk` (needs the YubiKey plugged in
      and touched). Register the `.pub` on GitHub. Each machine/key needs its own registration.
- [ ] Decide whether Bitwarden should hold/serve SSH keys (SSH agent).

## YubiKey
- [ ] Check the key is seen: `ykman info` and `fido2-token -L`.
- [ ] Set a FIDO2 PIN: `ykman fido access change-pin`.
- [ ] **sudo/login via `libpam-u2f`** (lock-out risk, do carefully):
  1. `sudo apt install libpam-u2f`
  2. Keep a root shell open in another terminal for the whole procedure: `sudo -s`.
  3. Register: `mkdir -p ~/.config/Yubico && pamu2fcfg > ~/.config/Yubico/u2f_keys`
     (touch the key; add a second/backup key with `pamu2fcfg -n >> ~/.config/Yubico/u2f_keys`).
  4. Enable for `sudo` first: add `auth sufficient pam_u2f.so` above the `@include common-auth`
     line in `/etc/pam.d/sudo`. Use `sufficient` (key OR password) until it is proven.
  5. Test in a *new* terminal before closing the root shell. Only then consider login/GDM.
- [ ] Register at least one backup YubiKey everywhere a key is enrolled.
- [ ] Optional: import/generate OpenPGP keys on the key (uses `pcscd` + `scdaemon`).

## Undecided
- [ ] Firefox stays as a backup browser (decided). It is a snap on Ubuntu; revisit only if you want
      it via Mozilla's apt repo instead (avoiding snaps is a stated preference).
- [ ] Verify Vivaldi is the default after the first run: `xdg-settings get default-web-browser`
      (expect `vivaldi-stable.desktop`; the script sets it but that is untested).
- [ ] Bitwarden `.deb` does not self-update: re-run `./install.sh bitwarden` to upgrade.
