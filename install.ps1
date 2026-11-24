# omniskill installer for Windows (PowerShell 5.1+). Requires git.
#
#   irm https://raw.githubusercontent.com/uv07/omniskill/main/install.ps1 | iex
#   .\install.ps1 [-Claude] [-Antigravity] [-Project DIR] [-Update] [-Uninstall]
param(
  [switch]$Claude, [switch]$Antigravity, [string]$Project = "",
  [switch]$Update, [switch]$Uninstall
)
$ErrorActionPreference = "Stop"
$Repo = if ($env:OMNISKILL_REPO) { $env:OMNISKILL_REPO } else { "https://github.com/uv07/omniskill.git" }
$Branch = if ($env:OMNISKILL_BRANCH) { $env:OMNISKILL_BRANCH } else { "main" }
$H = $HOME
$targets = @()
if ($Claude) { $targets += Join-Path $H ".claude\skills\omniskill" }
if ($Antigravity) { $targets += Join-Path $H ".gemini\config\skills\omniskill" }
if ($Project) { $targets += (Join-Path $Project ".claude\skills\omniskill"), (Join-Path $Project ".agents\skills\omniskill") }
if ($targets.Count -eq 0) {
  if (Test-Path (Join-Path $H ".claude")) { $targets += Join-Path $H ".claude\skills\omniskill" }
  if (Test-Path (Join-Path $H ".gemini")) { $targets += Join-Path $H ".gemini\config\skills\omniskill" }
  if ($targets.Count -eq 0) { $targets += Join-Path $H ".claude\skills\omniskill" }
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git is required" }

foreach ($dest in $targets) {
  $isGit = Test-Path (Join-Path $dest ".git")
  if ($Uninstall) {
    $skill = Join-Path $dest "SKILL.md"
    if ((Test-Path $skill) -and (Select-String -Path $skill -Pattern '^name: omniskill' -Quiet)) {
      Write-Host "remove   $dest"; Remove-Item -Recurse -Force $dest
    } else { Write-Host "skip     $dest (not an omniskill install)" }
  } elseif ($isGit) {
    Write-Host "update   $dest"; git -C $dest pull --ff-only --quiet
  } elseif ($Update) {
    Write-Host "skip     $dest (not installed)"
  } elseif (Test-Path $dest) {
    Write-Warning "skip     $dest (exists and is not a git clone)"
  } else {
    Write-Host "install  $dest"
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    git clone --quiet --depth 1 --branch $Branch $Repo $dest
  }
}
if (-not $Uninstall) { Write-Host "Done. Restart Claude Code / Antigravity to load the skill." }
