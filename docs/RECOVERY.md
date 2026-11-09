# Recovery for the tested laptop

## Stock startup

Press **F11** at power-on and choose **Windows Boot Manager**. A different measured boot path may request the BitLocker recovery key. Use the existing key privately; do not paste it into chat, issues, files in this repository, or logs.

To keep stock startup, enter BIOS with **Delete**, put Windows Boot Manager first under **Boot / UEFI Hard Disk Drive BBS Priorities** (wording varies), and save. Secure Boot can remain enabled.

## Local rollback

The local, ignored `test-v2.1.11/STARTUP-UNLOCK-RECOVERY.txt` contains the exact recovery and Administrator-shell rollback command for this PC. Its ownership record is kept locally under ProgramData, alongside a verified backup of the original EFI files and an exported BCD store in the private workspace.

The guarded local rollback helper removes only its owned boot entry and hash-matching task files, preserves the current recognized loader log, and restores the earlier Fast Startup setting if still at the value it set. It uses a one-reboot BitLocker suspension for the return to the stock path. Restart afterward and verify protection is On.

The public repository intentionally omits that machine-specific installer, ownership data, backup, and certificate. Do not substitute another machine's identifiers or signing materials.

## MOK trust

File/entry rollback leaves the public MOK enrollment in place. Removing that enrollment is a separate, certificate-specific procedure with physical confirmation. Avoid resetting firmware PK/KEK/db or deleting unrelated certificates. The private signing key used for this installation was deleted after signing.

## If performance returns to stock

Check MSI Center is still in Discrete Graphics Mode, Fast Startup is disabled, and the BIOS still selects NV Unlock GP76 first. Sleep, hibernation or GPU power-off can clear the volatile state; restart through the configured entry. Revalidate after driver or boot/firmware updates rather than assuming the earlier result still applies.
