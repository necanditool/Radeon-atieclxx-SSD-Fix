# Radeon-atieclxx-SSD-Fix – remoção (iniciada com direitos de administrador pelo REMOVER.cmd).
# Desfaz todas as alterações e exclui a pasta do programa.
. (Join-Path $PSScriptRoot 'Nucleo.ps1')
if (-not (Test-IstAdmin)) { Write-Host 'Inicie pelo REMOVER.cmd (são necessários direitos de administrador).' -ForegroundColor Red; return }
Write-Host ('Radeon-atieclxx-SSD-Fix ' + $script:Version + ' - Remover')
Write-Host ''
Remove-Alles
& logman stop $script:TraceName -ets *> $null
Write-Host ('Tarefa:    ' + $(if (Get-ScheduledTask -TaskName $script:AufgabeName -ErrorAction SilentlyContinue) { 'ainda existe!' } else { 'removida' }))
Write-Host ('Proteção:  ' + $(if (Test-Schutz) { 'ainda ativa!' } else { 'removida' }))
Write-Host ('Serviço:   ' + (Get-DienstText (Get-AmdDienst)))
if (Test-Path -LiteralPath $script:InstallDir) {
  $vonDrinnen = $PSScriptRoot.StartsWith($script:InstallDir + '\', [StringComparison]::OrdinalIgnoreCase)
  if ($vonDrinnen) {
    # Rodando a partir da pasta do programa: excluí-la só depois que esta janela for fechada.
    $warte = $PID
    try {
      $ich = Get-CimInstance Win32_Process -Filter "ProcessId=$PID"
      $eltern = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $ich.ParentProcessId)
      if ($eltern -and $eltern.Name -eq 'cmd.exe') { $warte = [int]$eltern.ProcessId }
    } catch {}
    $befehl = 'Wait-Process -Id ' + $warte + ' -ErrorAction SilentlyContinue; Start-Sleep -Seconds 1; Remove-Item -LiteralPath ''' + $script:InstallDir + ''' -Recurse -Force -ErrorAction SilentlyContinue'
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($befehl))
    Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList ('-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand ' + $enc) -WindowStyle Hidden -WorkingDirectory $env:SystemRoot
    Write-Host ('Pasta:     será excluída depois que esta janela for fechada (' + $script:InstallDir + ')')
  } else {
    Remove-Item -LiteralPath $script:InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host ('Pasta:     ' + $(if (Test-Path -LiteralPath $script:InstallDir) { 'não pôde ser excluída' } else { 'excluída' }))
  }
}
Write-Host ''
Write-Host 'Tudo foi desfeito. Com drivers afetados, o atieclxx.exe volta a se copiar a cada segundo.' -ForegroundColor Yellow
