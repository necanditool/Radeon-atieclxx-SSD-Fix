Radeon-atieclxx-SSD-Fix 2.1 – Radeon driver constantly writes to the SSD
==================================================================
(Deutsche Fassung: LIESMICH.txt)

WHAT IS THIS ABOUT?
ComputerBase reported on 2026-11-09 that the "AMD External Events Utility" service of the
AMD driver constantly writes to the system drive for many users (article in German):
https://www.computerbase.de/news/grafikkarten/schnelle-ssd-alterung-radeon-treiber-schreibt-fortwaehrend-daten-auf-die-ssd.100237/
AMD has confirmed the bug; a fixed driver version is not available yet.

WHAT EXACTLY HAPPENS?
Measured with Event Tracing for Windows (ETW): with affected drivers, atieclxx.exe copies
itself EVERY SECOND from the driver folder to
  C:\Windows\System32\config\systemprofile\AppData\Local\AMD\atieclxx.exe
The file is about 660 KB in size, which adds up to roughly 56 GB per day in continuous
operation. Afterwards the service looks for installation files of the filter driver amdkmpfd
(Smart Access Memory). That explains why turning off Resizable BAR helps some users.

THE TOOL (START.cmd)
START.cmd opens a window (confirm the Windows prompt for administrator rights with "Yes"). It
  - measures whether and how much atieclxx.exe writes and shows which variant is present:
    self-copy to the known location, writes to another location, or not affected,
  - estimates how much has already been written to the SSD unnecessarily (write rate times
    operating time since the AMD graphics were installed; an estimate, not an exact value),
  - offers buttons for the fix you want.
The measurement runs in the background; the window stays responsive.

LANGUAGE
The tool starts in German on a German Windows and in English everywhere else. You can switch
at any time with the selection box at the top right of the window; the choice is remembered
and also applies to PRUEFEN.cmd, ENTFERNEN.cmd and the log.

THE FIX BUTTONS
1) Targeted protection (recommended)
   Denies only the SYSTEM account the right to overwrite or delete the copy named above.
   The copy attempt fails immediately and nothing is written any more. The service keeps
   running; FreeSync, frame pacing and hotkeys remain untouched. In addition, the task
   "Radeon-atieclxx-SSD-Fix" is set up (Task Scheduler, runs as SYSTEM 3 minutes after startup
   and every 30 minutes): it re-applies the protection after driver updates and checks after a
   driver change whether AMD has fixed the bug. It then lifts the protection on its own.
2) Disable the service
   The option from the article: stops the service and sets its startup type to "Disabled".
   Always works, but may impair FreeSync and frame pacing.
3) Revert everything
   Reverts protection, automation and the disabled service. The program folder is kept.
The button "What is Resizable BAR?" explains the third option from the article. It can only
be set in the BIOS, which is why there is no button for it.

No files are downloaded, no internet connection is needed, and nothing about the driver is
changed. The entire source code is open in the "Skript" folder.

OTHER FILES (the file names are German)
  PRUEFEN.cmd    "check": quick status, measures for 10 seconds (without admin rights)
  ENTFERNEN.cmd  "remove": reverts everything and also deletes the program folder
  LIESMICH.txt   these instructions in German
  LICENSE.txt    license (MIT)
After "Targeted protection", START.cmd, PRUEFEN.cmd, ENTFERNEN.cmd and the log (protokoll.txt)
are also in
  C:\Program Files\Radeon-atieclxx-SSD-Fix

NOTES
- If Windows shows a warning at startup ("Windows protected your PC"):
  "More info" -> "Run anyway". Or unblock the ZIP file before extracting it:
  right-click -> Properties -> "Unblock".
- On company PCs where only signed PowerShell scripts are allowed, the tool does not start.
  In that case please disable the service via services.msc.
- On Windows Home the automation cannot show notification windows (msg.exe is missing there);
  everything is still written to the log.
- Other driver versions may behave differently. That is why the tool measures first and only
  intervenes when the fix works.

ALTERNATIVE WITHOUT THIS TOOL (suggestion from the article)
  Win+R -> services.msc -> "AMD External Events Utility" -> Stop, startup type "Disabled".

DISCLAIMER
Unofficial workaround, not affiliated with AMD and not reviewed by AMD. Use at your own risk,
without warranty and without liability (see LICENSE.txt). AMD, Radeon and Smart Access Memory
are trademarks of Advanced Micro Devices, Inc. As soon as AMD ships a fixed driver, the task
lifts the protection on its own; after that everything can be removed with ENTFERNEN.cmd.
