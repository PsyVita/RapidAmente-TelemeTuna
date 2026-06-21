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

# --- A little fish flair (colors degrade gracefully if the terminal ignores them) ---
_TUNA_GREEN=$'\033[32m'; _TUNA_YELLOW=$'\033[33m'; _TUNA_RED=$'\033[31m'
_TUNA_CYAN=$'\033[36m';  _TUNA_DIM=$'\033[2m';     _TUNA_RESET=$'\033[0m'
_TUNA_BI=$'\033[1;3m'    # bold + italic (normal/white text) — for the Docker-state lines

# Seconds since the epoch — used to time each stage. Works on macOS, Linux, Git Bash.
_tuna_now() { date +%s; }

# Status-line printers for tuna-doctor / tuna-health.
_tuna_ok()   { printf '   %s✔%s %s\n' "$_TUNA_GREEN"  "$_TUNA_RESET" "$1"; }
_tuna_ng()   { printf '   %s✘%s %s\n' "$_TUNA_RED"    "$_TUNA_RESET" "$1"; }
_tuna_warn() { printf '   %s⚠%s %s\n' "$_TUNA_YELLOW" "$_TUNA_RESET" "$1"; }

# Yes/no confirmation for destructive commands. Set TUNA_YES=1 to skip (automation).
# Defaults to NO on empty/EOF, so a non-interactive run never proceeds by accident.
_tuna_confirm() {
  [ -n "${TUNA_YES:-}" ] && return 0
  local ans
  printf '   %s%s [y/N] %s' "$_TUNA_YELLOW" "$1" "$_TUNA_RESET"
  read -r ans 2>/dev/null || true
  case "$ans" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

# Color-code docker/compose status words on stdin. Portable across BSD (macOS) and
# GNU (Linux/Git Bash) sed: uses [(] for literal parens and & for the match, no \b.
# Order matters where one word contains another (unhealthy/healthy, Unhealthy/Healthy).
# Set TUNA_NO_COLOR=1 to disable.
_tuna_colorize() {
  [ -n "${TUNA_NO_COLOR:-}" ] && { cat; return; }
  sed -E \
    -e "s/[(]unhealthy[)]/${_TUNA_RED}&${_TUNA_RESET}/g" \
    -e "s/[(]health: starting[)]/${_TUNA_YELLOW}&${_TUNA_RESET}/g" \
    -e "s/[(]healthy[)]/${_TUNA_GREEN}&${_TUNA_RESET}/g" \
    -e "s/(Unhealthy|Error|Dead|Failed)/${_TUNA_RED}&${_TUNA_RESET}/g" \
    -e "s/(Started|Running|Created|Recreated|Healthy)/${_TUNA_GREEN}&${_TUNA_RESET}/g" \
    -e "s/(Restarting|Restarted|Stopping|Removing|Recreating|Pulling)/${_TUNA_YELLOW}&${_TUNA_RESET}/g" \
    -e "s/(Stopped|Removed|Exited)/${_TUNA_DIM}&${_TUNA_RESET}/g"
}

# A swimming-fish spinner frame, chosen by tick number. No array indexing, so it
# behaves identically in bash and zsh.
_tuna_fish() {
  case $(( ${1:-0} % 4 )) in
    0) printf '><>   ' ;;
    1) printf ' ><>  ' ;;
    2) printf '  ><> ' ;;
    *) printf '   ><>' ;;
  esac
}

