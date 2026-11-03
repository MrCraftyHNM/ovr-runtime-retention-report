# OVRServer_x64 keeps gigabytes after the Link window closes, and OVRService restarts it within seconds, on any GPU

**Product:** Meta Horizon PC / Oculus VR Runtime Service (OVRService) + OVRServer_x64
**Runtime version:** 208.0.0.84.535 (Stable) revision 70b5b1dfe187
**OS:** Windows 11, 10.0.26200.9711
**Role:** PC client host, single user, Link used for gaming only

## Summary

A user who only opens the Meta Link client to play closes the window and expects the runtime to be gone. It is not. `OVRService` re-creates `OVRServer_x64` about **4 seconds** after it exits, keeps it as a supervisor-owned child for the life of the machine, and that child retains gigabytes of private memory after the streaming session ends.

Measured on the reporting machine, one 21.9 hour generation grew from 1,245.6 MB private to a peak of **5,781.3 MB private / 2,707.8 MB working set**, released **236.4 MB, which is 4.1%**, on session end, and held about **2,500 MB of working set with nothing attached** for the remaining 90 minutes of its life. The process cannot be closed by the user, because the service recreates it and the service ACL denies a normal user the stop right.

This is not a hardware or external-GPU phenomenon. The mechanism is process lifetime plus process-private memory, so the same retention applies on a laptop with an integrated GPU, a desktop with a discrete card, or a hybrid machine. The reporting machine happens to use a Radeon RX 7600M XT in a Thunderbolt enclosure, and its vendor GPU panel is what first made the lingering holder visible, which is how this report started. The retained memory itself shows up in Task Manager on any configuration.

**Scope of the generalisation, stated honestly.** Every figure below was measured on one machine, described in Environment. The claim that it generalises rests on the mechanism, not on a second sample. Users on a single GPU should be able to confirm it in under a minute: open Link, play, close the window, then watch `OVRServer_x64.exe` in Task Manager instead of disappearing.

## Severity

High for users on 16 GB machines who use Link for long sessions, medium for the wider population. Contributing factor: the runtime's per-session telemetry reports `encoder_backups=0` while its own ULL path logs 26,016 dropped-frame warnings in the same window, so the runtime is internally inconsistent about encoder pressure.

## Environment

One configuration, given for reproduction, not a requirement. Any GPU should show the same process behaviour.

- CPU: AMD Ryzen 7 8840HS (8 cores)
- Display adapters: AMD Radeon 780M (integrated), AMD Radeon RX 7600M XT over USB4/Thunderbolt (external GPU, `PCI\VEN_1002&DEV_7480`, driver 32.0.32015.7029). The external GPU is incidental, it is what made the lingering holder visible in a vendor GPU panel
- Memory: 15,624 MB
- Headset: Quest 3 over USB3 Link (`transmission_type=USB3_DISCO`), no Air Link used
- Stream settings: AVC, `encode_width=4096`, `encode_height=2208`, `fps=72`, fixed `encode-bitrate-mbps=200`, `dynamic_bitrate_enabled=0`

## Build fingerprint (machine readable, captured 2026-11-03T05:28:03Z)

- Runtime build `208.0.0.84.535`, revision `70b5b1dfe187`
- `OVRServer_x64.exe` sha256 prefix `4ad07e2f65b66a7e`, `OVRServiceLauncher.exe` sha256 prefix `6c6ebaeb387d7ec0`
- OS build `10.0.26200.9711`, display version `25H2`. Note the registry `ProductName` still reports `Windows 10 Pro`, so the build number is the authoritative field
- GPU drivers `32.0.32015.7029` for both the 780M and the RX 7600M XT, Meta virtual display `15.52.32.370`
- Service config at capture: `Manual`, state `Running`, path `"%ProgramFiles%\Meta Horizon\Support\oculus-runtime\OVRServiceLauncher.exe"`
- Full stamp in `version-stamp.json` alongside this report

## Steps to reproduce

1. Connect the headset over wired Link and start a session.
2. Stream for roughly one hour at 4096x2208 at 72 fps with a fixed 200 Mbps AVC bitrate.
3. Exit VR and close the Meta Horizon / Link window.
4. Observe `OVRServer_x64.exe` in Task Manager. Working set stays in the GB range instead of returning to the ~210 MB cold-start baseline.
5. End the `OVRServer_x64` task. Observe a new process with a new PID within about 4 seconds, with the service still `Running`.
6. Try to stop the service from a non-elevated shell. `Stop-Service OVRService` fails with `Cannot open OVRService service`.

## Observed

All figures come from the runtime's own log, `Service_2026-11-01_23.31.21.txt`, which carries 1,313 `[DxDiag] LogResourceUsage` samples at roughly one per minute.

