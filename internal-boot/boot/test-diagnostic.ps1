param([string]$Clang='clang',[string]$VcVars='C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Auxiliary/Build/vcvars64.bat')
$ErrorActionPreference='Stop'
Push-Location -LiteralPath $PSScriptRoot
try {
 $lines=& cmd.exe /d /c "call `"$VcVars`" >nul && set"
 if($LASTEXITCODE -ne 0){throw 'MSVC environment failed'}
 foreach($line in $lines){if($line -match '^([^=]+)=(.*)$'){[Environment]::SetEnvironmentVariable($matches[1],$matches[2],'Process')}}
 New-Item -ItemType Directory -Path build/diagnostic -Force | Out-Null
 & $Clang -std=c11 -O1 -Wall -Wextra -Werror -D_CRT_SECURE_NO_WARNINGS -I ../../deps/edk2/MdePkg/Include -I ../../deps/edk2/MdePkg/Include/X64 test_diagnostic.c -o build/diagnostic/test-diagnostic.exe
 if($LASTEXITCODE -ne 0){throw 'Diagnostic tests compile failed'}
 & ./build/diagnostic/test-diagnostic.exe
 if($LASTEXITCODE -ne 0){throw 'Diagnostic tests failed'}
 # Probe regression tests: the real probe.c behind simulated EFI services for
 # both reviewed profiles. No GPU, firmware or driver access is available.
 foreach($profile in @('GU_PROFILE_B650M_3090FE','GU_PROFILE_B660M_3070TI','GU_PROFILE_X870_3090TI','GU_PROFILE_B660PLUS_3060')) {
  & $Clang -std=c11 -O1 -Wall -Wextra -Werror -D_CRT_SECURE_NO_WARNINGS -DGU_DIAGNOSTIC_PROBE "-D$profile" -I ../../deps/edk2/MdePkg/Include -I ../../deps/edk2/MdePkg/Include/X64 test_probe.c probe.c ../unlock/sha256.c -o "build/diagnostic/test-probe-$profile.exe"
  if($LASTEXITCODE -ne 0){throw "Probe tests compile failed: $profile"}
  & "./build/diagnostic/test-probe-$profile.exe"
  if($LASTEXITCODE -ne 0){throw "Probe tests failed: $profile"}
 }
 # New identities use the guarded MMIO fixture, with and without PROM output.
 foreach($profile in @('GU_PROFILE_H610M_3060','GU_PROFILE_PROBE_H610M_3060','GU_PROFILE_PROBE_Z690UD_3060')) {
  foreach($prom in @($false,$true)) {
   $extra=@();if($prom){$extra+='-DGU_PROBE_DUMP_PROM'}
   $dest="build/diagnostic/test-checked-$profile-$prom.exe"
   & $Clang -std=c11 -O1 -Wall -Wextra -Werror -D_CRT_SECURE_NO_WARNINGS -DGU_DIAGNOSTIC_ONLY -DGU_DIAGNOSTIC_PROBE -DGU_USB_MEDIA "-D$profile" @extra -I ../../deps/edk2/MdePkg/Include -I ../../deps/edk2/MdePkg/Include/X64 test_probe_generic.c probe.c ../unlock/sha256.c -o $dest
   if($LASTEXITCODE -ne 0){throw "Checked probe compile failed: $profile dump=$prom"}
   & "./$dest"
   if($LASTEXITCODE -ne 0){throw "Checked probe tests failed: $profile dump=$prom"}
   "PASS checked probe: $profile dump=$prom"
  }
 }
 # Probe-only profiles must never compile into a write-side unit. These compiles
 # are expected to fail; PowerShell 5.1 would turn their stderr into a terminating error.
 $ErrorActionPreference='Continue'
 foreach($profile in @('GU_PROFILE_PROBE_H610M_3060','GU_PROFILE_PROBE_Z690UD_3060')) {
  foreach($bad in @('-DGU_FULL_UNLOCK','-DGU_UEFI_PORT','-DGU_HEADLESS_RESEARCH','-DGU_EXPERIMENTAL_3090','-DGU_INTERNAL_BOOT','-DGU_CONSOLE_PREPARE','-DGU_AUTOMATIC_BOOT')) {
   $out=& $Clang -target x86_64-pc-windows-msvc -std=c11 -ffreestanding -fsyntax-only -DGU_DIAGNOSTIC_ONLY -DGU_DIAGNOSTIC_PROBE "-D$profile" $bad -I ../../deps/edk2/MdePkg/Include -I ../../deps/edk2/MdePkg/Include/X64 probe.c 2>&1 | Out-String -Width 4096
   if($LASTEXITCODE -eq 0 -or $out -notmatch 'must not be combined with release or unlock builds'){throw "Probe-only profile $profile not rejected by its guard with $bad"}
  }
  foreach($prerequisite in @('-DGU_DIAGNOSTIC_PROBE','-DGU_DIAGNOSTIC_ONLY')) {
   $out=& $Clang -target x86_64-pc-windows-msvc -std=c11 -ffreestanding -fsyntax-only $prerequisite "-D$profile" -I ../../deps/edk2/MdePkg/Include -I ../../deps/edk2/MdePkg/Include/X64 probe.c 2>&1 | Out-String -Width 4096
   if($LASTEXITCODE -eq 0 -or $out -notmatch 'is for the read-only diagnostic probe only'){throw "Probe-only profile $profile not rejected with only $prerequisite"}
  }
  foreach($other in @('GU_PROFILE_B650M_3090FE','GU_PROFILE_B660M_3070TI','GU_PROFILE_X870_3090TI','GU_PROFILE_B660PLUS_3060','GU_PROFILE_LOCAL','GU_PROFILE_H610M_3060','GU_PROFILE_PROBE_H610M_3060','GU_PROFILE_PROBE_Z690UD_3060')) {
   if($other -eq $profile){continue}
   $out=& $Clang -target x86_64-pc-windows-msvc -std=c11 -ffreestanding -fsyntax-only -DGU_DIAGNOSTIC_ONLY -DGU_DIAGNOSTIC_PROBE "-D$profile" "-D$other" -I ../../deps/edk2/MdePkg/Include -I ../../deps/edk2/MdePkg/Include/X64 probe.c 2>&1 | Out-String -Width 4096
   if($LASTEXITCODE -eq 0 -or $out -notmatch 'Select exactly one machine profile'){throw "Probe-only profile $profile not rejected with $other"}
  }
 }
 $out=& $Clang -target x86_64-pc-windows-msvc -std=c11 -ffreestanding -fsyntax-only -DGU_DIAGNOSTIC_PROBE -DGU_PROBE_DUMP_PROM -I ../../deps/edk2/MdePkg/Include -I ../../deps/edk2/MdePkg/Include/X64 probe.c 2>&1 | Out-String -Width 4096
 if($LASTEXITCODE -eq 0 -or $out -notmatch 'only for the observation-only diagnostic image'){throw 'PROM dump not rejected outside a diagnostic-only build'}
 $ErrorActionPreference='Stop'
 foreach($profile in @('GU_PROFILE_PROBE_H610M_3060','GU_PROFILE_PROBE_Z690UD_3060')) {
  foreach($prom in @($false,$true)) {
   $extra=@();if($prom){$extra+='-DGU_PROBE_DUMP_PROM'}
   & $Clang -target x86_64-pc-windows-msvc -std=c11 -ffreestanding -fshort-wchar -fsyntax-only -Wall -Wextra -Werror -DGU_DIAGNOSTIC_ONLY -DGU_DIAGNOSTIC_PROBE -DGU_USB_MEDIA "-D$profile" @extra -I ../../deps/edk2/MdePkg/Include -I ../../deps/edk2/MdePkg/Include/X64 probe.c diagnostic.c
   if($LASTEXITCODE -ne 0){throw "Probe EFI syntax failed: $profile dump=$prom"}
  }
  "PASS probe-only profile rejected by write-side, non-diagnostic and conflicting builds; EFI syntax checked: $profile"
 }
 & $Clang -std=c11 -O1 -Wall -Wextra -Werror -D_CRT_SECURE_NO_WARNINGS -DGU_DIAGNOSTIC_ONLY -DGU_DIAGNOSTIC_PROBE -DGU_PROBE_GENERIC -I ../../deps/edk2/MdePkg/Include -I ../../deps/edk2/MdePkg/Include/X64 test_probe_generic.c probe.c ../unlock/sha256.c -o build/diagnostic/test-probe-generic.exe
 if($LASTEXITCODE -ne 0){throw 'Generic probe tests compile failed'}
 & ./build/diagnostic/test-probe-generic.exe
 if($LASTEXITCODE -ne 0){throw 'Generic probe tests failed'}
} finally {Pop-Location}
