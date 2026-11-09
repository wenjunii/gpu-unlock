# Exact-file cleanup for verified disposable scratch; never age-based or recursive.
$ErrorActionPreference='Stop'
$taskRoot=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$taskManifest=Join-Path $taskRoot '.local/cleanup-candidates.json'
if(-not (Test-Path -LiteralPath $taskManifest)) { Write-Output 'No registered scratch cleanup.'; return }
$taskEntries=Get-Content -LiteralPath $taskManifest -Raw | ConvertFrom-Json
$taskScratch=[IO.Path]::GetFullPath((Join-Path $taskRoot '.local/tmp'))+[IO.Path]::DirectorySeparatorChar
$taskTargets=@(foreach($taskEntry in $taskEntries) {
    if(-not $taskEntry.VerifiedComplete -or -not $taskEntry.DependenciesChecked -or -not $taskEntry.Reason -or $taskEntry.SHA256 -notmatch '^[a-fA-F0-9]{64}$' -or [IO.Path]::IsPathRooted($taskEntry.RelativePath)) { throw 'Incomplete scratch-cleanup authorization record.' }
    $taskPath=[IO.Path]::GetFullPath((Join-Path $taskRoot $taskEntry.RelativePath))
    if(-not $taskPath.StartsWith($taskScratch,[StringComparison]::OrdinalIgnoreCase)) { throw 'Cleanup target is outside .local/tmp.' }
    $taskParent=Split-Path $taskPath -Parent
    while($taskParent.Length -gt $taskRoot.Length) {
        if((Test-Path -LiteralPath $taskParent) -and ((Get-Item -LiteralPath $taskParent -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Cleanup path traverses a link.' }
        $taskParent=Split-Path $taskParent -Parent
    }
    if(-not (Test-Path -LiteralPath $taskPath)) { continue }
    $taskItem=Get-Item -LiteralPath $taskPath -Force
    if($taskItem.PSIsContainer -or ($taskItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-FileHash -LiteralPath $taskPath).Hash -ine $taskEntry.SHA256) { throw 'Cleanup file type or hash mismatch.' }
    [pscustomobject]@{Path=$taskPath;Bytes=$taskItem.Length;SHA256=$taskEntry.SHA256;Reason=$taskEntry.Reason}
})
if($taskTargets.Count -and $env:OS -ne 'Windows_NT') { throw 'This cleanup requires the Windows Recycle Bin.' }
if($taskTargets.Count) { Add-Type -AssemblyName Microsoft.VisualBasic }
foreach($taskTarget in $taskTargets) {
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($taskTarget.Path,[Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,[Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
    [ordered]@{Utc=[DateTime]::UtcNow.ToString('o');Path=$taskTarget.Path;Bytes=$taskTarget.Bytes;SHA256=$taskTarget.SHA256;Reason=$taskTarget.Reason;Recoverable=$true} | ConvertTo-Json -Compress | Add-Content -LiteralPath (Join-Path $taskRoot '.local/cleanup-history.jsonl') -Encoding UTF8
}
[IO.File]::WriteAllText($taskManifest,"[]`n",(New-Object Text.UTF8Encoding($false)))
Write-Output ('Recycled '+$taskTargets.Count+' verified scratch file(s).')