1. **Peak and trajectory.** Private usage 1,245.6 MB at 23:32:30 on 01/11, rising to 5,548.1 MB at 21:25:02 on 02/11. Peak 5,781.3 MB private and 2,707.8 MB working set at 19:46:00 on 02/11. Working set crossed 2 GB at 19:06:59.
2. **Teardown releases almost nothing.** At 19:47:00, immediately after the session ended, private usage fell from 5,781.3 MB to 5,544.9 MB and working set from 2,707.8 MB to 2,499.7 MB. That is **236.4 MB, or 4.1%** of the retained block. Working set then sat at approximately 2,500 MB, flat, from 19:47 to 21:25, a full 90 minutes of no session.
3. **Growth is confined to streaming.** Five hours with active streaming added 4,467 MB. Eighteen hours without streaming moved -165 MB in total, with 14 consecutive idle hours flat between 2,167 and 2,170 MB private. Idle behaviour is therefore not the leak. Streaming is.
4. **Encoder accounting is contradictory.** 26,016 `[ull] Frame(s) N to M dropped due to encoder backup` warnings were logged during the run, with 13,030 of them in a single hour. In the same period, all 93 per-minute `oculus_pc_xrs_stats_event` records report `encoder_backups=0`. Encode duration p50 was 8.1 to 8.4 ms per frame at 4096x2208 at 72 fps with a fixed 200 Mbps cap.

## Expected

- On session end, or on Link window close, the runtime returns to its cold-start footprint, which measured 210 MB working set for a fresh process on this machine.
- Or, at minimum, the per-session buffers are released when the streaming session terminates.
- A user-visible way to stop the runtime service, or a runtime that exits when no client is attached.

## Why the runtime is orphaned, and why its lifecycle is now in question

- `OVRService` is `DEMAND_START` and runs `OVRServiceLauncher.exe` as `LocalSystem`. It has **no idle timeout** and no exit path other than service stop. Idle polling continues indefinitely, mDNS every 15 seconds plus a headset enumeration loop.
- Closing the Link window does reach the runtime. At 21:25:50.800 the server logs `{WM_DESTROY} Unregistering session notifications and quitting` and a new generation starts at 21:25:54.953. Any user attempt to keep it down is reversed in about 4 seconds.
- Killing the child by hand has the same outcome. PID 10808 was terminated at 21:34:43. By 21:34:47 a new `OVRServer_x64` was running as PID 22184. The service state never changed from `Running`, and `sc qfailure OVRService` shows no recovery actions, so the re-spawn comes from the launcher itself, not from Service Control Manager.
- The service DACL grants interactive users no service stop right. `OpenProcess(PROCESS_TERMINATE)` succeeds on the child but returns `win32 5, access denied` on the launcher. Task Manager can therefore only end the child, which the supervisor immediately replaces. Measured with a forced-termination harness: `verdict=FAIL mode=forced respawn=yes respawnPid=22596 pid=3392 afterPid=22596 wsMB=210->28 privMB=184->36 gpuMB=40.8->0 svc=Running`, service never left `Running`, and a new process appeared within 2 seconds.
- Because the runtime holds live D3D11 and Vulkan devices on the external GPU, third-party GPU panels report the process as using that adapter. `amdvlk64.dll`, `amdlvr64.dll`, `amdenc64.dll`, `d3d11.dll` and `dxgi.dll` are all loaded in the process, and GPU Engine counters list the process on both adapters. Device removal is out of scope for this report.

## Impact

- 2.5 GB of working set and roughly 5.5 GB of private commit are held indefinitely after a session, on a 16 GB machine, with no client attached and no way to release them short of an elevated service stop or a reboot.
- The runtime cannot be closed by the user whose session it was, and the process is re-created on the order of seconds, so the retained block is effectively sticky.
- The runtime keeps a device context on the external GPU while idle, which GPU management panels surface as an app holding that adapter. The defect reported here is the process lifetime and the retained memory, not device removal.

## Workaround in use

Stop the service explicitly, elevated, when Link closes: `Stop-Service OVRService -Force`. A SYSTEM-level watcher automates it under one rule: the service stops only when no `Client.exe` process remains at all, confirmed across two consecutive polls, and it never stops while any client process is still present, which covers a client that lingers in the tray. The watcher also starts the service when the client launches, so the next Link session arms the runtime again. Device removal is deliberately not part of this workaround.

Verified records from that watcher, generated on the machine described above:

```
BUFFER-RELEASED verdict=PASS build=208.0.0.84.535/70b5b1dfe187 trigger=client-exited mode=graceful respawn=no respawnPid=- pid=22596 afterPid=- wsMB=211->0 privMB=185->0 gpuMB=40.8->0 svc=Stopped log=Service_2026-11-03_00.44.25.txt
BUFFER-RELEASED verdict=PASS build=208.0.0.84.535/70b5b1dfe187 trigger=client-gone-confirmed mode=graceful respawn=no respawnPid=- pid=27148 afterPid=- wsMB=212->0 privMB=182->0 gpuMB=40.8->0 svc=Stopped log=Service_2026-11-03_01.11.04.txt
```

After each stop the GPU panel holder list on the external adapter contained only `System` at 2 MB, and no `OVRServer_x64` process remained. That is the behaviour the runtime does not perform on its own: it never exits when the client exits, and when killed it is replaced within about 2 seconds.

## Retest matrix requested

1. After a session ends, does private usage return below 500 MB within 60 seconds.
2. Does `[ull] dropped due to encoder backup` still appear while `encoder_backups=0` is reported.
3. With encode set to 3664x1920 or 3840x2160, does the retained block scale down with surface size.
4. Does any documented setting disable the launcher's automatic re-spawn of `OVRServer_x64`.

## Attachments

- `Service_2026-11-01_23.31.21.txt` (22 hour generation, 26,664,775 bytes, 193,302 lines, includes all figures above)
- `mem-series.csv` (1,313 extracted memory samples)
- `hourly-mem.txt` (per-hour private and working set)
- Redactions applied. Machine id hash, motherboard serial and headset serial are removed from this report.

