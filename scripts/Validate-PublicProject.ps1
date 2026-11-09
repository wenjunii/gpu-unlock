$ErrorActionPreference='Stop'
$taskRoot=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$taskGitRoot=(& git -C $taskRoot rev-parse --show-toplevel) -join ''
if($LASTEXITCODE -ne 0 -or [IO.Path]::GetFullPath($taskGitRoot) -ine $taskRoot) { throw 'Refusing validation against another Git root.' }
$taskAllowed=Get-Content -LiteralPath (Join-Path $taskRoot 'public-files.json') -Raw | ConvertFrom-Json
if(@($taskAllowed).Count -ne @($taskAllowed | Select-Object -Unique).Count) { throw 'Publication allowlist has duplicate paths.' }
$taskVisible=@(& git -C $taskRoot ls-files --cached --others --exclude-standard)
if($LASTEXITCODE -ne 0) { throw 'Cannot list public Git candidates.' }
foreach($taskRel in $taskVisible) { if($taskAllowed -cnotcontains $taskRel) { throw ('Unlisted public Git candidate: '+$taskRel) } }
$taskSecretPatterns=@(
    '-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----',
    '(?:gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,})',
    '(?<!\d)\d{6}(?:-\d{6}){7}(?!\d)',
    '(?i)[A-Z]:[\\/]Users[\\/][A-Za-z0-9_. -]+[\\/]',
    '(?i)/home/[A-Za-z0-9_.-]+/',
    'S-1-5-21-\d+-\d+-\d+-\d+',
    'eui\.[a-fA-F0-9]{16}',
    'sk-[A-Za-z0-9_-]{24,}'
)
foreach($taskRel in $taskAllowed) {
    if([IO.Path]::IsPathRooted($taskRel) -or $taskRel -match '(^|/)\.\.(/|$)|\\') { throw 'Invalid public relative path.' }
    $taskPath=Join-Path $taskRoot $taskRel
    $taskItem=Get-Item -LiteralPath $taskPath -Force
    if($taskItem.PSIsContainer -or $taskItem.Length -gt 262144 -or ($taskItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw ('Invalid public file: '+$taskRel) }
    $taskParent=$taskItem.Directory
    while($taskParent.FullName.Length -gt $taskRoot.Length) { if($taskParent.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Public path traverses a link.' }; $taskParent=$taskParent.Parent }
    $taskText=(New-Object Text.UTF8Encoding($false,$true)).GetString([IO.File]::ReadAllBytes($taskPath))
    if($taskText.Contains([string][char]0)) { throw ('Binary content in public file: '+$taskRel) }
    foreach($taskPattern in $taskSecretPatterns) { if($taskText -match $taskPattern) { throw ('Possible private data in '+$taskRel+'; inspect locally without printing the match.') } }
    if($taskRel.EndsWith('.ps1')) { $taskTokens=$null; $taskErrors=$null; [Management.Automation.Language.Parser]::ParseFile($taskPath,[ref]$taskTokens,[ref]$taskErrors) | Out-Null; if($taskErrors.Count) { throw ('PowerShell parse error: '+$taskRel) } }
    if($taskRel.EndsWith('.json')) { $null=$taskText | ConvertFrom-Json }
}
$taskData=Get-Content -LiteralPath (Join-Path $taskRoot 'docs/results.json') -Raw | ConvertFrom-Json
$taskExpectedKeys=@('schema_version','verified_at_utc','platform','setup','validation','performance','observations','limitations')
if(@(Compare-Object $taskExpectedKeys @($taskData.PSObject.Properties.Name)).Count -or $taskData.schema_version -ne 1) { throw 'Aggregate result schema is unexpected.' }
$taskWorkflow=Get-Content -LiteralPath (Join-Path $taskRoot '.github/workflows/manual-validation.yml') -Raw
if($taskWorkflow -notmatch '(?m)^  workflow_dispatch:\s*$' -or $taskWorkflow -match '(?m)^\s+(?:push|pull_request|pull_request_target|schedule|workflow_run|repository_dispatch):') { throw 'Actions must remain manual-only.' }
$taskPython=Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if($taskPython) { & $taskPython.Source -c 'import ast,pathlib,sys; ast.parse(pathlib.Path(sys.argv[1]).read_bytes())' (Join-Path $taskRoot 'scripts/Benchmark-Tensor.py'); if($LASTEXITCODE -ne 0) { throw 'Python source failed syntax validation.' } }
Write-Output ('Validated '+@($taskAllowed).Count+' public files; private workspace excluded; Actions manual-only.')
