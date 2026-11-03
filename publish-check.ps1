param(
  [string]$Root = (Join-Path $PSScriptRoot 'report'),
  [string]$StampPath = (Join-Path $PSScriptRoot 'out\version-stamp.json')
)
$ErrorActionPreference = 'Stop'

$publish = @(
  (Join-Path $Root 'README.md'),
  (Join-Path $Root 'report.json'),
  (Join-Path $Root 'meta-bug-report.md'),
  (Join-Path $Root 'submission-message.md'),
  (Join-Path $Root 'evidence\stop-records.txt'),
  $StampPath
)

$patterns = [ordered]@{
  user_name        = 'Mr_AI'
  host_name        = 'DESKTOP-KDFQLL8'
  motherboard_sn   = 'YX0CFMZD'
  headset_serial   = 'D_2G0YC5ZG64025G'
  machine_id_hash  = 'c2f377ed974d9716'
  github_token     = 'gho_'
  aws_key          = 'AKIA'
  user_profile     = 'C:\Users\'
  private_key      = 'BEGIN PRIVATE KEY'
  password_field   = 'password='
}

$fail = 0
$rows = @()
foreach ($f in $publish) {
  if (-not (Test-Path $f)) { $rows += [pscustomobject]@{ File = (Split-Path $f -Leaf); Result = 'MISSING'; Detail = $f }; $fail++; continue }
  $raw = Get-Content $f -Raw
  $hits = @()
  foreach ($k in $patterns.Keys) {
    $c = ([regex]::Matches($raw, [regex]::Escape($patterns[$k]))).Count
    if ($c -gt 0) { $hits += "$k=$c" }
  }
  if ($hits.Count -gt 0) {
    $fail++
    $rows += [pscustomobject]@{ File = (Split-Path $f -Leaf); Result = 'BLOCK'; Detail = ($hits -join ', ') }
  } else {
    $rows += [pscustomobject]@{ File = (Split-Path $f -Leaf); Result = 'clean'; Detail = '' }
  }
}

$rows | Format-Table -AutoSize
if ($fail -gt 0) {
  Write-Host "PUBLISH-CHECK FAILED, $fail file(s) blocked. Nothing should be uploaded until these are fixed." -ForegroundColor Red
  exit 1
}
Write-Host 'PUBLISH-CHECK PASSED, all allowlisted files clean.' -ForegroundColor Green
exit 0
