# Results and validation limits

The report concerns one MSI Vector GP76 12UHSO with a 16 GB RTX 3080 Ti Laptop GPU and NVIDIA driver 621.14. The final configuration used Discrete Graphics, Secure Boot, BitLocker protection and Memory Integrity, with Windows Fast Startup disabled.

## Benchmark method

- Existing PyTorch 2.5.1+cu121 environment; no replacement NVIDIA driver or Python environment was installed for the test.
- `8192 x 8192` matrix multiplication, seed 1234, 10 warmup operations, 60 timed samples per round, three rounds per mode; median round throughput reported.
- TF32 disabled for the FP32 control; FP16/BF16 reduced-precision reductions disabled.
- Separate `128 x 128` operations checked against a CPU FP64 reference.
- Large outputs checked for finite values, and SHA256 of a `64 x 64` output sample matched stock for all three modes.
- AC power connected; desktop active and clocks not pinned. Stock and unlocked measurements necessarily came from different boots.

## Final protected-restart result

| Mode | Stock TFLOPS | Unlocked TFLOPS | Gain |
| --- | ---: | ---: | ---: |
| FP16 | 45.1067 | 70.8980 | 57.18% |
| BF16 | 46.3900 | 80.2269 | 72.94% |
| Strict FP32 control | 14.1449 | 14.2845 | 0.99% |

The final benchmark peaked at 77.94 C and 175.77 W, with zero reported thermal-slowdown samples and no new GPU/WHEA warnings/errors during that boot's check. These measurements describe the observed short run, not a durability guarantee.

The protected restart began with BitLocker protection On, used the internal default entry with no USB or one-time override, and returned to Windows without a recovery prompt. Secure Boot, shim signature enforcement, BitLocker protection and Memory Integrity were verified afterward. Firmware `db` matched its pre-setup hash. Windows selected PCR 0/2/4/11 automatically for the custom chain.

## Limits

The loader's scrubber timed out and the loader proceeded, as in the earlier stock-Secure-Boot-off unlock test. The remaining transaction completed, selectors survived the firmware reset/handoff, and all DMA was released according to the log.

This does not validate every element of the large output against the CPU, every application, sleep/resume, long-duration stability, future drivers, anti-cheat compatibility, or other laptops. Application gains depend on how much work uses the affected tensor paths. No Windows register-readback driver was loaded for these checks.

Machine identifiers, raw EFI/BCD data, certificates, user paths, USB contents and private recovery records have been excluded from the [aggregate JSON](results.json).
