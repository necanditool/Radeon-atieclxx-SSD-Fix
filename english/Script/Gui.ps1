# Radeon-atieclxx-SSD-Fix – window with analysis, wear estimate and fix buttons.
# Started via START.cmd (with administrator rights). Measurements run in the background, the window stays usable.
# Test: $Global:AMDFIX_NOSHOW = $true; $Global:AMDFIX_TEST = $true; . .\Gui.ps1; $f = Build-Form
$script:SkriptDir = $PSScriptRoot
$script:KernDatei = Join-Path $PSScriptRoot 'Core.ps1'
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

# Runs in a separate runspace: perform the action, then analyze again.
$script:HintergrundSkript = {
  param($kern, $aktion, $quelle, $rateVorher, $sync)
  . $kern
  $script:Fortschritt = $sync
  $ergebnis = @{}
  switch ($aktion) {
    'Schutz' {
      Set-Phase 'Applying targeted protection'
      $ok = Set-Schutz
      $auf = $false
      if ($ok) {
        Save-SchutzBefund -Art 'Schutz' -RateVorher $rateVorher -ErlaubeAnnahme
        Set-Phase 'Setting up the automatic task'
        $auf = Install-Aufgabe -Quelle $quelle
        Write-Protokoll 'Targeted protection applied from the window.'
      }
      $ergebnis = @{ Ok = $ok; Aufgabe = $auf }
    }
    'Dienst' {
      Set-Phase 'Disabling the service'
      $r = Disable-Dienst
      if ($r -eq 'OK' -or $r -eq 'LaeuftNoch') {
        Save-SchutzBefund -Art 'Dienst' -RateVorher $rateVorher
        Write-Protokoll 'Service disabled from the window.'
      }
      $ergebnis = @{ Ergebnis = $r }
    }
    'Zurueck' {
      Set-Phase 'Undoing all changes'
      Remove-Alles
      Write-Protokoll 'All changes undone from the window.'
      $ergebnis = @{ Ok = $true }
    }
  }
  $analyse = Get-Analyse -MessSekunden 8
  [pscustomobject]@{ Aktion = $aktion; Ergebnis = $ergebnis; Analyse = $analyse }
}

# ------------------------------------------------------------------ Helper functions
function Zeige-Nachricht {
  param([string]$Text, [string]$Knoepfe = 'OK', [string]$Symbol = 'Information', [string]$Titel = 'Radeon-atieclxx-SSD-Fix')
  if ($Global:AMDFIX_TEST) { [void]$script:TestMeldungen.Add($Text); if ($Knoepfe -eq 'YesNo') { return 'Yes' }; return 'OK' }
  $f = $script:Ctrl.Form
  if ($f -and -not $f.IsDisposed -and $f.Visible) { return [string][System.Windows.Forms.MessageBox]::Show($f, $Text, $Titel, $Knoepfe, $Symbol) }
  return [string][System.Windows.Forms.MessageBox]::Show($Text, $Titel, $Knoepfe, $Symbol)
}
function Format-Rate([double]$b) {
  if ($b -lt 0) { return 'not measurable' }
  if ($b -ge 1MB) { return ('{0:N2} MB/s' -f ($b / 1MB)) }
  return ('{0:N0} KB/s' -f ($b / 1KB))
}
function Format-Menge([double]$Bytes) {
  if ($Bytes -ge 1e11) { return ('{0:N1} TB' -f ($Bytes / 1e12)) }
  return ('{0:N0} GB' -f ($Bytes / 1e9))
}
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

