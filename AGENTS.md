# Project maintenance instructions

## Scope and public repository

- Work only inside this project's own Git root. Verify `git rev-parse --show-toplevel` before Git mutations. Never stage or push the parent home-directory repository.
- Public destination: `https://github.com/WenjunII/gpu-unlock`. Only files listed in `public-files.json` may be tracked or synced.
- Keep `test-v2.1.11/` and `.local/` private. Never publish raw machine records, USB contents, EFI/BCD backups, signing material, identifiers, credentials, or boot/firmware binaries.
- Publish aggregate results through `scripts/Export-Results.ps1`; review the exported fields. Run `scripts/Validate-PublicProject.ps1` before committing or pushing.
- Preserve the tested GPU startup configuration. Documentation/sync/cleanup tasks do not authorize boot-order, Secure Boot, BitLocker, firmware, driver, or GPU-mode changes.

## Automatic cleanup after completed tasks

- The user authorizes routine cleanup without another confirmation after verification. Include completed installation archives, abandoned partial downloads, one-off validation scripts, scratch outputs, and redundant task copies that are no longer needed.
- Verify exact paths, contents and dependencies before removal. Age, an empty-looking directory, or absence from the current command alone does not establish that something is unused.
- Preserve active tools/environments, source files, reference inputs, user outputs, active/shared models, and recovery backups. When a workflow is retired, remove models exclusive to it only after checking shared dependencies.
- Prefer the Recycle Bin; never empty it. Report material cleanup, size where useful, and recoverability.
- Put new disposable scratch files under `.local/tmp/`. Once a task finishes, record exact file paths and SHA256 values in `.local/cleanup-candidates.json`, with `VerifiedComplete` and `DependenciesChecked` both true. `scripts/Cleanup-Project.ps1` processes this manifest and refuses paths outside that scratch directory.
- Do not delete recovery backups or active boot assets through the scratch-cleanup mechanism. The user-data USB backup remains local until the restored source can be checked again or its removal is explicitly authorized.

## Regular sync and low GitHub usage

- Daily local sync is the default. Use `scripts/Sync-Project.ps1 -Push`; it validates public files, processes verified scratch cleanup, fetches once, and commits/pushes only when needed.
- Keep GitHub Actions manual-only (`workflow_dispatch`). Do not add push, pull-request, or scheduled triggers without a new user instruction. Routine sync requires no Actions run.
- No force pushes, automatic history rewriting, broad `git add -A`, repository-wide artifact deletion, or changes to other GitHub repositories.
- Stop and report remote divergence or unsafe incoming files rather than discarding changes. Use authenticated Git/GitHub CLI without printing tokens.
- Recurring maintenance must never reboot the PC, run GPU benchmarks, install firmware/drivers, enroll keys, or suspend encryption.
