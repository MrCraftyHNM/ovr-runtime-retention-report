# Meta submission, pointer only

Short by design. The evidence lives in the repository and the gist, so the form entry is a pointer plus the two numbers that make it worth a click. Use this instead of the long body when the form has a size limit or when the reader prefers documents.

---

## Subject

OVRServer_x64 keeps memory after the Meta Link window closes, and OVRService restarts it within seconds

## Body

Runtime 208.0.0.84.535, Windows 11 build 26200.9711, Quest 3 over wired Link.

Closing the Meta Link window does not stop the VR runtime. `OVRService` starts a new `OVRServer_x64` about 4 seconds later, and a normal user cannot stop the service. Memory is kept after the session ends. One 21.9 hour generation peaked at 5,781 MB private and 2,708 MB working set, released 4.1 percent at teardown, and held about 2,500 MB for 90 minutes with nothing attached. Stopping the service releases all of it to zero, six times over, so the retained block is real rather than measurement drift.

Full report, reproduction steps, build fingerprint and falsifiable claims, for you and for anyone else who wants to check it on their own machine:

- https://github.com/MrCraftyHNM/ovr-runtime-retention-report
- https://gist.github.com/MrCraftyHNM/a20aa1a65ca6cf4c05293e45779bb280

What would help. The runtime should exit when the client exits, or expose a way to stop it without administrator rights, and per-session buffers should be released at session end.

---

## After filing

Add the ticket reference to `STATUS.json` history and to the record, so the repository shows the filing date. No further copies of this text are needed; the repository is the documentation of record.
