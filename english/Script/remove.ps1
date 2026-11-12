# Radeon-atieclxx-SSD-Fix – removal (started with administrator rights by REMOVE.cmd).
# Undoes all changes and deletes the program folder.
. (Join-Path $PSScriptRoot 'Core.ps1')
if (-not (Test-IstAdmin)) { Write-Host 'Please start this via REMOVE.cmd (administrator rights needed).' -ForegroundColor Red; return }
Write-Host ('Radeon-atieclxx-SSD-Fix ' + $script:Version + ' - Remove')
Write-Host ''
Remove-Alles
& logman stop $script:TraceName -ets *> $null
Write-Host ('Task:       ' + $(if (Get-ScheduledTask -TaskName $script:AufgabeName -ErrorAction SilentlyContinue) { 'still present!' } else { 'removed' }))
Write-Host ('Protection: ' + $(if (Test-Schutz) { 'still active!' } else { 'removed' }))
Write-Host ('Service:    ' + (Get-DienstText (Get-AmdDienst)))
if (Test-Path -LiteralPath $script:InstallDir) {
  $vonDrinnen = $PSScriptRoot.StartsWith($script:InstallDir + '\', [StringComparison]::OrdinalIgnoreCase)
  if ($vonDrinnen) {
    # Running from the program folder: delete it only after this window has been closed.
    $warte = $PID
    try {
      $ich = Get-CimInstance Win32_Process -Filter "ProcessId=$PID"
      $eltern = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $ich.ParentProcessId)
      if ($eltern -and $eltern.Name -eq 'cmd.exe') { $warte = [int]$eltern.ProcessId }
    } catch {}
    $befehl = 'Wait-Process -Id ' + $warte + ' -ErrorAction SilentlyContinue; Start-Sleep -Seconds 1; Remove-Item -LiteralPath ''' + $script:InstallDir + ''' -Recurse -Force -ErrorAction SilentlyContinue'
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($befehl))
    Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList ('-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand ' + $enc) -WindowStyle Hidden -WorkingDirectory $env:SystemRoot
    Write-Host ('Folder:     will be deleted after this window is closed (' + $script:InstallDir + ')')
  } else {
    Remove-Item -LiteralPath $script:InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host ('Folder:     ' + $(if (Test-Path -LiteralPath $script:InstallDir) { 'could not be deleted' } else { 'deleted' }))
  }
}
Write-Host ''
Write-Host 'Everything has been undone. With affected drivers, atieclxx.exe now copies itself every second again.' -ForegroundColor Yellow
