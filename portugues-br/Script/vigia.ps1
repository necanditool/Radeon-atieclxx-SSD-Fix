# Radeon-atieclxx-SSD-Fix – vigia. Roda como SYSTEM pela tarefa "Radeon-atieclxx-SSD-Fix" (3 minutos após a inicialização e a cada 30 minutos).
# Mantém a proteção direcionada atualizada e, após uma troca de driver, verifica se a AMD corrigiu o bug.
. (Join-Path $PSScriptRoot 'Nucleo.ps1')

$proz = Get-AmdProzess
if (-not $proz) { return }   # serviço não está em execução (p. ex. desativado): nada a fazer
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
  if ($gleich) { return }                                   # caso normal: proteção ativa, driver inalterado
  if (-not $z) { Merken 'Fehler'; Write-Protokoll ('Vigia configurado, proteção ativa (driver ' + $kennung + ').'); return }
  # Driver trocado: remover a proteção brevemente e medir se o bug ainda existe.
  Remove-Schutz | Out-Null
  $b = Measure-Schreibrate 8
  if ($b -lt 0) { Set-Schutz | Out-Null; return }
  if ($b -lt $script:SchreibGrenze) {
    Merken 'Behoben'
    Write-Protokoll ('Novo driver (' + $kennung + '): sem gravação contínua (' + (KB $b) + '). A AMD corrigiu o bug, a proteção continua removida.')
    return
  }
  $ok = Set-Schutz
  Start-Sleep -Seconds 2
  $n = Measure-Schreibrate 8
  if ($ok -and $n -ge 0 -and $n -lt $script:SchreibGrenze) {
    Merken 'Fehler'
    Write-Protokoll ('Novo driver (' + $kennung + '): o bug continua (' + (KB $b) + '), proteção aplicada de novo, depois ' + (KB $n) + '.')
  } else {
    Merken 'Andere'
    Write-Protokoll ('AVISO: o novo driver (' + $kennung + ') continua gravando apesar da proteção (' + (KB $n) + '). Abra o Radeon-atieclxx-SSD-Fix e escolha "Desativar serviço".')
    Send-Meldung 'Radeon-atieclxx-SSD-Fix: o driver AMD continua gravando no SSD apesar da proteção. Abra o Radeon-atieclxx-SSD-Fix e escolha "Desativar serviço".'
  }
  return
}

# Nenhuma proteção ativa (p. ex. após uma atualização do driver que substituiu o arquivo): medir.
$b = Measure-Schreibrate 8
if ($b -lt 0) { return }
if ($b -lt $script:SchreibGrenze) {
  if (-not ($gleich -and $z.Befund -eq 'Behoben')) { Merken 'Behoben'; Write-Protokoll ('Sem gravação contínua (' + (KB $b) + ', driver ' + $kennung + '), nada a fazer.') }
  return
}
if ($gleich -and $z.Befund -eq 'Andere') { return }       # já informado para este driver
$ok = Set-Schutz
$n = $b
if ($ok) { Start-Sleep -Seconds 2; $n = Measure-Schreibrate 8 }
if ($ok -and $n -ge 0 -and $n -lt $script:SchreibGrenze) {
  Save-SchutzBefund -Art 'Schutz' -RateVorher $b
  Merken 'Fehler'
  Write-Protokoll ('Bug detectado (' + (KB $b) + ', driver ' + $kennung + '), proteção aplicada, depois ' + (KB $n) + '.')
} else {
  Merken 'Andere'
  Write-Protokoll ('AVISO: o atieclxx.exe grava continuamente (' + (KB $b) + '), a proteção direcionada não funciona aqui. Abra o Radeon-atieclxx-SSD-Fix e escolha "Desativar serviço".')
  Send-Meldung 'Radeon-atieclxx-SSD-Fix: o driver AMD grava continuamente no SSD e a proteção direcionada não funciona aqui. Abra o Radeon-atieclxx-SSD-Fix e escolha "Desativar serviço".'
}