# ------------------------------------------------------------------ Window
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

  $kopf = New-Beschriftung $f 18 14 624 32 'Analyzing ...'
  $kopf.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
  $kopf.ForeColor = $script:Farbe.Grau
  $unter = New-Beschriftung $f 20 48 624 20 'Please wait a moment'
  $unter.ForeColor = $script:Farbe.Grau

  $g1 = New-Gruppe $f 18 74 624 134 'Which bug is present?'
  $befund = New-Beschriftung $g1 14 22 596 104
  $g2 = New-Gruppe $f 18 214 624 160 'SSD wear caused so far (estimate)'
  $schaden = New-Beschriftung $g2 14 22 596 130
  $g3 = New-Gruppe $f 18 380 624 168 'Choose a fix'
  $btnSchutz = New-Knopf $g3 16 26 250 40 'Targeted protection (recommended)'
  $l1 = New-Beschriftung $g3 276 26 334 42 'Stops only the self-copy. The service, FreeSync and frame pacing keep working normally.'
  $btnDienst = New-Knopf $g3 16 74 250 38 'Disable service'
  $l2 = New-Beschriftung $g3 276 74 334 40 'Option from the article: always works, but may affect FreeSync and frame pacing.'
  $btnZurueck = New-Knopf $g3 16 120 250 36 'Undo everything'
  $l3 = New-Beschriftung $g3 276 120 334 40 'Removes the protection, the automatic task and the service change.'
  foreach ($l in $l1, $l2, $l3) { $l.ForeColor = $script:Farbe.Grau }

  $btnPruefen = New-Knopf $f 18 558 140 30 'Check again'
  $btnReBar = New-Knopf $f 166 558 180 30 'What is Resizable BAR?'
  $btnProt = New-Knopf $f 354 558 130 30 'Log'
  $btnHilfe = New-Knopf $f 492 558 150 30 'Instructions'
  $fuss = New-Beschriftung $f 20 594 624 22
  $fuss.ForeColor = $script:Farbe.Grau

  $script:Ctrl = @{ Form = $f; Kopf = $kopf; Unter = $unter; Befund = $befund; Schaden = $schaden; Fett = $fett; Normal = $f.Font
    BtnSchutz = $btnSchutz; BtnDienst = $btnDienst; BtnZurueck = $btnZurueck; BtnPruefen = $btnPruefen
    BtnReBar = $btnReBar; BtnProt = $btnProt; BtnHilfe = $btnHilfe; Fuss = $fuss }
  foreach ($k in 'BtnSchutz', 'BtnDienst', 'BtnZurueck', 'BtnPruefen') { $script:Ctrl[$k].Enabled = $false }
  $btnProt.Enabled = Test-Path -LiteralPath $script:ProtokollDatei

  $btnPruefen.Add_Click({ Klick-Pruefen })
  $btnSchutz.Add_Click({ Klick-Schutz })
  $btnDienst.Add_Click({ Klick-Dienst })
  $btnZurueck.Add_Click({ Klick-Zurueck })
  $btnReBar.Add_Click({ Klick-ReBar })
  $btnProt.Add_Click({ Klick-Protokoll })
  $btnHilfe.Add_Click({ Klick-Hilfe })
  $f.Add_FormClosing({ Beim-Schliessen $_ })

  $script:Timer = New-Object System.Windows.Forms.Timer
  $script:Timer.Interval = 200
  $script:Timer.Add_Tick({ Tick-Hintergrund })

  $f.ResumeLayout($false)
  return $f
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
    KeinDienst            = @('Not affected: no AMD External Events Utility', 'Gruen')
    DienstAus             = @('Stopped: the service is disabled', 'Gruen')
    DienstGestoppt        = @('The service is not running right now', 'Grau')
    MessungFehlgeschlagen = @('Measurement not possible', 'Orange')
    Geschuetzt            = @('Protected: targeted protection is active', 'Gruen')
    NichtBetroffen        = @('This PC is not affected', 'Gruen')
    BetroffenSelbstkopie  = @('Affected: constant writing to the SSD', 'Rot')
    BetroffenAndere       = @('Affected: constant writing to another location', 'Rot')
    SchutzWirktNicht      = @('Warning: the protection does not work here', 'Rot')
  }[[string]$a.Status]
  if (-not $kopf) { $kopf = @([string]$a.Status, 'Grau') }
  $c.Kopf.Text = $kopf[0]
  $c.Kopf.ForeColor = $script:Farbe[$kopf[1]]
  $c.Unter.Text = 'Measured at ' + $a.Zeit.ToString('HH:mm:ss') + '  –  ' + $(if ($a.Rate -lt 0) { 'atieclxx.exe is not running' } else { 'atieclxx.exe writes ' + (Format-Rate $a.Rate) })

  $z = New-Object System.Collections.ArrayList
  switch ([string]$a.Status) {
    'BetroffenSelbstkopie' {
      [void]$z.Add('atieclxx.exe keeps copying itself (about once per second) to:')
      [void]$z.Add('    ' + $script:ZielDatei)
      [void]$z.Add('This is the known bug. Targeted protection stops exactly this copy.')
    }
    'BetroffenAndere' {
      [void]$z.Add('atieclxx.exe writes constantly, but not to the known location. Found:')
      if (@($a.Ziele).Count) { foreach ($p in @($a.Ziele)) { [void]$z.Add('    ' + $p) } } else { [void]$z.Add('    (target could not be determined)') }
      [void]$z.Add('Targeted protection does not fit here. Recommended: disable the service.')
    }
    'SchutzWirktNicht' {
      [void]$z.Add('Targeted protection is set, but the copy is still being written:')
      [void]$z.Add('    ' + $script:ZielDatei)
      [void]$z.Add('Recommended: disable the service.')
    }
    'Geschuetzt' {
      [void]$z.Add('The SYSTEM account may no longer overwrite the copy:')
      [void]$z.Add('    ' + $script:ZielDatei)
      [void]$z.Add('The self-copy fails immediately, the service keeps running normally.')
      [void]$z.Add('Automatic task after driver updates: ' + $(if ($a.Aufgabe) { 'set up' } else { 'missing - set it up with "Targeted protection"' }))
    }
    'DienstAus' {
      [void]$z.Add('The "AMD External Events Utility" service is disabled. atieclxx.exe is not running and writes nothing.')
      [void]$z.Add('Drawback: FreeSync and frame pacing may be affected. Undo with "Undo everything".')
    }
    'NichtBetroffen' { [void]$z.Add('atieclxx.exe is running, but does not write constantly. No action is needed.') }
    'DienstGestoppt' { [void]$z.Add('The service is installed, but is not running right now. Please check again later.') }
    'KeinDienst' { [void]$z.Add('There is no "AMD External Events Utility" on this PC. It is not affected by this bug.') }
    'MessungFehlgeschlagen' { [void]$z.Add('atieclxx.exe was stopped or restarted during the measurement. Please check again.') }
  }
  $c.Befund.Text = ($z -join $script:NL)
  $c.Befund.ForeColor = $(if ($a.Betroffen) { $script:Farbe.Rot } else { $script:Farbe.Text })

  $s = $a.Schaden
  $ssdName = $(if ($a.Ssd -and $a.Ssd.Modell) { [string]$a.Ssd.Modell } else { 'System drive' })
  $d = New-Object System.Collections.ArrayList
  if (-not $s) {
    [void]$d.Add('No constant writing detected - this bug has caused no measurable wear.')
    if ($a.Ssd -and $a.Ssd.Wear) { [void]$d.Add(('Total SSD wear reported by the drive: {0} %.' -f $a.Ssd.Wear)) }
  } else {
    $bis = $(if ($s.Aktiv) { 'today' } else { $s.Ende.ToString('yyyy-MM-dd') })
    $woher = $(if ($s.StundenQuelle -eq 'SSD') { 'according to the SSD' } else { 'assumed' })
    [void]$d.Add(('Period: {0} to {1} ({2} days), {3:N1} operating hours per day ({4}).' -f $s.Seit.ToString('yyyy-MM-dd'), $bis, $s.Tage, $s.StundenProTag, $woher))
    [void]$d.Add(('Written unnecessarily: about {0} ({1}).' -f (Format-Menge $s.Bytes), $ssdName))
    if ($s.ProzentTbw) { [void]$d.Add(('About {0:N2} % of the usual write warranty of this SSD (about {1:N0} TB).' -f $s.ProzentTbw, $s.TbwTB)) }
    if ($s.Wear) { [void]$d.Add(('Total SSD wear reported by the drive: {0} %.' -f $s.Wear)) }
    if ($s.Aktiv) { [void]$d.Add(('As long as the bug is active, about {0:N0} GB are added per day.' -f $s.GbProTag)) }
    else { [void]$d.Add('Nothing has been added since the fix.') }
    if ($s.Basis -eq 'Annahme') { [void]$d.Add('Rate before the protection unknown, assumed: one copy per second.') }
    [void]$d.Add('Estimate from the write rate and the operating time since the AMD graphics card was installed.')
  }
  $c.Schaden.Text = ($d -join $script:NL)

  $c.Fuss.Text = 'Service: ' + (Get-DienstText $a.Dienst) + '   |   Protection: ' + $(if ($a.Schutz) { 'active' } else { 'off' }) + '   |   Automatic: ' + $(if ($a.Aufgabe) { 'on' } else { 'off' }) + '   |   ' + $ssdName
  Setze-Knoepfe $a
}

