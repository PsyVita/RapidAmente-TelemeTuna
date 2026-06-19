<#
  bootstrap-windows.ps1 — one-command Windows setup for the TelemeTuna tuna-* tools.

  Why this exists: the installer is a bash script, and Windows has no bash by default.
  This PowerShell script (PowerShell IS built into Windows) installs Git for Windows
  (which includes Git Bash), then hands off to the bash installer — which in turn
  installs AWS CLI + the SSM plugin (if missing), creates the SSO profiles, and adds
  the tuna-* shortcuts.

  HOW TO RUN — in PowerShell, from the repo root:
    powershell -ExecutionPolicy Bypass -File scripts\bootstrap-windows.ps1

  AFTER it finishes, open Git Bash (not PowerShell) and run:
    source ~/.bashrc
    tuna-login-op        # or tuna-login-ic / tuna-login-ad
    tuna-help
#>

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Find-Bash {
  $candidates = @(
    (Get-Command bash.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1),
    "$env:ProgramFiles\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
  )
  foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
  return $null
}

Write-Host "== TelemeTuna Windows bootstrap =="

# 1) Ensure Git Bash is present (install Git for Windows via winget if not).
$bash = Find-Bash
if (-not $bash) {
  Write-Host "Git Bash not found - installing Git for Windows..."
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget install -e --id Git.Git --accept-source-agreements --accept-package-agreements
  } else {
    Write-Host "ERROR: winget is unavailable on this machine." -ForegroundColor Red
    Write-Host "Install Git for Windows manually from https://git-scm.com/download/win then re-run this script."
    exit 1
  }
  $bash = Find-Bash
  if (-not $bash) {
    Write-Host "Git installed, but bash.exe wasn't found on PATH yet." -ForegroundColor Yellow
    Write-Host "Close and reopen PowerShell, then run this script again."
    exit 1
  }
}
Write-Host "Using bash: $bash"

# 2) Run the bash installer inside Git Bash (forward-slash path; run via 'bash' so the
#    file's execute bit doesn't matter on Windows).
$unixDir = ($ScriptDir -replace '\\', '/')
Write-Host "Running the bash installer (AWS CLI, SSM plugin, profiles, shortcuts)..."
& $bash -lc "cd '$unixDir' && bash install-tuna-shortcuts.sh"
if ($LASTEXITCODE -ne 0) {
  Write-Host "The bash installer reported an error (exit $LASTEXITCODE). See the output above." -ForegroundColor Red
  exit $LASTEXITCODE
}

Write-Host ""
Write-Host "== Done. Final step: open Git Bash (not PowerShell) and run: =="
Write-Host "   source ~/.bashrc"
Write-Host "   tuna-login-op        # or tuna-login-ic / tuna-login-ad"
Write-Host "   tuna-help"
