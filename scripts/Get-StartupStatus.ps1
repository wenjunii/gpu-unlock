# Read-only diagnostic. Missing/unavailable information is null, not an Off result.
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT') { throw 'This startup diagnostic requires Windows.' }
$taskPrincipal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$taskAdmin=$taskPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$taskNotes=New-Object 'System.Collections.Generic.List[string]'
$taskSB=$null; $taskSBVerified=$false; $taskBL=$null; $taskEncrypted=$null; $taskIntegrity=$null; $taskFastStartup=$null; $taskGPU=@()
if($taskAdmin) {
    try { $taskSB=Confirm-SecureBootUEFI; $taskSBVerified=$true } catch { $taskNotes.Add('UEFI Secure Boot query unavailable.') }
    try { $taskVolume=Get-BitLockerVolume -MountPoint $env:SystemDrive; $taskBL=$taskVolume.ProtectionStatus.ToString(); $taskEncrypted=$taskVolume.EncryptionPercentage } catch { $taskNotes.Add('BitLocker query unavailable.') }
} else {
    try { $taskValue=(Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -Name UEFISecureBootEnabled).UEFISecureBootEnabled; if($null -ne $taskValue){$taskSB=([int]$taskValue -eq 1)} } catch { $taskNotes.Add('Secure Boot registry status unavailable.') }
    $taskNotes.Add('Use an Administrator shell for verified UEFI and BitLocker queries.')
}
try { $taskDG=Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard; if($taskDG){$taskIntegrity=(@($taskDG.SecurityServicesRunning) -contains 2)} } catch { $taskNotes.Add('Memory Integrity status unavailable.') }
try { $taskValue=(Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled).HiberbootEnabled; if($null -ne $taskValue){$taskFastStartup=([int]$taskValue -eq 1)} } catch { $taskNotes.Add('Fast Startup status unavailable.') }
try {
    $taskSmi=Get-Command nvidia-smi -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $taskRows=@(& $taskSmi.Source --query-gpu=name,driver_version,display_active --format=csv,noheader)
    if($LASTEXITCODE -ne 0) { throw 'GPU query failed.' }; $taskGPU=$taskRows
} catch { $taskNotes.Add('NVIDIA GPU status unavailable.') }
[ordered]@{administrator=$taskAdmin;secure_boot=$taskSB;secure_boot_uefi_command_verified=$taskSBVerified;bitlocker_protection=$taskBL;encryption_percent=$taskEncrypted;memory_integrity=$taskIntegrity;fast_startup_enabled=$taskFastStartup;gpu=$taskGPU;notes=@($taskNotes.ToArray());note='Status flags do not establish the unlock; use throughput and firmware evidence.'} | ConvertTo-Json -Depth 4
