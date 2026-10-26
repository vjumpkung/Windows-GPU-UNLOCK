# RTX 3060 benchmark — Z690 UD, October 26, 2026

These are two measurements on the local Gigabyte Z690 UD / RTX 3060 machine, one
before and one after the boot that ran the experimental Z690 unlock. Both use the
same four-mode cuBLAS GEMM executable. See [the benchmark guide](docs/BENCHMARK.en.md)
for setup, protocol and comparison rules.

## Results

4096×4096 GEMM, two-second warmup and 30 samples per mode, three processes per
run. Each trial value is that process's sample median; each run's summary is the
median of its three trials. Change is the after/before ratio of the medians, from
`compare_results.py`.

| Mode | Before, median TFLOPS | After unlock, median TFLOPS | Change |
|---|---:|---:|---:|
| FP32 (`fp32_pedantic`) | 8.100556 | 7.470502 | ×0.92 (−7.8%) |
| FP16 Tensor / FP32 accumulation | 25.806140 | 42.411681 | ×1.64 (+64.3%) |
| BF16 Tensor / FP32 accumulation | 25.990331 | 49.383047 | ×1.90 (+90.0%) |
| TF32 Tensor / FP32 accumulation | 13.157028 | 22.991099 | ×1.75 (+74.7%) |

Each trial, in TFLOPS:

| Mode | Before 1 | Before 2 | Before 3 | After unlock 1 | After unlock 2 | After unlock 3 |
|---|---:|---:|---:|---:|---:|---:|
| FP32 | 8.100556 | 7.842140 | 8.160124 | 7.415600 | 7.470502 | 8.157297 |
| FP16 Tensor / FP32 acc. | 25.806140 | 22.983042 | 26.069603 | 42.411681 | 42.266020 | 47.840663 |
| BF16 Tensor / FP32 acc. | 25.717982 | 25.990331 | 25.997176 | 42.486989 | 49.392423 | 49.383047 |
| TF32 Tensor / FP32 acc. | 9.810520 | 13.157028 | 13.166265 | 22.733716 | 25.397025 | 22.991099 |

Trials vary within each run. The cause was not established. This GPU also drives
the display, so desktop activity during a trial cannot be ruled out. The lowest
after-unlock Tensor trial is still above the highest before-unlock Tensor trial in
every mode. All 24 mode results passed the benchmark's first/last-element
reference check.

## Unlock boot

- Before run: October 26, 21:37:46–21:38:15 (UTC+07:00). The boot path was not
  recorded.
- Unlock: the Z690 USB's automatic internal unlock wrote its log at 21:41:20.
  The log ends with `FINAL status=0 stage=transaction attempted=1 driver_release=0 clean=1`.
  It records selectors `SS0=88888888 SS1=00000008` before FLR and `FLR=1`.
  Windows booted at 21:41:23.
- The USB holds only this one log set, `RTX3090-UNLOCK\AUTO000000\REPORT.TXT` and
  `RTX3090-UNLOCK\HLS000000.TXT`, so no earlier unlock attempt is logged on it. The
  logs remain on the USB and are not copied into this repository.
- After-unlock run: 21:43:35–21:44:03 (UTC+07:00), about two minutes after Windows
  started, with no reboot in between.

## Machine and software

Both runs used the same machine, executable and GPU settings. Their
`comparison-context.json` files have the same SHA-256.

| Item | Value |
|---|---|
| Board / BIOS | Gigabyte Z690 UD DDR4, BIOS F27 |
| CPU | Intel Core i5-12400F (no iGPU) |
| GPU | NVIDIA GeForce RTX 3060, GA106, 12288 MiB, PCI `10de:2504`, subsystem `10de:1536`, `0000:01:00.0` |
| VBIOS | 94.06.2f.00.6d |
| OS | Windows 11 Education 10.0.26300 |
| Driver | 610.88 (CUDA driver API `13030`); not replaced between runs |
| Power limit / max clocks | 170 W (default 170 W) / SM 2100 MHz, memory 7501 MHz; unchanged after every trial of both runs |
| CUDA | 12.6 redistributables: nvcc 12.6.20, cudart 12.6.37, CCCL 12.6.37, cuBLAS 12.6.0.22 (runtime `12060`, cuBLAS `120600`) |
| Host compiler | MSVC 14.38.33130 (VS 2022 BuildTools), Windows SDK 10.0.22621.0 |
| Benchmark | `benchmark/compute-benchmark-3060.cu`, protocol 2, `tf32_allowed=true`, `NVIDIA_TF32_OVERRIDE` unset |

The [guide](docs/BENCHMARK.en.md) records VS2019 MSVC 14.29 for its measured
build. VS2019 BuildTools is not installed on this machine. CUDA 12.6 accepts MSVC
14.38 without `-AllowUnsupportedCompiler`. A different compiler produces
different executable hashes, so `compare_results.py` will compare these runs only
with runs of the same executable.

## Measurement conditions

