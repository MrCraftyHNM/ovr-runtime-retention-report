# Reproduce this yourself, step by step

Written for someone who has never run a PowerShell script and wants to see the same behaviour on their own machine, or to check whether their build still does it. No developer mode, no debugger, no tools beyond what ships with Windows.

The 21.9 hour session that produced the numbers in this repository is not required. Thirty to sixty minutes of Link is enough to see the shape: memory climbs while streaming, teardown gives back almost nothing, and the process survives the client exiting.

## What you need

- Windows 10 or 11, Meta Horizon PC installed, a Quest headset and a Link cable, or Air Link if that is what you use
- Permission to run PowerShell in a normal user window. Administrator rights are only needed for the optional steps marked as such
- About 90 minutes, most of it unattended

## Step 0, write down your build

Settings, General in the Meta Horizon PC client shows the version. Record it, along with your Windows build from `winver`. Every comparison later depends on those two strings, and a differing build is the most likely reason for a differing result.

## Step 1, measure the cold start

1. Close the Meta Horizon PC client completely, including any tray icon.
2. Open PowerShell and run `Get-Service OVRService` then `Stop-Service OVRService -Force`. If the second command says the service cannot be opened, your account lacks the stop right, which is itself one of the reported findings. Note it and continue; you can still do the rest.
3. Run `Get-Process OVRServer_x64` and note nothing is running.
4. Start the service again with `Start-Service OVRService`, wait five seconds, then run `Get-Process OVRServer_x64 | Select-Object Id, @{n='WS_MB';e={[math]::Round($_.WorkingSet64/1MB)}}`.

That working set is your cold-start baseline. On the reporting machine it was about 210 MB. Write it down, everything later is measured against it.

## Step 2, start sampling

Save `reproduce-sample.ps1` from this folder anywhere you like, then run it for the length of your session plus twenty minutes:

    powershell -ExecutionPolicy Bypass -File .\reproduce-sample.ps1 -Minutes 80

It writes one CSV row every thirty seconds with the time, whether the client is running, the runtime PID, working set in MB, private MB, GPU local memory in MB, and the service state. Leave it running. It is read-only and touches nothing.

If you prefer no script, the manual equivalent every few minutes is:

    Get-Process OVRServer_x64 | Select-Object Id, @{n='WS_MB';e={[math]::Round($_.WorkingSet64/1MB)}}, @{n='Priv_MB';e={[math]::Round($_.PrivateMemorySize64/1MB)}}

## Step 3, run a session

1. Open the Meta Link client, connect the headset, start Link.
2. Use it normally for at least thirty minutes, ideally an hour or two. Streaming time is what drives the growth, so sitting in the Link menu counts, playing counts more.
3. Do not restart the client during this step, and leave the sampling script alone.

What to watch. Working set should trend upward while you stream. On the reporting machine five streaming hours added 4,467 MB, so a 30 minute session may only show a few hundred MB. A positive slope that never comes back down is the signal, not the absolute size.

## Step 4, teardown

1. Exit VR, then close the Meta Horizon PC window completely.
2. Leave the sampler running for another fifteen minutes with nothing connected.
3. In the CSV, compare the last row with the client present against the rows after it.

Expected, and the reported defect: working set falls a little and then stays high. On the reporting machine it went from 2,707.8 MB to 2,499.7 MB, a release of 4.1 percent, and held about 2,500 MB for ninety minutes. Expected behaviour would be a return toward your Step 1 baseline within a minute.

## Step 5, the respawn test

1. With the client closed, note the runtime PID from the sampler.
2. In Task Manager, Details tab, end `OVRServer_x64.exe`.
3. Watch the sampler, or run `Get-Process OVRServer_x64` every second or two.

Expected, and reported: a new PID appears within about two seconds while `OVRService` stays Running. Note the new PID and the gap in seconds. On the reporting machine it was 21:34:43 to 21:34:47.

## Step 6, the privilege test

In a normal, non-administrator PowerShell window:

    Stop-Service OVRService -Force

Expected, and reported: `Cannot open OVRService service`. That is not a bug in your account, it is the service ACL denying interactive users the stop right. Administrator rights are required, which is why a normal user cannot close the runtime at all.

## Step 7, the idle control

Optional but it removes the obvious objection. With the client closed and the service running, leave the machine alone for thirty to sixty minutes. Idle working set should be flat. On the reporting machine, fourteen consecutive idle hours moved between 2,167 and 2,170 MB.

## What to record

Fill this in as you go, then compare with the numbers in this repository.

| Measurement | Yours | Reported here |
|---|---|---|
| Runtime version | | 208.0.0.84.535 |
| Windows build | | 26200.9711 |
| Cold-start working set | | about 210 MB |
| Peak working set during your session | | 2,707.8 MB after 21.9 h |
| Working set 15 min after closing the client | | about 2,500 MB |
| Released at teardown, percent | | 4.1 percent |
| Respawn delay after ending the task | | about 2 seconds |
| Unelevated `Stop-Service` result | | `Cannot open OVRService service` |

## How to report your result

Open an issue on this repository with the table above filled in, your runtime version and Windows build, and one line saying whether the process survived the client closing. Do not attach the raw `Service_*.txt` log, and do not include your machine name, user name, hardware serials or the machine id hash from the log; those identify you and change nothing about the finding. If you have a CSV, attach it, it contains no identifiers.

A result that contradicts this report is worth posting. If your build returns the process to a small footprint when the client closes, say so with the version, that tells everyone the fix landed.

## If something does not match

1. Different runtime build. Check Settings, General, and say which.
2. Headset connected over Air Link rather than cable. Note it, the transport does not change the process behaviour but it changes the encode load.
3. A desktop with one GPU, no external enclosure. Expected, the mechanism is process lifetime plus process-private memory, so the numbers should be smaller but the shape the same.
4. Service already stopped before you started. Someone or something else stopped it, restart it and begin again at Step 1.
