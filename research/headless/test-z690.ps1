# GPL-2.0-only. Exact Z690 host validation; all GPU/EFI operations are mocked.
param([Parameter(Mandatory)][string]$Assets,[string]$Clang='clang',[string]$Python='python',[string]$VcVars)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $repo 'internal-boot/unlock/local-profile.ps1')
. (Join-Path $PSScriptRoot 'z690-profile.ps1')
. (Join-Path $repo 'research/profile/host.ps1')
$local=Join-Path $repo 'research/profile/local/z690ud-3060'
$evidence=Join-Path $local 'test-results.json'
if(Test-Path -LiteralPath $evidence){Remove-Item -LiteralPath $evidence}
$results=[ordered]@{}
function Record([string]$Name,[int]$Code,[int]$Expected,$Output) {
 $lines=@($Output | ForEach-Object {"$_"})
 $lines | Set-Content -LiteralPath (Join-Path $local ($Name+'.test.log')) -Encoding utf8
 $script:results[$Name]=[ordered]@{Exit=$Code;Expected=$Expected;Last=($lines | Select-Object -Last 1)}
 "{0,-24} exit={1} expected={2} {3}" -f $Name,$Code,$Expected,($lines | Select-Object -Last 1)
 if($Code -ne $Expected){$lines | Select-Object -Last 20 | Write-Output;throw "Z690 host job failed: $Name"}
}
function Run([string]$Name,[string[]]$Compile,[string[]]$Arguments,[int]$Expected=0) {
 $compiled=& $Clang @Compile 2>&1
 if($LASTEXITCODE -ne 0){$compiled | Write-Output;throw "Compile failed: $Name"}
 $saved=$ErrorActionPreference;$ErrorActionPreference='Continue'
 $output=& $Arguments[0] @($Arguments | Select-Object -Skip 1) 2>&1
 $code=$LASTEXITCODE;$ErrorActionPreference=$saved
 Record $Name $code $Expected $output
}
Push-Location -LiteralPath $repo
try {
 $output=& $Python -I research/headless/prepare-z690-fixtures.py 2>&1
 Record 'capture-fixtures' $LASTEXITCODE 0 $output
 $fixtures=Get-Content -LiteralPath (Join-Path $local 'fixture-manifest.json') -Raw | ConvertFrom-Json
 $fx=Join-Path $local 'fixtures'
 $prom=Join-Path $fx 'PROM.BIN';$probe=Join-Path $fx 'probe.txt';$cold=Join-Path $fx 'cold.txt'
 $Assets=(Resolve-Path -LiteralPath $Assets).Path
 foreach($a in (Get-Content -LiteralPath internal-boot/unlock/assets.json -Raw | ConvertFrom-Json)){
  $p=Join-Path $Assets $a.Name
  if((Get-Item -LiteralPath $p).Length -ne $a.Bytes -or (Get-GuSha256 $p) -cne $a.Sha256){throw "Invalid asset: $($a.Name)"}
 }
 $tree=Get-LocalTreeDigest $repo
 Import-GuHostCompiler $VcVars
 Push-Location -LiteralPath internal-boot/unlock
 try {
  $out='build/tests/z690';[void][IO.Directory]::CreateDirectory((Join-Path $PWD $out))
  $flags=@('-std=c11','-O1','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-Wno-unused-function','-D_CRT_SECURE_NO_WARNINGS','-Icompat','-I../../deps/edk2/MdePkg/Include','-I../../deps/edk2/MdePkg/Include/X64')
  $profile=@('-DGU_PROFILE_Z690UD_3060')
  $core=@('port.c','compat.c','vendor/unlock_610.c','vendor/prep_610.c','vendor/layout_610.c','vendor/vbios_610.c','vendor/gfw_eval.c')
  $defs=@('-D__KERNEL__','-DGU_UEFI_PORT','-DGU_TARGET_PCI_ID=0x250410deU')
  $app=@('app_io.c','ownership.c','format.c','sha256.c','checks.c')+$core
  $latched=$flags+$profile+$defs+@('-DGU_EXPERIMENTAL_3090','-DGU_ENTRY_LATCHED_SS1_FULL')
  $output=& $Python tests/test_stock_selection.py $Clang 2>&1;Record 'stock-selection' $LASTEXITCODE 0 $output
  Run 'checks' ($flags+$profile+@('tests/test_checks.c','checks.c','-o',"$out/checks.exe")) @("./$out/checks.exe",$probe)
  Run 'other-profile' ($flags+@('-DGU_PROFILE_H610M_3060','tests/test_checks.c','checks.c','-o',"$out/checks-other.exe")) @("./$out/checks-other.exe",$probe) 1
  Run 'port' ($flags+$profile+@('-DGU_HOST_WRITE_TEST','tests/test_port.c','port.c','-o',"$out/port.exe")) @("./$out/port.exe")
  Run 'write-lock' ($flags+$profile+@('tests/test_preflight_lock.c','port.c','-o',"$out/write-lock.exe")) @("./$out/write-lock.exe")
  Run 'master' ($flags+$profile+$defs+@('-DGU_HOST_WRITE_TEST','tests/test_master_attributes.c')+$core+@('-o',"$out/master.exe")) @("./$out/master.exe")
  & $Clang @flags -fno-builtin -Dmemcpy=GuTestMemcpy -Dmemset=GuTestMemset -Dmemchr=GuTestMemchr -Dmemcmp=GuTestMemcmp -Dstrcmp=GuTestStrcmp -Dstrlen=GuTestStrlen -c runtime.c -o "$out/runtime-host.obj"
  if($LASTEXITCODE -ne 0){throw 'Runtime host compile failed'}
  Run 'runtime' ($flags+@('-fno-builtin','tests/test_runtime.c','format.c',"$out/runtime-host.obj",'-o',"$out/runtime.exe")) @("./$out/runtime.exe")
  foreach($variant in @(@('full','-DGU_ENTRY_LATCHED_SS1_FULL'),@('preserve','-DGU_ENTRY_LATCHED_SS1_PRESERVE'))){
   Run "lock-$($variant[0])" ($flags+$profile+@('-DGU_EXPERIMENTAL_3090',$variant[1],'tests/test_profile_lock.c','port.c','-o',"$out/lock-$($variant[0]).exe")) @("./$out/lock-$($variant[0]).exe")
  }
  Run 'core' ($latched+@('-DGU_INTERNAL_BOOT','tests/test_efi_transaction.c')+$core+@('-o',"$out/core.exe")) @("./$out/core.exe",$prom,$Assets,$cold)
  Run 'manual' ($latched+@('-DGU_INTERNAL_BOOT','tests/test_entry_latched.c')+$app+@('-o',"$out/manual.exe")) @("./$out/manual.exe",$prom,$cold,$Assets)
  Run 'automatic' ($latched+@('-DGU_INTERNAL_BOOT','-DGU_AUTOMATIC_BOOT','tests/test_automatic.c')+$app+@('-o',"$out/automatic.exe")) @("./$out/automatic.exe",$prom,$cold,$Assets)
  Run 'headless-usb' ($latched+@('-DGU_INTERNAL_BOOT','-DGU_AUTOMATIC_BOOT','-DGU_HEADLESS_RESEARCH','-DGU_USB_MEDIA','tests/test_headless.c')+$app+@('-o',"$out/headless.exe")) @("./$out/headless.exe",$prom,$cold,$Assets)
  '#include "machine-profile.h"' | Set-Content -LiteralPath "$out/refusal.c" -Encoding ascii
  $refusals=@(
   @{D=@('-DGU_PROFILE_Z690UD_3060','-DGU_FULL_UNLOCK','-DGU_HEADLESS_RESEARCH');Text='require the headless USB'},
   @{D=@('-DGU_PROFILE_Z690UD_3060','-DGU_FULL_UNLOCK','-DGU_USB_MEDIA');Text='require the headless USB'},
   @{D=@('-DGU_PROFILE_Z690UD_3060','-DGU_PROFILE_H610M_3060');Text='Select exactly one'},
   @{D=@('-DGU_PROFILE_PROBE_Z690UD_3060','-DGU_FULL_UNLOCK','-DGU_DIAGNOSTIC_PROBE','-DGU_DIAGNOSTIC_ONLY');Text='must not be combined'}
  )
  foreach($case in $refusals){
   $output=& $Clang -fsyntax-only -ffreestanding -I . @($case.D) "$out/refusal.c" 2>&1
   if($LASTEXITCODE -eq 0 -or ($output -join "`n") -notmatch $case.Text){throw 'Expected compile-time route/profile refusal was missing'}
  }
  $fake=[pscustomobject]@{Format=2;Mode='single-rtx-headless-unlock-then-windows-usb';CanUnlock=$true;RequiresHumanKey=$false;HardwareTested=$false;EfiSha256=('a'*64);ChildSha256=('b'*64);HardwareProfile='GIGABYTE-H610M-H-FC-RTX3060-12GB';ExperimentalTreeSha256=('c'*64);ExperimentalEvidenceSha256=('d'*64)}
  $rejected=$false
  try {Assert-GuUsbManifest $repo $fake}catch{if($_.Exception.Message -notmatch 'Experimental package metadata'){throw};$rejected=$true}
  if(!$rejected){throw 'Relabeled experimental manifest bypassed evidence gate'}
  Record 'non-usb-refusal' 0 0 'PASS non-USB, non-headless, multiple-profile, probe-write and relabeled package refusals'
 } finally {Pop-Location}
 Push-Location -LiteralPath internal-boot/boot
 try {
  $out='build/z690';[void][IO.Directory]::CreateDirectory((Join-Path $PWD $out))
  $w=@('-std=c11','-O1','-Wall','-Wextra','-Werror','-D_CRT_SECURE_NO_WARNINGS','-I../../deps/edk2/MdePkg/Include','-I../../deps/edk2/MdePkg/Include/X64')
  $head=@('-DGU_HEADLESS_RESEARCH','-DGU_SINGLE_RTX_CONSOLE','-DGU_FULL_UNLOCK','-DGU_AUTOMATIC_BOOT','-DGU_USB_MEDIA')
  Run 'cold-precheck' ($w+$profile+$head+@('test_cold_precheck.c','console-flow.c','../unlock/checks.c','../unlock/sha256.c','-o',"$out/cold.exe")) @("./$out/cold.exe")
  Run 'flow' ($w+@('test_full_flow.c','full-flow.c','-o',"$out/flow.exe")) @("./$out/flow.exe")
  $replay=@((Join-Path $fx 'edid.bin'),(Join-Path $fx 'nvgop.bin'),$prom,(Join-Path $fx 'config.bin'))
  foreach($number in 1..3){
   & $Python -I make-console-fixture.py (Join-Path $local "observe-boot$number/DIAG00.TXT") --single-rtx --no-igpu --no-edid-child --rtx-id=250410de --rtx-fb=0x0000000040000000
   if($LASTEXITCODE -ne 0){throw 'Capture graph fixture failed'}
   Run 'single-child-release' ($w+$profile+$head+@('test_headless_single.c','console-flow.c','../unlock/checks.c','../unlock/sha256.c','-o',"$out/release.exe")) (@("./$out/release.exe")+$replay)
  }
  Run 'foreign-release' ($w+@('-DGU_PROFILE_H610M_3060')+$head+@('test_headless_single.c','console-flow.c','../unlock/checks.c','../unlock/sha256.c','-o',"$out/foreign.exe")) (@("./$out/foreign.exe")+$replay) 1
 } finally {Pop-Location}
 if((Get-LocalTreeDigest $repo) -cne $tree){throw 'Sources changed during validation; rerun'}
 $expected=Get-Z690ExpectedJobs
 Assert-LocalKeys $results @($expected.Keys) 'Completed Z690 jobs'
 [ordered]@{Format=1;AllPassed=$true;HardwareAccess=$false;HardwareProfile='EXPERIMENTAL-GIGABYTE-Z690-UD-DDR4-F27-RTX3060-12GB';
 TreeSha256=$tree;CaptureInputs=$fixtures.CaptureInputs;FixtureInputs=$fixtures.FixtureInputs;Results=$results;TestedUtc=[DateTime]::UtcNow.ToString('o')
 } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $evidence -Encoding utf8
 $null=Assert-Z690Evidence $repo
 "PASS all $($results.Count) Z690 host jobs; hardware untested. Evidence: $evidence"
} finally {Pop-Location}