# ------------------------------------------------------------------ Background work
function Start-Hintergrund([string]$Aktion) {
  if ($script:Async) { return }
  $c = $script:Ctrl
  Set-Bedienbar $false
  $titel = @{ Analyse = 'Analyzing ...'; Schutz = 'Applying targeted protection ...'; Dienst = 'Disabling the service ...'; Zurueck = 'Undoing everything ...' }[$Aktion]
  $c.Kopf.Text = $titel
  $c.Kopf.ForeColor = $script:Farbe.Grau
  $c.Unter.Text = 'Please wait a moment'
  $script:Sync.Phase = ''
  $script:Sync.Ende = [datetime]::MinValue
  $rateVorher = $(if ($script:Letzte) { [double]$script:Letzte.Rate } else { -1.0 })
  $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
  $iss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass
  $rs = [runspacefactory]::CreateRunspace($iss)
  $rs.Open()
  $ps = [powershell]::Create()
  $ps.Runspace = $rs
  [void]$ps.AddScript($script:HintergrundSkript.ToString()).AddArgument($script:KernDatei).AddArgument($Aktion).AddArgument($script:SkriptDir).AddArgument($rateVorher).AddArgument($script:Sync)
  $script:Async = @{ PS = $ps; RS = $rs; Aktion = $Aktion; Handle = $ps.BeginInvoke() }
  $script:Timer.Start()
}
function Tick-Hintergrund {
  try {
    $a = $script:Async
    if (-not $a) { $script:Timer.Stop(); return }
    if (-not $a.Handle.IsCompleted) {
      try {
        $ph = [string]$script:Sync.Phase
        if ($ph) {
          $ende = [datetime]$script:Sync.Ende
          $text = $ph + ' ...'
          if ($ende -gt [datetime]::MinValue) {
            $sek = ($ende - (Get-Date)).TotalSeconds
            if ($sek -gt 0 -and $sek -lt 3600) { $text = $ph + ' - ' + [math]::Ceiling($sek) + ' s left' }
          }
          $script:Ctrl.Unter.Text = $text
        }
      } catch {}   # a faulty progress display must never interrupt the running work
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
      $script:Ctrl.Kopf.Text = 'Analysis failed'
      $script:Ctrl.Kopf.ForeColor = $script:Farbe.Orange
      $script:Ctrl.Unter.Text = 'Please try "Check again"'
      Set-Bedienbar $true
      Zeige-Nachricht ('The analysis failed.' + $script:NL + $fehler) 'OK' 'Warning' | Out-Null
      return
    }
    $script:Letzte = $paket.Analyse
    Refresh-Ansicht $paket.Analyse
    Melde-Aktion $paket
  } catch {
    # If the background work is still running, keep waiting instead of losing it
    # (otherwise two actions could overlap).
    $a = $script:Async
    if ($a -and -not $a.Handle.IsCompleted) { return }
    try { $script:Timer.Stop() } catch {}
    if ($a) { try { $a.PS.Dispose(); $a.RS.Close(); $a.RS.Dispose() } catch {} }
    $script:Async = $null
    Set-Bedienbar $true
    Zeige-Nachricht ('Unexpected error: ' + $_.Exception.Message) 'OK' 'Error' | Out-Null
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
  & logman stop $script:TraceName -ets *> $null   # in case a trace was running
}
function Melde-Aktion($p) {
  $e = $p.Ergebnis
  switch ([string]$p.Aktion) {
    'Schutz' {
      if ($e.Ok) {
        $auto = $(if ($e.Aufgabe) { 'The automatic task is set up: it checks at startup and every 30 minutes, re-applies the protection after driver updates and removes it as soon as AMD has fixed the bug.' }
                  else { 'The automatic task could not be set up. The protection still works until a driver update replaces the file.' })
        Zeige-Nachricht ('Targeted protection applied. The self-copy is stopped, the service keeps running.' + $script:NL + $script:NL + $auto) 'OK' 'Information' | Out-Null
      } else {
        Zeige-Nachricht 'The protection could not be applied: the copy was not found or permissions are missing.' 'OK' 'Warning' | Out-Null
      }
    }
    'Dienst' {
      $t = switch ([string]$e.Ergebnis) {
        'OK'         { 'The service is disabled, atieclxx.exe is no longer running.' }
        'LaeuftNoch' { 'The service is disabled, but atieclxx.exe is still running. After a restart it is off.' }
        'KeinDienst' { 'The service was not found.' }
        default      { 'The service could not be disabled.' }
      }
      Zeige-Nachricht $t 'OK' $(if ([string]$e.Ergebnis -eq 'OK') { 'Information' } else { 'Warning' }) | Out-Null
    }
    'Zurueck' { Zeige-Nachricht ('All changes have been undone.' + $script:NL + 'The program folder is kept. To remove everything: REMOVE.cmd.') 'OK' 'Information' | Out-Null }
  }
}

# ------------------------------------------------------------------ Buttons
function Fehler-Anzeigen($Fehler) { Set-Bedienbar $true; Zeige-Nachricht ('Unexpected error: ' + $Fehler.Exception.Message) 'OK' 'Error' | Out-Null }
function Klick-Pruefen { try { Start-Hintergrund 'Analyse' } catch { Fehler-Anzeigen $_ } }
function Klick-Schutz { try { Start-Hintergrund 'Schutz' } catch { Fehler-Anzeigen $_ } }
function Klick-Dienst {
  try {
    $r = Zeige-Nachricht ('Disable the "AMD External Events Utility" service?' + $script:NL + $script:NL +
      'This reliably stops the writing, but may affect FreeSync and frame pacing. You can undo it at any time with "Undo everything".') 'YesNo' 'Warning'
    if ($r -eq 'Yes') { Start-Hintergrund 'Dienst' }
  } catch { Fehler-Anzeigen $_ }
}
function Klick-Zurueck {
  try {
    $r = Zeige-Nachricht 'Undo all changes (protection, automatic task, disabled service)?' 'YesNo' 'Question'
    if ($r -eq 'Yes') { Start-Hintergrund 'Zurueck' }
  } catch { Fehler-Anzeigen $_ }
}
function Klick-ReBar {
  Zeige-Nachricht ('Resizable BAR (called "Smart Access Memory" by AMD) lets the processor access the entire graphics memory at once and gives a little more performance in many games.' + $script:NL + $script:NL +
    'The article suggests turning off Resizable BAR in the BIOS, because the bug is in the Smart Access Memory part of the driver. This can help, but costs performance depending on the game and can only be changed in the BIOS, not from here.' + $script:NL + $script:NL +
    'Targeted protection solves the problem without touching Resizable BAR.') 'OK' 'Information' 'What is Resizable BAR?' | Out-Null
}
function Klick-Protokoll {
  if (Test-Path -LiteralPath $script:ProtokollDatei) { Start-Process notepad.exe -ArgumentList ('"' + $script:ProtokollDatei + '"') }
  else { Zeige-Nachricht 'There is no log yet.' | Out-Null }
}
function Klick-Hilfe {
  $datei = Join-Path (Split-Path -Parent $script:SkriptDir) 'README.txt'
  if (-not (Test-Path -LiteralPath $datei)) { $datei = Join-Path $script:InstallDir 'README.txt' }
  if (Test-Path -LiteralPath $datei) { Start-Process notepad.exe -ArgumentList ('"' + $datei + '"') }
  else { Zeige-Nachricht 'The instructions (README.txt) were not found.' | Out-Null }
}
function Beim-Schliessen($e) {
  if ($script:Async -and $script:Async.Aktion -ne 'Analyse') {
    Zeige-Nachricht 'Please wait until the current action has finished.' | Out-Null
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
      # Restart with administrator rights (same PowerShell version).
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = (Get-Process -Id $PID).Path
      $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "' + $PSCommandPath + '"'
      $psi.Verb = 'runas'
      $psi.UseShellExecute = $true
      try { [void][System.Diagnostics.Process]::Start($psi) } catch {}   # Windows prompt declined
      return
    }
    $neu = $false
    $script:Mutex = New-Object System.Threading.Mutex($true, 'Global\Radeon-atieclxx-SSD-Fix-Oberflaeche', [ref]$neu)
    if (-not $neu) {
      [void][System.Windows.Forms.MessageBox]::Show('Radeon-atieclxx-SSD-Fix is already open.', 'Radeon-atieclxx-SSD-Fix', 'OK', 'Information')
      $script:Mutex.Dispose()
      $script:Mutex = $null
      return
    }
    & logman stop $script:TraceName -ets *> $null    # end leftovers of an aborted trace
    $form = Build-Form
    $form.Add_Shown({ $this.Activate(); Start-Hintergrund 'Analyse' })
    [void]$form.ShowDialog()
  } catch {
    $text = 'Radeon-atieclxx-SSD-Fix could not be started:' + $script:NL + $_.Exception.Message
    try { Add-Content -LiteralPath (Join-Path $env:TEMP 'Radeon-atieclxx-SSD-Fix-Error.txt') -Value ((Get-Date -Format s) + '  ' + $_.Exception.ToString()) -Encoding UTF8 } catch {}
    try { [void][System.Windows.Forms.MessageBox]::Show($text, 'Radeon-atieclxx-SSD-Fix', 'OK', 'Error') } catch {}
  } finally {
    if (Test-IstAdmin) { Stop-Hintergrund }
    if ($script:Timer) { try { $script:Timer.Dispose() } catch {} }
    if ($script:Mutex) { try { $script:Mutex.ReleaseMutex() } catch {}; try { $script:Mutex.Dispose() } catch {} }
  }
}