# Poll a command until its output contains <want>, animating a fish while we wait.
#   _tuna_wait "<label>" "<want>" <command> [args...]
_tuna_wait() {
  local label="$1" want="$2"; shift 2
  local i=0 waited=0 timeout="${TUNA_WAIT_TIMEOUT:-180}" out start now
  start="$(_tuna_now)"
  while [ "$waited" -lt "$timeout" ]; do
    out="$("$@" 2>/dev/null || true)"
    case "$out" in
      *"$want"*)
        now=$(( $(_tuna_now) - start ))
        printf '\r   %s✔%s %s %s(%ds)%s                 \n' "$_TUNA_GREEN" "$_TUNA_RESET" "$label" "$_TUNA_DIM" "$now" "$_TUNA_RESET"
        return 0 ;;
    esac
    printf '\r   %s  %s %s(%ds)%s ...' "$(_tuna_fish "$i")" "$label" "$_TUNA_DIM" "$(( $(_tuna_now) - start ))" "$_TUNA_RESET"
    i=$((i + 1)); sleep 3; waited=$((waited + 3))
  done
  printf '\r   %s⏳%s %s — still waiting after %ss     \n' "$_TUNA_YELLOW" "$_TUNA_RESET" "$label" "$timeout"
  return 1
}

# Wait for Docker to come up and settle (nothing still "health: starting"/restarting),
# but cap the whole thing at TUNA_DOCKER_WAIT secs (default 60 — the hard cap for the
# operation). Once the cap is hit we just present whatever's there. Reports only; never
# starts anything. Returns 0 if Docker is up (settled or not), 1 if it never came up.
_tuna_wait_docker() {
  local timeout="${TUNA_DOCKER_WAIT:-60}" i=0 start out up=""
  start="$(_tuna_now)"
  while [ "$(( $(_tuna_now) - start ))" -lt "$timeout" ]; do
    out="$(_tuna_run "docker ps --format '{{.Names}} {{.Status}}'" 2>/dev/null)"
    if [ -n "$out" ]; then
      up=1
      printf '%s' "$out" | grep -qiE 'health: starting|restarting' || { printf '\r\033[K'; return 0; }
    fi
    printf '\r   %s  waiting for Docker to settle %s(%ds)%s ...' "$(_tuna_fish "$i")" "$_TUNA_DIM" "$(( $(_tuna_now) - start ))" "$_TUNA_RESET"
    i=$((i + 1)); sleep 5
  done
  printf '\r\033[K'
  [ -n "$up" ] && return 0 || return 1
}

