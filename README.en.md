# Radeon-atieclxx-SSD-Fix

[Deutsch](README.md) | **English**

**Is the Radeon driver constantly writing to your SSD?** With affected drivers, `atieclxx.exe` (the "AMD External Events Utility" service) copies itself every second – about 56 GB per day. This tool checks whether your PC is affected, estimates the damage so far and stops the continuous writes in a targeted way, without turning the service off.

> **Note:** Unofficial workaround, not from AMD and not affiliated with AMD. Use at your own risk, without warranty and without liability (see [LICENSE.txt](LICENSE.txt)).

![Radeon-atieclxx-SSD-Fix: detected bug with damage estimate (example values, German interface)](docs/screenshot-betroffen.png)

*Example view with example values. The screenshots show the German interface; the window is also available in English.*

## The problem

ComputerBase reported on 2026-11-09 that the "AMD External Events Utility" service of the Radeon driver constantly writes to the system drive for many users ([article, in German](https://www.computerbase.de/news/grafikkarten/schnelle-ssd-alterung-radeon-treiber-schreibt-fortwaehrend-daten-auf-die-ssd.100237/)). AMD has confirmed the bug; a fixed driver version is not available yet.

Measured with Event Tracing for Windows (ETW): with affected drivers, `atieclxx.exe` copies **itself every second** from the driver folder to

```
C:\Windows\System32\config\systemprofile\AppData\Local\AMD\atieclxx.exe
```

The file is about 660 KB in size, which adds up to roughly 56 GB per day in continuous operation. Afterwards the service looks for installation files of the filter driver `amdkmpfd` (Smart Access Memory). That explains why turning off Resizable BAR helps some users.

## Download and start

1. Download `Radeon-atieclxx-SSD-Fix.zip` from [**Releases**](../../releases/latest).
2. Extract the ZIP file completely.
3. Double-click `START.cmd` and confirm the Windows prompt for administrator rights with "Yes".

If Windows shows a warning ("Windows protected your PC"): "More info" → "Run anyway". Or unblock the ZIP file before extracting it: right-click → Properties → "Unblock".

## Language

The window, the status and removal scripts and the log are available in German and English. The tool starts in German on a German Windows and in English everywhere else. You can switch at any time with the selection box at the top right of the window; the choice is remembered.

## What the tool does

- **Analysis:** measures whether and how much `atieclxx.exe` writes and shows which variant is present: self-copy to the known location, writes to another location, or not affected.
- **Damage estimate:** how much has already been written to the SSD unnecessarily (write rate × operating time since the AMD graphics were installed) and what share of the typical write warranty that is.
- **Fix buttons:**

| Button | Effect |
|---|---|
| **Targeted protection** (recommended) | Denies only the SYSTEM account the right to overwrite this one copy. The copy attempt fails immediately and nothing is written any more. The service, FreeSync, frame pacing and hotkeys remain untouched. Also sets up an automation (see below). |
| **Disable the service** | The option from the article. Always works, but may impair FreeSync and frame pacing. |
| **Revert everything** | Reverts protection, automation and the disabled service. |

The tool explains the third option from the article, turning off Resizable BAR in the BIOS. It can only be changed in the BIOS.

![State after targeted protection (example values, German interface)](docs/screenshot-geschuetzt.png)

*State after targeted protection, also with example values.*

### Automation after driver updates

Targeted protection sets up the task "Radeon-atieclxx-SSD-Fix" in Task Scheduler. It runs as SYSTEM 3 minutes after startup and every 30 minutes after that, and it

- re-applies the protection when a driver update has replaced the file,
- checks after a driver change whether AMD has fixed the bug, and then lifts the protection on its own,
- writes to the log `C:\Program Files\Radeon-atieclxx-SSD-Fix\protokoll.txt` only when something happens.

## Technical details

- Protection: `icacls <copy> /deny *S-1-5-18:(WD,AD,WEA,WA,DE)`, i.e. a deny entry only for the SYSTEM account on exactly this one file.
- The self-copy is detected via the USN of the NTFS change journal (`FSCTL_READ_FILE_USN_DATA`). Timestamps are useless for this because `CopyFile` takes them over from the source. As a fallback, a short ETW trace (64 MB at most, deleted immediately) determines where the writes go.
- The measurement runs in the background; the window stays responsive.
- No downloads, no internet connection, no changes to the driver, no AMD files in the package. The entire source code is in the [`Skript`](Skript) folder. German is the source language of the scripts; the English texts are in [`Skript/Englisch.ps1`](Skript/Englisch.ps1).

## Checking the status and removing

The file names are German:

| File | Purpose |
|---|---|
| `PRUEFEN.cmd` ("check") | status and a 10-second measurement, without admin rights |
| `ENTFERNEN.cmd` ("remove") | reverts everything and deletes the program folder |
| `README.txt` / `LIESMICH.txt` | instructions in English / German |

After targeted protection, these files are also in `C:\Program Files\Radeon-atieclxx-SSD-Fix`.

## Alternative without this tool

`Win+R` → `services.msc` → "AMD External Events Utility" → Stop, startup type "Disabled". This is the suggestion from the article; it may impair FreeSync and frame pacing.

## Limitations

- Other driver versions may behave differently. That is why the tool measures first and only intervenes when the fix works.
- The damage estimate is an estimate. Many SSDs do not report their power-on hours to Windows; in that case 8 hours per day are assumed.
- On PCs where company policy allows only signed PowerShell scripts, the tool does not start.
- On Windows Home the automation cannot show notification windows (`msg.exe` is missing there). Everything is still written to the log.

## License and trademarks

MIT license, see [LICENSE.txt](LICENSE.txt). AMD, Radeon and Smart Access Memory are trademarks of Advanced Micro Devices, Inc. This project is not affiliated with AMD and is neither supported nor reviewed by AMD.
