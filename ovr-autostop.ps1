param(
  [string]$ClientExe   = (Join-Path $env:ProgramFiles 'Meta Horizon\Support\oculus-client\Client.exe'),
  [string]$ServiceName = 'OVRService',
  [int]$ThresholdMB    = 1500,
  [int]$PollSeconds    = 2,
  [int]$ClientExitConfirmPolls = 2,
  [int]$PartialRetrySeconds = 30,
  [int]$PartialMaxAttempts = 2,
  [string]$LogPath     = (Join-Path $PSScriptRoot 'logs\ovr-autostop.log'),
  [switch]$Once,
  [switch]$DryRun
)
$ErrorActionPreference = 'Continue'
$clientName = [System.IO.Path]::GetFileNameWithoutExtension($ClientExe)

function Write-Log([string]$msg) {
  $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
  $dir = Split-Path -Parent $LogPath
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  Add-Content -Path $LogPath -Value $line -Encoding UTF8
}

function Get-OculusLogDir {
  $cands = @()
  if ($env:LOCALAPPDATA) { $cands += (Join-Path $env:LOCALAPPDATA 'Oculus') }
  if ($env:SystemDrive) {
    $usersDir = Join-Path $env:SystemDrive 'Users'
    if (Test-Path $usersDir) {
      $cands += (Get-ChildItem $usersDir -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'AppData\Local\Oculus' })
    }
  }
  $best = $null; $bestTime = [datetime]::MinValue
  foreach ($c in $cands) {
    if (-not (Test-Path $c)) { continue }
    $lg = Get-ChildItem $c -Filter 'Service_*.txt' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($lg -and $lg.LastWriteTime -gt $bestTime) { $bestTime = $lg.LastWriteTime; $best = $c }
  }
  if ($best) { return $best }
  return (Join-Path $env:LOCALAPPDATA 'Oculus')
}
function Get-BuildStamp {
  $rt  = (Get-Item (Join-Path $env:ProgramFiles 'Meta Horizon\Support\oculus-runtime\OVRServer_x64.exe') -ErrorAction SilentlyContinue).VersionInfo
  $lch = (Get-Item (Join-Path $env:ProgramFiles 'Meta Horizon\Support\oculus-runtime\OVRServiceLauncher.exe') -ErrorAction SilentlyContinue).VersionInfo
  $drv = (Get-CimInstance Win32_VideoController -Filter "Name LIKE '%7600M%'" -ErrorAction SilentlyContinue).DriverVersion
  $ubr = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).UBR
  $ver = if ($rt -and $rt.FileVersion) { $rt.FileVersion } elseif ($lch -and $lch.FileVersion) { $lch.FileVersion } else { '?' }
  $rev = '?'
  $lg = Get-ChildItem (Join-Path (Get-OculusLogDir) 'Service_*.txt') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($lg) {
    $head = Get-Content $lg.FullName -TotalCount 40 | Select-String -Pattern 'revision: ([0-9a-f]+)' | Select-Object -First 1
    if ($head) { $rev = [regex]::Match($head.Line, 'revision: ([0-9a-f]+)').Groups[1].Value }
  }
  "runtime={0} rev={1} os={2}.{3} driver7600M={4}" -f $ver, $rev, [Environment]::OSVersion.Version, $ubr, $drv
}

function Get-NewestLogName {
  $lg = Get-ChildItem (Join-Path (Get-OculusLogDir) 'Service_*.txt') -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($lg) { $lg.Name } else { 'none' }
}

function Kill-Lingering {
  $killed = @()
  foreach ($n in 'OVRServer_x64','OVRRedir','OVRServiceLauncher') {
    foreach ($pr in @(Get-Process -Name $n -ErrorAction SilentlyContinue)) {
      Stop-Process -Id $pr.Id -Force -ErrorAction SilentlyContinue
      Start-Sleep -Milliseconds 300
      $gone = -not (Get-Process -Id $pr.Id -ErrorAction SilentlyContinue)
      Write-Log ("LINGER-KILL name={0} pid={1} gone={2}" -f $n, $pr.Id, $gone)
      $killed += $n
    }
  }
  if ($killed.Count -eq 0) { Write-Log 'LINGER-KILL none-found' }
  $killed
}

