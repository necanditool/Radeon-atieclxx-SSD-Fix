# Radeon-atieclxx-SSD-Fix – Fenster mit Analyse, Schadensschätzung und Fix-Knöpfen.
# Start über START.cmd (mit Administratorrechten). Messungen laufen im Hintergrund, das Fenster bleibt bedienbar.
# Test: $Global:AMDFIX_NOSHOW = $true; $Global:AMDFIX_TEST = $true; . .\Oberflaeche.ps1; $f = Build-Form
$script:SkriptDir = $PSScriptRoot
$script:KernDatei = Join-Path $PSScriptRoot 'Kern.ps1'
. $script:KernDatei
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:Ctrl = @{}
$script:Async = $null
$script:Letzte = $null
$script:Beenden = $false
$script:Timer = $null
$script:Mutex = $null
$script:TestMeldungen = New-Object System.Collections.ArrayList
$script:Sync = [hashtable]::Synchronized(@{ Phase = ''; Ende = [datetime]::MinValue })
$script:NL = [Environment]::NewLine
$script:Farbe = @{
  Rot    = [System.Drawing.Color]::FromArgb(176, 0, 32)
  Gruen  = [System.Drawing.Color]::FromArgb(30, 120, 54)
  Orange = [System.Drawing.Color]::FromArgb(176, 96, 0)
  Grau   = [System.Drawing.Color]::FromArgb(90, 90, 90)
  Text   = [System.Drawing.Color]::FromArgb(32, 32, 32)
}

# Läuft in einem eigenen Runspace: Aktion ausführen, danach neu analysieren.
$script:HintergrundSkript = {
  param($kern, $aktion, $quelle, $rateVorher, $sync, $sprache)
  . $kern
  Set-Sprache $sprache
  $script:Fortschritt = $sync
  $ergebnis = @{}
  switch ($aktion) {
    'Schutz' {
      Set-Phase 'Setze den gezielten Schutz'
      $ok = Set-Schutz
      $auf = $false
      if ($ok) {
        Save-SchutzBefund -Art 'Schutz' -RateVorher $rateVorher -ErlaubeAnnahme
        Set-Phase 'Richte die Automatik ein'
        $auf = Install-Aufgabe -Quelle $quelle
        Write-Protokoll (T 'Gezielter Schutz über die Oberfläche gesetzt.')
      }
      $ergebnis = @{ Ok = $ok; Aufgabe = $auf }
    }
    'Dienst' {
      Set-Phase 'Deaktiviere den Dienst'
      $r = Disable-Dienst
      if ($r -eq 'OK' -or $r -eq 'LaeuftNoch') {
        Save-SchutzBefund -Art 'Dienst' -RateVorher $rateVorher
        Write-Protokoll (T 'Dienst über die Oberfläche deaktiviert.')
      }
      $ergebnis = @{ Ergebnis = $r }
    }
    'Zurueck' {
      Set-Phase 'Nehme alle Eingriffe zurück'
      Remove-Alles
      Write-Protokoll (T 'Alle Eingriffe über die Oberfläche zurückgenommen.')
      $ergebnis = @{ Ok = $true }
    }
  }
  $analyse = Get-Analyse -MessSekunden 8
  [pscustomobject]@{ Aktion = $aktion; Ergebnis = $ergebnis; Analyse = $analyse }
}

