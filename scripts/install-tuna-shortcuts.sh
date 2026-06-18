#!/usr/bin/env bash
# install-tuna-shortcuts.sh
#   1) Creates an AWS SSO CLI profile for the chosen role (if it doesn't already exist)
#   2) Installs tuna-up / tuna-down / tuna-status / tuna-help shell shortcuts
#
# Run ONCE per machine, after cloning the repo:
#   ./scripts/install-tuna-shortcuts.sh                 # profile 'tuna'    -> Operator
#   ./scripts/install-tuna-shortcuts.sh tuna-ic         # profile 'tuna-ic' -> InstanceController
#   ./scripts/install-tuna-shortcuts.sh myname Operator # explicit profile + role
#
# Safe to re-run: an existing AWS profile is left untouched; the shortcut block is
# replaced (never duplicated). Only the browser login (aws sso login) is manual.
set -euo pipefail

# ---- Org settings (safe to commit; these are NOT secrets) -------------------
SSO_START_URL="https://REPLACE-WITH-YOUR-PORTAL.awsapps.com/start"  # <-- set this once
SSO_REGION="ap-southeast-7"
ACCOUNT_ID="166637875233"        # Rapidamente
REGION="ap-southeast-7"
# -----------------------------------------------------------------------------

PROFILE="${1:-tuna}"
ROLE="${2:-}"
# Map known profile names to roles if a role wasn't passed explicitly.
if [ -z "$ROLE" ]; then
  case "$PROFILE" in
    tuna)    ROLE="Operator" ;;
    tuna-ic) ROLE="InstanceController" ;;
    *)       ROLE="Operator" ;;
  esac
fi

command -v aws >/dev/null 2>&1 || { echo "ERROR: AWS CLI not found — install it first."; exit 1; }

# ---- 1) Create the SSO profile if it doesn't exist --------------------------
if aws configure list-profiles 2>/dev/null | grep -qx "$PROFILE"; then
  echo "AWS profile '$PROFILE' already exists — leaving it as-is."
else
  # If the URL placeholder wasn't edited, try borrowing it from an existing 'tuna' profile.
  if [[ "$SSO_START_URL" == *REPLACE* ]]; then
    SSO_START_URL="$(aws configure get sso_start_url --profile tuna 2>/dev/null || true)"
  fi
  if [[ -z "$SSO_START_URL" || "$SSO_START_URL" == *REPLACE* ]]; then
    echo "ERROR: set SSO_START_URL at the top of this script to your access portal URL first." >&2
    exit 1
  fi
  echo "Creating AWS profile '$PROFILE' for role '$ROLE'..."
  aws configure set sso_start_url  "$SSO_START_URL" --profile "$PROFILE"
  aws configure set sso_region     "$SSO_REGION"    --profile "$PROFILE"
  aws configure set sso_account_id "$ACCOUNT_ID"    --profile "$PROFILE"
  aws configure set sso_role_name  "$ROLE"          --profile "$PROFILE"
  aws configure set region         "$REGION"        --profile "$PROFILE"
  aws configure set output         json             --profile "$PROFILE"
fi

# ---- 2) Install the shell shortcuts -----------------------------------------
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

