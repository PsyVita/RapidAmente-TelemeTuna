#!/usr/bin/env bash
# =============================================================================
#  TelemeTuna — one-time machine setup
# =============================================================================
#  WHAT THIS SCRIPT DOES
#    1) Installs AWS CLI v2 + the SSM Session Manager plugin (if missing)
#    2) Creates the SSO CLI profiles:
#         op-tuna -> Operator,  ic-tuna -> InstanceController,  ad-tuna -> Admin
#    3) Adds the tuna-* commands to your shell (sources scripts/tuna-shortcuts.sh)

#  HOW TO USE  — copy/paste, run ONCE per machine:
#  1. Step 1: Paste this script into a terminal and run it (don't paste the #):
#
#    cd ~/githubProjects/RapidAmente-TelemeTuna
#    chmod +x scripts/install-tuna-shortcuts.sh
#    ./scripts/install-tuna-shortcuts.sh
#
#  2. Step 2: Follow the instructions it prints at the end, which will either be:
#
#    source ~/.zshrc
#    OR
#    source ~/.bashrc
#
#  THEN, WHENEVER YOU WORK  — pick the role you need for this shell:
#    tuna-login-op                   # sign in as Operator (for SSM)
#    tuna-login-ic                   # sign in as InstanceController (for instance control)
#    tuna-start                      # start the server
#    tuna-stop                       # stop the server when you're done
#    tuna-help                       # list every command

#  NOTES
#    - A profile only works for roles you're assigned in Identity Center.
#    - Safe to re-run: existing profiles are kept; the rc block is replaced,
#      never duplicated. Only the browser login (aws sso login) is manual.
#    - WINDOWS USERS: Run this script inside Git Bash.
# =============================================================================
set -euo pipefail

# ---- Org settings (safe to commit; these are NOT secrets) -------------------
SSO_START_URL="https://d-8d6711dc59.awsapps.com/start"
SSO_REGION="ap-southeast-7"
ACCOUNT_ID="166637875233"        # Rapidamente
REGION="ap-southeast-7"

# Every profile this script sets up, as "profile:role" pairs.
PROFILES=(
  "op-tuna:Operator"
  "ic-tuna:InstanceController"
  "ad-tuna:Admin"
)

if [[ "$SSO_START_URL" == *REPLACE* ]]; then
  echo "ERROR: set SSO_START_URL at the top of this script (your access portal URL)." >&2
  exit 1
fi

# ---- Ensure AWS CLI v2 is installed -----------------------------------------
ensure_aws_cli() {
  if command -v aws >/dev/null 2>&1; then return 0; fi
  echo "AWS CLI not found — installing the latest v2..."
  case "$(uname -s)" in
    Darwin)
      if command -v brew >/dev/null 2>&1; then
        brew install awscli
      else
        curl -fsSL "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o /tmp/AWSCLIV2.pkg
        sudo installer -pkg /tmp/AWSCLIV2.pkg -target /
        rm -f /tmp/AWSCLIV2.pkg
      fi
      ;;
    Linux)
      curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o /tmp/awscliv2.zip
      unzip -q /tmp/awscliv2.zip -d /tmp
      sudo /tmp/aws/install --update
      rm -rf /tmp/awscliv2.zip /tmp/aws
      ;;
    MINGW*|MSYS*|CYGWIN*)
      echo "Downloading AWS CLI installer for Windows..."
      curl -fsSL "https://awscli.amazonaws.com/AWSCLIV2.msi" -o AWSCLIV2.msi
      echo "Installing AWS CLI (a Windows prompt may appear)..."
      # Run msiexec via cmd to ensure the script waits for it to finish
      cmd.exe //c "start /wait msiexec.exe /i AWSCLIV2.msi /qb"
      rm -f AWSCLIV2.msi
      # The MSI updates the SYSTEM PATH, but this already-running shell won't see it.
      # Add the install dir to PATH for the rest of this run (no Git Bash restart needed).
      local d
      for d in "/c/Program Files/Amazon/AWSCLIV2" "/c/Program Files (x86)/Amazon/AWSCLIV2"; do
        if [ -d "$d" ]; then PATH="$d:$PATH"; fi
      done
      export PATH
      ;;
    *)
      echo "ERROR: unsupported OS. Install AWS CLI manually:" >&2
      echo "  https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" >&2
      exit 1
      ;;
  esac
  
  # Note: On Windows Git Bash, the terminal might need a restart to recognize 'aws' in the PATH immediately after install.
  if ! command -v aws >/dev/null 2>&1; then
    echo "WARN: AWS CLI installed, but you may need to restart Git Bash for the 'aws' command to be recognized."
    return 0
  fi
  echo "AWS CLI ready: $(aws --version)"
}