# ------------------------------------------------------------------ Hilfsfunktionen
function Zeige-Nachricht {
  param([string]$Text, [string]$Knoepfe = 'OK', [string]$Symbol = 'Information', [string]$Titel = 'Radeon-atieclxx-SSD-Fix')
  if ($Global:AMDFIX_TEST) { [void]$script:TestMeldungen.Add($Text); if ($Knoepfe -eq 'YesNo') { return 'Yes' }; return 'OK' }
  $f = $script:Ctrl.Form
  if ($f -and -not $f.IsDisposed -and $f.Visible) { return [string][System.Windows.Forms.MessageBox]::Show($f, $Text, $Titel, $Knoepfe, $Symbol) }
  return [string][System.Windows.Forms.MessageBox]::Show($Text, $Titel, $Knoepfe, $Symbol)
}
function Format-Rate([double]$b) {
  if ($b -lt 0) { return (T 'nicht messbar') }
  if ($b -ge 1MB) { return ('{0:N2} MB/s' -f ($b / 1MB)) }
  return ('{0:N0} KB/s' -f ($b / 1KB))
}
function Format-Menge([double]$Bytes) {
  if ($Bytes -ge 1e11) { return ('{0:N1} TB' -f ($Bytes / 1e12)) }
  return ('{0:N0} GB' -f ($Bytes / 1e9))
}
function Format-Datum([datetime]$Datum) { $Datum.ToString((T 'dd.MM.yyyy')) }
function New-Beschriftung($Eltern, [int]$X, [int]$Y, [int]$B, [int]$H, [string]$Text = '') {
  $l = New-Object System.Windows.Forms.Label
  $l.Location = New-Object System.Drawing.Point($X, $Y)
  $l.Size = New-Object System.Drawing.Size($B, $H)
  $l.Text = $Text
  $Eltern.Controls.Add($l)
  return $l
}
function New-Knopf($Eltern, [int]$X, [int]$Y, [int]$B, [int]$H, [string]$Text) {
  $k = New-Object System.Windows.Forms.Button
  $k.Location = New-Object System.Drawing.Point($X, $Y)
  $k.Size = New-Object System.Drawing.Size($B, $H)
  $k.Text = $Text
  $Eltern.Controls.Add($k)
  return $k
}
function New-Gruppe($Eltern, [int]$X, [int]$Y, [int]$B, [int]$H, [string]$Text) {
  $g = New-Object System.Windows.Forms.GroupBox
  $g.Location = New-Object System.Drawing.Point($X, $Y)
  $g.Size = New-Object System.Drawing.Size($B, $H)
  $g.Text = $Text
  $Eltern.Controls.Add($g)
  return $g
}

# ------------------------------------------------------------------ Fenster
function Build-Form {
  $f = New-Object System.Windows.Forms.Form
  $f.SuspendLayout()
  $f.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
  $f.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
  $f.Text = 'Radeon-atieclxx-SSD-Fix ' + $script:Version
  $f.ClientSize = New-Object System.Drawing.Size(660, 620)
  $f.StartPosition = 'CenterScreen'
  $f.FormBorderStyle = 'FixedSingle'
  $f.MaximizeBox = $false
  $f.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
  $f.BackColor = [System.Drawing.Color]::White
  try { $f.Icon = [System.Drawing.SystemIcons]::Shield } catch {}
  $fett = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)

  $kopf = New-Beschriftung $f 18 14 624 32
  $kopf.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
  $kopf.ForeColor = $script:Farbe.Grau
  $unter = New-Beschriftung $f 20 48 520 20
  $unter.ForeColor = $script:Farbe.Grau
  $sprache = New-Object System.Windows.Forms.ComboBox
  $sprache.DropDownStyle = 'DropDownList'
  $sprache.Location = New-Object System.Drawing.Point(552, 46)
  $sprache.Size = New-Object System.Drawing.Size(90, 24)
  [void]$sprache.Items.AddRange(@('Deutsch', 'English'))
  $sprache.SelectedIndex = $(if ($script:Sprache -eq 'de') { 0 } else { 1 })
  $f.Controls.Add($sprache)

  $g1 = New-Gruppe $f 18 74 624 134 ''
  $befund = New-Beschriftung $g1 14 22 596 104
  $g2 = New-Gruppe $f 18 214 624 160 ''
  $schaden = New-Beschriftung $g2 14 22 596 130
  $g3 = New-Gruppe $f 18 380 624 168 ''
  $btnSchutz = New-Knopf $g3 16 26 250 40 ''
  $l1 = New-Beschriftung $g3 276 26 334 42
  $btnDienst = New-Knopf $g3 16 74 250 38 ''
  $l2 = New-Beschriftung $g3 276 74 334 40
  $btnZurueck = New-Knopf $g3 16 120 250 36 ''
  $l3 = New-Beschriftung $g3 276 120 334 40
  foreach ($l in $l1, $l2, $l3) { $l.ForeColor = $script:Farbe.Grau }

  $btnPruefen = New-Knopf $f 18 558 140 30 ''
  $btnReBar = New-Knopf $f 166 558 180 30 ''
  $btnProt = New-Knopf $f 354 558 130 30 ''
  $btnHilfe = New-Knopf $f 492 558 150 30 ''
  $fuss = New-Beschriftung $f 20 594 624 22
  $fuss.ForeColor = $script:Farbe.Grau

  $script:Ctrl = @{ Form = $f; Kopf = $kopf; Unter = $unter; Befund = $befund; Schaden = $schaden; Fett = $fett; Normal = $f.Font
    BtnSchutz = $btnSchutz; BtnDienst = $btnDienst; BtnZurueck = $btnZurueck; BtnPruefen = $btnPruefen
    BtnReBar = $btnReBar; BtnProt = $btnProt; BtnHilfe = $btnHilfe; Fuss = $fuss
    Sprache = $sprache; G1 = $g1; G2 = $g2; G3 = $g3; L1 = $l1; L2 = $l2; L3 = $l3 }
  Setze-Texte
  Zeige-Beschaeftigt 'Analyse'
  foreach ($k in 'BtnSchutz', 'BtnDienst', 'BtnZurueck', 'BtnPruefen') { $script:Ctrl[$k].Enabled = $false }
  $btnProt.Enabled = Test-Path -LiteralPath $script:ProtokollDatei

  $btnPruefen.Add_Click({ Klick-Pruefen })
  $btnSchutz.Add_Click({ Klick-Schutz })
  $btnDienst.Add_Click({ Klick-Dienst })
  $btnZurueck.Add_Click({ Klick-Zurueck })
  $btnReBar.Add_Click({ Klick-ReBar })
  $btnProt.Add_Click({ Klick-Protokoll })
  $btnHilfe.Add_Click({ Klick-Hilfe })
  $sprache.Add_SelectedIndexChanged({ Wechsel-Sprache })
  $f.Add_FormClosing({ Beim-Schliessen $_ })

  $script:Timer = New-Object System.Windows.Forms.Timer
  $script:Timer.Interval = 200
  $script:Timer.Add_Tick({ Tick-Hintergrund })

  $f.ResumeLayout($false)
  return $f
}

