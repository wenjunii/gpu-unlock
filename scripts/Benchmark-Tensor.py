"""Matched stock/unlocked GEMM benchmark; uses the existing PyTorch environment."""

import argparse
import hashlib
import json
import statistics
import subprocess
from datetime import datetime, timezone
from pathlib import Path

import torch


def telemetry():
    result = subprocess.run(
        ["nvidia-smi", "--query-gpu=name,pci.bus_id,driver_version,pstate,"
         "temperature.gpu,power.draw,clocks.sm,memory.used", "--format=csv,noheader"],
        capture_output=True, text=True, check=True,
    )
    return result.stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", choices=["stock", "unlocked", "current"], required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Output already exists; choose a new filename.")
    if not torch.cuda.is_available():
        raise RuntimeError("The existing PyTorch installation cannot use CUDA.")
    if torch.cuda.device_count() != 1:
        raise RuntimeError("Expected exactly one CUDA GPU; select the intended GPU first.")
    if "3080 Ti Laptop" not in torch.cuda.get_device_name(0):
        raise RuntimeError("Unexpected GPU; refusing to benchmark another device.")

    torch.backends.cuda.matmul.allow_tf32 = False
    torch.backends.cuda.matmul.allow_fp16_reduced_precision_reduction = False
    torch.backends.cuda.matmul.allow_bf16_reduced_precision_reduction = False
    n, warmups, samples, rounds = 8192, 10, 60, 3
    report = {
        "label": args.label,
        "utc": datetime.now(timezone.utc).isoformat(),
        "torch": torch.__version__,
        "cuda": torch.version.cuda,
        "gpu": torch.cuda.get_device_name(0),
        "shape": [n, n, n],
        "warmups": warmups,
        "samples_per_round": samples,
        "rounds": rounds,
        "seed": 1234,
        "tf32": False,
        "reduced_precision_reductions": False,
        "telemetry_before": telemetry(),
        "modes": {},
        "validation_scope": "CPU FP64 reference on a separate 128x128 GEMM; "
                            "finite check and sample hash for the large GEMM.",
    }

    for label, dtype, tolerance in [
        ("fp16", torch.float16, 0.005),
        ("bf16", torch.bfloat16, 0.04),
        ("fp32_control", torch.float32, 0.0001),
    ]:
        torch.manual_seed(1234)
        small_a = torch.randn(128, 128, device="cuda", dtype=dtype)
        small_b = torch.randn_like(small_a)
        observed = (small_a @ small_b).cpu().double()
        reference = small_a.cpu().double() @ small_b.cpu().double()
        torch.testing.assert_close(observed, reference, rtol=tolerance, atol=tolerance)
        max_abs_error = (observed - reference).abs().max().item()
        del small_a, small_b, observed, reference

        torch.manual_seed(1234)
        a = torch.randn(n, n, device="cuda", dtype=dtype)
        b = torch.randn_like(a)
        c = torch.empty_like(a)
        round_results = []
        for round_index in range(rounds):
            for _ in range(warmups):
                torch.mm(a, b, out=c)
            torch.cuda.synchronize()
            milliseconds = []
            start = torch.cuda.Event(enable_timing=True)
            end = torch.cuda.Event(enable_timing=True)
            for _ in range(samples):
                start.record()
                torch.mm(a, b, out=c)
                end.record()
                end.synchronize()
                milliseconds.append(start.elapsed_time(end))
            median_ms = statistics.median(milliseconds)
            tflops = 2 * n ** 3 / (median_ms / 1000) / 1e12
            round_results.append({"median_ms": median_ms, "tflops": tflops})
            print(f"{label} round {round_index + 1}: {tflops:.2f} TFLOPS", flush=True)

        if not torch.isfinite(c).all().item():
            raise RuntimeError(f"{label}: non-finite large-GEMM output")
        sample_bytes = c[:64, :64].float().cpu().contiguous().numpy().tobytes()
        report["modes"][label] = {
            "rounds": round_results,
            "median_tflops": statistics.median(r["tflops"] for r in round_results),
            "small_gemm_max_abs_error": max_abs_error,
            "small_gemm_check_passed": True,
            "large_gemm_finite": True,
            "output_sample_sha256": hashlib.sha256(sample_bytes).hexdigest(),
        }
        del a, b, c
        torch.cuda.empty_cache()

    report["telemetry_after"] = telemetry()
    with args.output.open("x", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)
    print(f"Saved {args.output}", flush=True)


if __name__ == "__main__":
    main()
