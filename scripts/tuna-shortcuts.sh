# TelemeTuna shell shortcuts.
# Sourced from your shell rc by install-tuna-shortcuts.sh. Works in bash and zsh.
# Region is fixed; the active profile defaults to op-tuna and is switched by tuna-login-*.

TUNA_REGION="${TUNA_REGION:-ap-southeast-7}"
TUNA_PROFILE="${TUNA_PROFILE:-ic-tuna}"

# On Windows (Git Bash), make sure AWS CLI + the SSM plugin are on PATH even when this
# shell started with a stale PATH (VS Code / Git Bash inherit a PATH snapshot, so a
# tool installed after the shell opened isn't seen). No-op on macOS/Linux — those
# folders don't exist there, so nothing is added.
for _d in "/c/Program Files/Amazon/AWSCLIV2" "/c/Program Files (x86)/Amazon/AWSCLIV2" \
          "/c/Program Files/Amazon/SessionManagerPlugin/bin" "/c/Program Files (x86)/Amazon/SessionManagerPlugin/bin"; do
  if [ -d "$_d" ] && [[ ":$PATH:" != *":$_d:"* ]]; then PATH="$_d:$PATH"; fi
done
export PATH
unset _d

# Each login picks a role for THIS shell: signs in AND repoints the tuna-* actions.
tuna-login-op() { export TUNA_PROFILE=op-tuna; export AWS_PROFILE=op-tuna; aws sso login --profile op-tuna; }
tuna-login-ic() { export TUNA_PROFILE=ic-tuna; export AWS_PROFILE=ic-tuna; aws sso login --profile ic-tuna; }
tuna-login-ad() { export TUNA_PROFILE=ad-tuna; export AWS_PROFILE=ad-tuna; aws sso login --profile ad-tuna; }

tuna-whoami() { echo "active TUNA_PROFILE=$TUNA_PROFILE"; }
tuna-check() {
  if aws sts get-caller-identity --profile "$TUNA_PROFILE" >/dev/null 2>&1; then
    echo "Logged in ($TUNA_PROFILE): $(aws sts get-caller-identity --profile "$TUNA_PROFILE" --query Arn --output text)"
  else
    echo "NOT logged in for '$TUNA_PROFILE' — run: tuna-login-op | tuna-login-ic | tuna-login-ad"
  fi
}

# Look up the instance ID by tag. Prints a clear message (and returns non-zero) when
# nothing is found — e.g. the stack is down / not deployed, or you're not logged in.
tuna-id() {
  local id
  id="$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=telemetuna-prod" \
              "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query "Reservations[].Instances[].InstanceId" --output text \
    --region "$TUNA_REGION" --profile "$TUNA_PROFILE" 2>/dev/null)"
  if [ -z "$id" ] || [ "$id" = "None" ]; then
    echo "No 'telemetuna-prod' instance found — the stack looks down or not deployed (terraform apply), or you're not logged in (try tuna-check)." >&2
    return 1
  fi
  printf '%s\n' "$id"
}
tuna-start()  { local id; id="$(tuna-id)" || return 1; aws ec2 start-instances --instance-ids "$id" --region "$TUNA_REGION" --profile "$TUNA_PROFILE"; }
tuna-stop()   { local id; id="$(tuna-id)" || return 1; aws ec2 stop-instances  --instance-ids "$id" --region "$TUNA_REGION" --profile "$TUNA_PROFILE"; }
tuna-status() {
  local id; id="$(tuna-id)" || return 1
  aws ec2 describe-instances --instance-ids "$id" \
    --query "Reservations[].Instances[].{ID:InstanceId,State:State.Name,IP:PublicIpAddress}" \
    --output table --region "$TUNA_REGION" --profile "$TUNA_PROFILE"
}
tuna-ip() {
  local id; id="$(tuna-id)" || return 1
  aws ec2 describe-instances --instance-ids "$id" \
    --query "Reservations[].Instances[].PublicIpAddress" --output text \
    --region "$TUNA_REGION" --profile "$TUNA_PROFILE"
}

_tuna_browse() {
  if command -v open >/dev/null 2>&1; then open "$1"
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$1"
  elif command -v start >/dev/null 2>&1; then start "$1" # Added Windows Git Bash support
  else echo "$1"; fi
}
# The UI ports (3001/1881/5051) are open in the security group, so these just
# open the public URL directly — no SSM tunnel needed, works for any role.
tuna-grafana() { local ip; ip="$(tuna-ip)" || return 1; _tuna_browse "http://$ip:3001"; }   # Grafana
tuna-nodered() { local ip; ip="$(tuna-ip)" || return 1; _tuna_browse "http://$ip:1881"; }   # Node-RED
tuna-pgadmin() { local ip; ip="$(tuna-ip)" || return 1; _tuna_browse "http://$ip:5051"; }   # pgAdmin