function Setze-Texte {
  # Alle festen Beschriftungen in der gewählten Sprache (beim Aufbau und nach einem Sprachwechsel).
  $c = $script:Ctrl
  $c.G1.Text = T 'Welcher Fehler liegt vor?'
  $c.G2.Text = T 'Bisheriger Schaden an der SSD (Schätzung)'
  $c.G3.Text = T 'Fix auswählen'
  $c.BtnSchutz.Text = T 'Gezielter Schutz (empfohlen)'
  $c.L1.Text = T 'Stoppt nur die Selbstkopie. Dienst, FreeSync und Frame Pacing laufen normal weiter.'
  $c.BtnDienst.Text = T 'Dienst deaktivieren'
  $c.L2.Text = T 'Variante aus dem Artikel: wirkt sicher, kann aber FreeSync und Frame Pacing beeinträchtigen.'
  $c.BtnZurueck.Text = T 'Alles rückgängig'
  $c.L3.Text = T 'Nimmt Schutz, Automatik und Dienst-Deaktivierung zurück.'
  $c.BtnPruefen.Text = T 'Erneut prüfen'
  $c.BtnReBar.Text = T 'Was ist Resizable BAR?'
  $c.BtnProt.Text = T 'Protokoll'
  $c.BtnHilfe.Text = T 'Anleitung'
}
function Zeige-Beschaeftigt([string]$Aktion) {
  $c = $script:Ctrl
  $c.Kopf.Text = switch ($Aktion) {
    'Schutz'  { T 'Setze den gezielten Schutz ...' }
    'Dienst'  { T 'Deaktiviere den Dienst ...' }
    'Zurueck' { T 'Nehme alles zurück ...' }
    default   { T 'Analysiere ...' }
  }
  $c.Kopf.ForeColor = $script:Farbe.Grau
  $c.Unter.Text = T 'Bitte kurz warten'
}
function Wechsel-Sprache {
  try {
    $neu = $(if ($script:Ctrl.Sprache.SelectedIndex -eq 0) { 'de' } else { 'en' })
    if ($neu -eq $script:Sprache) { return }
    Set-Sprache $neu -Merken
    Setze-Texte
    if ($script:Async) { Zeige-Beschaeftigt $script:Async.Aktion }
    elseif ($script:Letzte) { Refresh-Ansicht $script:Letzte }
  } catch { Zeige-Nachricht ((T 'Unerwarteter Fehler: ') + $_.Exception.Message) 'OK' 'Error' | Out-Null }
}
function Setze-Knoepfe($a) {
  $c = $script:Ctrl
  $deaktiviert = [bool]($a.Dienst -and [string]$a.Dienst.StartType -eq 'Disabled')
  $c.BtnSchutz.Enabled = ($a.Status -eq 'BetroffenSelbstkopie') -or ($a.Status -eq 'Geschuetzt' -and -not $a.Aufgabe)
  $c.BtnDienst.Enabled = [bool]$a.Dienst -and -not $deaktiviert
  $c.BtnZurueck.Enabled = [bool]($a.Schutz -or $a.Aufgabe -or $deaktiviert -or $a.Befund)
  $c.BtnPruefen.Enabled = $true
  $c.BtnProt.Enabled = Test-Path -LiteralPath $script:ProtokollDatei
  $c.BtnSchutz.Font = $(if ($c.BtnSchutz.Enabled) { $c.Fett } else { $c.Normal })
  $c.BtnDienst.Font = $(if ($a.Status -in 'BetroffenAndere', 'SchutzWirktNicht') { $c.Fett } else { $c.Normal })
}
function Set-Bedienbar([bool]$An) {
  $c = $script:Ctrl
  if ($An) {
    if ($script:Letzte) { Setze-Knoepfe $script:Letzte } else { $c.BtnPruefen.Enabled = $true }
  } else {
    foreach ($k in 'BtnSchutz', 'BtnDienst', 'BtnZurueck', 'BtnPruefen') { $c[$k].Enabled = $false }
  }
}