# ---- Ensure the SSM Session Manager plugin (for tuna-ssm/nodered/pgadmin) ----
ensure_ssm_plugin() {
  if command -v session-manager-plugin >/dev/null 2>&1; then return 0; fi
  echo "Session Manager plugin not found — installing..."
  case "$(uname -s)" in
    Darwin)
      if command -v brew >/dev/null 2>&1; then
        brew install --cask session-manager-plugin
      else
        local url="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac/sessionmanager-bundle.zip"
        if [ "$(uname -m)" = "arm64" ]; then
          url="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac_arm64/sessionmanager-bundle.zip"
        fi
        curl -fsSL "$url" -o /tmp/sessionmanager-bundle.zip
        unzip -q /tmp/sessionmanager-bundle.zip -d /tmp
        sudo /tmp/sessionmanager-bundle/install -i /usr/local/sessionmanagerplugin -b /usr/local/bin/session-manager-plugin
        rm -rf /tmp/sessionmanager-bundle.zip /tmp/sessionmanager-bundle
      fi
      ;;
    Linux)
      local arch_path="ubuntu_64bit"
      if [ "$(uname -m)" = "aarch64" ]; then arch_path="ubuntu_arm64"; fi
      curl -fsSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/${arch_path}/session-manager-plugin.deb" -o /tmp/session-manager-plugin.deb
      sudo dpkg -i /tmp/session-manager-plugin.deb
      rm -f /tmp/session-manager-plugin.deb
      ;;
    MINGW*|MSYS*|CYGWIN*)
      echo "Downloading Session Manager Plugin installer for Windows..."
      curl -fsSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPluginSetup.exe" -o SessionManagerPluginSetup.exe
      echo "Please complete the setup in the window that just popped up..."
      cmd.exe //c "start /wait SessionManagerPluginSetup.exe"
      rm -f SessionManagerPluginSetup.exe
      # Make the plugin usable in THIS shell without a restart (PATH not yet refreshed).
      local d
      for d in "/c/Program Files/Amazon/SessionManagerPlugin/bin" "/c/Program Files (x86)/Amazon/SessionManagerPlugin/bin"; do
        if [ -d "$d" ]; then PATH="$d:$PATH"; fi
      done
      export PATH
      ;;
    *)
      echo "WARN: can't auto-install the Session Manager plugin on this OS — see AWS docs." >&2
      return 0
      ;;
  esac
  
  if command -v session-manager-plugin >/dev/null 2>&1; then
    echo "Session Manager plugin ready."
  else
    echo "WARN: plugin install may have finished, but you might need to restart Git Bash for it to be detected."
  fi
}

ensure_aws_cli
ensure_ssm_plugin || true

# ---- 1) Create every SSO profile (skip any that already exist) --------------
for entry in "${PROFILES[@]}"; do
  p="${entry%%:*}"
  r="${entry##*:}"
  if aws configure list-profiles 2>/dev/null | grep -qx "$p"; then
    echo "AWS profile '$p' already exists — leaving it as-is."
  else
    echo "Creating AWS profile '$p' (role: $r)..."
    aws configure set sso_start_url  "$SSO_START_URL" --profile "$p"
    aws configure set sso_region     "$SSO_REGION"    --profile "$p"
    aws configure set sso_account_id "$ACCOUNT_ID"    --profile "$p"
    aws configure set sso_role_name  "$r"             --profile "$p"
    aws configure set region         "$REGION"        --profile "$p"
    aws configure set output         json             --profile "$p"
  fi
done

# ---- 2) Wire the shortcuts file into your shell rc --------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SHORTCUTS="$SCRIPT_DIR/tuna-shortcuts.sh"
START_MARK="# >>> TelemeTuna instance control >>>"
END_MARK="# <<< TelemeTuna instance control <<<"

case "$(basename "${SHELL:-zsh}")" in
  bash) RC="$HOME/.bashrc" ;;
  *)    RC="$HOME/.zshrc"  ;;
esac
touch "$RC"

if grep -qF "$START_MARK" "$RC"; then
  tmp="$(mktemp)"
  sed "/$START_MARK/,/$END_MARK/d" "$RC" > "$tmp"
  mv "$tmp" "$RC"
fi
{
  echo "$START_MARK"
  echo "[ -f \"$SHORTCUTS\" ] && source \"$SHORTCUTS\""
  echo "$END_MARK"
} >> "$RC"

# ---- 3) Tell the user what to do next ---------------------------------------
echo
echo "==================================================================="
echo "  TelemeTuna setup complete"
echo "==================================================================="
echo "  Profiles  : op-tuna, ic-tuna, ad-tuna"
echo "  Shortcuts : $SHORTCUTS"
echo "  Shell rc  : $RC"
echo
echo "  NEXT STEPS"
echo "    1) Load the commands into THIS shell (Windows users may need to restart Git Bash first):"
echo
echo "         source $RC"
echo
echo "    2) Sign in with the role you need:"
echo "         tuna-login-op     Operator (most tasks)"
echo "         tuna-login-ic     InstanceController (start/stop only)"
echo "         tuna-login-ad     Admin"
echo
echo "    3) Verify you are signed in:"
echo "         tuna-check"
echo "==================================================================="
echo
echo "  All commands (preview):"
echo
if [ -f "$SHORTCUTS" ]; then
  . "$SHORTCUTS"
  tuna-help
fi