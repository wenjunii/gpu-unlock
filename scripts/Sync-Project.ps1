param([switch]$Push,[switch]$RefreshResults)
$ErrorActionPreference='Stop'
$taskRoot=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
function Invoke-ProjectGit([string[]]$GitArguments) {
    $taskOutput=@(& git -C $taskRoot @GitArguments)
    if($LASTEXITCODE -ne 0) { throw ('git failed: '+($GitArguments -join ' ')) }
    return $taskOutput
}
$taskActual=(Invoke-ProjectGit -GitArguments @('rev-parse','--show-toplevel')) -join ''
if([IO.Path]::GetFullPath($taskActual) -ine $taskRoot -or -not (Test-Path -LiteralPath (Join-Path $taskRoot '.git'))) { throw 'Refusing another Git root.' }
if(((Invoke-ProjectGit -GitArguments @('branch','--show-current')) -join '') -cne 'main') { throw 'Automatic sync only supports main.' }
$taskRemote=(Invoke-ProjectGit -GitArguments @('remote','get-url','origin')) -join ''
if(($taskRemote.TrimEnd('/') -replace '\.git$','') -ine 'https://github.com/WenjunII/gpu-unlock') { throw 'Unexpected public remote.' }
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
    foreach($taskOperation in @('MERGE_HEAD','rebase-merge','rebase-apply','CHERRY_PICK_HEAD','REVERT_HEAD')) {
        $taskStatePath=(Invoke-ProjectGit -GitArguments @('rev-parse','--git-path',$taskOperation)) -join ''
        if(-not [IO.Path]::IsPathRooted($taskStatePath)) { $taskStatePath=Join-Path $taskRoot $taskStatePath }
        if(Test-Path -LiteralPath $taskStatePath) { throw 'Finish the existing Git operation before automatic sync.' }
    }
    if($RefreshResults) { & (Join-Path $PSScriptRoot 'Export-Results.ps1') }
    & (Join-Path $PSScriptRoot 'Validate-PublicProject.ps1')
    & (Join-Path $PSScriptRoot 'Cleanup-Project.ps1')
    Invoke-ProjectGit -GitArguments @('fetch','--no-tags','origin','main') | Out-Null
    $taskDirty=@(Invoke-ProjectGit -GitArguments @('status','--porcelain'))
    $taskCounts=((Invoke-ProjectGit -GitArguments @('rev-list','--left-right','--count','HEAD...origin/main')) -join '') -split '\s+'
    $taskAhead=[int]$taskCounts[0]; $taskBehind=[int]$taskCounts[1]
    if($taskBehind -gt 0) {
        if($taskAhead -gt 0 -or $taskDirty.Count -gt 0) { throw 'Remote changes need review; no automatic rebase, reset or overwrite.' }
        $taskIncoming=@(Invoke-ProjectGit -GitArguments @('diff','--name-only','HEAD..origin/main'))
        if(@($taskIncoming | Where-Object {$_ -match '^(scripts/|\.github/|AGENTS\.md$|public-files\.json$|\.gitignore$|\.gitattributes$)'}).Count) { throw 'Incoming executable or maintenance-policy changes require manual review.' }
        # Inspect fetched Git blobs using this trusted validator before checkout.
        & (Join-Path $PSScriptRoot 'Validate-PublicProject.ps1') -Revision origin/main
        Invoke-ProjectGit -GitArguments @('merge','--ff-only','origin/main') | Out-Null
        & (Join-Path $PSScriptRoot 'Validate-PublicProject.ps1')
    }
    $taskAllowed=Get-Content -LiteralPath (Join-Path $taskRoot 'public-files.json') -Raw | ConvertFrom-Json
    Invoke-ProjectGit -GitArguments (@('add','--')+@($taskAllowed)) | Out-Null
    & (Join-Path $PSScriptRoot 'Validate-PublicProject.ps1')
    $taskStaged=@(Invoke-ProjectGit -GitArguments @('diff','--cached','--name-only'))
    if($taskStaged.Count) { Invoke-ProjectGit -GitArguments @('commit','-m','Sync project documentation and maintenance tools') | Write-Output }
    $taskAhead=[int]((Invoke-ProjectGit -GitArguments @('rev-list','--count','origin/main..HEAD')) -join '')
    if($taskAhead -gt 0) { Invoke-ProjectGit -GitArguments @('push','origin','main') | Write-Output; Write-Output 'Public project synchronized.' }
    else { Write-Output 'Already synchronized; no commit or push needed.' }
} finally {
    $taskLock.Dispose()
}