function Refresh-Ansicht {
  param($a)
  $c = $script:Ctrl
  if (-not $c.Form -or $c.Form.IsDisposed) { return }
  $kopf = @{
    KeinDienst            = @((T 'Nicht betroffen: kein AMD External Events Utility'), 'Gruen')
    DienstAus             = @((T 'Gestoppt: Der Dienst ist deaktiviert'), 'Gruen')
    DienstGestoppt        = @((T 'Der Dienst läuft gerade nicht'), 'Grau')
    MessungFehlgeschlagen = @((T 'Messung nicht möglich'), 'Orange')
    Geschuetzt            = @((T 'Geschützt: Der gezielte Schutz ist aktiv'), 'Gruen')
    NichtBetroffen        = @((T 'Dieser PC ist nicht betroffen'), 'Gruen')
    BetroffenSelbstkopie  = @((T 'Betroffen: Dauerschreiben auf die SSD'), 'Rot')
    BetroffenAndere       = @((T 'Betroffen: Dauerschreiben an anderer Stelle'), 'Rot')
    SchutzWirktNicht      = @((T 'Achtung: Der Schutz wirkt hier nicht'), 'Rot')
  }[[string]$a.Status]
  if (-not $kopf) { $kopf = @([string]$a.Status, 'Grau') }
  $c.Kopf.Text = $kopf[0]
  $c.Kopf.ForeColor = $script:Farbe[$kopf[1]]
  $c.Unter.Text = ((T 'Gemessen um {0} Uhr') -f $a.Zeit.ToString('HH:mm:ss')) + '  –  ' + $(if ($a.Rate -lt 0) { T 'atieclxx.exe läuft nicht' } else { (T 'atieclxx.exe schreibt {0}') -f (Format-Rate $a.Rate) })

  $z = New-Object System.Collections.ArrayList
  switch ([string]$a.Status) {
    'BetroffenSelbstkopie' {
      [void]$z.Add((T 'atieclxx.exe kopiert sich fortlaufend selbst (etwa einmal pro Sekunde) nach:'))
      [void]$z.Add('    ' + $script:ZielDatei)
      [void]$z.Add((T 'Das ist der bekannte Fehler. Der gezielte Schutz stoppt genau diese Kopie.'))
    }
    'BetroffenAndere' {
      [void]$z.Add((T 'atieclxx.exe schreibt dauerhaft, aber nicht an die bekannte Stelle. Gefunden:'))
      if (@($a.Ziele).Count) { foreach ($p in @($a.Ziele)) { [void]$z.Add('    ' + $p) } } else { [void]$z.Add('    ' + (T '(Ziel nicht eindeutig ermittelbar)')) }
      [void]$z.Add((T 'Der gezielte Schutz passt hier nicht. Empfohlen: Dienst deaktivieren.'))
    }
    'SchutzWirktNicht' {
      [void]$z.Add((T 'Der gezielte Schutz ist gesetzt, trotzdem wird die Kopie weiter geschrieben:'))
      [void]$z.Add('    ' + $script:ZielDatei)
      [void]$z.Add((T 'Empfohlen: Dienst deaktivieren.'))
    }
    'Geschuetzt' {
      [void]$z.Add((T 'Das Konto SYSTEM darf die Kopie nicht mehr überschreiben:'))
      [void]$z.Add('    ' + $script:ZielDatei)
      [void]$z.Add((T 'Die Selbstkopie scheitert sofort, der Dienst läuft normal weiter.'))
      [void]$z.Add((T 'Automatik nach Treiber-Updates: ') + $(if ($a.Aufgabe) { T 'eingerichtet' } else { T 'fehlt - mit "Gezielter Schutz" einrichten' }))
    }
    'DienstAus' {
      [void]$z.Add((T 'Der Dienst "AMD External Events Utility" ist deaktiviert. atieclxx.exe läuft nicht und schreibt nichts.'))
      [void]$z.Add((T 'Nachteil: FreeSync und Frame Pacing können beeinträchtigt sein. Rückgängig mit "Alles rückgängig".'))
    }
    'NichtBetroffen' { [void]$z.Add((T 'atieclxx.exe läuft, schreibt aber nicht dauerhaft. Es ist kein Eingriff nötig.')) }
    'DienstGestoppt' { [void]$z.Add((T 'Der Dienst ist installiert, läuft aber gerade nicht. Bitte später erneut prüfen.')) }
    'KeinDienst' { [void]$z.Add((T 'Auf diesem PC gibt es kein "AMD External Events Utility". Er ist von diesem Fehler nicht betroffen.')) }
    'MessungFehlgeschlagen' { [void]$z.Add((T 'atieclxx.exe wurde während der Messung beendet oder neu gestartet. Bitte erneut prüfen.')) }
  }
  $c.Befund.Text = ($z -join $script:NL)
  $c.Befund.ForeColor = $(if ($a.Betroffen) { $script:Farbe.Rot } else { $script:Farbe.Text })

  $s = $a.Schaden
  $ssdName = $(if ($a.Ssd -and $a.Ssd.Modell) { [string]$a.Ssd.Modell } else { T 'Systemlaufwerk' })
  $d = New-Object System.Collections.ArrayList
  if (-not $s) {
    [void]$d.Add((T 'Kein Dauerschreiben festgestellt - durch diesen Fehler ist kein Schaden messbar.'))
    if ($a.Ssd -and $a.Ssd.Wear) { [void]$d.Add(((T 'Abnutzung der SSD insgesamt laut Laufwerk: {0} %.') -f $a.Ssd.Wear)) }
  } else {
    $bis = $(if ($s.Aktiv) { T 'heute' } else { Format-Datum $s.Ende })
    $woher = $(if ($s.StundenQuelle -eq 'SSD') { T 'laut SSD' } else { T 'angenommen' })
    [void]$d.Add(((T 'Zeitraum: {0} bis {1} ({2} Tage), {3:N1} Betriebsstunden pro Tag {4}.') -f (Format-Datum $s.Seit), $bis, $s.Tage, $s.StundenProTag, $woher))
    [void]$d.Add(((T 'Unnötig geschrieben: rund {0} auf {1}.') -f (Format-Menge $s.Bytes), $ssdName))
    if ($s.ProzentTbw) { [void]$d.Add(((T 'Etwa {0:N2} % der üblichen Schreib-Garantie dieser SSD (rund {1:N0} TB).') -f $s.ProzentTbw, $s.TbwTB)) }
    if ($s.Wear) { [void]$d.Add(((T 'Abnutzung der SSD insgesamt laut Laufwerk: {0} %.') -f $s.Wear)) }
    if ($s.Aktiv) { [void]$d.Add(((T 'Solange der Fehler aktiv ist, kommen etwa {0:N0} GB pro Tag dazu.') -f $s.GbProTag)) }
    else { [void]$d.Add((T 'Seit dem Eingriff kommt nichts mehr dazu.')) }
    if ($s.Basis -eq 'Annahme') { [void]$d.Add((T 'Rate vor dem Schutz unbekannt, angenommen: eine Kopie pro Sekunde.')) }
    [void]$d.Add((T 'Schätzung aus Schreibrate und Betriebszeit seit Installation der AMD-Grafik.'))
  }
  $c.Schaden.Text = ($d -join $script:NL)

  $c.Fuss.Text = (T 'Dienst: ') + (Get-DienstText $a.Dienst) + '   |   ' + (T 'Schutz: ') + $(if ($a.Schutz) { T 'aktiv' } else { T 'aus' }) + '   |   ' + (T 'Automatik: ') + $(if ($a.Aufgabe) { T 'ein' } else { T 'aus' }) + '   |   ' + $ssdName
  Setze-Knoepfe $a
}

