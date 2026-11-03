param(
  [int]$Minutes = 60,
  [int]$IntervalSeconds = 30,
  [string]$OutDir = (Join-Path $PSScriptRoot 'logs')
)
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$csv = Join-Path $OutDir ("ovr-samples-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".csv")

function Get-GpuMB {
  $pids = @(Get-Process -Name 'OVRServer_x64','OVRRedir' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
  if ($pids.Count -eq 0) { return 0 }
  $rx = 'pid_(' + ($pids -join '|') + ')_'
  $sum = (Get-Counter '\GPU Process Memory(*)\Local Usage' -ErrorAction SilentlyContinue).CounterSamples |
    Where-Object { $_.InstanceName -match $rx } | Measure-Object -Property CookedValue -Sum
  if (-not $sum.Sum) { return 0 }
  [math]::Round($sum.Sum / 1MB, 1)
}

"time,client_present,ovr_pid,ws_mb,priv_mb,gpu_mb,service" | Set-Content $csv -Encoding UTF8
$deadline = (Get-Date).AddMinutes($Minutes)
while ((Get-Date) -lt $deadline) {
  $client = [bool](Get-Process -Name 'Client' -ErrorAction SilentlyContinue)
  $srv    = Get-Process -Name 'OVRServer_x64' -ErrorAction SilentlyContinue
  $svc    = (Get-Service -Name 'OVRService' -ErrorAction SilentlyContinue).Status
  $line = '{0},{1},{2},{3},{4},{5},{6}' -f `
    (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $client,
    $(if ($srv) { $srv.Id } else { '' }),
    $(if ($srv) { [math]::Round($srv.WorkingSet64 / 1MB) } else { 0 }),
    $(if ($srv) { [math]::Round($srv.PrivateMemorySize64 / 1MB) } else { 0 }),
    (Get-GpuMB),
    $(if ($svc) { [string]$svc } else { 'Absent' })
  Add-Content -Path $csv -Value $line -Encoding UTF8
  Write-Host $line
  Start-Sleep -Seconds $IntervalSeconds
}
Write-Host ''
Write-Host "samples written to $csv"
