# Radeon-atieclxx-SSD-Fix – core: shared functions for the window, the guard, the status check and removal.
# Included with . (dot-source); loading it changes nothing.
$ErrorActionPreference = 'Continue'

$script:Version        = '2.1'
$script:ZielDatei      = Join-Path $env:SystemRoot 'System32\config\systemprofile\AppData\Local\AMD\atieclxx.exe'
$script:DienstName     = 'AMD External Events Utility'
$script:Name           = 'Radeon-atieclxx-SSD-Fix'
$script:AufgabeName    = $script:Name
$script:InstallDir     = Join-Path $env:ProgramFiles $script:Name
$script:AlterName      = 'AMD-SSD-Fix'   # former name; a task and a folder with this name are removed during setup
$script:AlteInstallDir = Join-Path $env:ProgramFiles $script:AlterName
$script:ProtokollDatei = Join-Path $script:InstallDir 'log.txt'
$script:ZustandDatei   = Join-Path $script:InstallDir 'state.json'
$script:BefundDatei    = Join-Path $script:InstallDir 'record.json'
$script:SystemSid      = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')
$script:TraceName      = 'RadeonSsdFixTrace'
# From this write rate (bytes/s) on, atieclxx.exe counts as affected. The bug writes ~660 KB/s and more;
# a single copy when the service starts (~0.66 MB) stays far below that in the 8-second window (~85 KB/s).
$script:SchreibGrenze  = 150KB

# ------------------------------------------------------------------ Basics
function Test-IstAdmin {
  ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-AmdProzesse { @(Get-Process atieclxx -ErrorAction SilentlyContinue) }
function Get-AmdProzess { Get-AmdProzesse | Select-Object -First 1 }
function Get-AmdDienst {
  # Look up by service name first, then by display name, finally via the program atiesrxx.exe.
  $d = Get-Service -Name $script:DienstName -ErrorAction SilentlyContinue
  if (-not $d) { $d = Get-Service -DisplayName $script:DienstName -ErrorAction SilentlyContinue }
  if (-not $d) {
    $w = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.PathName -match 'atiesrxx\.exe' } | Select-Object -First 1
    if ($w) { $d = Get-Service -Name $w.Name -ErrorAction SilentlyContinue }
  }
  return ($d | Select-Object -First 1)
}
function Get-DienstText($Dienst) {
  if (-not $Dienst) { return 'not installed' }
  $st = switch ([string]$Dienst.Status) { 'Running' { 'running' } 'Stopped' { 'stopped' } 'StartPending' { 'starting' } 'StopPending' { 'stopping' } default { [string]$Dienst.Status } }
  $ty = switch ([string]$Dienst.StartType) { 'Automatic' { 'automatic' } 'Manual' { 'manual' } 'Disabled' { 'disabled' } default { [string]$Dienst.StartType } }
  return ($st + ', ' + $ty)
}
function Write-Protokoll([string]$Text) {
  try {
    New-Item -ItemType Directory -Force -Path $script:InstallDir | Out-Null
    Add-Content -LiteralPath $script:ProtokollDatei -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $Text) -Encoding UTF8
  } catch {}
}
function Send-Meldung([string]$Text) {
  $m = Join-Path $env:SystemRoot 'System32\msg.exe'   # not available on Windows Home
  if (Test-Path -LiteralPath $m) { try { & $m '*' '/TIME:3600' ($Text + ' Details: ' + $script:ProtokollDatei) } catch {} }
}
function Wait-Messung([double]$Sekunden, [string]$Phase) {
  # Waits and reports the progress to the window (if there is one).
  if ($script:Fortschritt) { $script:Fortschritt.Phase = $Phase; $script:Fortschritt.Ende = (Get-Date).AddSeconds($Sekunden) }
  Start-Sleep -Milliseconds ([int]($Sekunden * 1000))
}
function Set-Phase([string]$Phase) {
  if ($script:Fortschritt) { $script:Fortschritt.Phase = $Phase; $script:Fortschritt.Ende = [datetime]::MinValue }
}