# ------------------------------------------------------------------ Hintergrundarbeit
function Start-Hintergrund([string]$Aktion) {
  if ($script:Async) { return }
  $c = $script:Ctrl
  Set-Bedienbar $false
  Zeige-Beschaeftigt $Aktion
  $script:Sync.Phase = ''
  $script:Sync.Ende = [datetime]::MinValue
  $rateVorher = $(if ($script:Letzte) { [double]$script:Letzte.Rate } else { -1.0 })
  $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
  $iss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass
  $rs = [runspacefactory]::CreateRunspace($iss)
  $rs.Open()
  $ps = [powershell]::Create()
  $ps.Runspace = $rs
  [void]$ps.AddScript($script:HintergrundSkript.ToString()).AddArgument($script:KernDatei).AddArgument($Aktion).AddArgument($script:SkriptDir).AddArgument($rateVorher).AddArgument($script:Sync).AddArgument($script:Sprache)
  $script:Async = @{ PS = $ps; RS = $rs; Aktion = $Aktion; Handle = $ps.BeginInvoke() }
  $script:Timer.Start()
}
function Tick-Hintergrund {
  try {
    $a = $script:Async
    if (-not $a) { $script:Timer.Stop(); return }
    if (-not $a.Handle.IsCompleted) {
      try {
        $ph = [string]$script:Sync.Phase   # der Hintergrund meldet die Phase auf Deutsch, übersetzt wird hier
        if ($ph) {
          $ph = T $ph
          $ende = [datetime]$script:Sync.Ende
          $text = $ph + ' ...'
          if ($ende -gt [datetime]::MinValue) {
            $sek = ($ende - (Get-Date)).TotalSeconds
            if ($sek -gt 0 -and $sek -lt 3600) { $text = (T '{0} - noch {1} s') -f $ph, [math]::Ceiling($sek) }
          }
          $script:Ctrl.Unter.Text = $text
        }
      } catch {}   # eine fehlerhafte Fortschrittsanzeige darf die laufende Arbeit nie abbrechen
      return
    }
    $script:Timer.Stop()
    $res = @(); $fehler = ''
    try { $res = @($a.PS.EndInvoke($a.Handle)) } catch { $fehler = $_.Exception.Message }
    if (-not $fehler -and $a.PS.Streams.Error.Count) { $fehler = [string]$a.PS.Streams.Error[0] }
    try { $a.PS.Dispose(); $a.RS.Close(); $a.RS.Dispose() } catch {}
    $script:Async = $null
    if ($script:Beenden -or $script:Ctrl.Form.IsDisposed) { return }
    $paket = $res | Where-Object { $_ -and $_.PSObject.Properties['Analyse'] } | Select-Object -Last 1
    if (-not $paket -or -not $paket.Analyse) {
      $script:Ctrl.Kopf.Text = T 'Analyse fehlgeschlagen'
      $script:Ctrl.Kopf.ForeColor = $script:Farbe.Orange
      $script:Ctrl.Unter.Text = T 'Bitte "Erneut prüfen" versuchen'
      Set-Bedienbar $true
      Zeige-Nachricht ((T 'Die Analyse ist fehlgeschlagen.') + $script:NL + $fehler) 'OK' 'Warning' | Out-Null
      return
    }
    $script:Letzte = $paket.Analyse
    Refresh-Ansicht $paket.Analyse
    Melde-Aktion $paket
  } catch {
    # Läuft die Hintergrundarbeit noch, weiter abwarten statt sie zu verlieren
    # (sonst könnten sich zwei Aktionen überschneiden).
    $a = $script:Async
    if ($a -and -not $a.Handle.IsCompleted) { return }
    try { $script:Timer.Stop() } catch {}
    if ($a) { try { $a.PS.Dispose(); $a.RS.Close(); $a.RS.Dispose() } catch {} }
    $script:Async = $null
    Set-Bedienbar $true
    Zeige-Nachricht ((T 'Unerwarteter Fehler: ') + $_.Exception.Message) 'OK' 'Error' | Out-Null
  }
}
function Stop-Hintergrund {
  try { if ($script:Timer) { $script:Timer.Stop() } } catch {}
  $a = $script:Async
  $script:Async = $null
  if ($a) {
    try { $a.PS.Stop() } catch {}
    try { $a.PS.Dispose(); $a.RS.Close(); $a.RS.Dispose() } catch {}
  }
  & logman stop $script:TraceName -ets *> $null   # falls eine Aufzeichnung lief
}
function Melde-Aktion($p) {
  $e = $p.Ergebnis
  switch ([string]$p.Aktion) {
    'Schutz' {
      if ($e.Ok) {
        $auto = $(if ($e.Aufgabe) { T 'Die Automatik ist eingerichtet: Sie prüft beim Start und alle 30 Minuten, setzt den Schutz nach Treiber-Updates neu und hebt ihn auf, sobald AMD den Fehler behoben hat.' }
                  else { T 'Die Automatik konnte nicht eingerichtet werden. Der Schutz wirkt trotzdem, bis ein Treiber-Update die Datei ersetzt.' })
        Zeige-Nachricht ((T 'Gezielter Schutz gesetzt. Die Selbstkopie ist gestoppt, der Dienst läuft weiter.') + $script:NL + $script:NL + $auto) 'OK' 'Information' | Out-Null
      } else {
        Zeige-Nachricht (T 'Der Schutz konnte nicht gesetzt werden: Die Kopie wurde nicht gefunden oder es fehlen Rechte.') 'OK' 'Warning' | Out-Null
      }
    }
    'Dienst' {
      $t = switch ([string]$e.Ergebnis) {
        'OK'         { T 'Der Dienst ist deaktiviert, atieclxx.exe läuft nicht mehr.' }
        'LaeuftNoch' { T 'Der Dienst ist deaktiviert, atieclxx.exe läuft aber noch. Nach einem Neustart ist es aus.' }
        'KeinDienst' { T 'Der Dienst wurde nicht gefunden.' }
        default      { T 'Der Dienst konnte nicht deaktiviert werden.' }
      }
      Zeige-Nachricht $t 'OK' $(if ([string]$e.Ergebnis -eq 'OK') { 'Information' } else { 'Warning' }) | Out-Null
    }
    'Zurueck' { Zeige-Nachricht ((T 'Alle Eingriffe wurden zurückgenommen.') + $script:NL + (T 'Der Programmordner bleibt erhalten. Ganz entfernen: ENTFERNEN.cmd.')) 'OK' 'Information' | Out-Null }
  }
}

