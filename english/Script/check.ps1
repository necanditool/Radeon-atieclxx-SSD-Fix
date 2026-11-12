# Radeon-atieclxx-SSD-Fix – quick status, without administrator rights.
. (Join-Path $PSScriptRoot 'Core.ps1')
Write-Host ('Radeon-atieclxx-SSD-Fix ' + $script:Version + ' - Status')
Write-Host ''
$t = Get-ScheduledTask -TaskName $script:AufgabeName -ErrorAction SilentlyContinue
$eingerichtet = [bool]$t -or (Test-Path -LiteralPath (Join-Path $script:InstallDir 'Script\guard.ps1'))
if ($t) {
  $i = $null
  try { $i = Get-ScheduledTaskInfo -TaskName $script:AufgabeName -ErrorAction Stop } catch {}
  Write-Host 'Automatic task: set up' -ForegroundColor Green
  if ($i) {
    $letzter = $(if ($i.LastRunTime -and $i.LastRunTime.Year -ge 2000) { $i.LastRunTime.ToString('yyyy-MM-dd HH:mm') } else { 'not yet' })
    $naechster = $(if ($i.NextRunTime) { $i.NextRunTime.ToString('yyyy-MM-dd HH:mm') } else { 'unknown' })
    Write-Host ('  last run: ' + $letzter + '   next run: ' + $naechster)
  }
} elseif ($eingerichtet) { Write-Host 'Automatic task: set up (details only readable with administrator rights)' -ForegroundColor Green }
else { Write-Host 'Automatic task: not set up' -ForegroundColor Yellow }
Write-Host ('Service:        ' + (Get-DienstText (Get-AmdDienst)))
if (Test-Path -LiteralPath $script:ProtokollDatei) {
  Write-Host 'Latest log entries:'
  Get-Content -LiteralPath $script:ProtokollDatei -Tail 5 -Encoding UTF8 | ForEach-Object { Write-Host ('  ' + $_) }
}
Write-Host ''
if (-not (Get-AmdProzess)) { Write-Host 'atieclxx.exe is not running - no write load.' -ForegroundColor Green; return }
Write-Host 'Measuring for 10 seconds ...'
$rate = Measure-Schreibrate 10
if ($rate -lt 0) { Write-Host 'atieclxx.exe was stopped during the measurement.'; return }
Write-Host ('atieclxx.exe writes {0:N0} KB/s (about {1:N1} GB per day in continuous operation)' -f ($rate / 1KB), ($rate * 86400 / 1e9))
if ($rate -ge $script:SchreibGrenze) {
  if ($eingerichtet) { Write-Host 'AFFECTED: atieclxx.exe writes constantly. The automatic task acts on its next run; to fix it now: START.cmd.' -ForegroundColor Red }
  else { Write-Host 'AFFECTED: atieclxx.exe writes constantly. Run START.cmd and choose a fix.' -ForegroundColor Red }
} else { Write-Host 'OK: no constant writing.' -ForegroundColor Green }
