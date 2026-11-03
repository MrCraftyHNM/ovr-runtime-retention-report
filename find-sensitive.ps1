param(
  [string[]]$Roots = @(
    (Join-Path $PSScriptRoot 'report'),
    (Join-Path $PSScriptRoot 'out')
  ),
  [string[]]$Include = @('*.md','*.json','*.txt','*.csv','*.ps1','*.tsv'),
  [switch]$Json
)
$ErrorActionPreference = 'Stop'

$patterns = @(
  @{ id='user_name';        sev='HIGH';   rx='Mr_AI' }
  @{ id='host_name';        sev='HIGH';   rx='DESKTOP-KDFQLL8' }
  @{ id='motherboard_sn';   sev='HIGH';   rx='YX0CFMZD' }
  @{ id='headset_serial';   sev='HIGH';   rx='D_2G0YC5ZG64025G' }
  @{ id='machine_id_hash';  sev='HIGH';   rx='c2f377ed974d9716' }
  @{ id='github_token';     sev='HIGH';   rx='gh[pousr]_[A-Za-z0-9]{20,}' }
  @{ id='github_pat';       sev='HIGH';   rx='github_pat_[A-Za-z0-9_]{20,}' }
  @{ id='aws_key';          sev='HIGH';   rx='AKIA[0-9A-Z]{16}' }
  @{ id='openai_key';       sev='HIGH';   rx='sk-[A-Za-z0-9]{20,}' }
  @{ id='private_key';      sev='HIGH';   rx='BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY' }
  @{ id='password_field';   sev='HIGH';   rx='(?i)(password|passwd|pwd)\s*[:=]\s*\S' }
  @{ id='user_profile_path';sev='HIGH';   rx='[A-Za-z]:\\Users\\[A-Za-z0-9_.-]+' }
  @{ id='email_address';    sev='HIGH';   rx='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' }
  @{ id='mac_address';      sev='MEDIUM'; rx='([0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}' }
  @{ id='program_files_path'; sev='MEDIUM'; rx='[A-Za-z]:\\Program Files' }
  @{ id='unexpanded_home';  sev='LOW';    rx='%USERPROFILE%' }
)

$files = @()
foreach ($r in $Roots) {
  if (-not (Test-Path $r)) { continue }
  $item = Get-Item $r
  if ($item.PSIsContainer) {
    foreach ($inc in $Include) { $files += Get-ChildItem $r -Recurse -File -Filter $inc -ErrorAction SilentlyContinue }
  } else {
    $files += $item
  }
}
$files = $files | Sort-Object FullName -Unique | Where-Object { $_.Name -notin @('find-sensitive.ps1','publish-check.ps1') -and $_.FullName -notmatch '\\\\\.git\\\\' -and $_.FullName -notmatch '\\\\archive\\\\' }

$findings = @()
foreach ($f in $files) {
  $lineNo = 0
  foreach ($line in [System.IO.File]::ReadLines($f.FullName)) {
    $lineNo++
    foreach ($p in $patterns) {
      if ([regex]::IsMatch($line, $p.rx)) {
        $findings += [pscustomobject]@{
          severity = $p.sev
          id       = $p.id
          file     = $f.FullName
          line     = $lineNo
          excerpt  = ($line.Trim() -replace '\s+',' ').Substring(0, [Math]::Min(110, ($line.Trim() -replace '\s+',' ').Length))
        }
      }
    }
  }
}

if ($Json) {
  $findings | ConvertTo-Json -Depth 4
} else {
  if ($findings.Count -eq 0) {
    "SCAN files=$($files.Count) findings=0"
  } else {
    $findings | Group-Object severity | ForEach-Object { "$($_.Name)=$($_.Count)" }
    $findings | Sort-Object severity, id, file, line | Format-Table severity, id, line, excerpt -AutoSize -Wrap
  }
}

$high = @($findings | Where-Object { $_.severity -eq 'HIGH' })
"SCAN files=$($files.Count) findings=$($findings.Count) high=$($high.Count)"
if ($high.Count -gt 0) { exit 1 } else { exit 0 }


