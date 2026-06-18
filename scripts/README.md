# TelemeTuna control shortcuts

Friendly `tuna-*` commands to sign in and run the TelemeTuna server, for any teammate.

- `install-tuna-shortcuts.sh` — one-time setup: installs AWS CLI + the SSM plugin
  (if missing), creates the SSO profiles (`op-tuna`, `ic-tuna`, `ad-tuna`), and wires
  the shortcuts into your shell.
- `tuna-shortcuts.sh` — the `tuna-*` functions themselves (sourced by your shell rc).

---

## Setup

### macOS / Linux

```
git clone https://github.com/PsyVita/RapidAmente-TelemeTuna.git
cd RapidAmente-TelemeTuna
chmod +x scripts/install-tuna-shortcuts.sh
./scripts/install-tuna-shortcuts.sh
```

Then run the `source ...` line the script prints (e.g. `source ~/.zshrc` on macOS,
`source ~/.bashrc` on most Linux).

### Windows

Run it from **Git Bash** (ships with Git for Windows) — the script handles the
Windows installers for AWS CLI and the SSM plugin automatically:

```
git clone https://github.com/PsyVita/RapidAmente-TelemeTuna.git
cd RapidAmente-TelemeTuna
./scripts/install-tuna-shortcuts.sh
source ~/.bashrc
```

Notes for Windows:
- Use **Git Bash**, not PowerShell or CMD (the script is bash). WSL works too and
  behaves like the Linux instructions above.
- After AWS CLI installs for the first time you may need to **close and reopen Git
  Bash** so `aws` is on your PATH, then re-run the script.
- A Windows installer window may pop up for the AWS CLI / SSM plugin — complete it.

---

## Everyday use

Pick the role you need for this terminal (this also signs you in):

```
tuna-login-op      # Operator  (most tasks)
tuna-login-ic      # InstanceController (start/stop only)
tuna-login-ad      # Admin
```

Then, for example:

```
tuna-check         # confirm you're signed in
tuna-start         # boot the server
tuna-status        # show its state + public IP
tuna-grafana       # open the dashboards
tuna-stop          # pause it when you're done
tuna-help          # full list of commands
```

`tuna-help` prints two tables: commands any role can run, and commands that need an
SSM-capable role (`op-tuna`/`ad-tuna`) with the instance running.

---

## Notes

- A profile only works for roles you're actually assigned in Identity Center;
  creating one you don't have is harmless (login just won't authorize it).
- Safe to re-run the installer anytime — existing AWS profiles are left as-is and the
  shell block is replaced, never duplicated.
- The portal URL is baked into the installer, so there's nothing to configure.
