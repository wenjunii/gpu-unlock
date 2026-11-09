# GPU unlock on an MSI Vector GP76

Results and maintenance tools for a tested **RTX 3080 Ti Laptop GPU with 16 GB VRAM**. The configured laptop unlocks automatically from its internal EFI system partition, then starts Windows with **Secure Boot, BitLocker protection, and Memory Integrity enabled**. Daily startup does not require the test USB.

This is a record of one experimental setup, with diagnostic and benchmark source. It is not a general-purpose installer. Machine-specific administrative helpers and recovery material stay local; this public repository does not flash a BIOS, modify drivers, or install an unlocker.

## Tested configuration

| Item | Tested value |
| --- | --- |
| Laptop | MSI Vector GP76 12UHSO |
| GPU | NVIDIA RTX 3080 Ti Laptop, 16 GB, PCI device `10de:2420` |
| NVIDIA driver | 621.14 |
| Unlocker | `nv-uefi-unlocker` v2.1.11 |
| MSI Center GPU Switch | **Discrete Graphics Mode** |
| Windows Fast Startup | **Disabled** |
| Secure Boot / BitLocker / Memory Integrity | **On** |
| Normal boot | Internal `NV Unlock GP76` entry, five-second automatic countdown |
| Verification date | November 8, 2026, America/New_York |

Leave MSI Center in Discrete Graphics Mode for the tested configuration. GPU power-off, sleep or hibernation can clear the volatile unlock; restarting through the unlocker applies it again. Sleep/resume and long-duration stability have not been validated.

## Measured results

Matched PyTorch matrix multiplication on the same laptop and driver:

| Compute mode | Stock TFLOPS | Final protected boot TFLOPS | Change |
| --- | ---: | ---: | ---: |
| FP16, FP32 accumulation | 45.11 | 70.90 | **+57.2%** |
| BF16, FP32 accumulation | 46.39 | 80.23 | **+72.9%** |
| Strict FP32 control | 14.14 | 14.28 | +1.0% |

The final check was a normal USB-free restart with BitLocker already protecting the drive. No suspension or boot-order change was requested for that check, and Windows started without a recovery-key prompt. Fresh firmware logs showed automatic execution and successful handoff; numerical checks passed. No GPU/WHEA warnings/errors or thermal-slowdown samples were observed during the final benchmark.

These are GEMM throughput measurements, not a promised application speedup. See [results and methodology](docs/RESULTS.md) and the [sanitized result data](docs/results.json).

## Boot chain and security

```text
UEFI with Secure Boot on
  -> Microsoft-signed Ubuntu shim on the internal EFI partition
  -> locally MOK-signed v2.1.11 unlocker with an SBAT section
  -> original Windows Boot Manager
  -> Windows / BitLocker
```

The initial setup required physical MOK certificate enrollment and limited BitLocker suspensions for setup reboots. Protection was restored and a further fully protected restart was tested. The local private signing key was deleted after signing. The firmware Secure Boot `db` still matched its pre-setup hash, and shim signature enforcement remained active.

Adding a MOK extends the trusted boot chain. Windows automatically selected TPM PCRs **0, 2, 4, 11**, instead of the original **7, 11**, for this chain; no BitLocker PCR policy was manually changed. Boot/firmware updates or switching boot paths can trigger recovery. Keep the recovery key accessible outside the PC, and never publish it. [Microsoft explains these TPM validation profiles](https://learn.microsoft.com/en-us/troubleshoot/windows-server/setup-upgrade-and-drivers/pcr7-configuration-binding-not-possible).

On this GP76, changing boot order from Windows did not persist: firmware restored Windows Boot Manager first. Selecting **NV Unlock GP76** first directly in BIOS **Boot / UEFI Hard Disk Drive BBS Priorities** fixed it, and a later normal restart retained that priority. [MSI boot-order guide](https://us.msi.com/support/technical_details/NB_BIOS_Boot_Order).

The loader still reports a **scrubber timeout** and proceeds. Its remaining transaction and handoff completed, and the measured checks passed. That warning and the limited test duration remain part of this experimental result.

## Included tools

```powershell
# Read status; an Administrator shell supplies the complete BitLocker/Secure Boot status.
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Get-StartupStatus.ps1

# Use an existing CUDA-enabled PyTorch environment; this runs a GPU workload.
New-Item -ItemType Directory -Force .\.local\results | Out-Null
python .\scripts\Benchmark-Tensor.py --label current --output .\.local\results\benchmark.json

# Validate the public source without running a GPU benchmark or an Actions workflow.
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Validate-PublicProject.ps1
```

The benchmark retains the tested GPU identity guard. Status flags alone do not prove the tensor unlock; compare throughput and firmware evidence.

## Recovery and local material

Use **F11 -> Windows Boot Manager** for stock startup if the custom entry fails; a recovery-key prompt is possible after a boot-path change. [Recovery notes](docs/RECOVERY.md) explain the local rollback procedure.

The ignored `test-v2.1.11/` directory contains the operational helpers, verified EFI/BCD backup, original USB-data backup, signed/unsigned boot kits, raw logs, and detailed private records. The public repository excludes these files, all signing certificates/keys, firmware binaries, machine identifiers and personal USB contents. A public clone alone cannot recreate the installed boot chain.

## Cleanup and regular sync

Completed disposable task artifacts are cleaned automatically after verification, preferably to the Recycle Bin. Active tools, source, reference inputs, user outputs, shared models and recovery backups are preserved. New scratch cleanup is limited to exact verified files in `.local/tmp/`; see [maintenance](docs/MAINTENANCE.md) and [AGENTS.md](AGENTS.md).

Regular sync runs locally once daily, with a single remote fetch and a commit/push only when needed. Only files in `public-files.json` can be synced. The one GitHub Actions workflow is **manual-only**: pushes, pull requests and schedules do not start it. Local scheduled work requires this PC and the desktop app to be running. [OpenAI scheduled-task guidance](https://developers.openai.com/training/walkthroughs/scheduled-tasks).

## Upstream projects and licensing

- [physicsdolphin/nv-uefi-unlocker](https://github.com/physicsdolphin/nv-uefi-unlocker): the actual v2.1.11 implementation used in the tests.
- [J0s3f/nv-unlock-secureboot-esp](https://github.com/J0s3f/nv-unlock-secureboot-esp): shim/MOK and internal-ESP reference procedure.
- [JustAResearcher/gpu-unlock-ada](https://github.com/JustAResearcher/gpu-unlock-ada): the research project that prompted the investigation.

Original documentation and scripts here use the MIT license. Third-party firmware and executables are not redistributed; upstream licenses still apply.
