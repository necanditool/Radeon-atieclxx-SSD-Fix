# Radeon-atieclxx-SSD-Fix – janela com análise, estimativa de desgaste e botões de correção.
# Iniciada pelo INICIAR.cmd (com direitos de administrador). As medições rodam em segundo plano, a janela continua utilizável.
# Teste: $Global:AMDFIX_NOSHOW = $true; $Global:AMDFIX_TEST = $true; . .\Janela.ps1; $f = Build-Form
$script:SkriptDir = $PSScriptRoot
$script:KernDatei = Join-Path $PSScriptRoot 'Nucleo.ps1'
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

# Roda em um runspace próprio: executa a ação e depois analisa de novo.
$script:HintergrundSkript = {
  param($kern, $aktion, $quelle, $rateVorher, $sync)
  . $kern
  $script:Fortschritt = $sync
  $ergebnis = @{}
  switch ($aktion) {
    'Schutz' {
      Set-Phase 'Aplicando a proteção direcionada'
      $ok = Set-Schutz
      $auf = $false
      if ($ok) {
        Save-SchutzBefund -Art 'Schutz' -RateVorher $rateVorher -ErlaubeAnnahme
        Set-Phase 'Configurando a tarefa automática'
        $auf = Install-Aufgabe -Quelle $quelle
        Write-Protokoll 'Proteção direcionada aplicada pela janela.'
      }
      $ergebnis = @{ Ok = $ok; Aufgabe = $auf }
    }
    'Dienst' {
      Set-Phase 'Desativando o serviço'
      $r = Disable-Dienst
      if ($r -eq 'OK' -or $r -eq 'LaeuftNoch') {
        Save-SchutzBefund -Art 'Dienst' -RateVorher $rateVorher
        Write-Protokoll 'Serviço desativado pela janela.'
      }
      $ergebnis = @{ Ergebnis = $r }
    }
    'Zurueck' {
      Set-Phase 'Desfazendo todas as alterações'
      Remove-Alles
      Write-Protokoll 'Todas as alterações desfeitas pela janela.'
      $ergebnis = @{ Ok = $true }
    }
  }
  $analyse = Get-Analyse -MessSekunden 8
  [pscustomobject]@{ Aktion = $aktion; Ergebnis = $ergebnis; Analyse = $analyse }
}

