$check = [System.IO.File]::ReadAllBytes('C:\Work\Allodshome\.qwen\tmp\check_prewater.gd')
$mine  = [System.IO.File]::ReadAllBytes('C:\Work\Allodshome\.qwen\tmp\alm_map_prewater.gd')
Write-Output ("check length: " + $check.Length)
Write-Output ("mine  length: " + $mine.Length)
# count LF (0x0A) and CR (0x0D) per file
$cLF = 0; $cCR = 0
foreach ($b in $check) { if ($b -eq 10) { $cLF++ } ; if ($b -eq 13) { $cCR++ } }
Write-Output ("check LF=" + $cLF + " CR=" + $cCR)
$mLF = 0; $mCR = 0
foreach ($b in $mine) { if ($b -eq 10) { $mLF++ } ; if ($b -eq 13) { $mCR++ } }
Write-Output ("mine  LF=" + $mLF + " CR=" + $mCR)
# first 16 bytes each
$cb = ""; for ($i = 0; $i -lt [Math]::Min(16, $check.Length); $i++) { $cb += $check[$i].ToString("X2") + " " }
$mb = ""; for ($i = 0; $i -lt [Math]::Min(16, $mine.Length); $i++) { $mb += $mine[$i].ToString("X2") + " " }
Write-Output ("check head: " + $cb)
Write-Output ("mine  head: " + $mb)
# find first index where content differs
$first = -1
$n = [Math]::Min($check.Length, $mine.Length)
for ($i = 0; $i -lt $n; $i++) { if ($check[$i] -ne $mine[$i]) { $first = $i; break } }
Write-Output ("first diff byte index: " + $first)
if ($first -ge 0) {
  $s = [Math]::Max(0, $first - 8)
  $cb = ""; $mb = ""
  for ($i = $s; $i -lt [Math]::Min($first + 8, $check.Length); $i++) { $cb += $check[$i].ToString("X2") + " " }
  for ($i = $s; $i -lt [Math]::Min($first + 8, $mine.Length); $i++) { $mb += $mine[$i].ToString("X2") + " " }
  Write-Output ("check around diff: " + $cb)
  Write-Output ("mine  around diff: " + $mb)
}
Remove-Item C:\Work\Allodshome\.qwen\tmp\check_eol.ps1