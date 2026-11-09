param([string]$Revision)
$ErrorActionPreference='Stop'
$taskRoot=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$taskGitRoot=(& git -C $taskRoot rev-parse --show-toplevel) -join ''
if($LASTEXITCODE -ne 0 -or [IO.Path]::GetFullPath($taskGitRoot) -ine $taskRoot) { throw 'Refusing validation against another Git root.' }
function Invoke-ValidationGit([string[]]$GitArguments) {
    $taskResult=@(& git -C $taskRoot @GitArguments)
    if($LASTEXITCODE -ne 0) { throw 'Git object inspection failed.' }
    return $taskResult
}
$taskRevisionSHA=$null
if($Revision) {
    if($Revision -notmatch '^(?!-)[A-Za-z0-9_./-]+$') { throw 'Invalid revision name.' }
    $taskRevisionSHA=(Invoke-ValidationGit -GitArguments @('rev-parse','--verify',($Revision+'^{commit}'))) -join ''
    if($taskRevisionSHA -notmatch '^(?:[a-fA-F0-9]{40}|[a-fA-F0-9]{64})$') { throw 'Invalid commit object.' }
}
function Get-PublicText([string]$RelativePath) {
    if($RelativePath -notmatch '^[A-Za-z0-9_./-]+$' -or $RelativePath -match '(^|/)\.\.(/|$)' -or [IO.Path]::IsPathRooted($RelativePath)) { throw 'Invalid public relative path.' }
    if($taskRevisionSHA) {
        $taskObject=$taskRevisionSHA+':'+$RelativePath
        $taskSize=[int64]((Invoke-ValidationGit -GitArguments @('cat-file','-s',$taskObject)) -join '')
        if($taskSize -gt 262144) { throw ('Oversized public blob: '+$RelativePath) }
        $taskInfo=New-Object Diagnostics.ProcessStartInfo
        $taskInfo.FileName=(Get-Command git -CommandType Application | Select-Object -First 1).Source
        $taskInfo.Arguments='-C "'+$taskRoot+'" cat-file blob '+$taskObject
        $taskInfo.UseShellExecute=$false; $taskInfo.CreateNoWindow=$true
        $taskInfo.RedirectStandardOutput=$true; $taskInfo.RedirectStandardError=$true
        $taskProcess=New-Object Diagnostics.Process; $taskProcess.StartInfo=$taskInfo
        $taskBuffer=New-Object IO.MemoryStream
        try {
            $null=$taskProcess.Start(); $taskProcess.StandardOutput.BaseStream.CopyTo($taskBuffer)
            $null=$taskProcess.StandardError.ReadToEnd(); $taskProcess.WaitForExit()
            if($taskProcess.ExitCode -ne 0 -or $taskBuffer.Length -ne $taskSize) { throw 'Git blob read failed.' }
            return (New-Object Text.UTF8Encoding($false,$true)).GetString($taskBuffer.ToArray())
        } finally { $taskProcess.Dispose(); $taskBuffer.Dispose() }
    }
    $taskItem=Get-Item -LiteralPath (Join-Path $taskRoot $RelativePath) -Force
    if($taskItem.PSIsContainer -or $taskItem.Length -gt 262144 -or ($taskItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw ('Invalid public file: '+$RelativePath) }
    $taskParent=$taskItem.Directory
    while($taskParent.FullName.Length -gt $taskRoot.Length) { if($taskParent.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Public path traverses a link.' }; $taskParent=$taskParent.Parent }
    return (New-Object Text.UTF8Encoding($false,$true)).GetString([IO.File]::ReadAllBytes($taskItem.FullName))
}
$taskAllowed=Get-Content -LiteralPath (Join-Path $taskRoot 'public-files.json') -Raw | ConvertFrom-Json
if(@($taskAllowed).Count -ne @($taskAllowed | Select-Object -Unique).Count) { throw 'Publication allowlist has duplicate paths.' }
if($taskRevisionSHA) {
    $taskVisible=@(Invoke-ValidationGit -GitArguments @('ls-tree','-r','--name-only',$taskRevisionSHA))
    $taskIncomingAllowed=(Get-PublicText 'public-files.json') | ConvertFrom-Json
    if(($taskAllowed -join "`n") -cne ($taskIncomingAllowed -join "`n")) { throw 'Fetched publication allowlist requires manual review.' }
} else { $taskVisible=@(Invoke-ValidationGit -GitArguments @('ls-files','--cached','--others','--exclude-standard')) }
foreach($taskRel in $taskVisible) { if($taskAllowed -cnotcontains $taskRel) { throw ('Unlisted public Git candidate: '+$taskRel) } }
if(@(Compare-Object @($taskAllowed) @($taskVisible | Select-Object -Unique)).Count) { throw 'Public candidate tree is incomplete.' }
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
    $taskText=Get-PublicText $taskRel
    if($taskText.Contains([string][char]0)) { throw ('Binary content in public file: '+$taskRel) }
    foreach($taskPattern in $taskSecretPatterns) { if($taskText -match $taskPattern) { throw ('Possible private data in '+$taskRel+'; inspect locally without printing the match.') } }
    if($taskRel.EndsWith('.ps1')) { $taskTokens=$null; $taskErrors=$null; [Management.Automation.Language.Parser]::ParseInput($taskText,[ref]$taskTokens,[ref]$taskErrors) | Out-Null; if($taskErrors.Count) { throw ('PowerShell parse error: '+$taskRel) } }
    if($taskRel.EndsWith('.json')) { $null=$taskText | ConvertFrom-Json }
}
function Assert-ResultKeys($Value,[string[]]$Keys) {
    if($null -eq $Value -or @(Compare-Object $Keys @($Value.PSObject.Properties.Name)).Count) { throw 'Aggregate result schema is unexpected.' }
}
$taskData=(Get-PublicText 'docs/results.json') | ConvertFrom-Json
Assert-ResultKeys $taskData @('schema_version','verified_at_utc','platform','setup','validation','performance','observations','limitations')
Assert-ResultKeys $taskData.platform @('laptop','gpu','driver','unlocker')
Assert-ResultKeys $taskData.setup @('automatic_startup','usb_required','graphics_mode','fast_startup_enabled','secure_boot','bitlocker_protection','encryption_percent','memory_integrity','shim_verification','tpm_pcrs','pcr_policy_manually_modified')
Assert-ResultKeys $taskData.validation @('protected_restart_before','protected_restart_after','recovery_prompt_observed','suspension_requested','numerical_checks')
Assert-ResultKeys $taskData.observations @('peak_temperature_c','peak_power_w','thermal_slowdown_samples','gpu_whea_warnings_errors','known_warning')
if($taskData.schema_version -ne 1) { throw 'Unsupported aggregate result version.' }
foreach($taskMode in $taskData.performance) { Assert-ResultKeys $taskMode @('mode','stock_tflops','unlocked_tflops','gain_percent','sample_hash_matched') }
# Accept only the project's simple manual-trigger form, rather than a blacklist
# of selected automatic events that could miss a different event name.
$taskWorkflow=Get-PublicText '.github/workflows/manual-validation.yml'
$taskLines=$taskWorkflow -split '\r?\n'; $taskOn=@(); $taskRootKeys=@()
for($taskIndex=0;$taskIndex -lt $taskLines.Count;$taskIndex++) {
    $taskLine=$taskLines[$taskIndex]
    if($taskLine -match '^\S' -and $taskLine -notmatch '^#') {
        if($taskLine -notmatch '^(name|on|permissions|concurrency|jobs):(?:\s|$)') { throw 'Unsupported workflow structure; review triggers manually.' }
        $taskRootKeys+=$Matches[1]
        if($Matches[1] -ceq 'on') { if($taskLine.Trim() -cne 'on:'){throw 'Actions must remain manual-only.'}; $taskOn+=$taskIndex }
    }
}
if($taskOn.Count -ne 1 -or @($taskRootKeys | Select-Object -Unique).Count -ne $taskRootKeys.Count) { throw 'Duplicate or missing workflow keys.' }
$taskEvents=@(for($taskIndex=$taskOn[0]+1;$taskIndex -lt $taskLines.Count;$taskIndex++) { $taskLine=$taskLines[$taskIndex]; if($taskLine -match '^\S'){break}; if($taskLine.Trim() -and $taskLine.Trim() -notmatch '^#'){$taskLine.Trim()} })
if($taskEvents.Count -ne 1 -or $taskEvents[0] -cne 'workflow_dispatch:') { throw 'Actions must remain manual-only.' }
$taskPython=Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if($taskPython -and -not $taskRevisionSHA) { & $taskPython.Source -c 'import ast,pathlib,sys; ast.parse(pathlib.Path(sys.argv[1]).read_bytes())' (Join-Path $taskRoot 'scripts/Benchmark-Tensor.py'); if($LASTEXITCODE -ne 0) { throw 'Python source failed syntax validation.' } }
Write-Output ('Validated '+@($taskAllowed).Count+' public files'+$(if($taskRevisionSHA){' at '+$taskRevisionSHA}else{''})+'; private workspace excluded; Actions manual-only.')
