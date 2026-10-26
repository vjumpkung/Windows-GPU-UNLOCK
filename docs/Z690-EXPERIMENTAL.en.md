# Experimental local Z690 / RTX 3060 USB build

This local port has **one logged clean unlock transaction** with a measured
Tensor GEMM change; see [First physical result](#first-physical-result-october-26-2026).
It remains experimental. It is separate from the five hardware-reported profiles
and does not widen `proven.json` or the generic local-profile generator.

Exact machine: Gigabyte Z690 UD DDR4 BIOS F27, i5-12400F (no iGPU), RTX 3060
GA106 12 GiB, PCI `10de:2504`, subsystem `10de:1536`, BDF `0000:01:00.0`.
Three archived read-only captures agree on the complete PCI configuration,
cold state, one physical GOP/one NVIDIA display child, PROM hash and bound
AMI/NVIDIA driver fingerprints. Windows resources confirm BAR0
`0x53000000`–`0x53ffffff` (16 MiB). Captures and firmware remain private in
`research/profile/local/z690ud-3060/`.

The profile reuses the existing GA10x transaction and non-aggregate headless
release path. It pins this machine's identity/PROM and requires exactly one
display child. Other cards, monitor topologies and BIOS versions are not covered.
Only headless USB write builds are provided. Boot package creation and staging
require all 19 host validation groups to pass against matching source and fixtures:

```powershell
.\research\headless\test-z690.ps1 -Assets .\assets `
  -Clang C:\TOOLS\LLVM20\bin\clang.exe
.\research\headless\build-usb.ps1 `
  -WindowsEspGuid (Get-Partition | Where-Object IsSystem | Select-Object -ExpandProperty Guid) `
  -HardwareProfile z690ud-3060 `
  -Clang C:\TOOLS\LLVM20\bin\clang.exe `
  -LldLink C:\TOOLS\LLVM20\bin\lld-link.exe
.\research\headless\stage-usb.ps1 -Drive E -Assets .\assets
```

These paths/GUID/USB letter are specific to this Windows installation. The
validation mocks every hardware effect; it cannot establish actual firmware
disconnect behavior, Windows display recovery or performance.

For a supervised first trial, save work, fully shut down, power on, press F12
and select **UEFI: KingstonDataTraveler 2.0, Partition 1**. Do not use Restart
for the controlled cold trial. Leave the monitor arrangement as captured.
During the first five seconds, Esc skips unlock and starts Windows. Otherwise
the display goes black during driver release. Do not press T, U or Enter.
Esc during the child's later three-second interval stops after release.
Success should start Windows directly without reset and restore display.

If Windows does not return, fully power off, then use F12 → **Windows Boot
Manager**. Do not retry unlock in the same power session. Keep Windows Boot
Manager first in firmware priority until a supervised success is confirmed.

After boot, preserve `E:\RTX3090-UNLOCK\HLS*.TXT` and
`E:\RTX3090-UNLOCK\AUTO*\REPORT.TXT`. A black screen or successful build is
not proof of unlock. Review cleanup/handoff logs and compare a controlled
benchmark before enabling any default boot path.

## First physical result (October 26, 2026)

- One automatic internal unlock ran from the USB. `AUTO000000\REPORT.TXT` passed
  every gate and cold-state check and ends with
  `FINAL status=0 stage=transaction attempted=1 driver_release=0 clean=1`.
  It records selectors `SS0=88888888 SS1=00000008` before FLR and `FLR=1`.
- Windows booted at 21:41:23 (UTC+07:00), three seconds after the log was
  written at 21:41:20. No unexpected-shutdown event was logged. After boot,
  the RTX 3060 drives the monitor at 1920×1080. Whether the trial started
  from a full shutdown or from Restart was not recorded.
- Four-mode cuBLAS GEMM medians, with the same executable and driver 610.88:

| Mode | Before, TFLOPS | After unlock, TFLOPS |
|---|---:|---:|
| FP32 control | 8.10 | 7.47 |
| FP16 Tensor / FP32 accumulation | 25.81 | 42.41 |
| BF16 Tensor / FP32 accumulation | 25.99 | 49.38 |
| TF32 Tensor / FP32 accumulation | 13.16 | 22.99 |

Full measurements, conditions and hashes are in [BENCHMARK.en.md](../BENCHMARK.en.md).
This is one transaction and one before/after pair. The before run's boot path was
not recorded. The 7.8% drop in the FP32 control is unexplained. Repeated cold
boots and stability remain untested. The logs stay on the USB and are not
committed.
