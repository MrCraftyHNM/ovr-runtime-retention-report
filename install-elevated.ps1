$log = (Join-Path $PSScriptRoot 'logs\install-elevated.log')
function W([string]$m) { Add-Content -Path $log -Value ('{0} {1}' -f (Get-Date -Format 'HH:mm:ss'), $m) -Encoding UTF8 }
W 'START'
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
W ("identity={0} isAdmin={1}" -f $id.Name, $isAdmin)
$installer = (Join-Path $PSScriptRoot 'install-ovr-autostop.ps1')
W ("installerExists={0}" -f (Test-Path $installer))
try {
  $out = & $installer -Action Install 2>&1 | Out-String
  W ("installerOutput=" + ($out -replace '\s+', ' ').Trim())
} catch {
  W ("installerException=" + $_.Exception.Message)
}
$t = Get-ScheduledTask -TaskName 'OVR-AutoStop' -ErrorAction SilentlyContinue
if ($t) {
  W ("task state={0} principal={1} runLevel={2}" -f $t.State, $t.Principal.UserId, $t.Principal.RunLevel)
} else {
  W 'task ABSENT after install attempt'
}
W 'END'



