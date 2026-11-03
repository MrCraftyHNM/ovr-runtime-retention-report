param(
  [string]$OutDir = (Join-Path $PSScriptRoot 'out')
)
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Hash([string]$p) {
  if (-not (Test-Path $p)) { return $null }
  (Get-FileHash -Path $p -Algorithm SHA256).Hash.Substring(0, 16).ToLower()
}
function Ver([string]$p) {
  if (-not (Test-Path $p)) { return $null }
  $v = (Get-Item $p).VersionInfo
  $out = if ($v.FileVersion) { $v.FileVersion } else { $v.ProductVersion }
  if ($out) { return $out }
  return $null
}
function LogRuntimeBuild {
  $lg = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Oculus\Service_*.txt') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $lg) { return $null }
  $line = (Get-Content $lg.FullName -TotalCount 3 | Select-String -Pattern 'Starting Oculus Runtime Service' | Select-Object -First 1).Line
  if (-not $line) { return $null }
  $m = [regex]::Match($line, 'Version: \[[^\]]*\] \(Release\) ([0-9.]+) \(([0-9.]+)\) \(revision: ([0-9a-f]+)\)')
  if ($m.Success) { return "$($m.Groups[2].Value) rev $($m.Groups[3].Value)" }
  return $null
}

$rtDir   = (Join-Path $env:ProgramFiles 'Meta Horizon\Support\oculus-runtime')
$cliDir  = (Join-Path $env:ProgramFiles 'Meta Horizon\Support\oculus-client')
$osKey   = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$svc     = Get-CimInstance Win32_Service -Filter "Name='OVRService'"
$gpus    = Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, DeviceID
$latest  = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Oculus\Service_*.txt') | Sort-Object LastWriteTime -Descending | Select-Object -First 1

$stamp = [ordered]@{
  captured_at_utc   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  runtime_file_ver  = Ver "$rtDir\OVRServer_x64.exe"
  runtime_build     = LogRuntimeBuild
  runtime_hash      = Hash "$rtDir\OVRServer_x64.exe"
  launcher_file_ver = Ver "$rtDir\OVRServiceLauncher.exe"
  launcher_hash     = Hash "$rtDir\OVRServiceLauncher.exe"
  client_file_ver   = Ver "$cliDir\Client.exe"
  client_hash       = Hash "$cliDir\Client.exe"
  os_product        = $osKey.ProductName
  os_display_ver    = $osKey.DisplayVersion
  os_build          = "$($osKey.CurrentBuild).$($osKey.UBR)"
  service_start     = $svc.StartMode
  service_state     = $svc.State
  service_path      = (($svc.PathName) -replace [regex]::Escape($env:ProgramFiles), '%ProgramFiles%' -replace [regex]::Escape($env:LOCALAPPDATA), '%LOCALAPPDATA%')
  gpu               = @($gpus | ForEach-Object { "$($_.Name) | driver $($_.DriverVersion) | $($_.DeviceID)" })
  newest_log        = if ($latest) { "$($latest.Name) | $($latest.Length) B | $($latest.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" } else { $null }
  script_autostop   = Hash (Join-Path $PSScriptRoot 'ovr-autostop.ps1')
  script_eject_ab   = Hash (Join-Path $PSScriptRoot 'n/a-superseded')
  script_extract    = Hash (Join-Path $PSScriptRoot 'n/a-temp-analysis')
}

$stamp | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $OutDir 'version-stamp.json') -Encoding UTF8
$stamp.GetEnumerator() | ForEach-Object { "{0,-18} {1}" -f $_.Key, $(if ($_.Value -is [array]) { $_.Value -join ' ;; ' } else { $_.Value }) }