# ------------------------------------------------------------------ Funções auxiliares
function Zeige-Nachricht {
  param([string]$Text, [string]$Knoepfe = 'OK', [string]$Symbol = 'Information', [string]$Titel = 'Radeon-atieclxx-SSD-Fix')
  if ($Global:AMDFIX_TEST) { [void]$script:TestMeldungen.Add($Text); if ($Knoepfe -eq 'YesNo') { return 'Yes' }; return 'OK' }
  $f = $script:Ctrl.Form
  if ($f -and -not $f.IsDisposed -and $f.Visible) { return [string][System.Windows.Forms.MessageBox]::Show($f, $Text, $Titel, $Knoepfe, $Symbol) }
  return [string][System.Windows.Forms.MessageBox]::Show($Text, $Titel, $Knoepfe, $Symbol)
}
function Format-Rate([double]$b) {
  if ($b -lt 0) { return 'não mensurável' }
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

# ------------------------------------------------------------------ Janela
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

  $kopf = New-Beschriftung $f 18 14 624 32 'Analisando ...'
  $kopf.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
  $kopf.ForeColor = $script:Farbe.Grau
  $unter = New-Beschriftung $f 20 48 624 20 'Aguarde um momento'
  $unter.ForeColor = $script:Farbe.Grau

  $g1 = New-Gruppe $f 18 74 624 134 'Qual bug está presente?'
  $befund = New-Beschriftung $g1 14 22 596 104
  $g2 = New-Gruppe $f 18 214 624 160 'Desgaste do SSD até agora (estimativa)'
  $schaden = New-Beschriftung $g2 14 22 596 130
  $g3 = New-Gruppe $f 18 380 624 168 'Escolha uma correção'
  $btnSchutz = New-Knopf $g3 16 26 250 40 'Proteção direcionada (recomendada)'
  $l1 = New-Beschriftung $g3 276 26 334 42 'Interrompe só a autocópia. O serviço, o FreeSync e o frame pacing continuam funcionando.'
  $btnDienst = New-Knopf $g3 16 74 250 38 'Desativar serviço'
  $l2 = New-Beschriftung $g3 276 74 334 40 'Opção do artigo: sempre funciona, mas pode afetar o FreeSync e o frame pacing.'
  $btnZurueck = New-Knopf $g3 16 120 250 36 'Desfazer tudo'
  $l3 = New-Beschriftung $g3 276 120 334 40 'Remove a proteção, a tarefa automática e a desativação do serviço.'
  foreach ($l in $l1, $l2, $l3) { $l.ForeColor = $script:Farbe.Grau }

  $btnPruefen = New-Knopf $f 18 558 140 30 'Verificar de novo'
  $btnReBar = New-Knopf $f 166 558 180 30 'O que é Resizable BAR?'
  $btnProt = New-Knopf $f 354 558 130 30 'Registro'
  $btnHilfe = New-Knopf $f 492 558 150 30 'Instruções'
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
    KeinDienst            = @('Não afetado: sem AMD External Events Utility', 'Gruen')
    DienstAus             = @('Parado: o serviço está desativado', 'Gruen')
    DienstGestoppt        = @('O serviço não está em execução agora', 'Grau')
    MessungFehlgeschlagen = @('Não foi possível medir', 'Orange')
    Geschuetzt            = @('Protegido: a proteção direcionada está ativa', 'Gruen')
    NichtBetroffen        = @('Este PC não está afetado', 'Gruen')
    BetroffenSelbstkopie  = @('Afetado: gravação contínua no SSD', 'Rot')
    BetroffenAndere       = @('Afetado: gravação contínua em outro local', 'Rot')
    SchutzWirktNicht      = @('Atenção: a proteção não funciona aqui', 'Rot')
  }[[string]$a.Status]
  if (-not $kopf) { $kopf = @([string]$a.Status, 'Grau') }
  $c.Kopf.Text = $kopf[0]
  $c.Kopf.ForeColor = $script:Farbe[$kopf[1]]
  $c.Unter.Text = 'Medido às ' + $a.Zeit.ToString('HH:mm:ss') + '  –  ' + $(if ($a.Rate -lt 0) { 'atieclxx.exe não está em execução' } else { 'atieclxx.exe grava ' + (Format-Rate $a.Rate) })

  $z = New-Object System.Collections.ArrayList
  switch ([string]$a.Status) {
    'BetroffenSelbstkopie' {
      [void]$z.Add('atieclxx.exe se copia continuamente (cerca de uma vez por segundo) para:')
      [void]$z.Add('    ' + $script:ZielDatei)
      [void]$z.Add('Este é o bug conhecido. A proteção direcionada interrompe exatamente esta cópia.')
    }
    'BetroffenAndere' {
      [void]$z.Add('atieclxx.exe grava continuamente, mas não no local conhecido. Encontrado:')
      if (@($a.Ziele).Count) { foreach ($p in @($a.Ziele)) { [void]$z.Add('    ' + $p) } } else { [void]$z.Add('    (não foi possível determinar o destino)') }
      [void]$z.Add('A proteção direcionada não serve aqui. Recomendado: desativar o serviço.')
    }
    'SchutzWirktNicht' {
      [void]$z.Add('A proteção direcionada está ativa, mas a cópia continua sendo gravada:')
      [void]$z.Add('    ' + $script:ZielDatei)
      [void]$z.Add('Recomendado: desativar o serviço.')
    }
    'Geschuetzt' {
      [void]$z.Add('A conta SYSTEM não pode mais sobrescrever a cópia:')
      [void]$z.Add('    ' + $script:ZielDatei)
      [void]$z.Add('A autocópia falha imediatamente, o serviço continua funcionando normalmente.')
      [void]$z.Add('Tarefa automática após atualizações do driver: ' + $(if ($a.Aufgabe) { 'configurada' } else { 'ausente - configure com "Proteção direcionada"' }))
    }
    'DienstAus' {
      [void]$z.Add('O serviço "AMD External Events Utility" está desativado. O atieclxx.exe não está em execução e não grava nada.')
      [void]$z.Add('Desvantagem: o FreeSync e o frame pacing podem ser afetados. Para desfazer: "Desfazer tudo".')
    }
    'NichtBetroffen' { [void]$z.Add('O atieclxx.exe está em execução, mas não grava continuamente. Nenhuma ação é necessária.') }
    'DienstGestoppt' { [void]$z.Add('O serviço está instalado, mas não está em execução agora. Verifique de novo mais tarde.') }
    'KeinDienst' { [void]$z.Add('Este PC não tem "AMD External Events Utility". Ele não é afetado por este bug.') }
    'MessungFehlgeschlagen' { [void]$z.Add('O atieclxx.exe foi encerrado ou reiniciado durante a medição. Verifique de novo.') }
  }
  $c.Befund.Text = ($z -join $script:NL)
  $c.Befund.ForeColor = $(if ($a.Betroffen) { $script:Farbe.Rot } else { $script:Farbe.Text })

  $s = $a.Schaden
  $ssdName = $(if ($a.Ssd -and $a.Ssd.Modell) { [string]$a.Ssd.Modell } else { 'Unidade do sistema' })
  $d = New-Object System.Collections.ArrayList
  if (-not $s) {
    [void]$d.Add('Nenhuma gravação contínua detectada - este bug não causou desgaste mensurável.')
    if ($a.Ssd -and $a.Ssd.Wear) { [void]$d.Add(('Desgaste total do SSD informado pela unidade: {0} %.' -f $a.Ssd.Wear)) }
  } else {
    $bis = $(if ($s.Aktiv) { 'hoje' } else { $s.Ende.ToString('dd/MM/yyyy') })
    $woher = $(if ($s.StundenQuelle -eq 'SSD') { 'segundo o SSD' } else { 'valor presumido' })
    [void]$d.Add(('Período: {0} a {1} ({2} dias), {3:N1} horas de uso por dia ({4}).' -f $s.Seit.ToString('dd/MM/yyyy'), $bis, $s.Tage, $s.StundenProTag, $woher))
    [void]$d.Add(('Gravado sem necessidade: cerca de {0} ({1}).' -f (Format-Menge $s.Bytes), $ssdName))
    if ($s.ProzentTbw) { [void]$d.Add(('Cerca de {0:N2} % da garantia de gravação usual deste SSD (cerca de {1:N0} TB).' -f $s.ProzentTbw, $s.TbwTB)) }
    if ($s.Wear) { [void]$d.Add(('Desgaste total do SSD informado pela unidade: {0} %.' -f $s.Wear)) }
    if ($s.Aktiv) { [void]$d.Add(('Enquanto o bug estiver ativo, são acrescentados cerca de {0:N0} GB por dia.' -f $s.GbProTag)) }
    else { [void]$d.Add('Nada foi acrescentado desde a correção.') }
    if ($s.Basis -eq 'Annahme') { [void]$d.Add('Taxa antes da proteção desconhecida, presumido: uma cópia por segundo.') }
    [void]$d.Add('Estimativa a partir da taxa de gravação e do tempo de uso desde a instalação da placa de vídeo AMD.')
  }
  $c.Schaden.Text = ($d -join $script:NL)

  $c.Fuss.Text = 'Serviço: ' + (Get-DienstText $a.Dienst) + '   |   Proteção: ' + $(if ($a.Schutz) { 'ativa' } else { 'inativa' }) + '   |   Automática: ' + $(if ($a.Aufgabe) { 'sim' } else { 'não' }) + '   |   ' + $ssdName
  Setze-Knoepfe $a
}

