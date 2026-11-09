# Maintenance and GitHub usage

## Public source boundary

This project has its own Git root. `public-files.json` is the complete publication allowlist. `.gitignore` excludes the private test workspace, `.local/`, firmware, executables, keys, certificates and caches. Validation rejects unlisted tracked or visible candidate files, oversized/binary text inputs, common credential patterns, recovery passwords and concrete user-home paths.

Update the allowlist deliberately when adding public source. Review changes before publication; an automated pattern scan cannot detect every possible secret.

```powershell
# Offline preview and validation
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Sync-Project.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Validate-PublicProject.ps1

# Daily maintenance: refresh when a private final report exists, clean, validate and sync
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Sync-Project.ps1 -Push -RefreshResults

# Inspect an already-fetched commit without checking it out or running its scripts
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Validate-PublicProject.ps1 -Revision origin/main
```

Export requires a completed protected restart, Boolean verification flags and matched finite benchmark measurements. It writes aggregate fields to `docs/results.json`; unchanged data is left byte-for-byte intact even when PowerShell versions format JSON differently. No private report is needed to use a public clone.

Without `-Push`, sync is an offline, read-only preview. `-RefreshResults` requires `-Push`. A real run holds a per-project lock, optionally refreshes results, validates, processes registered scratch cleanup, and fetches once. A clean checkout may fast-forward documentation changes after the fetched Git blobs pass the current trusted validator. Incoming script, workflow, allowlist or maintenance-policy changes require manual review before checkout. Diverged history, an unfinished Git operation, an unexpected remote, or another Git root stops the run. There are no force pushes or automatic rebases.

Only changed public files are committed and pushed. Nested result fields are also allowlisted. Status diagnostics return `null` and explanatory notes for unavailable information instead of interpreting a failed query as Off.

## Automatic cleanup

Cleanup follows the instructions in AGENTS.md. For new disposable scratch files, use `.local/tmp/` and a private `.local/cleanup-candidates.json` manifest:

```json
[
  {
    "RelativePath": ".local/tmp/completed-validation.txt",
    "SHA256": "replace-with-the-verified-64-character-sha256",
    "VerifiedComplete": true,
    "DependenciesChecked": true,
    "Reason": "One-off validation output; result retained in the project report"
  }
]
```

The cleanup script requires actual JSON Boolean completion/dependency flags, rejects duplicate targets, alternate-stream paths and links, and checks exact containment and hash. The hash is checked again immediately before recycling. It never uses an age rule or recursively removes directories. Missing already-cleaned files are harmless, and an empty manifest is left untouched. Records go to `.local/cleanup-history.jsonl`.

Files outside this scratch area require a separate exact-target dependency review by the agent. Keep active boot kits, source, reference inputs, shared models, user outputs and recovery backups. Do not empty the Recycle Bin.

## Daily local sync

A local scheduled task runs once daily at 09:15 America/New_York, using `Sync-Project.ps1 -Push -RefreshResults`. The PC and desktop app must be available for local-file work. It does not run a GPU workload, modify boot/security settings or dispatch Actions.

## GitHub Actions

The validation workflow has only `workflow_dispatch`. There are no push, pull-request, or cron triggers, no artifact uploads, and no caches. It has read-only repository permissions, a five-minute timeout and cancellation of duplicate manual runs. Run it from GitHub's Actions page only when a remote check is actually useful.

Regular Git synchronization and GitHub Actions are separate: committing/pushing these files does not require a workflow run.
