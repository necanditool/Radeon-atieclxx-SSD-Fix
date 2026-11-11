# Radeon-atieclxx-SSD-Fix – Wächter. Läuft als SYSTEM über die Aufgabe "Radeon-atieclxx-SSD-Fix" (3 Minuten nach dem Start und alle 30 Minuten).
# Hält den gezielten Schutz aktuell und prüft nach einem Treiberwechsel, ob AMD den Fehler behoben hat.
. (Join-Path $PSScriptRoot 'Kern.ps1')

$proz = Get-AmdProzess
if (-not $proz) { return }   # Dienst läuft nicht (z. B. deaktiviert): nichts zu tun
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
  if ($gleich) { return }                                   # Normalfall: Schutz steht, Treiber unverändert
  if (-not $z) { Merken 'Fehler'; Write-Protokoll ((T 'Wächter eingerichtet, Schutz aktiv (Treiber {0}).') -f $kennung); return }
  # Treiber gewechselt: Schutz kurz aufheben und messen, ob der Fehler noch besteht.
  Remove-Schutz | Out-Null
  $b = Measure-Schreibrate 8
  if ($b -lt 0) { Set-Schutz | Out-Null; return }
  if ($b -lt $script:SchreibGrenze) {
    Merken 'Behoben'
    Write-Protokoll ((T 'Neuer Treiber ({0}): keine Dauerschreiblast mehr ({1}). AMD hat den Fehler behoben, der Schutz bleibt aufgehoben.') -f $kennung, (KB $b))
    return
  }
  $ok = Set-Schutz
  Start-Sleep -Seconds 2
  $n = Measure-Schreibrate 8
  if ($ok -and $n -ge 0 -and $n -lt $script:SchreibGrenze) {
    Merken 'Fehler'
    Write-Protokoll ((T 'Neuer Treiber ({0}): Fehler besteht weiter ({1}), Schutz wieder gesetzt, danach {2}.') -f $kennung, (KB $b), (KB $n))
  } else {
    Merken 'Andere'
    Write-Protokoll ((T 'WARNUNG: Neuer Treiber ({0}) schreibt trotz Schutz weiter ({1}). Bitte Radeon-atieclxx-SSD-Fix öffnen und "Dienst deaktivieren" wählen.') -f $kennung, (KB $n))
    Send-Meldung (T 'Radeon-atieclxx-SSD-Fix: Der AMD-Treiber schreibt trotz Schutz dauerhaft auf die SSD. Bitte Radeon-atieclxx-SSD-Fix öffnen und "Dienst deaktivieren" wählen.')
  }
  return
}

# Kein Schutz gesetzt (z. B. nach einem Treiber-Update, das die Datei ersetzt hat): messen.
$b = Measure-Schreibrate 8
if ($b -lt 0) { return }
if ($b -lt $script:SchreibGrenze) {
  if (-not ($gleich -and $z.Befund -eq 'Behoben')) { Merken 'Behoben'; Write-Protokoll ((T 'Keine Dauerschreiblast ({0}, Treiber {1}), nichts zu tun.') -f (KB $b), $kennung) }
  return
}
if ($gleich -and $z.Befund -eq 'Andere') { return }       # bei diesem Treiber schon gemeldet
$ok = Set-Schutz
$n = $b
if ($ok) { Start-Sleep -Seconds 2; $n = Measure-Schreibrate 8 }
if ($ok -and $n -ge 0 -and $n -lt $script:SchreibGrenze) {
  Save-SchutzBefund -Art 'Schutz' -RateVorher $b
  Merken 'Fehler'
  Write-Protokoll ((T 'Fehler erkannt ({0}, Treiber {1}), Schutz gesetzt, danach {2}.') -f (KB $b), $kennung, (KB $n))
} else {
  Merken 'Andere'
  Write-Protokoll ((T 'WARNUNG: atieclxx.exe schreibt dauerhaft ({0}), der gezielte Schutz greift hier nicht. Bitte Radeon-atieclxx-SSD-Fix öffnen und "Dienst deaktivieren" wählen.') -f (KB $b))
  Send-Meldung (T 'Radeon-atieclxx-SSD-Fix: Der AMD-Treiber schreibt dauerhaft auf die SSD, der gezielte Schutz greift hier nicht. Bitte Radeon-atieclxx-SSD-Fix öffnen und "Dienst deaktivieren" wählen.')
}
