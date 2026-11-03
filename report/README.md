# README, OVRServer retention report

> DEPRECATED. This report is withdrawn. Do not act on it without reading STATUS.json for the reason and the superseding reference.


**Status:** deprecated since 2026-11-03T19:58:45Z because final mechanism verification

For a support agent or an automated triage pipeline. Read this page first, it has everything needed to reproduce and rank the issue without a log request.

## The symptom in one line

Close the Meta Link window on a PC and the VR runtime does not close. `OVRServer_x64.exe` stays, keeps memory, and a normal user cannot stop it.

## Numbers, all measured on the reporting machine

| Metric | Value |
|---|---|
| Runtime build | 208.0.0.84.535, revision 70b5b1dfe187 |
| Peak private memory, one 21.9 hour generation | 5,781.3 MB |
| Peak working set, same generation | 2,707.8 MB |
| Working set held after session end | about 2,500 MB, for 90 minutes |
| Released at session end | 236.4 MB, which is 4.1 percent |
| Cold-start footprint, fresh process | 210 MB |
| Growth in 5 streaming hours | plus 4,467 MB |
| Movement in 18 idle hours | minus 165 MB |
| Restart after client exit | about 4 seconds |
| Restart after manual kill | about 2 seconds |
| Dropped-frame warnings vs reported backups | 26,016 vs 0 in 93 samples |
| Stops verified to release everything | 6 |

## Files in this gist

| File | Purpose |
|---|---|
| `report.json` | machine-readable claims, each with id, metric, value, method, evidence and falsifier |
| `meta-bug-report.md` | full write-up, environment, steps, expected behaviour, retest matrix |
| `submission-message.md` | the prose report body plus a short forum version |
| `stop-records.txt` | six PASS stop records and the failed unelevated attempts |
| `version-stamp.json` | build fingerprint, runtime and launcher hashes, OS build, GPU drivers, service config |

## If you are an automated agent

1. Read `report.json`.
2. Every claim has a falsifier. Use those instead of asking for the raw log.
3. Any claim whose evidence field is empty must be treated as unverified.
4. The figures were extracted by script from the runtime's own `[DxDiag] LogResourceUsage` lines, 1,313 samples at about one per minute, so the series can be rechecked from the CSVs in the full report rather than the 22 MB log.

## If you are a human agent

The reproduction is 60 seconds: open Link, play, close the window, watch Task Manager. If `OVRServer_x64.exe` is still there with a working set in the gigabytes, the report applies. Then end the task and watch a replacement appear in about two seconds.

## Scope

The measurements come from one hybrid laptop with an external GPU, mentioned only because a vendor GPU panel is what first exposed the lingering process. The defect is process lifetime plus process-private memory, so the same retention applies on integrated, discrete or hybrid graphics. A single-GPU user can confirm it in the same minute.

## What is not in here

The raw 22 MB `Service_*.txt` generation and the machine's hardware serials. Both are available on request, and neither is needed to reproduce.

## Deprecating this report

Anyone may withdraw this report, without asking the gist owner, by changing one field.

    powershell -File set-status.ps1 -Status deprecated -Reason "why" -By "who"

That writes `STATUS.json` with a timestamp, the previous status and the reason appended to `history`, and prepends a DEPRECATED notice to this page. Commit it, or open a pull request if you do not have write access.

What deprecation does and does not do. It changes what readers are told, immediately, for anyone reading the repository. It does not delete the gist, because GitHub only lets the gist owner delete a gist; the owner propagates a deprecation with `gh gist edit`, one file per call, and can delete the gist outright if that is the decision. No third party can delete content they do not own, on any host, so the mechanism here is a status that any reader can check and any contributor can flip.