# Each login picks a role for THIS shell: signs in AND repoints the tuna-* actions.
tuna-login-op() { export TUNA_PROFILE=op-tuna; export AWS_PROFILE=op-tuna; aws sso login --profile op-tuna; }
tuna-login-ic() { export TUNA_PROFILE=ic-tuna; export AWS_PROFILE=ic-tuna; aws sso login --profile ic-tuna; }
tuna-login-ad() { export TUNA_PROFILE=ad-tuna; export AWS_PROFILE=ad-tuna; aws sso login --profile ad-tuna; }

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
    echo "No 'telemetuna-prod' instance found — the stack looks down or not deployed (terraform apply), or you're not logged in (try tuna-doctor)." >&2
    return 1
  fi
  printf '%s\n' "$id"
}
tuna-start() {
  local id begin; id="$(tuna-id)" || return 1
  begin="$(_tuna_now)"
  printf '\n   %s🐟  Starting TelemeTuna%s  (%s)\n\n' "$_TUNA_CYAN" "$_TUNA_RESET" "$id"
  if ! aws ec2 start-instances --instance-ids "$id" \
        --region "$TUNA_REGION" --profile "$TUNA_PROFILE" >/dev/null 2>&1; then
    printf '   %s✘%s Could not start the instance — run tuna-doctor to diagnose.\n' "$_TUNA_RED" "$_TUNA_RESET"
    return 1
  fi
  _tuna_wait "EC2 instance running" "running" \
    aws ec2 describe-instances --instance-ids "$id" \
      --query "Reservations[].Instances[].State.Name" --output text \
      --region "$TUNA_REGION" --profile "$TUNA_PROFILE"
  # Report whether Docker is up (needs an SSM-capable role). Never auto-starts it.
  if aws ssm describe-instance-information \
        --filters "Key=InstanceIds,Values=$id" \
        --region "$TUNA_REGION" --profile "$TUNA_PROFILE" >/dev/null 2>&1; then
    _tuna_wait "SSM agent online" "Online" \
      aws ssm describe-instance-information \
        --filters "Key=InstanceIds,Values=$id" \
        --query "InstanceInformationList[].PingStatus" --output text \
        --region "$TUNA_REGION" --profile "$TUNA_PROFILE"
    if _tuna_wait_docker; then
      case "$(_tuna_compose_kind)" in
        production) printf '   %s✔%s Production stack is running — containers:\n' "$_TUNA_GREEN" "$_TUNA_RESET" ;;
        dev)        printf '   %s⚠%s DEV stack is running (base compose, not production) — containers:\n' "$_TUNA_YELLOW" "$_TUNA_RESET" ;;
        *)          printf '   %s✔%s Docker is running — containers:\n' "$_TUNA_GREEN" "$_TUNA_RESET" ;;
      esac
      tuna-ps 2>/dev/null | sed 's/^/      /'
    else
      printf '   %s✘ Docker is NOT running%s — start the stack with: %stuna-prod-up%s\n' "$_TUNA_RED" "$_TUNA_RESET" "$_TUNA_CYAN" "$_TUNA_RESET"
    fi
    _tuna_storage_line
  else
    printf '   %s🐡%s  Instance is up. If the Docker containers seem off, contact someone with the op role to check.\n' "$_TUNA_YELLOW" "$_TUNA_RESET"
  fi
  local ip total; ip="$(tuna-ip 2>/dev/null)"; total=$(( $(_tuna_now) - begin ))
  printf '\n   %s🌊  Grafana → http://%s:3001%s   %s(total %ds)%s\n\n' "$_TUNA_GREEN" "$ip" "$_TUNA_RESET" "$_TUNA_DIM" "$total" "$_TUNA_RESET"
}
tuna-stop() {
  local id kind; id="$(tuna-id)" || return 1
  _tuna_confirm "Stop instance $id?" || { printf '   Cancelled.\n'; return 1; }
  printf '\n   %s🐟  Stopping TelemeTuna%s  (%s)\n\n' "$_TUNA_CYAN" "$_TUNA_RESET" "$id"
  # Report Docker's state right now (best-effort; needs an SSM-capable role).
  if aws ssm describe-instance-information \
        --filters "Key=InstanceIds,Values=$id" \
        --region "$TUNA_REGION" --profile "$TUNA_PROFILE" >/dev/null 2>&1; then
    kind="$(_tuna_compose_kind)"
    case "$kind" in
      production) printf '   %s↳ Production stack is running — it goes down with the instance and comes back up automatically next start.%s\n' "$_TUNA_BI" "$_TUNA_RESET" ;;
      dev)        printf '   %s↳ DEV stack is running (base compose, not production) — it goes down with the instance and comes back up automatically next start.%s\n' "$_TUNA_BI" "$_TUNA_RESET" ;;
      *)          printf '   %s↳ Docker is not running — it will stay down next start too; bring it up with tuna-prod-up.%s\n' "$_TUNA_BI" "$_TUNA_RESET" ;;
    esac
    _tuna_storage_line
  else
    printf '   %s🐡%s  Sign in with tuna-login-op to check Docker status.\n' "$_TUNA_YELLOW" "$_TUNA_RESET"
  fi
  if ! aws ec2 stop-instances --instance-ids "$id" \
        --region "$TUNA_REGION" --profile "$TUNA_PROFILE" >/dev/null 2>&1; then
    printf '   %s✘%s Could not stop the instance — run tuna-doctor to diagnose.\n' "$_TUNA_RED" "$_TUNA_RESET"
    return 1
  fi
  _tuna_wait "EC2 instance stopped" "stopped" \
    aws ec2 describe-instances --instance-ids "$id" \
      --query "Reservations[].Instances[].State.Name" --output text \
      --region "$TUNA_REGION" --profile "$TUNA_PROFILE"
  printf '\n   %s💤  Stopped — data is safe; same IP next start.%s\n\n' "$_TUNA_GREEN" "$_TUNA_RESET"
}
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