# ------------------------------------------------------------------ Trabalho em segundo plano
function Start-Hintergrund([string]$Aktion) {
  if ($script:Async) { return }
  $c = $script:Ctrl
  Set-Bedienbar $false
  $titel = @{ Analyse = 'Analisando ...'; Schutz = 'Aplicando a proteção direcionada ...'; Dienst = 'Desativando o serviço ...'; Zurueck = 'Desfazendo tudo ...' }[$Aktion]
  $c.Kopf.Text = $titel
  $c.Kopf.ForeColor = $script:Farbe.Grau
  $c.Unter.Text = 'Aguarde um momento'
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
            if ($sek -gt 0 -and $sek -lt 3600) { $text = $ph + ' - faltam ' + [math]::Ceiling($sek) + ' s' }
          }
          $script:Ctrl.Unter.Text = $text
        }
      } catch {}   # uma exibição de progresso com erro nunca pode interromper o trabalho em andamento
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
      $script:Ctrl.Kopf.Text = 'A análise falhou'
      $script:Ctrl.Kopf.ForeColor = $script:Farbe.Orange
      $script:Ctrl.Unter.Text = 'Tente "Verificar de novo"'
      Set-Bedienbar $true
      Zeige-Nachricht ('A análise falhou.' + $script:NL + $fehler) 'OK' 'Warning' | Out-Null
      return
    }
    $script:Letzte = $paket.Analyse
    Refresh-Ansicht $paket.Analyse
    Melde-Aktion $paket
  } catch {
    # Se o trabalho em segundo plano ainda estiver rodando, continuar esperando em vez de perdê-lo
    # (senão duas ações poderiam se sobrepor).
    $a = $script:Async
    if ($a -and -not $a.Handle.IsCompleted) { return }
    try { $script:Timer.Stop() } catch {}
    if ($a) { try { $a.PS.Dispose(); $a.RS.Close(); $a.RS.Dispose() } catch {} }
    $script:Async = $null
    Set-Bedienbar $true
    Zeige-Nachricht ('Erro inesperado: ' + $_.Exception.Message) 'OK' 'Error' | Out-Null
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
  & logman stop $script:TraceName -ets *> $null   # caso um rastreamento estivesse rodando
}
function Melde-Aktion($p) {
  $e = $p.Ergebnis
  switch ([string]$p.Aktion) {
    'Schutz' {
      if ($e.Ok) {
        $auto = $(if ($e.Aufgabe) { 'A tarefa automática está configurada: ela verifica na inicialização e a cada 30 minutos, aplica a proteção de novo após atualizações do driver e a remove assim que a AMD corrigir o bug.' }
                  else { 'Não foi possível configurar a tarefa automática. A proteção continua funcionando até que uma atualização do driver substitua o arquivo.' })
        Zeige-Nachricht ('Proteção direcionada aplicada. A autocópia foi interrompida, o serviço continua funcionando.' + $script:NL + $script:NL + $auto) 'OK' 'Information' | Out-Null
      } else {
        Zeige-Nachricht 'Não foi possível aplicar a proteção: a cópia não foi encontrada ou faltam permissões.' 'OK' 'Warning' | Out-Null
      }
    }
    'Dienst' {
      $t = switch ([string]$e.Ergebnis) {
        'OK'         { 'O serviço está desativado, o atieclxx.exe não está mais em execução.' }
        'LaeuftNoch' { 'O serviço está desativado, mas o atieclxx.exe ainda está em execução. Depois de reiniciar, ele estará desligado.' }
        'KeinDienst' { 'O serviço não foi encontrado.' }
        default      { 'Não foi possível desativar o serviço.' }
      }
      Zeige-Nachricht $t 'OK' $(if ([string]$e.Ergebnis -eq 'OK') { 'Information' } else { 'Warning' }) | Out-Null
    }
    'Zurueck' { Zeige-Nachricht ('Todas as alterações foram desfeitas.' + $script:NL + 'A pasta do programa é mantida. Para remover tudo: REMOVER.cmd.') 'OK' 'Information' | Out-Null }
  }
}

