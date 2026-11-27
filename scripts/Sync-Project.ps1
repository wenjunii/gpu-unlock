param([switch]$Push,[switch]$RefreshResults)
$ErrorActionPreference='Stop'
$taskRoot=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
function Invoke-ProjectGit([string[]]$GitArguments) {
    $taskOutput=@(& git --no-optional-locks --no-replace-objects -C $taskRoot @GitArguments)
    if($LASTEXITCODE -ne 0) { throw ('git failed: '+($GitArguments -join ' ')) }
    return $taskOutput
}
function Get-ProjectTreeId([string]$Commit) {
    return (Invoke-ProjectGit -GitArguments @('rev-parse','--verify',($Commit+'^{tree}'))) -join ''
}
$taskActual=(Invoke-ProjectGit -GitArguments @('rev-parse','--show-toplevel')) -join ''
if([IO.Path]::GetFullPath($taskActual) -ine $taskRoot -or -not (Test-Path -LiteralPath (Join-Path $taskRoot '.git'))) { throw 'Refusing another Git root.' }
if(((Invoke-ProjectGit -GitArguments @('branch','--show-current')) -join '') -cne 'main') { throw 'Automatic sync only supports main.' }
$taskFetchUrls=@(Invoke-ProjectGit -GitArguments @('remote','get-url','--all','origin'))
$taskPushUrls=@(Invoke-ProjectGit -GitArguments @('remote','get-url','--push','--all','origin'))
if($taskFetchUrls.Count -ne 1 -or $taskPushUrls.Count -ne 1) { throw 'Expected one public fetch URL and one public push URL.' }
foreach($taskUrl in ($taskFetchUrls+$taskPushUrls)) {
    if(($taskUrl.TrimEnd('/') -replace '\.git$','') -ine 'https://github.com/WenjunII/gpu-unlock') { throw 'Unexpected public fetch or push URL.' }
}
if($RefreshResults -and -not $Push) { throw '-RefreshResults requires -Push; preview does not write files.' }
& (Join-Path $PSScriptRoot 'Validate-PublicProject.ps1')
if(-not $Push) { Invoke-ProjectGit -GitArguments @('status','--short'); Write-Output 'Preview only; no cleanup, refresh, fetch, commit or push.'; return }
$taskLocal=Join-Path $taskRoot '.local'
if((Test-Path -LiteralPath $taskLocal) -and ((Get-Item -LiteralPath $taskLocal -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Local sync state must not traverse a link.' }
if(-not (Test-Path -LiteralPath $taskLocal)) { New-Item -ItemType Directory -Path $taskLocal | Out-Null }
$taskLockPath=Join-Path $taskLocal 'sync.lock'
if((Test-Path -LiteralPath $taskLockPath) -and ((Get-Item -LiteralPath $taskLockPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Sync lock must not be a link.' }
try { $taskLock=[IO.File]::Open($taskLockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) } catch { throw 'Another sync is active, or the sync lock is unavailable.' }
try {
    foreach($taskOperation in @('MERGE_HEAD','rebase-merge','rebase-apply','CHERRY_PICK_HEAD','REVERT_HEAD','sequencer')) {
        $taskStatePath=(Invoke-ProjectGit -GitArguments @('rev-parse','--git-path',$taskOperation)) -join ''
        if(-not [IO.Path]::IsPathRooted($taskStatePath)) { $taskStatePath=Join-Path $taskRoot $taskStatePath }
        if(Test-Path -LiteralPath $taskStatePath) { throw 'Finish the existing Git operation before automatic sync.' }
    }
    if($RefreshResults) { & (Join-Path $PSScriptRoot 'Export-Results.ps1') }
    & (Join-Path $PSScriptRoot 'Validate-PublicProject.ps1')
    & (Join-Path $PSScriptRoot 'Cleanup-Project.ps1')
    $taskReviewBranch='sync/gpu-project/review'
    $taskReviewTrackingRef='refs/remotes/origin/'+$taskReviewBranch
    $taskReviewUrl='https://github.com/wenjunii/gpu-unlock/compare/main...'+$taskReviewBranch+'?expand=1'
    # Scope the one fetch to main and the optional review branch namespace.
    # The wildcard also allows a first run before the review branch exists.
    $taskFetchRefspecs=@(
        'refs/heads/main:refs/remotes/origin/main'
        'refs/heads/sync/gpu-project/*:refs/remotes/origin/sync/gpu-project/*'
    )
    Invoke-ProjectGit -GitArguments (@('fetch','--no-tags','--prune','--refmap=','origin')+$taskFetchRefspecs) | Out-Null
    $taskFetchedCommit=(Invoke-ProjectGit -GitArguments @('rev-parse','--verify','refs/remotes/origin/main^{commit}')) -join ''
    $taskHeadCommit=(Invoke-ProjectGit -GitArguments @('rev-parse','--verify','HEAD')) -join ''
    $taskDirty=@(Invoke-ProjectGit -GitArguments @('status','--porcelain'))
    $taskCounts=((Invoke-ProjectGit -GitArguments @('rev-list','--left-right','--count',($taskHeadCommit+'...'+$taskFetchedCommit))) -join '') -split '\s+'
    $taskAhead=[int]$taskCounts[0]; $taskBehind=[int]$taskCounts[1]
    if($taskBehind -gt 0) {
        if($taskAhead -gt 0 -or $taskDirty.Count -gt 0) { throw 'Remote changes need review; no automatic rebase, reset or overwrite.' }
        $taskIncomingRange=$taskHeadCommit+'..'+$taskFetchedCommit
        $taskIncomingPaths=@(Invoke-ProjectGit -GitArguments @('log','-m','--no-renames','--format=','--name-only',$taskIncomingRange))
        if(@($taskIncomingPaths | Where-Object {$_ -match '^(scripts/|\.github/|AGENTS\.md$|public-files\.json$|\.gitignore$|\.gitattributes$|docs/MAINTENANCE\.md$)'}).Count) {
            # A PR merge can diff against an older parent even when every
            # incoming commit has the exact files already checked out here.
            $taskHeadTree=Get-ProjectTreeId $taskHeadCommit
            $taskIncomingTrees=@(Invoke-ProjectGit -GitArguments @('log','--format=%T',$taskIncomingRange))
            if(@($taskIncomingTrees | Where-Object {$_ -cne $taskHeadTree}).Count) { throw 'Incoming executable or maintenance-policy changes require manual review.' }
        }
        # Inspect every new tree before merging the exact commit we fetched.
        $taskIncomingCommits=@(Invoke-ProjectGit -GitArguments @('rev-list','--reverse',$taskIncomingRange))
        foreach($taskCommit in $taskIncomingCommits) {
            & (Join-Path $PSScriptRoot 'Validate-PublicProject.ps1') -Revision $taskCommit
        }
        Invoke-ProjectGit -GitArguments @('merge','--ff-only',$taskFetchedCommit) | Out-Null
        & (Join-Path $PSScriptRoot 'Validate-PublicProject.ps1')
        $taskHeadCommit=$taskFetchedCommit
    }

    # Pushing publishes the full unpublished history, even when HEAD is clean.
    $taskOutgoingRange=$taskFetchedCommit+'..'+$taskHeadCommit
    $taskCheckedCommits=@(Invoke-ProjectGit -GitArguments @('rev-list','--reverse',$taskOutgoingRange))
    foreach($taskCommit in $taskCheckedCommits) {
        & (Join-Path $PSScriptRoot 'Validate-PublicProject.ps1') -Revision $taskCommit
    }

    $taskReviewCommit=$null
    $taskComparisonCommit=$taskFetchedCommit
    if($taskCheckedCommits.Count -or $taskDirty.Count) {
        $taskReviewEntries=@(Invoke-ProjectGit -GitArguments @('for-each-ref','--format=%(refname) %(objectname)',$taskReviewTrackingRef))
        $taskReviewEntry=$taskReviewEntries | Where-Object { $_.StartsWith($taskReviewTrackingRef+' ',[StringComparison]::Ordinal) } | Select-Object -First 1
        if($taskReviewEntry) {
            $taskReviewCommit=($taskReviewEntry -split ' ',2)[1]
            $taskReviewOnlyCount=[int]((Invoke-ProjectGit -GitArguments @('rev-list','--count',($taskHeadCommit+'..'+$taskReviewCommit))) -join '')
            if($taskReviewOnlyCount) { throw 'The GitHub review branch has commits absent from local main. Review them before publishing.' }
            $taskPendingReviewCount=[int]((Invoke-ProjectGit -GitArguments @('rev-list','--count',($taskFetchedCommit+'..'+$taskReviewCommit))) -join '')
            if($taskPendingReviewCount) { $taskComparisonCommit=$taskReviewCommit }
        }
    }

    if($taskDirty.Count) {
        $taskAllowed=Get-Content -LiteralPath (Join-Path $taskRoot 'public-files.json') -Raw | ConvertFrom-Json
        Invoke-ProjectGit -GitArguments (@('add','--')+@($taskAllowed)) | Out-Null
        $taskStaged=@(Invoke-ProjectGit -GitArguments @('diff','--cached','--name-only'))
        if($taskStaged.Count) {
            & (Join-Path $PSScriptRoot 'Validate-PublicProject.ps1') -Staged
            Invoke-ProjectGit -GitArguments @('commit','-m','Sync project documentation and maintenance tools') | Write-Output
        }
    }

    $taskPublishCommit=(Invoke-ProjectGit -GitArguments @('rev-parse','--verify','HEAD')) -join ''
    $taskPublishRange=$taskFetchedCommit+'..'+$taskPublishCommit
    $taskPublishCommits=@(Invoke-ProjectGit -GitArguments @('rev-list','--reverse',$taskPublishRange))
    foreach($taskCommit in $taskPublishCommits) {
        if($taskCheckedCommits -cnotcontains $taskCommit) {
            & (Join-Path $PSScriptRoot 'Validate-PublicProject.ps1') -Revision $taskCommit
        }
    }
    if(-not $taskPublishCommits.Count) {
        Write-Output 'Already synchronized. No commit or push needed.'
        return
    }
    if((Get-ProjectTreeId $taskComparisonCommit) -ceq (Get-ProjectTreeId $taskPublishCommit)) {
        if($taskComparisonCommit -ceq $taskReviewCommit) {
            Write-Output 'The review branch already has these public changes.'
            Write-Output $taskReviewUrl
        } else {
            Write-Output 'No public file differences from GitHub main.'
        }
        return
    }

    Invoke-ProjectGit -GitArguments @('push','--no-follow-tags','origin',($taskPublishCommit+':refs/heads/'+$taskReviewBranch)) | Write-Output
    Write-Output 'Public changes pushed to the review branch. Merge through a GitHub pull request.'
    Write-Output $taskReviewUrl
} finally {
    $taskLock.Dispose()
}
