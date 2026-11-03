# Submission message, Meta Horizon PC / OVRServer retention and lifecycle

Submit through Meta Horizon PC, Help, Report a problem, and post the short version on the Meta Community Forums PC VR section with the gist link. Attach the three files listed at the end. No absolute user paths and no hardware serials appear in this text or in the attachments.

---

## Subject

OVRServer_x64 keeps gigabytes after the Link window closes, on any GPU, and OVRService restarts it within seconds

## Body

This is written from the point of view of a normal user who only opens the Meta Link client to play. You close the window, and the runtime is still there, still holding memory, with no way to close it that a non-administrator can find.

Two behaviours reproduce on this machine and should reproduce on any GPU, because neither depends on the graphics hardware.

First, closing the window does not end the runtime. The close reaches `OVRServer_x64`, which logs a session teardown, and then `OVRService` starts a new `OVRServer_x64` within about four seconds. Killing the process in Task Manager behaves the same way, a replacement appears within about two seconds, and the service never leaves the Running state. The service ACL gives a normal user no stop right, so Task Manager can only end the child that the supervisor replaces. From the user's chair the runtime simply cannot be closed, and the client window state and the runtime process state never agree.

Second, memory is kept after the session. Across one 21.9 hour runtime generation, `OVRServer_x64` grew from 1,245.6 MB private to a peak of 5,781.3 MB private and 2,707.8 MB working set. When the session ended it released 236.4 MB, which is 4.1 percent, and then held about 2,500 MB working set for the remaining 90 minutes with nothing attached. Growth happens only while streaming: five streaming hours added 4,467 MB, while eighteen idle hours moved minus 165 MB in total, with fourteen consecutive idle hours flat between 2,167 and 2,170 MB. A fresh process on this machine measures 210 MB working set, so roughly 2.5 GB is retained that only a restart clears.

The measurements come from one configuration, a hybrid laptop with an external GPU, and I mention the hardware only because a vendor GPU panel is what first showed me the lingering process. The retention itself is process-private memory and shows in Task Manager on any machine. A user with a single GPU can confirm it in under a minute: open Link, play, close the window, then watch whether `OVRServer_x64.exe` disappears.

Environment for reproduction: runtime 208.0.0.84.535, revision 70b5b1dfe187, Windows 11 build 26200.9711, Ryzen 7 8840HS, Radeon 780M plus a Radeon RX 7600M XT over Thunderbolt, driver 32.0.32015.7029, Quest 3 over wired USB3 Link at 4096x2208, 72 fps, AVC, fixed 200 Mbps.

One detail that may help narrow the encoder path. The run contains 26,016 `[ull] Frame(s) N to M dropped due to encoder backup` warnings, while all 93 per-minute `oculus_pc_xrs_stats_event` records report `encoder_backups=0`. The two sources disagree, and encode duration at those settings is about 8.1 to 8.4 ms per frame.

What I would like:

1. Closing the client should stop the runtime, or the runtime should exit on its own when no client is attached.
2. Session end should return memory to the cold-start footprint, or at least release per-session buffers. A fresh process here measures 210 MB working set.
3. `encoder_backups` should agree with the dropped-frame warnings, or the difference should be documented.

Workaround as evidence that the block is releasable: stopping the service on client exit drops memory to zero and leaves only a 2 MB kernel context on the GPU. Six consecutive stops produced identical results, for example

`verdict=PASS build=208.0.0.84.535/70b5b1dfe187 trigger=client-gone-confirmed mode=graceful wsMB=212 privMB=182 gpuMB=40.8 -> 0 svc=Stopped`

That line comes from my own watcher, not from the runtime, which is the point: the runtime never does this on its own.

Attachments:

1. `meta-bug-report.md`, the full write-up with the environment, steps, observed figures, expected behaviour and retest matrix.
2. `version-stamp.json`, machine-readable build fingerprint, runtime and launcher hashes, OS build, GPU drivers, service configuration.
3. `stop-records.txt`, the six stop records above plus the failed unelevated attempts, showing what does and does not release the block.

Logs are available on request, including the 22 hour `Service_*.txt` generation and the per-minute memory series extracted from it.

---

## Short version, for a forum post

If you close the Meta Link window on a PC, the VR runtime does not close with it. `OVRServer_x64` stays, and if you end it in Task Manager the service starts a new one within about two seconds, so a normal user cannot stop it. On my machine one 21.9 hour session grew it to 5.8 GB private and 2.7 GB working set, and when the session ended it gave back 4.1 percent, holding about 2.5 GB with nothing attached. Growth is confined to streaming hours, idle hours are flat. This is on runtime 208.0.0.84.535 and it looks hardware-independent, since the retained memory is private to the process and the restart is done by the service. Stopping the service drops everything to zero, so the block is real and recoverable, just never recovered. Reported with build fingerprint and stop records.
