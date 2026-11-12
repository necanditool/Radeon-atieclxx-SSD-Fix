# Radeon-atieclxx-SSD-Fix – status rápido, sem direitos de administrador.
. (Join-Path $PSScriptRoot 'Nucleo.ps1')
Write-Host ('Radeon-atieclxx-SSD-Fix ' + $script:Version + ' - Status')
Write-Host ''
$t = Get-ScheduledTask -TaskName $script:AufgabeName -ErrorAction SilentlyContinue
$eingerichtet = [bool]$t -or (Test-Path -LiteralPath (Join-Path $script:InstallDir 'Script\vigia.ps1'))
if ($t) {
  $i = $null
  try { $i = Get-ScheduledTaskInfo -TaskName $script:AufgabeName -ErrorAction Stop } catch {}
  Write-Host 'Tarefa automática: configurada' -ForegroundColor Green
  if ($i) {
    $letzter = $(if ($i.LastRunTime -and $i.LastRunTime.Year -ge 2000) { $i.LastRunTime.ToString('dd/MM/yyyy HH:mm') } else { 'ainda não' })
    $naechster = $(if ($i.NextRunTime) { $i.NextRunTime.ToString('dd/MM/yyyy HH:mm') } else { 'desconhecida' })
    Write-Host ('  última execução: ' + $letzter + '   próxima execução: ' + $naechster)
  }
} elseif ($eingerichtet) { Write-Host 'Tarefa automática: configurada (detalhes só com direitos de administrador)' -ForegroundColor Green }
else { Write-Host 'Tarefa automática: não configurada' -ForegroundColor Yellow }
Write-Host ('Serviço:           ' + (Get-DienstText (Get-AmdDienst)))
if (Test-Path -LiteralPath $script:ProtokollDatei) {
  Write-Host 'Últimas entradas do registro:'
  Get-Content -LiteralPath $script:ProtokollDatei -Tail 5 -Encoding UTF8 | ForEach-Object { Write-Host ('  ' + $_) }
}
Write-Host ''
if (-not (Get-AmdProzess)) { Write-Host 'O atieclxx.exe não está em execução - sem carga de gravação.' -ForegroundColor Green; return }
Write-Host 'Medindo por 10 segundos ...'
$rate = Measure-Schreibrate 10
if ($rate -lt 0) { Write-Host 'O atieclxx.exe foi encerrado durante a medição.'; return }
Write-Host ('O atieclxx.exe grava {0:N0} KB/s (cerca de {1:N1} GB por dia em funcionamento contínuo)' -f ($rate / 1KB), ($rate * 86400 / 1e9))
if ($rate -ge $script:SchreibGrenze) {
  if ($eingerichtet) { Write-Host 'AFETADO: o atieclxx.exe grava continuamente. A tarefa automática age na próxima execução; para corrigir agora: INICIAR.cmd.' -ForegroundColor Red }
  else { Write-Host 'AFETADO: o atieclxx.exe grava continuamente. Execute INICIAR.cmd e escolha uma correção.' -ForegroundColor Red }
} else { Write-Host 'OK: sem gravação contínua.' -ForegroundColor Green }