| Run | Start utilization | Start VRAM | Start temperature |
|---|---:|---:|---:|
| Before | 0% | 824 MiB | 40°C |
| After unlock | 0% | 714 MiB | 41°C |

Windows desktop processes stayed resident on the GPU. Before the first run they
included a remote-desktop host and NVIDIA Broadcast; the list was not captured
for the second run. Nothing was stopped. All six trials exited with code 0 and
empty stderr.

Snapshots taken after each trial; they are not a thermal trace over the run:

| Run, trial | SM clock | Power draw | Temperature | Software thermal slowdown |
|---|---:|---:|---:|---|
| Before 1 | 1920 MHz | 98.38 W | 50°C | Not active |
| Before 2 | 1942 MHz | 97.33 W | 53°C | Not active |
| Before 3 | 1942 MHz | 103.41 W | 55°C | Not active |
| After unlock 1 | 1942 MHz | 132.86 W | 56°C | Not active |
| After unlock 2 | 1920 MHz | 141.45 W | 59°C | Not active |
| After unlock 3 | 1935 MHz | 135.30 W | 61°C | Not active |

## Provenance

Raw results:

- Before: `benchmark/results/20261026-213746-374/`
- After unlock: `benchmark/results/20261026-214335-667/`

Both directories are gitignored and stay only on this machine.
`python benchmark/compare_results.py <before> <after> --same-machine-confirmed`
accepts the pair and exits 0. The same-machine confirmation rests on the
identical board/BIOS, VBIOS, PCI identity, driver, power limit and clock limits
recorded above.

| Artifact (both runs) | Bytes | SHA-256 |
|---|---:|---|
| `compute-benchmark-3060.cu` | 5976 | `a99d8084f1ff44f8b5b3c80cff8021c3f87db526fc03e5ba498cf8cae5c7b10a` |
| `upstream-compute-benchmark.cu` | 4438 | `57b04fa8599ce298d58237246b4353e72000ce65d3d75bd406e97d1d26ec0fd2` |
| `bin/compute-benchmark-3060.exe` | 361984 | `609263ff3b48cd20be601616be4c6eb9737852f82eb1d3de60c27cba077fffbe` |
| `bin/compute-benchmark-3060.exp` | 792 | `9f3d1cd5a4fd46d9a7721731976d6d7fa2136f65e8e01e19f97d53c7e8baa07e` |
| `bin/compute-benchmark-3060.lib` | 1992 | `3de7302c383cea50beb73893f022a6632647da0f32e6fcd34915225789dacc74` |
| `bin/cublas64_12.dll` | 100796416 | `e26c6a52b7df762633978b282d6f172d0085719b116ff1a8ca4c96ff5786e142` |
| `bin/cublasLt64_12.dll` | 494290944 | `0fa3aabf2e90f0ba3d331699b95305ee29fe1cda0f4d4b64c883e04f01a35b49` |
| `bin/nvblas64_12.dll` | 331776 | `305807fb9ad83e7a900b6bfbd07adb587c678cf28bd6a8f2ce0ff64338ed7b01` |

| Result file | Before SHA-256 | After unlock SHA-256 |
|---|---|---|
| `comparison-context.json` | `8ad5cf2d13f8f0522d7d746dd7c6a8ada651b784154f4f0611363da422d50900` | `8ad5cf2d13f8f0522d7d746dd7c6a8ada651b784154f4f0611363da422d50900` |
| `trial-1.json` | `9c76529c17ecfe459cb7177ec8e489614687b82a75d6be7227c1da71646b1e22` | `3a88c5622e6ad799aa86e951159c325c38ce6061f30575b0523bb8c1562c56de` |
| `trial-2.json` | `634e1d59c9e717961eb6f8fda7e6fe026c4bb7e74f15c147d8046c6054d7ac77` | `b295a110f2d79a821cd5ee3233f408ae48d5c1c4716982f372df868f41819d33` |
| `trial-3.json` | `ffb01692041ce00503793378b1459f605409414ce35c3230a3820ee4a2356e46` | `48e05e806028a2040e3a32a3b5898ad89c1fc4ac0cfee70c3fa547c4247f0ba8` |

These hashes detect accidental edits; they are not signed hardware evidence.

## Interpretation and limits

- Tensor medians rose 1.64–1.90× after the unlock boot, with the same driver and
  executable. The FP32 control fell 7.8%, from 8.10 to 7.47 TFLOPS. That drop is
  not explained: two of the three after-unlock FP32 trials were lower, while the
  third matched the before run.
- This is one before/after pair. There is no repeated locked cold boot, no
  control boot without the unlock, and no instrumentation across the full POST
  path. The benchmark and `compare_results.py` cannot prove unlock or causality.
- The before run's boot path was not recorded. Only the absence of an earlier log
  on the USB supports it being a boot without the unlock.
- Numbers in `evidence/` come from other machines or protocols and are not
  comparable with these runs.
- Numerical checks cover only the first and last output elements, as upstream.
- GEMM throughput does not predict speed in games, video work or ComfyUI
  workflows. Stability after the unlock was not tested.
