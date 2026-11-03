param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('active', 'deprecated', 'superseded')]
  [string]$Status,
  [string]$Reason = '',
  [string]$By = $env:USERNAME,
  [switch]$NoCommit
)
$ErrorActionPreference = 'Stop'
$root   = $PSScriptRoot
$state  = Join-Path $root 'STATUS.json'
$readme = Join-Path $root 'report\README.md'

if (-not (Test-Path $state)) { throw "missing $state" }
$s = Get-Content $state -Raw | ConvertFrom-Json
$prev = $s.status

$entry = [pscustomobject]@{
  at_utc  = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  from    = $prev
  to      = $Status
  by      = $By
  reason  = $Reason
}
$s.status    = $Status
$s.since_utc = $entry.at_utc
$s.by        = $By
$s.reason    = $Reason
$s.history   = @($s.history) + $entry
$s | ConvertTo-Json -Depth 6 | Set-Content $state -Encoding UTF8

if (Test-Path $readme) {
  $lines = Get-Content $readme
  $banner = "**Status:** $Status" + $(if ($Reason) { " since $($entry.at_utc) because $Reason" } else { " since $($entry.at_utc)" })
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\*\*Status:\*\*') { $idx = $i; break } }
  if ($idx -ge 0) {
    $lines[$idx] = $banner
  } else {
    $lines = @($lines[0], '', $banner) + $lines[1..($lines.Count - 1)]
  }
  if ($Status -eq 'deprecated') {
    $notice = '> DEPRECATED. This report is withdrawn. Do not act on it without reading STATUS.json for the reason and the superseding reference.'
    if (-not ($lines -contains $notice)) { $lines = @($lines[0], '', $notice) + $lines[1..($lines.Count - 1)] }
  } else {
    $lines = @($lines | Where-Object { $_ -notmatch '^> DEPRECATED\.' })
  }
  Set-Content $readme -Value $lines -Encoding UTF8
}

Write-Host "status: $prev -> $Status by $By" -ForegroundColor Green
Write-Host "state:  $state"
Write-Host "readme: $readme"
Write-Host ''
Write-Host 'To propagate to the published gist, edit one file per call and verify the size afterwards:'
Write-Host '  gh gist edit <id> -a report\README.md'
Write-Host '  gh gist edit <id> -a STATUS.json'
Write-Host 'Deleting the gist is owner-only. Deprecating the content is not.'

if (-not $NoCommit) {
  $repo = git -C $root rev-parse --show-toplevel 2>$null
  if (-not $repo) {
    Write-Host 'No git repository here, skipped commit.' -ForegroundColor Yellow
    exit 0
  }
  $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  git -C $root add STATUS.json report/README.md 2>$null | Out-Null
  $msg = "status: $Status"
  if ($Reason) { $msg = "$msg, $Reason" }
  git -C $root commit -m $msg 2>$null | Out-Null
  $commitExit = $LASTEXITCODE
  $ErrorActionPreference = $eap
  if ($commitExit -ne 0) { Write-Host 'commit failed, files left staged: run git status' -ForegroundColor Red; exit 1 }
  Write-Host ("committed: " + $msg) -ForegroundColor Green
}