function Test-Partial {
  $pids = @(Get-Process -Name 'OVRServer_x64','OVRRedir','OVRServiceLauncher' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
  $gpu = Get-OvrGpuMB
  $svc = (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue).Status
  [pscustomobject]@{
    Lingering = ($pids.Count -gt 0)
    GpuMB     = $gpu
    Service   = if ($svc) { [string]$svc } else { 'Absent' }
    Clean     = ($pids.Count -eq 0 -and $gpu -le 1 -and $svc -ne 'Running')
  }
}

function Get-RuntimeSnap {
  $srv = Get-Process -Name 'OVRServer_x64' -ErrorAction SilentlyContinue
  $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
  $priv = if ($srv) { [math]::Round($srv.PrivateMemorySize64 / 1MB) } else { 0 }
  $ws   = if ($srv) { [math]::Round($srv.WorkingSet64 / 1MB) } else { 0 }
  [pscustomobject]@{
    Pid      = if ($srv) { $srv.Id } else { $null }
    PrivateMB = $priv
    WsMB      = $ws
    GpuMB     = Get-OvrGpuMB
    Service  = if ($svc) { [string]$svc.Status } else { 'Absent' }
    Over     = ($ws -ne $null -and $ws -gt $ThresholdMB)
  }
}

function Get-OvrGpuMB {
  $pids = @(Get-Process -Name 'OVRServer_x64','OVRRedir' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
  if ($pids.Count -eq 0) { return 0 }
  $rx = 'pid_(' + ($pids -join '|') + ')_'
  $sum = (Get-Counter '\GPU Process Memory(*)\Local Usage' -ErrorAction SilentlyContinue).CounterSamples |
    Where-Object { $_.InstanceName -match $rx } |
    Measure-Object -Property CookedValue -Sum
  if (-not $sum.Sum) { return 0 }
  [math]::Round($sum.Sum / 1MB, 1)
}


function Stop-Runtime([string]$reason) {
  $snap = Get-RuntimeSnap
  $clientStill = [bool](Get-Process -Name $clientName -ErrorAction SilentlyContinue)
  Write-Log ("TRIGGER reason={0} basis=no-client-processes clientPresentAtStop={1} confirmPolls={2}" -f $reason, $clientStill, $ClientExitConfirmPolls)
  if ($clientStill) { Write-Log 'STOP-SKIP client still present, tray process or relaunch. Not stopping.'; return }
  Write-Log ("STOP-REQUEST reason={0} pid={1} wsMB={2} privMB={3} gpuMB={4} svc={5} overThreshold={6}" -f $reason, $snap.Pid, $snap.WsMB, $snap.PrivateMB, $snap.GpuMB, $snap.Service, $snap.Over)
  if ($snap.Over) { Write-Log ("WARN retained working set {0}MB exceeds {1}MB threshold" -f $snap.WsMB, $ThresholdMB) }
  if ($snap.Service -ne 'Running') { Write-Log 'SKIP service not running'; return 'SKIP' }
  if ($DryRun) { Write-Log 'DRYRUN would Stop-Service '; return 'DRYRUN' }
  $mode = 'graceful'
  $respawn = 'no'
  Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
  $deadline = (Get-Date).AddSeconds(15)
  while ((Get-Date) -lt $deadline) {
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    $srv = Get-Process -Name 'OVRServer_x64' -ErrorAction SilentlyContinue
    if ((-not $svc -or $svc.Status -ne 'Running') -and -not $srv) { break }
    Start-Sleep -Milliseconds 500
  }
  $svcNow = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
  $srvNow = Get-Process -Name 'OVRServer_x64' -ErrorAction SilentlyContinue
  if ($srvNow -or ($svcNow -and $svcNow.Status -eq 'Running')) {
    $mode = 'forced'
    Write-Log ("FORCE-STEP reason=stop-timeout pid={0} svc={1}" -f $(if ($srvNow) { $srvNow.Id } else { '-' }), $(if ($svcNow) { [string]$svcNow.Status } else { 'Absent' }))
    foreach ($n in 'OVRServer_x64','OVRRedir') {
      foreach ($pr in @(Get-Process -Name $n -ErrorAction SilentlyContinue)) {
        Stop-Process -Id $pr.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 300
        $gone = -not (Get-Process -Id $pr.Id -ErrorAction SilentlyContinue)
        Write-Log ("FORCE-KILL name={0} pid={1} gone={2}" -f $n, $pr.Id, $gone)
      }
    }
    $deadline2 = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline2) {
      if (-not (Get-Process -Name 'OVRServer_x64' -ErrorAction SilentlyContinue)) { break }
      Start-Sleep -Milliseconds 500
    }
  }
  $respawnPid = '-'
  $stable = 0
  $settle = (Get-Date).AddSeconds(10)
  while ((Get-Date) -lt $settle) {
    $s = Get-Process -Name 'OVRServer_x64' -ErrorAction SilentlyContinue
    $v = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($s -and $snap.Pid -and $s.Id -ne $snap.Pid) { $respawn = 'yes'; $respawnPid = $s.Id; break }
    if (-not $s -and (-not $v -or $v.Status -ne 'Running')) { $stable++; if ($stable -ge 3) { break } } else { $stable = 0 }
    Start-Sleep -Milliseconds 500
  }
  $after = Get-RuntimeSnap
  if ($after.Service -eq 'Running' -or $after.Pid) { $verdict = 'FAIL' }
  elseif ($after.GpuMB -gt 1) { $verdict = 'PARTIAL' }
  else { $verdict = 'PASS' }
  $ver = [regex]::Match($script:BuildStamp, 'runtime=(\S+)').Groups[1].Value
  $rev = [regex]::Match($script:BuildStamp, 'rev=(\S+)').Groups[1].Value
  if (-not $ver) { $ver = 'unknown' }
  if (-not $rev) { $rev = 'unknown' }
  $shortBuild = "$ver/$rev"
  $afterPid = if ($after.Pid) { $after.Pid } else { '-' }
  Write-Log ("BUFFER-RELEASED verdict={0} build={1} trigger={2} mode={3} respawn={4} respawnPid={5} pid={6} afterPid={7} wsMB={8}->{9} privMB={10}->{11} gpuMB={12}->{13} svc={14} log={15}" -f `
    $verdict, $shortBuild, $reason, $mode, $respawn, $respawnPid, $snap.Pid, $afterPid, $snap.WsMB, $after.WsMB, $snap.PrivateMB, $after.PrivateMB, $snap.GpuMB, $after.GpuMB, $after.Service, (Get-NewestLogName))
  if ($verdict -eq 'FAIL') {
    Write-Log ("FAIL-NOTE svc={0} pid={1} respawn={2} means no elevation, or a runtime wedged in kernel" -f $after.Service, $after.Pid, $respawn)
  }
  if ($verdict -eq 'PARTIAL') {
    Write-Log ("PARTIAL-NOTE service stopped and no OVRServer, but gpuMB={0} remains, so another OVR process still holds the adapter. Scheduling kill-then-recheck." -f $after.GpuMB)
  }
  return $verdict
}

function Start-Runtime([string]$reason) {
  $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
  if (-not $svc) { Write-Log 'START-SKIP service absent'; return }
  if ($svc.Status -eq 'Running') { Write-Log 'START-SKIP already running'; return }
  Write-Log ("START-REQUEST reason={0} priorState={1}" -f $reason, $svc.Status)
  if ($DryRun) { Write-Log 'DRYRUN would Set-Service Manual + Start-Service'; return }
  Set-Service -Name $ServiceName -StartupType Manual -ErrorAction SilentlyContinue
  Start-Service -Name $ServiceName -ErrorAction SilentlyContinue
  $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
  Write-Log ("START-RESULT svc={0}" -f $(if ($svc) { $svc.Status } else { 'Absent' }))
}

$script:BuildStamp = Get-BuildStamp
$wasRunning = [bool](Get-Process -Name $clientName -ErrorAction SilentlyContinue)
Write-Log ("BUILD-STAMP " + $script:BuildStamp)
Write-Log ("WATCHER-START client={0} present={1} poll={2}s threshold={3}MB dryrun={4}" -f $clientName, $wasRunning, $PollSeconds, $ThresholdMB, [bool]$DryRun)

if ($Once) {
  Write-Log ("ONCE snapshot: " + ((Get-RuntimeSnap) | ConvertTo-Json -Compress))
  if (-not $wasRunning -and (Get-RuntimeSnap).Service -eq 'Running') { Stop-Runtime 'once-client-absent' }
  Write-Log 'ONCE done'
  return
}

$backoff = @(5, 15, 45, 120)
$pending = $null
$absentPolls = 0
$seenClient = $false
while ($true) {
  Start-Sleep -Seconds $PollSeconds
  $now = [bool](Get-Process -Name $clientName -ErrorAction SilentlyContinue)
  if ($now) {
    if (-not $wasRunning) { Start-Runtime 'client-launched' }
    if ($pending) { Write-Log ("RETRY-CANCELLED reason=client-relaunched attempts={0}" -f $pending.Attempt); $pending = $null }
    $seenClient = $true
    $absentPolls = 0
  } else {
    if ($seenClient) { $absentPolls++ }
    if ($seenClient -and -not $pending -and $absentPolls -ge $ClientExitConfirmPolls) {
      $v = Stop-Runtime 'client-gone-confirmed'
      $absentPolls = 0
      if ($v -eq 'FAIL') {
        $pending = [pscustomobject]@{ Kind = 'fail'; Attempt = 1; Due = (Get-Date).AddSeconds($backoff[0]) }
        Write-Log ("RETRY-NEEDED basis=verdict-FAIL attempt=1 dueIn={0}s" -f $backoff[0])
      } elseif ($v -eq 'PARTIAL') {
        $pending = [pscustomobject]@{ Kind = 'partial'; Attempt = 1; Due = (Get-Date).AddSeconds($PartialRetrySeconds) }
        Write-Log ("RETRY-NEEDED basis=verdict-PARTIAL attempt=1 dueIn={0}s action=kill-then-recheck" -f $PartialRetrySeconds)
      } else {
        Write-Log ("RETRY-NOT-NEEDED basis=verdict-{0}" -f $v)
        $seenClient = $false
      }
    }
  }
  if ($pending -and (Get-Date) -ge $pending.Due) {
    if ($pending.Kind -eq 'partial') {
      $n = $pending.Attempt + 1
      if ($n -gt $PartialMaxAttempts) {
        $st = Test-Partial
        Write-Log ("RETRY-EXHAUSTED kind=partial attempts={0} lingering={1} gpuMB={2} svc={3}. Report-worthy residue." -f $pending.Attempt, $st.Lingering, $st.GpuMB, $st.Service)
        $pending = $null
        $seenClient = $false
      } else {
        Write-Log ("PARTIAL-RETRY attempt={0} action=kill-then-recheck wait={1}s" -f $n, $PartialRetrySeconds)
        [void](Kill-Lingering)
        $deadline = (Get-Date).AddSeconds($PartialRetrySeconds)
        $clientBack = $false
        while ((Get-Date) -lt $deadline) {
          if (Get-Process -Name $clientName -ErrorAction SilentlyContinue) { $clientBack = $true; break }
          Start-Sleep -Milliseconds 1000
        }
        if ($clientBack) {
          Write-Log 'RETRY-CANCELLED reason=client-relaunched during partial recheck'
          $pending = $null
          $seenClient = $true
        } else {
          $st = Test-Partial
          if ($st.Clean) {
            Write-Log ("RETRY-SUCCEEDED kind=partial attempt={0} verdict=PASS lingering={1} gpuMB={2} svc={3}" -f $n, $st.Lingering, $st.GpuMB, $st.Service)
            $pending = $null
            $seenClient = $false
          } else {
            $pending = [pscustomobject]@{ Kind = 'partial'; Attempt = $n; Due = (Get-Date).AddSeconds($PartialRetrySeconds) }
            Write-Log ("RETRY-NEEDED basis=verdict-PARTIAL attempt={0} dueIn={1}s lingering={2} gpuMB={3}" -f $n, $PartialRetrySeconds, $st.Lingering, $st.GpuMB)
          }
        }
      }
    } else {
      $n = $pending.Attempt + 1
      if ($n -gt $backoff.Count) {
        Write-Log ("RETRY-EXHAUSTED attempts={0} lastVerdict=FAIL" -f $pending.Attempt)
        $pending = $null
        $seenClient = $false
      } else {
        $v = Stop-Runtime ("client-gone-retry-{0}" -f $n)
        if ($v -eq 'FAIL') {
          $pending = [pscustomobject]@{ Kind = 'fail'; Attempt = $n; Due = (Get-Date).AddSeconds($backoff[$n - 1]) }
          Write-Log ("RETRY-NEEDED basis=verdict-FAIL attempt={0} dueIn={1}s" -f $n, $backoff[$n - 1])
        } elseif ($v -eq 'PARTIAL') {
          $pending = [pscustomobject]@{ Kind = 'partial'; Attempt = $n; Due = (Get-Date).AddSeconds($PartialRetrySeconds) }
          Write-Log ("RETRY-NEEDED basis=verdict-PARTIAL attempt={0} dueIn={1}s action=kill-then-recheck" -f $n, $PartialRetrySeconds)
        } else {
          Write-Log ("RETRY-SUCCEEDED attempt={0} verdict={1}" -f $n, $v)
          $pending = $null
          $seenClient = $false
        }
      }
    }
  }
  $wasRunning = $now
}




