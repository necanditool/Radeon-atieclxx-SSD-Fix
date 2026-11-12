# Radeon-atieclxx-SSD-Fix – guard. Runs as SYSTEM via the task "Radeon-atieclxx-SSD-Fix" (3 minutes after startup and every 30 minutes).
# Keeps the targeted protection up to date and, after a driver change, checks whether AMD has fixed the bug.
. (Join-Path $PSScriptRoot 'Core.ps1')

$proz = Get-AmdProzess
if (-not $proz) { return }   # service not running (e.g. disabled): nothing to do
$kennung = ''
try { $kennung = $proz.MainModule.FileVersionInfo.FileVersion + ' | ' + $proz.MainModule.FileName } catch { try { $kennung = [string]$proz.Path } catch {} }
$z = $null
if (Test-Path -LiteralPath $script:ZustandDatei) { try { $z = Get-Content -LiteralPath $script:ZustandDatei -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }
function Merken([string]$Befund) {
  try {
    New-Item -ItemType Directory -Force -Path $script:InstallDir | Out-Null
    [pscustomobject]@{ Kennung = $kennung; Befund = $Befund; Datum = (Get-Date -Format s) } | ConvertTo-Json | Set-Content -LiteralPath $script:ZustandDatei -Encoding UTF8
  } catch {}
}
function KB([double]$Bytes) { '{0:N0} KB/s' -f ([math]::Max($Bytes, 0) / 1KB) }
$gleich = [bool]($z -and $z.Kennung -eq $kennung)

if (Test-Schutz) {
  if ($gleich) { return }                                   # normal case: protection in place, driver unchanged
  if (-not $z) { Merken 'Fehler'; Write-Protokoll ('Guard set up, protection active (driver ' + $kennung + ').'); return }
  # Driver changed: remove the protection briefly and measure whether the bug is still there.
  Remove-Schutz | Out-Null
  $b = Measure-Schreibrate 8
  if ($b -lt 0) { Set-Schutz | Out-Null; return }
  if ($b -lt $script:SchreibGrenze) {
    Merken 'Behoben'
    Write-Protokoll ('New driver (' + $kennung + '): no more constant writing (' + (KB $b) + '). AMD has fixed the bug, the protection stays removed.')
    return
  }
  $ok = Set-Schutz
  Start-Sleep -Seconds 2
  $n = Measure-Schreibrate 8
  if ($ok -and $n -ge 0 -and $n -lt $script:SchreibGrenze) {
    Merken 'Fehler'
    Write-Protokoll ('New driver (' + $kennung + '): bug still present (' + (KB $b) + '), protection applied again, afterwards ' + (KB $n) + '.')
  } else {
    Merken 'Andere'
    Write-Protokoll ('WARNING: New driver (' + $kennung + ') keeps writing despite the protection (' + (KB $n) + '). Please open Radeon-atieclxx-SSD-Fix and choose "Disable service".')
    Send-Meldung 'Radeon-atieclxx-SSD-Fix: The AMD driver keeps writing to the SSD despite the protection. Please open Radeon-atieclxx-SSD-Fix and choose "Disable service".'
  }
  return
}

# No protection set (e.g. after a driver update that replaced the file): measure.
$b = Measure-Schreibrate 8
if ($b -lt 0) { return }
if ($b -lt $script:SchreibGrenze) {
  if (-not ($gleich -and $z.Befund -eq 'Behoben')) { Merken 'Behoben'; Write-Protokoll ('No constant writing (' + (KB $b) + ', driver ' + $kennung + '), nothing to do.') }
  return
}
if ($gleich -and $z.Befund -eq 'Andere') { return }       # already reported for this driver
$ok = Set-Schutz
$n = $b
if ($ok) { Start-Sleep -Seconds 2; $n = Measure-Schreibrate 8 }
if ($ok -and $n -ge 0 -and $n -lt $script:SchreibGrenze) {
  Save-SchutzBefund -Art 'Schutz' -RateVorher $b
  Merken 'Fehler'
  Write-Protokoll ('Bug detected (' + (KB $b) + ', driver ' + $kennung + '), protection applied, afterwards ' + (KB $n) + '.')
} else {
  Merken 'Andere'
  Write-Protokoll ('WARNING: atieclxx.exe writes constantly (' + (KB $b) + '), targeted protection does not work here. Please open Radeon-atieclxx-SSD-Fix and choose "Disable service".')
  Send-Meldung 'Radeon-atieclxx-SSD-Fix: The AMD driver writes to the SSD constantly and targeted protection does not work here. Please open Radeon-atieclxx-SSD-Fix and choose "Disable service".'
}
