# Read-only diagnostic. Does not prove the tensor unlock or change security settings.
$ErrorActionPreference='Stop'
$taskPrincipal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$taskAdmin=$taskPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$taskSB=$null; $taskBL='Administrator shell required'; $taskEncrypted=$null; $taskIntegrity=$null
if($taskAdmin) {
    $taskSB=Confirm-SecureBootUEFI
    $taskVolume=Get-BitLockerVolume -MountPoint $env:SystemDrive
    $taskBL=$taskVolume.ProtectionStatus.ToString(); $taskEncrypted=$taskVolume.EncryptionPercentage
} else {
    $taskSB=([int](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State').UEFISecureBootEnabled -eq 1)
}
try { $taskDG=Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard; $taskIntegrity=(@($taskDG.SecurityServicesRunning) -contains 2) } catch { $taskIntegrity=$null }
$taskGPU=@(& nvidia-smi --query-gpu=name,driver_version,display_active --format=csv,noheader)
if($LASTEXITCODE -ne 0) { throw 'nvidia-smi failed.' }
[ordered]@{administrator=$taskAdmin;secure_boot=$taskSB;secure_boot_uefi_command_verified=$taskAdmin;bitlocker_protection=$taskBL;encryption_percent=$taskEncrypted;memory_integrity=$taskIntegrity;fast_startup_enabled=([int](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power').HiberbootEnabled -eq 1);gpu=$taskGPU;note='Status flags do not establish the unlock; use throughput and firmware evidence.'} | ConvertTo-Json -Depth 4