# Print a service's URL and whether it's responding (HTTP probe over the public port,
# so it works for ANY role — no SSM). Returns 0 if up (caller then opens the browser),
# 1 if no answer (caller skips opening a dead tab). If curl is missing, returns 0.
_tuna_probe() {
  local name="$1" url="$2" code
  printf '   %s%s%s → %s\n' "$_TUNA_CYAN" "$name" "$_TUNA_RESET" "$url"
  command -v curl >/dev/null 2>&1 || return 0
  code="$(curl -sS -m 6 -o /dev/null -w '%{http_code}' "$url" 2>/dev/null)"
  if [ -z "$code" ] || [ "$code" = "000" ]; then
    printf '   %s✘ not responding%s — is the stack up? (tuna-ps / tuna-prod-up)\n' "$_TUNA_RED" "$_TUNA_RESET"
    return 1
  fi
  printf '   %s✔ responding%s (HTTP %s)\n' "$_TUNA_GREEN" "$_TUNA_RESET" "$code"
  return 0
}
# The UI ports (3001/1881/5051) are open in the security group, so these just
# open the public URL directly — no SSM tunnel needed, works for any role.
tuna-grafana() { local ip; ip="$(tuna-ip)" || return 1; _tuna_probe "Grafana" "http://$ip:3001" && _tuna_browse "http://$ip:3001"; }   # Grafana
tuna-nodered() { local ip; ip="$(tuna-ip)" || return 1; _tuna_probe "Node-RED" "http://$ip:1881" && _tuna_browse "http://$ip:1881"; }   # Node-RED
tuna-pgadmin() { local ip; ip="$(tuna-ip)" || return 1; _tuna_probe "pgAdmin" "http://$ip:5051" && _tuna_browse "http://$ip:5051"; }   # pgAdmin

tuna-ssm() { local id; id="$(tuna-id)" || return 1; aws ssm start-session --target "$id" --region "$TUNA_REGION" --profile "$TUNA_PROFILE"; }

# --- Remote one-shot commands: run on the box via SSM and print the output. ---
# Need an SSM-capable role (op-tuna/ad-tuna) AND the instance running.
_tuna_run() {  # _tuna_run "<shell command>" -> prints stdout; on failure shows status + stderr
  local id params cid st out err   # 'st' not 'status' — 'status' is read-only in zsh
  id="$(tuna-id)" || return 1
  params="$(printf '{"commands":["%s"]}' "$1")"
  # send-command: capture stderr too, so an AccessDenied / role problem is shown, not swallowed.
  cid="$(aws ssm send-command --instance-ids "$id" \
    --document-name AWS-RunShellScript --parameters "$params" \
    --query Command.CommandId --output text \
    --region "$TUNA_REGION" --profile "$TUNA_PROFILE" 2>&1)" || {
      printf '%stuna:%s could not start the remote command (SSM send-command failed).\n' "$_TUNA_RED" "$_TUNA_RESET" >&2
      printf '      %s\n' "$cid" >&2
      printf '      Are you on an SSM-capable role (tuna-login-op / tuna-login-ad) and is the box running (tuna-status)?\n' >&2
      return 1
    }
  aws ssm wait command-executed --command-id "$cid" --instance-id "$id" \
    --region "$TUNA_REGION" --profile "$TUNA_PROFILE" 2>/dev/null || true
  st="$(aws ssm get-command-invocation --command-id "$cid" --instance-id "$id" \
    --query Status --output text --region "$TUNA_REGION" --profile "$TUNA_PROFILE" 2>/dev/null)"
  out="$(aws ssm get-command-invocation --command-id "$cid" --instance-id "$id" \
    --query StandardOutputContent --output text --region "$TUNA_REGION" --profile "$TUNA_PROFILE" 2>/dev/null)"
  [ -n "$out" ] && printf '%s\n' "$out"
  if [ "$st" != "Success" ]; then
    err="$(aws ssm get-command-invocation --command-id "$cid" --instance-id "$id" \
      --query StandardErrorContent --output text --region "$TUNA_REGION" --profile "$TUNA_PROFILE" 2>/dev/null)"
    printf '%stuna:%s remote command did not succeed (status: %s)\n' "$_TUNA_YELLOW" "$_TUNA_RESET" "${st:-unknown}" >&2
    [ -n "$err" ] && printf '%s\n' "$err" >&2
    return 1
  fi
}
# The compose invocation used on the box (kept in one place). prod-up/down keep
# compose's progress on stderr (shown only if it fails); logs/restart fold it in.
_TUNA_COMPOSE="cd /opt/RapidAmente-TelemeTuna && docker compose -f docker-compose.yaml -f docker-compose.production.yaml"

