Radeon-atieclxx-SSD-Fix 2.1 – Radeon driver keeps writing to the SSD
=====================================================================

WHAT IS THIS ABOUT?
On 2026-11-09, ComputerBase reported that the "AMD External Events Utility" service
of the AMD driver keeps writing to the system drive for many users:
https://www.computerbase.de/news/grafikkarten/schnelle-ssd-alterung-radeon-treiber-schreibt-fortwaehrend-daten-auf-die-ssd.100237/
AMD has confirmed the bug, a fixed driver version is not available yet.

WHAT EXACTLY HAPPENS?
Measured with Windows event tracing (ETW): with affected drivers, atieclxx.exe copies
itself EVERY SECOND from the driver folder to
  C:\Windows\System32\config\systemprofile\AppData\Local\AMD\atieclxx.exe
The file is about 660 KB, which adds up to about 56 GB per day in continuous operation.
After that, the service looks for installation files of the amdkmpfd filter driver (Smart
Access Memory). This explains why turning off Resizable BAR helps some people.

THE PROGRAM (START.cmd)
START.cmd opens a window (confirm the Windows prompt for administrator rights with "Yes").
It
  - measures whether and how much atieclxx.exe writes and shows which variant is present:
    self-copy to the known location, writing to another location, or not affected,
  - estimates how much has already been written to the SSD unnecessarily (write rate times
    operating time since the AMD graphics card was installed; an estimate, not an exact value),
  - offers buttons for the fix you want.
The measurement runs in the background, the window stays usable in the meantime.

THE FIX BUTTONS
1) Targeted protection (recommended)
   Denies only the SYSTEM account overwriting or deleting the copy named above.
   The copy attempt fails immediately, nothing is written any more. The service keeps
   running, FreeSync, frame pacing and hotkeys are not affected. In addition, the task
   "Radeon-atieclxx-SSD-Fix" is set up (Task Scheduler, runs as SYSTEM 3 minutes after startup and
   every 30 minutes): it applies the protection again after driver updates and, after a
   driver change, checks by itself whether AMD has fixed the bug. Then it removes the protection on its own.
2) Disable service
   The option from the article: stops the service and sets the startup type to "Disabled".
   Always works, but may affect FreeSync and frame pacing.
3) Undo everything
   Removes the protection, the automatic task and the disabled service. The program folder is kept.
The "What is Resizable BAR?" button explains the third option from the article. It can
only be set in the BIOS, so there is no button for it.

No files are downloaded, no internet connection is needed, and nothing is changed in the
driver. The complete source code is openly available in the "Script" folder.

OTHER FILES
  CHECK.cmd      quick status, measures for 10 seconds (without administrator rights)
  REMOVE.cmd     undoes everything and also deletes the program folder
  LICENSE.txt    license (MIT)
After "Targeted protection", START.cmd, CHECK.cmd, REMOVE.cmd and the log are also in
  C:\Program Files\Radeon-atieclxx-SSD-Fix

NOTES
- If Windows shows a warning at startup ("Windows protected your PC"):
  "More info" -> "Run anyway". Or, before extracting, right-click the ZIP file ->
  Properties -> "Unblock".
- On company PCs that only allow signed PowerShell scripts, the program does not
  start. There, please disable the service via services.msc.
- On Windows Home there are no pop-up messages from the automatic task (msg.exe is
  missing there); everything is still written to the log.
- Other driver versions may behave differently. The program therefore measures first
  and only acts if the fix works.

ALTERNATIVE WITHOUT THIS PROGRAM (suggestion from the article)
  Win+R -> services.msc -> "AMD External Events Utility" -> Stop, startup type "Disabled".

DISCLAIMER
Unofficial workaround, not affiliated with AMD and not reviewed by AMD. Use at your own
risk, without warranty and without liability (see LICENSE.txt). AMD, Radeon and
Smart Access Memory are trademarks of Advanced Micro Devices, Inc. As soon as AMD ships a
fixed driver, the task removes the protection on its own; after that, everything can be
removed with REMOVE.cmd.
