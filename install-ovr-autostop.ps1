param(
  [ValidateSet('Install','Uninstall','Status')]
  [string]$Action = 'Status',
  [string]$TaskName = 'OVR-AutoStop',
  [string]$Script   = (Join-Path $PSScriptRoot 'ovr-autostop.ps1')
)
$ErrorActionPreference = 'Stop'
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$elevated = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

switch ($Action) {
  'Status' {
    "elevated=$elevated"
    $t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $t) { "task '$TaskName' absent" } else {
      "task '$TaskName' state=$($t.State) principal=$($t.Principal.UserId) runlevel=$($t.Principal.RunLevel)"
      (Get-ScheduledTaskInfo -TaskName $TaskName | Select-Object LastRunTime, LastTaskResult | Format-List | Out-String).Trim()
    }
  }
  'Install' {
    if (-not $elevated) { throw 'Install needs an elevated shell (Run as administrator).' }
    if (-not (Test-Path $Script)) { throw "script not found: $Script" }
    $argList = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $Script
    $taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argList
    $taskTrigger = New-ScheduledTaskTrigger -AtStartup
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $TaskName -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Settings $taskSettings -Force | Out-Null
    Start-ScheduledTask -TaskName $TaskName
    $t = Get-ScheduledTask -TaskName $TaskName
    "installed task '$TaskName' state=$($t.State) principal=$($t.Principal.UserId) runlevel=$($t.Principal.RunLevel)"
  }
  'Uninstall' {
    if (-not $elevated) { throw 'Uninstall needs an elevated shell (Run as administrator).' }
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    "removed task '$TaskName'"
  }
}


