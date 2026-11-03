$log = (Join-Path $PSScriptRoot 'logs\watcher-restart.log')
function W([string]$m) { Add-Content -Path $log -Value ('{0} {1}' -f (Get-Date -Format 'HH:mm:ss'), $m) -Encoding UTF8 }
W 'START'
try {
  Stop-ScheduledTask -TaskName 'OVR-AutoStop' -ErrorAction Stop
  W 'stopped task'
} catch { W ("stop exception: " + $_.Exception.Message) }
Start-Sleep -Seconds 2
try {
  Start-ScheduledTask -TaskName 'OVR-AutoStop' -ErrorAction Stop
  W 'started task'
} catch { W ("start exception: " + $_.Exception.Message) }
Start-Sleep -Seconds 3
$t = Get-ScheduledTask -TaskName 'OVR-AutoStop' -ErrorAction SilentlyContinue
W ("task state=" + $(if ($t) { [string]$t.State } else { 'ABSENT' }))
$procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.SessionId -eq 0 })
W ("session0 powershell count=" + $procs.Count + " pids=" + (($procs | Select-Object -ExpandProperty ProcessId) -join ','))
W 'END'