# ------------------------------------------------------------------ Botões
function Fehler-Anzeigen($Fehler) { Set-Bedienbar $true; Zeige-Nachricht ('Erro inesperado: ' + $Fehler.Exception.Message) 'OK' 'Error' | Out-Null }
function Klick-Pruefen { try { Start-Hintergrund 'Analyse' } catch { Fehler-Anzeigen $_ } }
function Klick-Schutz { try { Start-Hintergrund 'Schutz' } catch { Fehler-Anzeigen $_ } }
function Klick-Dienst {
  try {
    $r = Zeige-Nachricht ('Desativar o serviço "AMD External Events Utility"?' + $script:NL + $script:NL +
      'Isso interrompe a gravação com segurança, mas pode afetar o FreeSync e o frame pacing. Você pode desfazer a qualquer momento com "Desfazer tudo".') 'YesNo' 'Warning'
    if ($r -eq 'Yes') { Start-Hintergrund 'Dienst' }
  } catch { Fehler-Anzeigen $_ }
}
function Klick-Zurueck {
  try {
    $r = Zeige-Nachricht 'Desfazer todas as alterações (proteção, tarefa automática, desativação do serviço)?' 'YesNo' 'Question'
    if ($r -eq 'Yes') { Start-Hintergrund 'Zurueck' }
  } catch { Fehler-Anzeigen $_ }
}
function Klick-ReBar {
  Zeige-Nachricht ('O Resizable BAR (na AMD, "Smart Access Memory") permite que o processador acesse toda a memória de vídeo de uma vez e traz um pouco mais de desempenho em muitos jogos.' + $script:NL + $script:NL +
    'O artigo sugere desligar o Resizable BAR na BIOS, porque o bug está na parte Smart Access Memory do driver. Isso pode ajudar, mas custa desempenho dependendo do jogo e só pode ser alterado na BIOS, não daqui.' + $script:NL + $script:NL +
    'A proteção direcionada resolve o problema sem mexer no Resizable BAR.') 'OK' 'Information' 'O que é Resizable BAR?' | Out-Null
}
function Klick-Protokoll {
  if (Test-Path -LiteralPath $script:ProtokollDatei) { Start-Process notepad.exe -ArgumentList ('"' + $script:ProtokollDatei + '"') }
  else { Zeige-Nachricht 'Ainda não há registro.' | Out-Null }
}
function Klick-Hilfe {
  $datei = Join-Path (Split-Path -Parent $script:SkriptDir) 'LEIAME.txt'
  if (-not (Test-Path -LiteralPath $datei)) { $datei = Join-Path $script:InstallDir 'LEIAME.txt' }
  if (Test-Path -LiteralPath $datei) { Start-Process notepad.exe -ArgumentList ('"' + $datei + '"') }
  else { Zeige-Nachricht 'As instruções (LEIAME.txt) não foram encontradas.' | Out-Null }
}
function Beim-Schliessen($e) {
  if ($script:Async -and $script:Async.Aktion -ne 'Analyse') {
    Zeige-Nachricht 'Aguarde até que a ação atual termine.' | Out-Null
    $e.Cancel = $true
    return
  }
  $script:Beenden = $true
  Stop-Hintergrund
}

