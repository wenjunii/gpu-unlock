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

# Inspect the exact files Git would commit from the index
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Validate-PublicProject.ps1 -Staged
```

Export requires a completed protected restart, Boolean verification flags and matched finite benchmark measurements. It writes aggregate fields to `docs/results.json`; unchanged data is left byte-for-byte intact even when PowerShell versions format JSON differently. No private report is needed to use a public clone.

Without `-Push`, sync is an offline, read-only preview. `-RefreshResults` requires `-Push`. A real run holds a per-project lock, optionally refreshes results, validates, processes registered scratch cleanup, and fetches `main` and the review branch in one request. A clean checkout can fast-forward documentation changes after every incoming commit passes the current validator. Changes to scripts, workflows, or publication and maintenance rules in the incoming history require manual review. A pull-request merge can fast-forward when every incoming tree matches the checked-out files exactly and passes validation. The run also stops on diverged history, unfinished Git operations, an unexpected Git root, or a fetch or push URL outside the public destination.

Sync checks the staged blobs before committing and validates each unpublished commit before pushing the validated tip. This scan covers files that were added and later removed on the local branch. Git objects under public paths must be regular files. Nested result fields are also allowlisted.

## Publish to protected main

1. Run `Sync-Project.ps1 -Push -RefreshResults`. It sends changed public files to `sync/gpu-project/review` and prints the GitHub comparison link. Later runs reuse the branch and skip the push when the pending files match.
2. Review the changes in a GitHub pull request from that branch to `main`. Choose **Create a merge commit** to preserve the commit history and let the next sync fast-forward.
3. Run sync again or let the daily job pick up the merge. Review any divergence before making further changes. Squash and rebase merges create different commit IDs and can make local `main` diverge.

If the review branch contains commits absent from local `main`, sync stops before staging or pushing. Review those commits before continuing.

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

Sync leaves pull-request creation and merging to a separate review step. GitHub’s automatic CodeQL checks can run independently of the manual validation workflow.
