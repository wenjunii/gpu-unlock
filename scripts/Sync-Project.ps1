param([switch]$Push)
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
& (Join-Path $PSScriptRoot 'Validate-PublicProject.ps1')
if(-not $Push) { Invoke-ProjectGit -GitArguments @('status','--short'); Write-Output 'Preview only; use -Push for regular sync.'; return }
& (Join-Path $PSScriptRoot 'Cleanup-Project.ps1')
Invoke-ProjectGit -GitArguments @('fetch','--no-tags','origin','main') | Out-Null
$taskDirty=@(Invoke-ProjectGit -GitArguments @('status','--porcelain'))
$taskCounts=((Invoke-ProjectGit -GitArguments @('rev-list','--left-right','--count','HEAD...origin/main')) -join '') -split '\s+'
$taskAhead=[int]$taskCounts[0]; $taskBehind=[int]$taskCounts[1]
if($taskBehind -gt 0) {
    if($taskAhead -gt 0 -or $taskDirty.Count -gt 0) { throw 'Remote changes need review; no automatic rebase, reset or overwrite.' }
    $taskAllowed=Get-Content -LiteralPath (Join-Path $taskRoot 'public-files.json') -Raw | ConvertFrom-Json
    foreach($taskRel in (Invoke-ProjectGit -GitArguments @('diff','--name-only','HEAD..origin/main'))) { if($taskAllowed -cnotcontains $taskRel) { throw 'Incoming paths need allowlist review.' } }
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