# ------------------------------------------------------------------ Knöpfe
function Fehler-Anzeigen($Fehler) { Set-Bedienbar $true; Zeige-Nachricht ((T 'Unerwarteter Fehler: ') + $Fehler.Exception.Message) 'OK' 'Error' | Out-Null }
function Klick-Pruefen { try { Start-Hintergrund 'Analyse' } catch { Fehler-Anzeigen $_ } }
function Klick-Schutz { try { Start-Hintergrund 'Schutz' } catch { Fehler-Anzeigen $_ } }
function Klick-Dienst {
  try {
    $r = Zeige-Nachricht ((T 'Den Dienst "AMD External Events Utility" deaktivieren?') + $script:NL + $script:NL +
      (T 'Das stoppt das Schreiben zuverlässig, kann aber FreeSync und Frame Pacing beeinträchtigen. Rückgängig jederzeit mit "Alles rückgängig".')) 'YesNo' 'Warning'
    if ($r -eq 'Yes') { Start-Hintergrund 'Dienst' }
  } catch { Fehler-Anzeigen $_ }
}
function Klick-Zurueck {
  try {
    $r = Zeige-Nachricht (T 'Alle Eingriffe zurücknehmen (Schutz, Automatik, Dienst-Deaktivierung)?') 'YesNo' 'Question'
    if ($r -eq 'Yes') { Start-Hintergrund 'Zurueck' }
  } catch { Fehler-Anzeigen $_ }
}
function Klick-ReBar {
  Zeige-Nachricht ((T 'Resizable BAR (bei AMD "Smart Access Memory") lässt den Prozessor auf den gesamten Grafikspeicher auf einmal zugreifen und bringt in vielen Spielen etwas mehr Leistung.') + $script:NL + $script:NL +
    (T 'Der Artikel schlägt vor, Resizable BAR im BIOS abzuschalten, weil der Fehler im Smart-Access-Memory-Teil des Treibers steckt. Das kann helfen, kostet aber je nach Spiel Leistung und lässt sich nur im BIOS ändern, nicht von hier aus.') + $script:NL + $script:NL +
    (T 'Der gezielte Schutz löst das Problem, ohne Resizable BAR anzufassen.')) 'OK' 'Information' (T 'Was ist Resizable BAR?') | Out-Null
}
function Klick-Protokoll {
  if (Test-Path -LiteralPath $script:ProtokollDatei) { Start-Process notepad.exe -ArgumentList ('"' + $script:ProtokollDatei + '"') }
  else { Zeige-Nachricht (T 'Noch kein Protokoll vorhanden.') | Out-Null }
}
function Klick-Hilfe {
  # Anleitung in der gewählten Sprache (LIESMICH.txt oder README.txt), sonst die deutsche.
  $datei = $null
  foreach ($name in @((T 'LIESMICH.txt'), 'LIESMICH.txt')) {
    foreach ($ordner in (Split-Path -Parent $script:SkriptDir), $script:InstallDir) {
      $p = Join-Path $ordner $name
      if (-not $datei -and (Test-Path -LiteralPath $p)) { $datei = $p }
    }
  }
  if ($datei) { Start-Process notepad.exe -ArgumentList ('"' + $datei + '"') }
  else { Zeige-Nachricht (T 'Die Anleitung (LIESMICH.txt) wurde nicht gefunden.') | Out-Null }
}
function Beim-Schliessen($e) {
  if ($script:Async -and $script:Async.Aktion -ne 'Analyse') {
    Zeige-Nachricht (T 'Bitte warten, bis die laufende Aktion fertig ist.') | Out-Null
    $e.Cancel = $true
    return
  }
  $script:Beenden = $true
  Stop-Hintergrund
}

