[CmdletBinding()]
param(
  [switch]$Plan,
  [switch]$Force,
  [int]$WaitSeconds = 20,
  [string]$ServiceName = 'OVRService',
  [string]$LogPath    = (Join-Path $PSScriptRoot 'logs\ovr-close-proper.log')
)
$ErrorActionPreference = 'Continue'

function Log([string]$m) {
  $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
  $d = Split-Path -Parent $LogPath
  if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
  Add-Content -Path $LogPath -Value $line -Encoding UTF8
  Write-Host $line
}

function Get-LuidRows {
  $rows = @()
  foreach ($s in (Get-Counter '\GPU Process Memory(*)\Local Usage' -ErrorAction SilentlyContinue).CounterSamples) {
    $m = [regex]::Match($s.InstanceName, 'pid_(?<pid>\d+)_luid_0x(?<hi>[0-9a-fA-F]{8})_0x(?<lo>[0-9a-fA-F]{8})')
    if (-not $m.Success) { continue }
    if ($s.CookedValue -le 1MB) { continue }
    $pidN = [int]$m.Groups['pid'].Value
    $p = Get-Process -Id $pidN -ErrorAction SilentlyContinue
    $rows += [pscustomobject]@{
      Luid = "$($m.Groups['hi'].Value)_$($m.Groups['lo'].Value)"
      Pid  = $pidN
      Name = if ($p) { $p.ProcessName } else { 'exited' }
      MB   = [math]::Round($s.CookedValue / 1MB, 1)
    }
  }
  $rows
}

function Get-OvrPids {
  @(Get-Process -Name 'OVRServer_x64','OVRRedir','OVRServiceLauncher' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
}

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$elevated = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
$ovrPids = Get-OvrPids
$rowsBefore = Get-LuidRows
$targetLuids = @($rowsBefore | Where-Object { $ovrPids -contains $_.Pid } | Select-Object -ExpandProperty Luid -Unique)
$client = Get-Process -Name 'Client' -ErrorAction SilentlyContinue

Log ("PREFLIGHT elevated={0} svc={1} ovrPids={2} clientRunning={3} targetLuids={4}" -f $elevated, $(if ($svc) { [string]$svc.Status } else { 'Absent' }), ($ovrPids -join ','), $(if ($client) { 'yes' } else { 'no' }), ($targetLuids -join ','))
foreach ($r in $rowsBefore) { Log ("HOLDER luid={0} pid={1} name={2} localMB={3}" -f $r.Luid, $r.Pid, $r.Name, $r.MB) }

if ($Plan) {
  Log 'PLAN order: 1 close Meta Link window (session end) -> 2 stop OVRService -> 3 verify the adapter holder list shows no OVR entries'
  Log 'PLAN scope: process lifetime and memory only. No device removal of any kind.'
  return
}

if (-not $elevated) { Log 'ABORT not elevated. Stopping the service needs administrator rights.'; exit 2 }
if ($client -and -not $Force) { Log 'ABORT Meta Link client is running. Close the Link window first, that is step 1 of the correct order. Use -Force to override.'; exit 3 }

Log 'STEP1 session close acknowledged'
Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
$deadline = (Get-Date).AddSeconds($WaitSeconds)
while ((Get-Date) -lt $deadline) {
  $s = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
  $p = Get-Process -Name 'OVRServer_x64' -ErrorAction SilentlyContinue
  if ((-not $s -or $s.Status -ne 'Running') -and -not $p) { break }
  Start-Sleep -Milliseconds 500
}
$mode = 'graceful'
if ((Get-Process -Name 'OVRServer_x64' -ErrorAction SilentlyContinue) -or ((Get-Service -Name $ServiceName -ErrorAction SilentlyContinue).Status -eq 'Running')) {
  $mode = 'forced'
  Log 'STEP2 service stop did not land, escalating'
  foreach ($n in 'OVRServer_x64','OVRRedir') {
    foreach ($pr in @(Get-Process -Name $n -ErrorAction SilentlyContinue)) {
      Stop-Process -Id $pr.Id -Force -ErrorAction SilentlyContinue
      Start-Sleep -Milliseconds 300
      Log ("FORCE-KILL name={0} pid={1} gone={2}" -f $n, $pr.Id, (-not (Get-Process -Id $pr.Id -ErrorAction SilentlyContinue)))
    }
  }
  Start-Sleep -Seconds 3
}

$rowsAfter = Get-LuidRows
$stillOvr = @($rowsAfter | Where-Object { ($ovrPids + (Get-OvrPids)) -contains $_.Pid -or $_.Name -like 'OVR*' })
$svcAfter = (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue).Status
$left = @($stillOvr | Where-Object { $targetLuids -contains $_.Luid })

Log ("STEP3 remainingOvrHolders={0} svc={1} mode={2}" -f $left.Count, $(if ($svcAfter) { [string]$svcAfter } else { 'Absent' }), $mode)
foreach ($r in ($rowsAfter | Where-Object { $targetLuids -contains $_.Luid })) { Log ("REMAIN luid={0} pid={1} name={2} localMB={3}" -f $r.Luid, $r.Pid, $r.Name, $r.MB) }

$verdict = if ($left.Count -eq 0 -and $svcAfter -ne 'Running') { 'PASS' } elseif ($left.Count -eq 0) { 'PARTIAL' } else { 'FAIL' }
Log ("CLOSE-PROPER verdict={0} mode={1} luids={2} remaining={3} svc={4}" -f $verdict, $mode, ($targetLuids -join ','), $left.Count, $(if ($svcAfter) { [string]$svcAfter } else { 'Absent' }))

Log 'SCOPE device removal is out of scope. The runtime only releases the adapter by exiting, and that is what this script verifies.'