tuna-ps() {
  local out rc
  out="$(_tuna_run "docker ps -a --format '{{.Names}}: {{.Status}}'")"; rc=$?
  [ "$rc" -ne 0 ] && return "$rc"          # _tuna_run already explained the error
  if [ -z "$out" ]; then
    printf '   No containers found — run %stuna-prod-up%s to start the stack.\n' "$_TUNA_CYAN" "$_TUNA_RESET"
  else
    printf '%s\n' "$out" | _tuna_colorize
  fi
}
tuna-storage()     { _tuna_run "df -h / /mnt/pgdata"; }   # OS/root volume + Postgres data volume

# Print a compact "Storage  OS xx%  ·  DB yy%" line (one SSM call); no-op on failure.
# Used by tuna-start / tuna-stop / tuna-prod-up.
_tuna_storage_line() {
  local out root data
  out="$(_tuna_run "df -hP / /mnt/pgdata" 2>/dev/null)" || return 0
  root="$(printf '%s\n' "$out" | awk '$NF=="/"{print $(NF-1)}')"
  data="$(printf '%s\n' "$out" | awk '$NF=="/mnt/pgdata"{print $(NF-1)}')"
  [ -z "$root$data" ] && return 0
  printf '   %sStorage%s  OS %s  ·  DB %s\n' "$_TUNA_CYAN" "$_TUNA_RESET" "${root:-n/a}" "${data:-n/a}"
}

# What's running on the box: echoes "production", "dev", or "" (nothing). One SSM call.
# Reads the compose config_files label on the running containers — the production
# stack is brought up with docker-compose.production.yaml, the dev stack isn't.
_tuna_compose_kind() {
  local labels
  labels="$(_tuna_run "docker ps --format '{{.Labels}}'" 2>/dev/null)"
  case "$labels" in
    *docker-compose.production*) printf 'production' ;;
    *com.docker.compose*)        printf 'dev' ;;
    *)                           printf '' ;;
  esac
}
tuna-logs()        { _tuna_run "$_TUNA_COMPOSE logs --tail 40 ${1:-} 2>&1"; }
tuna-restart()     { _tuna_run "$_TUNA_COMPOSE restart ${1:-} 2>&1" | _tuna_colorize; }
tuna-prod-up() {   # start the prod stack (optional: one service)
  printf '   %s🐟 Bringing the prod stack up...%s\n' "$_TUNA_CYAN" "$_TUNA_RESET"
  if _tuna_run "$_TUNA_COMPOSE up -d ${1:-}" >/dev/null; then
    printf '   %s✔ Done.%s Run %stuna-ps%s to check the containers.\n' "$_TUNA_GREEN" "$_TUNA_RESET" "$_TUNA_CYAN" "$_TUNA_RESET"
    _tuna_storage_line
  else
    printf '   %s✘ Prod up did not complete cleanly%s — see the error above.\n' "$_TUNA_RED" "$_TUNA_RESET"
  fi
}
tuna-prod-down() {   # stop+remove prod containers (data volumes kept)
  _tuna_confirm "Remove the prod containers (compose down)? Data volumes are kept." || { printf '   Cancelled.\n'; return 1; }
  printf '   %s🐟 Taking the prod stack down...%s\n' "$_TUNA_CYAN" "$_TUNA_RESET"
  if _tuna_run "$_TUNA_COMPOSE down ${1:-}" >/dev/null; then
    printf '   %s✔ Done.%s Run %stuna-ps%s to confirm.\n' "$_TUNA_GREEN" "$_TUNA_RESET" "$_TUNA_CYAN" "$_TUNA_RESET"
  else
    printf '   %s✘ Prod down did not complete cleanly%s — see the error above.\n' "$_TUNA_RED" "$_TUNA_RESET"
  fi
}