tuna-ssm() { local id; id="$(tuna-id)" || return 1; aws ssm start-session --target "$id" --region "$TUNA_REGION" --profile "$TUNA_PROFILE"; }

# --- Remote one-shot commands: run on the box via SSM and print the output. ---
# Need an SSM-capable role (op-tuna/ad-tuna) AND the instance running.
_tuna_run() {  # _tuna_run "<shell command>"  -> prints its stdout from the instance
  local id cid params
  id="$(tuna-id)" || return 1
  params="$(printf '{"commands":["%s"]}' "$1")"
  cid="$(aws ssm send-command --instance-ids "$id" \
    --document-name AWS-RunShellScript --parameters "$params" \
    --query Command.CommandId --output text \
    --region "$TUNA_REGION" --profile "$TUNA_PROFILE")" || return 1
  aws ssm wait command-executed --command-id "$cid" --instance-id "$id" \
    --region "$TUNA_REGION" --profile "$TUNA_PROFILE" 2>/dev/null || true
  aws ssm get-command-invocation --command-id "$cid" --instance-id "$id" \
    --query StandardOutputContent --output text \
    --region "$TUNA_REGION" --profile "$TUNA_PROFILE"
}
tuna-ps()      { _tuna_run "docker ps -a --format '{{.Names}}: {{.Status}}'"; }
tuna-disk()    { _tuna_run "df -h /"; }
tuna-logs()    { _tuna_run "cd /opt/RapidAmente-TelemeTuna && docker compose -f docker-compose.yaml -f docker-compose.production.yaml logs --tail 40 ${1:-}"; }
tuna-restart() { _tuna_run "cd /opt/RapidAmente-TelemeTuna && docker compose -f docker-compose.yaml -f docker-compose.production.yaml restart ${1:-}"; }

tuna-help() {
  echo "TelemeTuna controls — active profile: $TUNA_PROFILE (region: $TUNA_REGION)"
  echo
  echo "  ANY role (op-tuna / ic-tuna / ad-tuna):"
  printf '    %-13s | %s\n' "COMMAND" "WHAT IT DOES"
  printf '    %-13s-+-%s\n' "-------------" "---------------------------------------------"
  printf '    %-13s | %s\n' "tuna-login-op" "Sign in as Operator (op-tuna) for this shell"
  printf '    %-13s | %s\n' "tuna-login-ic" "Sign in as InstanceController (ic-tuna)"
  printf '    %-13s | %s\n' "tuna-login-ad" "Sign in as Admin (ad-tuna)"
  printf '    %-13s | %s\n' "tuna-whoami"   "Show which profile the actions use"
  printf '    %-13s | %s\n' "tuna-check"    "Check whether you are logged in (role ARN)"
  printf '    %-13s | %s\n' "tuna-start"    "Start the instance and resume the stack"
  printf '    %-13s | %s\n' "tuna-stop"     "Stop the instance (pause; data safe, same IP)"
  printf '    %-13s | %s\n' "tuna-status"   "Show instance ID, state, and public IP"
  printf '    %-13s | %s\n' "tuna-ip"       "Print just the public IP"
  printf '    %-13s | %s\n' "tuna-grafana"  "Open Grafana in your browser"
  printf '    %-13s | %s\n' "tuna-nodered"  "Open Node-RED in your browser"
  printf '    %-13s | %s\n' "tuna-pgadmin"  "Open pgAdmin in your browser"
  printf '    %-13s | %s\n' "tuna-help"     "Show this help"
  echo
  echo "  SSM-capable roles ONLY (op-tuna / ad-tuna) + instance must be running:"
  printf '    %-13s | %s\n' "COMMAND" "WHAT IT DOES"
  printf '    %-13s-+-%s\n' "-------------" "---------------------------------------------"
  printf '    %-13s | %s\n' "tuna-ssm"     "Shell into the box via SSM"
  printf '    %-13s | %s\n' "tuna-ps"      "Container status + health"
  printf '    %-13s | %s\n' "tuna-logs"    "Tail logs; one svc: tuna-logs grafana"
  printf '    %-13s | %s\n' "tuna-restart" "Restart stack; or tuna-restart grafana"
  printf '    %-13s | %s\n' "tuna-disk"    "Show disk usage on the box"
}
