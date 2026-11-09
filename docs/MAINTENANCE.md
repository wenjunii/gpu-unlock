# Maintenance and GitHub usage

## Public source boundary

This project has its own Git root. `public-files.json` is the complete publication allowlist. `.gitignore` excludes the private test workspace, `.local/`, firmware, executables, keys, certificates and caches. Validation rejects unlisted tracked or visible candidate files, oversized/binary text inputs, common credential patterns, recovery passwords and concrete user-home paths.

Update the allowlist deliberately when adding public source. Review changes before publication; an automated pattern scan cannot detect every possible secret.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Export-Results.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Validate-PublicProject.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Sync-Project.ps1 -Push
```

Export reads the final private report when present and writes aggregate fields to `docs/results.json`. No private report is needed to use a public clone. The normal sync validates, processes registered scratch cleanup, fetches once, fast-forwards a clean checkout when possible, and commits/pushes changed public files only. It refuses an unexpected remote, another Git root, non-main branches, unsafe incoming paths or diverged history. It does not force-push or automatically rebase.

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

The cleanup script checks completion/dependency flags, exact containment, path links and hash before moving an existing file to the Recycle Bin. It never uses an age rule or recursively removes directories. Missing already-cleaned files are harmless. Records go to `.local/cleanup-history.jsonl`.

Files outside this scratch area require a separate exact-target dependency review by the agent. Keep active boot kits, source, reference inputs, shared models, user outputs and recovery backups. Do not empty the Recycle Bin.

## Daily local sync

A local scheduled task runs once daily at 09:15 America/New_York. The PC and desktop app must be available for local-file work. It refreshes the aggregate export only if the private final report exists, performs verified cleanup, validates the public source and runs change-only sync. It does not run a GPU workload, modify boot/security settings or dispatch Actions.

## GitHub Actions

The validation workflow has only `workflow_dispatch`. There are no push, pull-request, or cron triggers, no artifact uploads, and no caches. It has read-only repository permissions, a five-minute timeout and cancellation of duplicate manual runs. Run it from GitHub's Actions page only when a remote check is actually useful.

Regular Git synchronization and GitHub Actions are separate: committing/pushing these files does not require a workflow run.
