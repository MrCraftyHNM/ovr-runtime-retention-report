# Atomic stop record, schema and dual use

One line per stop event. Append only. Never edited, never summarised in place.

## Line format

```
<timestamp> BUFFER-RELEASED verdict=<PASS|PARTIAL|FAIL> build=<version>/<revision> trigger=<reason> mode=<graceful|forced> respawn=<yes|no> respawnPid=<n|-> pid=<before> afterPid=<n|-> wsMB=<a>-><b> privMB=<a>-><b> gpuMB=<a>-><b> svc=<state> log=<Service_*.txt>
```

Real record from an unelevated forced attempt, which is the failure shape:
`2026-11-03 00:44:26 BUFFER-RELEASED verdict=FAIL build=208.0.0.84.535/70b5b1dfe187 trigger=once-client-absent mode=forced respawn=yes respawnPid=22596 pid=3392 afterPid=22596 wsMB=210->28 privMB=184->36 gpuMB=40.8->0 svc=Running log=Service_2026-11-03_00.44.25.txt`

## Fields and why each exists

| Field | Source | Why it must be in the line |
|---|---|---|
| timestamp | watcher clock | orders events, lets Meta match to their telemetry window |
| verdict | computed | PASS only when pid gone, service stopped, gpuMB <= 1. PARTIAL when the GPU context survives. FAIL when the stop did not land |
| build | OVRServer/launcher version plus revision parsed from the runtime log | binds the measurement to one build, so an update cannot silently blend results |
| trigger | watcher | distinguishes client exit, manual run, and once-mode so a reviewer knows what caused the stop |
| pid | process table | proves which process the before numbers belonged to |
| mode | watcher | graceful means the service stop was accepted, forced means a terminate was required |
| respawn, respawnPid | process table during a 10 s settle window | records that the supervisor replaced the process, which is the defect itself, and which pid the after numbers belong to |
| afterPid | process table | the after numbers are only meaningful if the same pid produced them |
| wsMB, privMB | process counters | the retained host memory, which is what the user feels |
| gpuMB | GPU Process Memory counters across all LUIDs | the only pool that can independently fail to release |
| svc | service control manager | separates the two assertions, stop happened and allocation returned |
| log | newest `Service_*.txt` | pins the line to one runtime generation, since the filename encodes that process start time |

## Invariants

1. A verdict is never written without all six numbers on the same line.
2. The build is embedded, so no reader has to look up a second file to interpret the line.
3. Append only. A wrong line is corrected by a later line, never by editing.
4. Enumerated verdict set, no free text verdicts.

## Dual use

**Machine fix.** The watcher stops `OVRService` on the `Client.exe` running to exited edge, so the retained block cannot outlive the session. The record is the receipt, and its verdict is what tells you the fix worked rather than appeared to.

**Meta report.** The same line is the workaround evidence and the reproduction artifact. It carries the build, the trigger, the exact before and after of all three pools, and the log file that holds the generation history. Attached with `version-stamp.json`, it answers the two questions triage asks first, which build, and how do you know.

## Acceptance

- The record exists for every stop, including failed ones.
- `PASS` appears only with `gpuMB <value>->0` and `svc=Stopped` and no pid.
- `PARTIAL` appearing sets the fifth report finding, GPU context not released on process exit.