tuna-health() {   # one-shot readout: instance + Docker + disk + UIs
  local id; id="$(tuna-id)" || return 1
  printf '\n   %s🐟 TelemeTuna health%s  (%s)\n\n' "$_TUNA_CYAN" "$_TUNA_RESET" "$id"
  local info state ip
  info="$(aws ec2 describe-instances --instance-ids "$id" \
    --query 'Reservations[].Instances[].[State.Name,PublicIpAddress]' --output text \
    --region "$TUNA_REGION" --profile "$TUNA_PROFILE" 2>/dev/null)"
  state="$(printf '%s\n' "$info" | awk 'NR==1{print $1}')"
  ip="$(printf '%s\n' "$info" | awk 'NR==1{print $2}')"
  if [ "$state" = "running" ]; then
    _tuna_ok "Instance running   IP: $ip"
  else
    _tuna_warn "Instance: ${state:-unknown} — start it with tuna-start"
    echo; return 0
  fi
  if aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$id" \
        --region "$TUNA_REGION" --profile "$TUNA_PROFILE" >/dev/null 2>&1; then
    printf '\n   %sContainers%s\n' "$_TUNA_CYAN" "$_TUNA_RESET"
    tuna-ps 2>/dev/null | sed 's/^/      /'
    printf '\n   %sDisk%s\n' "$_TUNA_CYAN" "$_TUNA_RESET"
    tuna-storage 2>/dev/null | sed 's/^/      /'
  else
    _tuna_warn "Sign in with tuna-login-op to see Docker, containers, and disk."
  fi
  printf '\n   %sServices%s\n' "$_TUNA_CYAN" "$_TUNA_RESET"
  _tuna_probe "Grafana " "http://$ip:3001"
  _tuna_probe "Node-RED" "http://$ip:1881"
  _tuna_probe "pgAdmin " "http://$ip:5051"
  echo
}
tuna-doctor() {   # diagnose setup / login / role
  printf '\n   %s🐟 TelemeTuna doctor%s — profile: %s\n\n' "$_TUNA_CYAN" "$_TUNA_RESET" "$TUNA_PROFILE"
  if command -v aws >/dev/null 2>&1; then _tuna_ok "AWS CLI installed ($(aws --version 2>&1 | awk '{print $1}'))"
  else _tuna_ng "AWS CLI not found — re-run scripts/install-tuna-shortcuts.sh"; fi
  if command -v session-manager-plugin >/dev/null 2>&1; then _tuna_ok "SSM Session Manager plugin installed"
  else _tuna_warn "SSM plugin not found — needed for tuna-ssm/ps/logs (re-run the installer)"; fi
  local p missing=""
  for p in op-tuna ic-tuna ad-tuna; do
    aws configure list-profiles 2>/dev/null | grep -qx "$p" || missing="$missing $p"
  done
  if [ -z "$missing" ]; then _tuna_ok "Profiles configured (op-tuna, ic-tuna, ad-tuna)"
  else _tuna_warn "Missing profiles:$missing — re-run the installer"; fi
  local arn
  arn="$(aws sts get-caller-identity --profile "$TUNA_PROFILE" --query Arn --output text 2>/dev/null)"
  if [ -n "$arn" ]; then
    _tuna_ok "Logged in as $TUNA_PROFILE"
    printf '       %s%s%s\n' "$_TUNA_DIM" "$arn" "$_TUNA_RESET"
  else
    _tuna_ng "Not logged in for $TUNA_PROFILE — run: tuna-login-op | tuna-login-ic | tuna-login-ad"
  fi
  local id; id="$(tuna-id 2>/dev/null)"
  if [ -n "$id" ]; then _tuna_ok "Instance found: $id"
  else _tuna_ng "No telemetuna-prod instance found (is it deployed? are you logged in?)"; fi
  if [ -n "$id" ]; then
    if aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$id" \
          --region "$TUNA_REGION" --profile "$TUNA_PROFILE" >/dev/null 2>&1; then
      _tuna_ok "SSM access OK — Docker commands (tuna-ps / tuna-prod-up / tuna-logs) will work"
    else
      _tuna_warn "No SSM on this role — start/stop works; Docker commands need op-tuna/ad-tuna"
    fi
  fi
  echo
}
tuna-help() {
  printf '%s><>  TelemeTuna controls%s — active profile: %s (region: %s)\n' "$_TUNA_CYAN" "$_TUNA_RESET" "$TUNA_PROFILE" "$TUNA_REGION"
  echo
  echo "  ANY role (op-tuna / ic-tuna / ad-tuna):"
  printf '    %-13s | %s\n' "COMMAND" "WHAT IT DOES"
  printf '    %-13s-+-%s\n' "-------------" "---------------------------------------------"
  printf '    %-13s | %s\n' "tuna-login-op" "Sign in as Operator (op-tuna) for this shell"
  printf '    %-13s | %s\n' "tuna-login-ic" "Sign in as InstanceController (ic-tuna)"
  printf '    %-13s | %s\n' "tuna-login-ad" "Sign in as Admin (ad-tuna)"
  printf '    %-13s | %s\n' "tuna-doctor"   "Diagnose setup / login / role (+ your role ARN)"
  printf '    %-13s | %s\n' "tuna-health"   "Full status: instance, Docker, disk, UIs"
  printf '    %-13s | %s\n' "tuna-start"    "Start the instance and resume the stack"
  printf '    %-13s | %s\n' "tuna-stop"     "Stop the instance (pause; data safe, same IP)"
  printf '    %-13s | %s\n' "tuna-status"   "Show instance ID, state, and public IP"
  printf '    %-13s | %s\n' "tuna-ip"       "Print just the public IP"
  printf '    %-13s | %s\n' "tuna-grafana"  "Show Grafana status + open it"
  printf '    %-13s | %s\n' "tuna-nodered"  "Show Node-RED status + open it"
  printf '    %-13s | %s\n' "tuna-pgadmin"  "Show pgAdmin status + open it"
  printf '    %-13s | %s\n' "tuna-help"     "Show this help"
  echo
  echo "  SSM-capable roles ONLY (op-tuna / ad-tuna) + instance must be running:"
  printf '    %-16s | %s\n' "COMMAND" "WHAT IT DOES"
  printf '    %-16s-+-%s\n' "----------------" "---------------------------------------------"
  printf '    %-16s | %s\n' "tuna-ssm"         "Shell into the box via SSM"
  printf '    %-16s | %s\n' "tuna-ps"          "Container status + health"
  printf '    %-16s | %s\n' "tuna-logs"        "Tail logs; one svc: tuna-logs grafana"
  printf '    %-16s | %s\n' "tuna-restart"     "Restart stack; or tuna-restart grafana"
  printf '    %-16s | %s\n' "tuna-prod-up"     "Start the prod stack (compose up -d)"
  printf '    %-16s | %s\n' "tuna-prod-down"   "Stop+remove prod stack (compose down)"
  printf '    %-16s | %s\n' "tuna-storage"     "Storage usage: OS/root + data volume"
}
