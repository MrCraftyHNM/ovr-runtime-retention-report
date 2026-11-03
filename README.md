# OVRServer retention report

**Status:** active, see [STATUS.json](STATUS.json) for the current state, the reason and the history.

A bug report against Meta Horizon PC, runtime 208.0.0.84.535, revision 70b5b1dfe187: `OVRServer_x64.exe` keeps gigabytes of private memory after the Meta Link window closes, and `OVRService` restarts the process within seconds of any exit, so a normal user cannot close the VR runtime at all.

## Read this first

- [report/README.md](report/README.md) is the entry point, symptom, numbers table and reproduction in under a minute
- [report/report.json](report/report.json) is the machine-readable layer, six claims with metric, value, method, evidence and falsifier each
- [report/meta-bug-report.md](report/meta-bug-report.md) is the full write-up with environment, expected behaviour and retest matrix
- [report/submission-message.md](report/submission-message.md) is the text submitted to Meta
- [report/evidence/stop-records.txt](report/evidence/stop-records.txt) holds the six verified stop records

Published copy of the same content: https://gist.github.com/MrCraftyHNM/24fa2e2fb750db41cf94fbbcaec7c618

## Headline numbers

| Metric | Value |
|---|---|
| Peak private memory, one 21.9 hour generation | 5,781.3 MB |
| Working set held after the session ended | about 2,500 MB, for 90 minutes |
| Released at session end | 236.4 MB, 4.1 percent |
| Cold-start footprint, fresh process | 210 MB |
| Restart after client exit | about 4 seconds |
| Restart after manual kill | about 2 seconds |

## Tooling in this folder

- `ovr-autostop.ps1` stops the service when the client fully exits and restarts it when the client launches, writing an atomic record per stop
- `ovr-close-proper.ps1` performs the ordered manual close and verifies the result, `-Plan` for a dry read
- `version-stamp.ps1` writes the build fingerprint used as evidence
- `find-sensitive.ps1` scans the tree for personal and machine identifiers
- `publish-check.ps1` gates what may be uploaded
- `.githooks/pre-commit` runs `find-sensitive.ps1` before every commit
- `set-status.ps1` changes the report status, `deprecated` withdraws it

## Withdrawal

Anyone may withdraw this report by setting the status to `deprecated`, one command, one commit, no owner involvement. Gist deletion remains owner-only, which is a host limitation, so the README documents both.

## Scope

Measured on one hybrid laptop with an external GPU, which is incidental. The defect is process lifetime plus process-private memory, so it is expected on integrated, discrete and hybrid graphics alike.