block="$(cat <<'EOF'
# >>> TelemeTuna instance control >>>
TUNA_REGION=__REGION__
# Override per-shell with: export TUNA_PROFILE=<your-profile>
TUNA_PROFILE="${TUNA_PROFILE:-__PROFILE__}"
tuna-id() {
  aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=telemetuna-prod" \
              "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query "Reservations[].Instances[].InstanceId" --output text \
    --region "$TUNA_REGION" --profile "$TUNA_PROFILE"
}
tuna-login()  { aws sso login --profile "$TUNA_PROFILE"; }
tuna-up()     { aws ec2 start-instances --instance-ids "$(tuna-id)" --region "$TUNA_REGION" --profile "$TUNA_PROFILE"; }
tuna-down()   { aws ec2 stop-instances  --instance-ids "$(tuna-id)" --region "$TUNA_REGION" --profile "$TUNA_PROFILE"; }
tuna-status() {
  aws ec2 describe-instances --instance-ids "$(tuna-id)" \
    --query "Reservations[].Instances[].{ID:InstanceId,State:State.Name,IP:PublicIpAddress}" \
    --output table --region "$TUNA_REGION" --profile "$TUNA_PROFILE"
}
tuna-ip() {
  aws ec2 describe-instances --instance-ids "$(tuna-id)" \
    --query "Reservations[].Instances[].PublicIpAddress" --output text \
    --region "$TUNA_REGION" --profile "$TUNA_PROFILE"
}
_tuna_browse() {  # open a URL in the default browser (mac/linux), else print it
  if command -v open >/dev/null 2>&1; then open "$1"
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$1"
  else echo "$1"; fi
}
tuna-grafana() { _tuna_browse "http://$(tuna-ip):3001"; }   # public, works for everyone
# Node-RED and pgAdmin are firewalled off — reached via a local SSM tunnel.
# These need an SSM-capable role (Operator/Admin), NOT InstanceController/Viewer.
tuna-nodered() {
  echo "Node-RED -> http://localhost:1881   (keep this window open; Ctrl-C to stop)"
  ( sleep 3; _tuna_browse http://localhost:1881 ) >/dev/null 2>&1 &
  aws ssm start-session --target "$(tuna-id)" \
    --document-name AWS-StartPortForwardingSession \
    --parameters '{"portNumber":["1881"],"localPortNumber":["1881"]}' \
    --region "$TUNA_REGION" --profile "$TUNA_PROFILE"
}
tuna-pgadmin() {
  echo "pgAdmin -> http://localhost:5051   (keep this window open; Ctrl-C to stop)"
  ( sleep 3; _tuna_browse http://localhost:5051 ) >/dev/null 2>&1 &
  aws ssm start-session --target "$(tuna-id)" \
    --document-name AWS-StartPortForwardingSession \
    --parameters '{"portNumber":["5051"],"localPortNumber":["5051"]}' \
    --region "$TUNA_REGION" --profile "$TUNA_PROFILE"
}
tuna-ssm()    { aws ssm start-session --target "$(tuna-id)" --region "$TUNA_REGION" --profile "$TUNA_PROFILE"; }
tuna-help() {
  cat <<USAGE
TelemeTuna controls (profile: $TUNA_PROFILE, region: $TUNA_REGION)
  tuna-login    Sign in (aws sso login) for this profile
  tuna-up       Start the instance and resume the stack
  tuna-down     Stop the instance (pause; data safe, same IP)
  tuna-status   Show instance ID, state, and public IP
  tuna-ip       Print just the public IP
  tuna-grafana  Open Grafana in your browser (public)
  tuna-nodered  Tunnel + open Node-RED via SSM (SSM-capable roles)
  tuna-pgadmin  Tunnel + open pgAdmin via SSM (SSM-capable roles)
  tuna-ssm      Shell into the box via SSM (SSM-capable roles)
  tuna-help     Show this help
USAGE
}
# <<< TelemeTuna instance control <<<
EOF
)"
block="${block//__REGION__/$REGION}"
block="${block//__PROFILE__/$PROFILE}"
printf '\n%s\n' "$block" >> "$RC"

# ---- 3) Tell the user what to do next ---------------------------------------
echo
echo "Installed TelemeTuna shortcuts into $RC (profile: $PROFILE, role: $ROLE)."
echo
echo "Commands now available:"
echo "  tuna-login    Sign in (aws sso login) for this profile"
echo "  tuna-up       Start the instance and resume the stack"
echo "  tuna-down     Stop the instance (pause; data safe, same IP)"
echo "  tuna-status   Show instance ID, state, and public IP"
echo "  tuna-ip       Print just the public IP"
echo "  tuna-grafana  Open Grafana in your browser (public)"
echo "  tuna-nodered  Tunnel + open Node-RED via SSM (SSM-capable roles)"
echo "  tuna-pgadmin  Tunnel + open pgAdmin via SSM (SSM-capable roles)"
echo "  tuna-ssm      Shell into the box via SSM (SSM-capable roles)"
echo "  tuna-help     List these commands anytime"
echo
echo "Final step (one-time browser login, then you're set):"
echo "  source $RC"
echo "  tuna-login"
echo "  tuna-status"