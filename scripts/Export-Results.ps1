param([string]$LocalReportPath=(Join-Path (Split-Path $PSScriptRoot -Parent) 'test-v2.1.11/startup-final-verification.json'))
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
if(-not (Test-Path -LiteralPath $LocalReportPath -PathType Leaf)) { Write-Output 'No private final report; retained the published aggregate.'; return }
$taskReport=Get-Content -LiteralPath $LocalReportPath -Raw | ConvertFrom-Json
if($taskReport.State -ne 'Complete' -or -not $taskReport.AutomaticStartupVerified -or -not $taskReport.ProtectedRestart.UserConfirmedNoRecoveryPrompt) { throw 'Only a completed protected-startup report may be exported.' }
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
$taskText=($taskPublic | ConvertTo-Json -Depth 8)+"`n"
if(-not (Test-Path -LiteralPath $taskDestination) -or [IO.File]::ReadAllText($taskDestination) -cne $taskText) { [IO.File]::WriteAllText($taskDestination,$taskText,(New-Object Text.UTF8Encoding($false))) }
Write-Output 'Sanitized aggregate results exported.'