# ------------------------------------------------------------------ Start
if (-not $Global:AMDFIX_NOSHOW) {
  try {
    if (-not (Test-IstAdmin)) {
      # Mit Administratorrechten neu starten (gleiche PowerShell-Version).
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = (Get-Process -Id $PID).Path
      $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "' + $PSCommandPath + '"'
      $psi.Verb = 'runas'
      $psi.UseShellExecute = $true
      try { [void][System.Diagnostics.Process]::Start($psi) } catch {}   # Windows-Abfrage abgelehnt
      return
    }
    $neu = $false
    $script:Mutex = New-Object System.Threading.Mutex($true, 'Global\Radeon-atieclxx-SSD-Fix-Oberflaeche', [ref]$neu)
    if (-not $neu) {
      [void][System.Windows.Forms.MessageBox]::Show((T 'Radeon-atieclxx-SSD-Fix ist bereits geöffnet.'), 'Radeon-atieclxx-SSD-Fix', 'OK', 'Information')
      $script:Mutex.Dispose()
      $script:Mutex = $null
      return
    }
    & logman stop $script:TraceName -ets *> $null    # Reste einer abgebrochenen Aufzeichnung beenden
    $form = Build-Form
    $form.Add_Shown({ $this.Activate(); Start-Hintergrund 'Analyse' })
    [void]$form.ShowDialog()
  } catch {
    $text = (T 'Radeon-atieclxx-SSD-Fix konnte nicht ausgeführt werden:') + $script:NL + $_.Exception.Message
    try { Add-Content -LiteralPath (Join-Path $env:TEMP 'Radeon-atieclxx-SSD-Fix-Fehler.txt') -Value ((Get-Date -Format s) + '  ' + $_.Exception.ToString()) -Encoding UTF8 } catch {}
    try { [void][System.Windows.Forms.MessageBox]::Show($text, 'Radeon-atieclxx-SSD-Fix', 'OK', 'Error') } catch {}
  } finally {
    if (Test-IstAdmin) { Stop-Hintergrund }
    if ($script:Timer) { try { $script:Timer.Dispose() } catch {} }
    if ($script:Mutex) { try { $script:Mutex.ReleaseMutex() } catch {}; try { $script:Mutex.Dispose() } catch {} }
  }
}
