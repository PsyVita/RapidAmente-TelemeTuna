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

**Easiest — one PowerShell command (installs everything, including Git Bash):**

Get the repo first (clone if you have git, or download the ZIP from GitHub and
extract it), then in **PowerShell**, from the repo root:

```
powershell -ExecutionPolicy Bypass -File scripts\bootstrap-windows.ps1
```

That installs Git for Windows (if missing) via winget, then runs the bash installer
(AWS CLI + SSM plugin + profiles + shortcuts). When it finishes, open **Git Bash** and:

```
source ~/.bashrc
tuna-login-op        # or tuna-login-ic / tuna-login-ad
```

**Manual alternative (if you already have Git Bash):** run the bash installer directly
from Git Bash:

```
git clone https://github.com/PsyVita/RapidAmente-TelemeTuna.git
cd RapidAmente-TelemeTuna
./scripts/install-tuna-shortcuts.sh
source ~/.bashrc
```

Notes for Windows:
- The `tuna-*` commands run in **Git Bash**, not PowerShell/CMD (they're bash). The
  PowerShell bootstrap is only the installer; daily use is in Git Bash. WSL also works
  and behaves like the Linux instructions above.
- `winget` is needed for the auto-install (built into Windows 10 1709+ / 11). On older
  Windows, install Git for Windows manually first, then use the manual alternative.
- UAC / installer windows may pop up for AWS CLI / the SSM plugin — approve them. If
  `aws` isn't found right after a first-time install, reopen the shell and re-run.

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
