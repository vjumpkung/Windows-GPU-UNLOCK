# GPL-2.0-only. Evidence gate for the experimental, exact Z690 USB profile.
# No hardware access. Never treat a host pass as a successful physical boot.
function Get-Z690ExpectedJobs {
 [ordered]@{'capture-fixtures'=0;'stock-selection'=0;'checks'=0;'other-profile'=1;
 'port'=0;'write-lock'=0;'master'=0;'runtime'=0;'lock-full'=0;'lock-preserve'=0;
 'cold-precheck'=0;'flow'=0;'core'=0;'manual'=0;'automatic'=0;'headless-usb'=0;
 'single-child-release'=0;'foreign-release'=1;'non-usb-refusal'=0}
}
function Assert-Z690Evidence([string]$Repo) {
 $path=Join-Path $Repo 'research/profile/local/z690ud-3060/test-results.json'
 if(!(Test-Path -LiteralPath $path)){throw 'Experimental Z690 profile needs test-z690.ps1 evidence first'}
 $e=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
 if(($e.Format -isnot [int] -and $e.Format -isnot [long]) -or $e.Format -ne 1 -or $e.AllPassed -isnot [bool] -or !$e.AllPassed -or
    $e.HardwareAccess -isnot [bool] -or $e.HardwareAccess -or
    $e.HardwareProfile -cne 'EXPERIMENTAL-GIGABYTE-Z690-UD-DDR4-F27-RTX3060-12GB' -or
    $e.TreeSha256 -cne (Get-LocalTreeDigest $Repo)){throw 'Experimental Z690 source/test evidence is stale or invalid; rerun test-z690.ps1'}
 $expected=Get-Z690ExpectedJobs
 Assert-LocalKeys $e.Results @($expected.Keys) 'Z690 host jobs'
 foreach($name in $expected.Keys){
  $job=$e.Results.$name
  if(($job.Exit -isnot [int] -and $job.Exit -isnot [long]) -or ($job.Expected -isnot [int] -and $job.Expected -isnot [long]) -or $job.Exit -ne $expected[$name] -or $job.Expected -ne $expected[$name]){throw "Invalid Z690 host result: $name"}
 }
 foreach($set in @('CaptureInputs','FixtureInputs')){
  $prefix='research/profile/local/z690ud-3060/'
  $required=if($set -eq 'FixtureInputs'){
   @('probe.txt','cold.txt','config.bin','PROM.BIN','edid.bin','nvgop.bin') | ForEach-Object {$prefix+'fixtures/'+$_}
  }else{
   foreach($number in 1..3){
    @('DIAG00.TXT','PROM.BIN','probe-BOOTX64.EFI','SHA256SUMS.txt')+@(0..39 | ForEach-Object {'IMG{0:00}.BIN' -f $_}) | ForEach-Object {$prefix+"observe-boot$number/"+$_}
   }
  }
  $paths=@($e.$set | ForEach-Object {$_.Path})
  if($paths.Count -ne @($required).Count -or @($paths | Sort-Object -Unique).Count -ne $paths.Count -or @($required | Where-Object {$paths -cnotcontains $_}).Count){throw "Incomplete Z690 $set"}
  foreach($entry in $e.$set){
   if($entry.Path -isnot [string] -or $entry.Sha256 -isnot [string] -or $entry.Sha256 -cnotmatch '^[0-9a-f]{64}$' -or
      !(Test-Path -LiteralPath (Join-Path $Repo $entry.Path) -PathType Leaf) -or
      (Get-GuSha256 (Join-Path $Repo $entry.Path)) -cne $entry.Sha256){throw 'Experimental Z690 capture/fixture changed; rerun test-z690.ps1'}
  }
 }
 return $e
}
function Assert-Z690Package([string]$Repo,$Manifest) {
 $e=Assert-Z690Evidence $Repo
 if($Manifest.ExperimentalTreeSha256 -cne $e.TreeSha256 -or
    $Manifest.ExperimentalEvidenceSha256 -cne (Get-GuSha256 (Join-Path $Repo 'research/profile/local/z690ud-3060/test-results.json'))){throw 'Experimental Z690 USB package is stale; rebuild it'}
}
