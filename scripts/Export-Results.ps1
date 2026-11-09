param([string]$LocalReportPath=(Join-Path (Split-Path $PSScriptRoot -Parent) 'test-v2.1.11/startup-final-verification.json'))
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
if(-not (Test-Path -LiteralPath $LocalReportPath -PathType Leaf)) { Write-Output 'No private final report; retained the published aggregate.'; return }
$taskReport=Get-Content -LiteralPath $LocalReportPath -Raw | ConvertFrom-Json
if($taskReport.State -ne 'Complete') { throw 'Only a completed protected-startup report may be exported.' }
foreach($taskFlag in @($taskReport.AutomaticStartupVerified,$taskReport.ProtectedRestart.UserConfirmedNoRecoveryPrompt,$taskReport.Security.SecureBoot,$taskReport.Security.MemoryIntegrity,$taskReport.Security.ShimSignatureVerificationActive)) {
    if($taskFlag -isnot [bool] -or -not $taskFlag) { throw 'Protected-startup verification flags must be Boolean true.' }
}
if($taskReport.ProtectedRestart.Before -ne 'On' -or $taskReport.ProtectedRestart.After -ne 'On' -or $taskReport.Security.BitLockerProtection -ne 'On' -or $taskReport.Security.EncryptionPercentage -ne 100 -or $taskReport.ProtectedRestart.AgentRequestedSuspension -isnot [bool] -or $taskReport.ProtectedRestart.AgentRequestedSuspension) { throw 'A fully protected restart is required for the public result.' }
if(@($taskReport.Security.TPMPCRProfiles).Count -ne 1) { throw 'An unambiguous TPM profile is required.' }
$taskModes=@($taskReport.Performance | ForEach-Object {$_.Mode})
if($taskModes.Count -ne 3 -or @($taskModes | Select-Object -Unique).Count -ne 3 -or @(Compare-Object @('fp16','bf16','fp32_control') $taskModes).Count) { throw 'The three matched benchmark modes are required.' }
foreach($taskMode in $taskReport.Performance) {
    foreach($taskNumber in @($taskMode.StockTFLOPS,$taskMode.SecureBootTFLOPS)) { if($null -eq $taskNumber -or [double]::IsNaN([double]$taskNumber) -or [double]::IsInfinity([double]$taskNumber) -or [double]$taskNumber -le 0) { throw 'Benchmark throughput must be finite and positive.' } }
    if($taskMode.SampleHashMatches -isnot [bool] -or -not $taskMode.SampleHashMatches) { throw 'Matched numerical checks are required.' }
}
# Explicit field selection: never serialize the raw report or nested evidence wholesale.
$taskPublic=[ordered]@{
    schema_version=1;verified_at_utc=([datetimeoffset]$taskReport.CompletedUtc).ToUniversalTime().ToString('o');
    platform=[ordered]@{laptop=$taskReport.Computer;gpu=$taskReport.GPU;driver=$taskReport.Driver;unlocker=$taskReport.UnlockerVersion};
    setup=[ordered]@{automatic_startup=[bool]$taskReport.AutomaticStartupVerified;usb_required=[bool]$taskReport.USBRequired;graphics_mode=$taskReport.GraphicsMode;fast_startup_enabled=[bool]$taskReport.WindowsFastStartupEnabled;secure_boot=[bool]$taskReport.Security.SecureBoot;bitlocker_protection=$taskReport.Security.BitLockerProtection;encryption_percent=$taskReport.Security.EncryptionPercentage;memory_integrity=[bool]$taskReport.Security.MemoryIntegrity;shim_verification=[bool]$taskReport.Security.ShimSignatureVerificationActive;tpm_pcrs=@($taskReport.Security.TPMPCRProfiles[0].PCRs);pcr_policy_manually_modified=[bool]$taskReport.Security.PCRPolicyManuallyModified};
    validation=[ordered]@{protected_restart_before=$taskReport.ProtectedRestart.Before;protected_restart_after=$taskReport.ProtectedRestart.After;recovery_prompt_observed=(-not $taskReport.ProtectedRestart.UserConfirmedNoRecoveryPrompt);suspension_requested=[bool]$taskReport.ProtectedRestart.AgentRequestedSuspension;numerical_checks=$taskReport.NumericalChecks};
    performance=@($taskReport.Performance | ForEach-Object {[ordered]@{mode=$_.Mode;stock_tflops=$_.StockTFLOPS;unlocked_tflops=$_.SecureBootTFLOPS;gain_percent=$_.GainPercent;sample_hash_matched=[bool]$_.SampleHashMatches}});
    observations=[ordered]@{peak_temperature_c=$taskReport.PeakTemperatureC;peak_power_w=$taskReport.PeakPowerW;thermal_slowdown_samples=$taskReport.ThermalSlowdownSamples;gpu_whea_warnings_errors=$taskReport.GPUOrWHEAWarningsErrors;known_warning=$taskReport.KnownWarning};
    limitations=@($taskReport.Limitations)
}
$taskDestination=Join-Path $taskRoot 'docs/results.json'
$taskComparable=$taskPublic | ConvertTo-Json -Depth 8 -Compress
if(Test-Path -LiteralPath $taskDestination) {
    $taskExisting=Get-Content -LiteralPath $taskDestination -Raw | ConvertFrom-Json
    # PS7 can decode date strings automatically; PS5 leaves them as strings.
    $taskExisting.verified_at_utc=([datetimeoffset]$taskExisting.verified_at_utc).ToUniversalTime().ToString('o')
    if(($taskExisting | ConvertTo-Json -Depth 8 -Compress) -ceq $taskComparable) { Write-Output 'Sanitized aggregate already current; no file rewrite.'; return }
}
$taskText=(($taskPublic | ConvertTo-Json -Depth 8) -replace "`r`n","`n")+"`n"
[IO.File]::WriteAllText($taskDestination,$taskText,(New-Object Text.UTF8Encoding($false)))
Write-Output 'Sanitized aggregate results updated.'