# ------------------------------------------------------------------ Windows functions (P/Invoke)
function Initialize-Nativ {
  if ('AmdFix.Nativ' -as [type]) { return }
  Add-Type -Namespace AmdFix -Name Nativ -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern Microsoft.Win32.SafeHandles.SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern uint QueryDosDeviceW(string device, System.Text.StringBuilder target, int max);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool DeviceIoControl(Microsoft.Win32.SafeHandles.SafeFileHandle handle, uint code, IntPtr inBuffer, uint inSize, byte[] outBuffer, uint outSize, out uint returned, IntPtr overlapped);
public static long DateiUsn(string pfad) {
  // FSCTL_READ_FILE_USN_DATA: latest change number of the file in the NTFS change journal.
  using (Microsoft.Win32.SafeHandles.SafeFileHandle h = CreateFileW(pfad, 0x80, 7, IntPtr.Zero, 3, 0x02000000, IntPtr.Zero)) {
    if (h.IsInvalid) return -1;
    byte[] puffer = new byte[1024];
    uint n;
    if (!DeviceIoControl(h, 0x000900EB, IntPtr.Zero, 0, puffer, (uint)puffer.Length, out n, IntPtr.Zero) || n < 48) return -1;
    int version = BitConverter.ToUInt16(puffer, 4);
    return BitConverter.ToInt64(puffer, version >= 3 ? 40 : 24);
  }
}
'@
}
function Get-DateiUsn([string]$Pfad) {
  # Change number in the NTFS change journal; it increases with every write (0/-1 = not available).
  # Timestamps are useless here: CopyFile takes over LastWriteTime and even the NTFS change time from the source.
  try { Initialize-Nativ; return [AmdFix.Nativ]::DateiUsn($Pfad) } catch { return -1 }
}
function Get-LaufwerkZuordnung {
  # \Device\HarddiskVolumeN -> C:
  $karte = @{}
  try {
    Initialize-Nativ
    foreach ($lw in [System.IO.DriveInfo]::GetDrives()) {
      $name = $lw.Name.TrimEnd('\')
      $sb = New-Object System.Text.StringBuilder 1024
      if ([AmdFix.Nativ]::QueryDosDeviceW($name, $sb, 1024) -gt 0) { $karte[$sb.ToString()] = $name }
    }
  } catch {}
  return $karte
}

# ------------------------------------------------------------------ Measuring
function Measure-Schreibrate {
  # Bytes per second written by all atieclxx.exe processes together (-1 = not measurable).
  param([int]$Sekunden = 8)
  $start = @(Get-CimInstance Win32_Process -Filter "Name='atieclxx.exe'" -ErrorAction SilentlyContinue)
  if (-not $start.Count) { return -1 }
  $vorher = @{}
  foreach ($p in $start) { $vorher[[int]$p.ProcessId] = [double]$p.WriteTransferCount }
  Wait-Messung $Sekunden 'Measuring the write rate'
  $summe = 0.0; $gefunden = 0
  foreach ($q in @(Get-CimInstance Win32_Process -Filter "Name='atieclxx.exe'" -ErrorAction SilentlyContinue)) {
    $id = [int]$q.ProcessId
    if ($vorher.ContainsKey($id)) { $summe += [double]$q.WriteTransferCount - $vorher[$id]; $gefunden++ }
  }
  if ($gefunden -eq 0) { return -1 }
  return ($summe / $Sekunden)
}
function Test-Selbstkopie {
  # Is the known copy being rewritten over and over right now? Visible from the USN of the file.
  # Without a change journal (rare) this returns $false; then the ETW trace decides.
  if (-not (Test-Path -LiteralPath $script:ZielDatei)) { return $false }
  $u0 = Get-DateiUsn $script:ZielDatei
  if ($u0 -le 0) { return $false }
  Wait-Messung 3 'Checking for the self-copy'
  $u1 = Get-DateiUsn $script:ZielDatei
  return ($u1 -gt 0 -and $u1 -ne $u0)
}
function Get-TraceZiele {
  # Uses event tracing (ETW) to find out where atieclxx.exe writes. Administrator rights only.
  param([int]$Sekunden = 4)
  if (-not (Test-IstAdmin)) { return @() }
  $ids = @(Get-AmdProzesse | ForEach-Object { $_.Id })
  if (-not $ids.Count) { return @() }
  $etl = Join-Path $env:TEMP ('amdfix-' + [guid]::NewGuid().ToString('N') + '.etl')
  try {
    & logman stop $script:TraceName -ets *> $null
    # Small buffers and a file of at most 64 MB, so that an aborted trace cannot grow out of bounds.
    & logman start $script:TraceName -p Microsoft-Windows-Kernel-File 0x1FB0 0xFF -o $etl -ets -bs 256 -nb 16 64 -max 64 *> $null
    if ($LASTEXITCODE -ne 0) { return @() }
    Wait-Messung $Sekunden 'Finding out where it writes'
    & logman stop $script:TraceName -ets *> $null
    Set-Phase 'Evaluating the trace'
    $filter = ($ids | ForEach-Object { '@ProcessID=' + $_ }) -join ' or '
    $ev = @(Get-WinEvent -Path $etl -Oldest -FilterXPath ('*[System[Execution[' + $filter + ']]]') -ErrorAction Stop)
    $fo = @{}; $treffer = @{}; $offen = @{}
    foreach ($e in $ev) {
      $h = @{}; foreach ($d in ([xml]$e.ToXml()).Event.EventData.Data) { $h[$d.Name] = $d.'#text' }
      $n = $h['FileName']; if (-not $n) { $n = $h['FilePath'] }
      if ($e.Id -eq 12 -and $h['FileObject']) { $fo[$h['FileObject']] = $n }
      if (-not $n -and $h['FileObject'] -and $fo.ContainsKey($h['FileObject'])) { $n = $fo[$h['FileObject']] }
      if ($e.Id -eq 16 -or $e.Id -eq 30) {        # 16 = Write, 30 = CreateNewFile
        if ($n) { $treffer[$n] = 1 + [int]$treffer[$n] }
        elseif ($h['FileKey']) { $offen[$h['FileKey']] = 1 + [int]$offen[$h['FileKey']] }
      }
    }
    if ($offen.Count) {
      # Files opened before the trace started: look up their names via NameCreate events (ID 10).
      foreach ($e in @(Get-WinEvent -Path $etl -Oldest -FilterXPath '*[System[(EventID=10)]]' -ErrorAction SilentlyContinue)) {
        $h = @{}; foreach ($d in ([xml]$e.ToXml()).Event.EventData.Data) { $h[$d.Name] = $d.'#text' }
        $k = $h['FileKey']
        if ($k -and $offen.ContainsKey($k) -and $h['FileName']) { $treffer[$h['FileName']] = [int]$treffer[$h['FileName']] + $offen[$k]; $offen.Remove($k) }
      }
    }
    $karte = Get-LaufwerkZuordnung
    $liste = New-Object System.Collections.ArrayList
    foreach ($kv in ($treffer.GetEnumerator() | Sort-Object Value -Descending)) {
      $p = [string]$kv.Key
      if ($p -match 'DriverStore') { continue }
      foreach ($g in $karte.GetEnumerator()) { if ($p.StartsWith($g.Key + '\', [StringComparison]::OrdinalIgnoreCase)) { $p = $g.Value + $p.Substring($g.Key.Length); break } }
      [void]$liste.Add($p)
    }
    return @($liste | Select-Object -First 5)
  } catch { return @() }
  finally {
    & logman stop $script:TraceName -ets *> $null
    Remove-Item -LiteralPath $etl -Force -ErrorAction SilentlyContinue
  }
}

# ------------------------------------------------------------------ Targeted protection (file permissions)
function Test-Schutz {
  if (-not (Test-Path -LiteralPath $script:ZielDatei)) { return $false }
  try { $acl = Get-Acl -LiteralPath $script:ZielDatei } catch { return $false }
  foreach ($r in $acl.Access) {
    if ($r.AccessControlType -ne 'Deny' -or $r.IsInherited) { continue }
    try { if ($r.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]) -eq $script:SystemSid) { return $true } } catch {}
  }
  return $false
}
function Set-Schutz {
  # Denies only the SYSTEM account overwriting and deleting this one file.
  for ($i = 0; $i -lt 6 -and -not (Test-Path -LiteralPath $script:ZielDatei); $i++) { Start-Sleep -Milliseconds 300 }
  if (-not (Test-Path -LiteralPath $script:ZielDatei)) { return $false }
  & icacls $script:ZielDatei /deny '*S-1-5-18:(WD,AD,WEA,WA,DE)' *> $null
  return (Test-Schutz)
}
function Remove-Schutz {
  if (Test-Path -LiteralPath $script:ZielDatei) { & icacls $script:ZielDatei /remove:d '*S-1-5-18' *> $null }
  return (-not (Test-Schutz))
}

# ------------------------------------------------------------------ Service
function Disable-Dienst {
  # Returns: OK, LaeuftNoch (restart needed), Fehler or KeinDienst
  $d = Get-AmdDienst
  if (-not $d) { return 'KeinDienst' }
  try { Set-Service -Name $d.Name -StartupType Disabled -ErrorAction Stop } catch { return 'Fehler' }
  try { Stop-Service -Name $d.Name -Force -ErrorAction SilentlyContinue } catch {}
  for ($i = 0; $i -lt 20 -and (Get-AmdProzess); $i++) { Start-Sleep -Milliseconds 250 }
  if (Get-AmdProzess) { Get-AmdProzesse | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 700 }
  if (Get-AmdProzess) { return 'LaeuftNoch' }
  return 'OK'
}
function Enable-Dienst {
  $d = Get-AmdDienst
  if (-not $d) { return $false }
  try { Set-Service -Name $d.Name -StartupType Automatic -ErrorAction Stop } catch { return $false }
  try { Start-Service -Name $d.Name -ErrorAction Stop } catch {}
  for ($i = 0; $i -lt 20 -and -not (Get-AmdProzess); $i++) { Start-Sleep -Milliseconds 250 }
  return $true
}

# ------------------------------------------------------------------ SSD, time span, fix record
function Get-SsdInfo {
  $res = [ordered]@{ Modell = ''; Kapazitaet = 0; Wear = $null; PowerOnHours = $null }
  try {
    $pd = Get-Partition -DriveLetter ($env:SystemDrive.TrimEnd(':')) -ErrorAction Stop | Get-Disk -ErrorAction Stop | Get-PhysicalDisk -ErrorAction Stop | Select-Object -First 1
    $res.Modell = [string]$pd.FriendlyName; $res.Kapazitaet = [double]$pd.Size
    try {
      $rc = $pd | Get-StorageReliabilityCounter -ErrorAction Stop
      if ($rc.Wear -gt 0) { $res.Wear = [double]$rc.Wear }                       # many SSDs only report 0 here
      if ($rc.PowerOnHours -gt 0) { $res.PowerOnHours = [double]$rc.PowerOnHours }
    } catch {}
  } catch {}
  [pscustomobject]$res
}
function Get-GpuErstInstall {
  # Earliest first-install date of an AMD graphics card (the bug cannot have happened before that).
  $daten = @()
  try {
    foreach ($d in @(Get-PnpDevice -Class Display -ErrorAction Stop | Where-Object { $_.FriendlyName -match 'Radeon|AMD' })) {
      $p = Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName DEVPKEY_Device_FirstInstallDate -ErrorAction SilentlyContinue
      if ($p -and $p.Data) { $daten += [datetime]$p.Data }
    }
  } catch {}
  if ($daten.Count) { return ($daten | Sort-Object | Select-Object -First 1) }
  return $null
}
function Save-SchutzBefund {
  # Remembers when a fix stopped the writing and how high the rate was before.
  param([string]$Art, [double]$RateVorher, [switch]$ErlaubeAnnahme)
  if (Test-Path -LiteralPath $script:BefundDatei) { return }
  $r = $RateVorher
  if ($r -lt $script:SchreibGrenze) {
    if (-not $ErlaubeAnnahme) { return }
    $r = 0
    if (Test-Path -LiteralPath $script:ZielDatei) { try { $r = [double](Get-Item -LiteralPath $script:ZielDatei -Force).Length } catch {} }
  }
  try {
    New-Item -ItemType Directory -Force -Path $script:InstallDir | Out-Null
    [pscustomobject]@{ Art = $Art; Seit = (Get-Date -Format s); RateVorher = [math]::Round($r) } | ConvertTo-Json | Set-Content -LiteralPath $script:BefundDatei -Encoding UTF8
  } catch {}
}
function Get-SchutzBefund {
  if (-not (Test-Path -LiteralPath $script:BefundDatei)) { return $null }
  try { return (Get-Content -LiteralPath $script:BefundDatei -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}
function Get-Schaden {
  # Estimate: write rate x operating hours since the AMD graphics card was installed.
  param([string]$Status, [double]$Rate, $Ssd, $Befund)
  $einzel = $null
  if (Test-Path -LiteralPath $script:ZielDatei) { try { $einzel = [double](Get-Item -LiteralPath $script:ZielDatei -Force).Length } catch {} }
  $aktiv = $Status -in 'BetroffenSelbstkopie', 'BetroffenAndere', 'SchutzWirktNicht'
  if ($aktiv) { $r = $Rate; $ende = Get-Date; $basis = 'Messung' }
  elseif ($Befund -and $Befund.Seit) { $r = [double]$Befund.RateVorher; $ende = [datetime]$Befund.Seit; $basis = 'Befund' }
  elseif ($Status -eq 'Geschuetzt' -and $einzel) { $r = $einzel; $ende = Get-Date; $basis = 'Annahme' }
  else { return $null }
  if ($r -le 0) { return $null }
  $start = Get-GpuErstInstall
  $osInstall = $null
  try { $osInstall = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).InstallDate } catch {}
  if (-not $start) { $start = $osInstall }
  if (-not $start -or $ende -le $start) { return $null }
  $tage = ($ende - $start).TotalDays
  $poh = if ($Ssd -and $Ssd.PowerOnHours) { [double]$Ssd.PowerOnHours } else { $null }
  # Operating hours per day: from the SSD if plausible (feature updates reset the installation date),
  # otherwise 8 hours as a neutral assumption.
  $hpd = 8.0; $quelle = 'Annahme'
  if ($poh -and $osInstall) {
    $alter = ((Get-Date) - $osInstall).TotalDays
    if ($alter -ge 30) { $x = $poh / $alter; if ($x -ge 1 -and $x -le 16) { $hpd = $x; $quelle = 'SSD' } }
  }
  $stunden = $tage * $hpd
  if ($poh) { $stunden = [math]::Min($stunden, $poh) }
  $bytes = $r * $stunden * 3600
  $tbw = $null
  if ($Ssd -and $Ssd.Kapazitaet -gt 0) { $tbw = [math]::Round($Ssd.Kapazitaet / 1e12, 1) * 600 }   # usual warranty ~600 TBW per TB
  [pscustomobject]@{
    Basis = $basis; Aktiv = $aktiv; Rate = $r; Seit = $start; Ende = $ende; Tage = [int][math]::Round($tage)
    StundenProTag = [math]::Round($hpd, 1); StundenQuelle = $quelle
    Bytes = $bytes; GbProTag = $r * $hpd * 3600 / 1e9
    TbwTB = $tbw; ProzentTbw = $(if ($tbw) { $bytes / 1e12 / $tbw * 100 } else { $null })
    Wear = $(if ($Ssd) { $Ssd.Wear } else { $null })
  }
}

# ------------------------------------------------------------------ Analysis
function Get-Analyse {
  param([int]$MessSekunden = 8)
  Set-Phase 'Reading the system state'
  $dienst  = Get-AmdDienst
  $proz    = Get-AmdProzess
  $schutz  = Test-Schutz
  $aufgabe = [bool](Get-ScheduledTask -TaskName $script:AufgabeName -ErrorAction SilentlyContinue)
  $befund  = Get-SchutzBefund
  $ssd     = Get-SsdInfo
  $rate    = -1
  if ($proz) { $rate = Measure-Schreibrate -Sekunden $MessSekunden }
  $variante = ''; $ziele = @(); $betroffen = $false
  if (-not $dienst) { $status = 'KeinDienst' }
  elseif (-not $proz) { $status = $(if ([string]$dienst.StartType -eq 'Disabled') { 'DienstAus' } else { 'DienstGestoppt' }) }
  elseif ($rate -lt 0) { $status = 'MessungFehlgeschlagen' }
  elseif ($rate -ge $script:SchreibGrenze) {
    $betroffen = $true
    $selbst = Test-Selbstkopie
    if (-not $selbst) {
      $ziele = @(Get-TraceZiele -Sekunden 4)
      $selbst = [bool]($ziele | Where-Object { $_ -match 'systemprofile\\AppData\\Local\\AMD\\atieclxx\.exe' })
    }
    if ($selbst) { $variante = 'Selbstkopie'; $ziele = @($script:ZielDatei); $status = $(if ($schutz) { 'SchutzWirktNicht' } else { 'BetroffenSelbstkopie' }) }
    else { $variante = 'Andere'; $status = 'BetroffenAndere' }
  }
  elseif ($schutz) { $status = 'Geschuetzt'; $variante = 'Selbstkopie' }
  else { $status = 'NichtBetroffen' }
  Set-Phase 'Estimating the wear'
  $schaden = Get-Schaden -Status $status -Rate $rate -Ssd $ssd -Befund $befund
  [pscustomobject]@{
    Status = $status; Betroffen = $betroffen; Variante = $variante; Ziele = $ziele
    Rate = $rate; Prozess = [bool]$proz; Dienst = $dienst; Schutz = $schutz; Aufgabe = $aufgabe; Befund = $befund
    Ssd = $ssd; Schaden = $schaden; Zeit = (Get-Date)
  }
}

# ------------------------------------------------------------------ Automatic task (Task Scheduler)
function Remove-AlteVersion {
  # Cleans up the previous version under the former name "AMD-SSD-Fix"; the fix record and the log are carried over.
  if (Get-ScheduledTask -TaskName $script:AlterName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $script:AlterName -Confirm:$false -ErrorAction SilentlyContinue
  }
  if (Test-Path -LiteralPath $script:AlteInstallDir) {
    New-Item -ItemType Directory -Force -Path $script:InstallDir | Out-Null
    foreach ($paar in @(@('befund.json', 'record.json'), @('protokoll.txt', 'log.txt'))) {
      $q = Join-Path $script:AlteInstallDir $paar[0]
      $z = Join-Path $script:InstallDir $paar[1]
      if ((Test-Path -LiteralPath $q) -and -not (Test-Path -LiteralPath $z)) { Copy-Item -LiteralPath $q -Destination $z -Force }
    }
    Remove-Item -LiteralPath $script:AlteInstallDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}
function Install-Aufgabe {
  # Copies the scripts to Program Files\Radeon-atieclxx-SSD-Fix (only administrators may change files there) and sets up the task.
  param([string]$Quelle)
  Remove-AlteVersion
  $skriptZiel = Join-Path $script:InstallDir 'Script'
  New-Item -ItemType Directory -Force -Path $skriptZiel | Out-Null
  if ($Quelle -and (Test-Path -LiteralPath $Quelle)) {
    $quelleVoll = (Resolve-Path -LiteralPath $Quelle).ProviderPath.TrimEnd('\')
    if (-not [string]::Equals($quelleVoll, $skriptZiel.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
      foreach ($f in 'Core.ps1', 'guard.ps1', 'Gui.ps1', 'check.ps1', 'remove.ps1') {
        $src = Join-Path $quelleVoll $f
        if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $skriptZiel $f) -Force }
      }
      $paket = Split-Path -Parent $quelleVoll
      foreach ($f in 'START.cmd', 'REMOVE.cmd', 'CHECK.cmd', 'README.txt', 'LICENSE.txt') {
        $src = Join-Path $paket $f
        if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $script:InstallDir $f) -Force }
      }
    }
    foreach ($alt in 'Skript\installieren.ps1', 'INSTALLIEREN.cmd', 'installation.txt') {
      $p = Join-Path $script:InstallDir $alt
      if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
    }
    # Remove the download mark so that the scripts also run under stricter policies.
    Get-ChildItem -LiteralPath $script:InstallDir -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
  }
  $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $arg = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $skriptZiel 'guard.ps1') + '"'
  $action = New-ScheduledTaskAction -Execute $psExe -Argument $arg
  $tStart = New-ScheduledTaskTrigger -AtStartup
  $tStart.Delay = 'PT3M'
  $tTakt = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(30) -RepetitionInterval (New-TimeSpan -Minutes 30)
  $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew
  $sysName = $script:SystemSid.Translate([System.Security.Principal.NTAccount]).Value   # localized name of SYSTEM
  $pr = New-ScheduledTaskPrincipal -UserId $sysName -LogonType ServiceAccount -RunLevel Highest
  $desc = 'Unofficial workaround: stops atieclxx.exe (AMD External Events Utility) from copying itself every second and wearing out the SSD. After driver updates it checks by itself whether AMD has fixed the bug. To remove: ' + (Join-Path $script:InstallDir 'REMOVE.cmd')
  Register-ScheduledTask -TaskName $script:AufgabeName -Action $action -Trigger @($tStart, $tTakt) -Settings $set -Principal $pr -Description $desc -Force | Out-Null
  try {
    # Read access for signed-in users, so that CHECK.cmd can show the status without administrator rights.
    $svc = New-Object -ComObject Schedule.Service
    $svc.Connect()
    $reg = $svc.GetFolder('\').GetTask($script:AufgabeName)
    $sd = $reg.GetSecurityDescriptor(4)
    if ($sd -notmatch '\(A;;FR;;;AU\)') { $reg.SetSecurityDescriptor($sd + '(A;;FR;;;AU)', 0) }
  } catch {}
  return [bool](Get-ScheduledTask -TaskName $script:AufgabeName -ErrorAction SilentlyContinue)
}
function Remove-Aufgabe {
  Unregister-ScheduledTask -TaskName $script:AufgabeName -Confirm:$false -ErrorAction SilentlyContinue
  return (-not (Get-ScheduledTask -TaskName $script:AufgabeName -ErrorAction SilentlyContinue))
}
function Remove-Alles {
  # Undoes all changes: task, protection, disabled service, stored records (also those of a previous version).
  Remove-AlteVersion
  Remove-Aufgabe | Out-Null
  Remove-Schutz | Out-Null
  $d = Get-AmdDienst
  if ($d -and [string]$d.StartType -eq 'Disabled') { Enable-Dienst | Out-Null }
  foreach ($f in $script:BefundDatei, $script:ZustandDatei) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
}