# ------------------------------------------------------------------ Início
if (-not $Global:AMDFIX_NOSHOW) {
  try {
    if (-not (Test-IstAdmin)) {
      # Reinicia com direitos de administrador (mesma versão do PowerShell).
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = (Get-Process -Id $PID).Path
      $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "' + $PSCommandPath + '"'
      $psi.Verb = 'runas'
      $psi.UseShellExecute = $true
      try { [void][System.Diagnostics.Process]::Start($psi) } catch {}   # solicitação do Windows recusada
      return
    }
    $neu = $false
    $script:Mutex = New-Object System.Threading.Mutex($true, 'Global\Radeon-atieclxx-SSD-Fix-Oberflaeche', [ref]$neu)
    if (-not $neu) {
      [void][System.Windows.Forms.MessageBox]::Show('O Radeon-atieclxx-SSD-Fix já está aberto.', 'Radeon-atieclxx-SSD-Fix', 'OK', 'Information')
      $script:Mutex.Dispose()
      $script:Mutex = $null
      return
    }
    & logman stop $script:TraceName -ets *> $null    # encerra restos de um rastreamento interrompido
    $form = Build-Form
    $form.Add_Shown({ $this.Activate(); Start-Hintergrund 'Analyse' })
    [void]$form.ShowDialog()
  } catch {
    $text = 'Não foi possível iniciar o Radeon-atieclxx-SSD-Fix:' + $script:NL + $_.Exception.Message
    try { Add-Content -LiteralPath (Join-Path $env:TEMP 'Radeon-atieclxx-SSD-Fix-Erro.txt') -Value ((Get-Date -Format s) + '  ' + $_.Exception.ToString()) -Encoding UTF8 } catch {}
    try { [void][System.Windows.Forms.MessageBox]::Show($text, 'Radeon-atieclxx-SSD-Fix', 'OK', 'Error') } catch {}
  } finally {
    if (Test-IstAdmin) { Stop-Hintergrund }
    if ($script:Timer) { try { $script:Timer.Dispose() } catch {} }
    if ($script:Mutex) { try { $script:Mutex.ReleaseMutex() } catch {}; try { $script:Mutex.Dispose() } catch {} }
  }
}
