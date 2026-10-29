---
name: windows-debloat
description: Full Windows 10/11 debloat and PC tune-up - remove preinstalled bloatware, telemetry, ads, Copilot/Recall and Bing search (via Win11Debloat), find what fills the disk (fast big-file scan), free RAM, trim startup apps and third-party services, clean dev build artifacts and caches, audit duplicate IDEs and bloated/unused editor extensions, check whether disk/RAM/CPU speed is normal, repair disk/system files, update drivers and apps. Use when the user says their disk or RAM is full, the laptop is slow, or asks to clean, speed up, debloat, refresh or "make Windows faster/cleaner".
---

# Windows Debloat

A safe, fast and complete Windows debloat and tune-up. It has three phases: **survey in parallel**, **agree a plan with the user**, then **act through scripts the user runs as Administrator**. The goal is that every gigabyte or megabyte of RAM freed is real, measured, and that nothing important breaks.

## Golden rules (learned the hard way)

1. **Measure, don't guess.** Report sizes from real commands. **Watch the locale:** in Indonesian or European locales `{0:N0}` prints `71.906 MB`, which means 71,906 MB (= 70 GB), not 71 MB. Use the bundled `survey.ps1`, which formats numbers invariantly in GB.
2. **Changing system settings is not something you do yourself.** Services, HKLM startup entries, chkdsk, DISM, uninstall: put them in a `.ps1` script, show it, and have the user run it from **PowerShell → Run as Administrator**. The Claude panel terminal is **not** admin. Every script must have an admin check at the top and print `GAGAL`/`FAILED` when a step fails (never a fake "OK").
3. **If the auto-mode classifier rejects a bulk delete** (e.g. `%TEMP%`), don't work around it. Give the user the command to run themselves.
4. **Before deleting, look at the target:**
   - List Docker containers and volumes before any purge (they may belong to other projects).
   - Check `git status` after cleaning node_modules/target to confirm no tracked files were lost.
   - Delete folders with `cmd /c rmdir /s /q`, which does not follow junctions (pnpm/workspace/worktree links). Never `Remove-Item -Recurse` on a folder that may contain a junction to shared data.
5. **Manual, not Disabled.** Third-party services go to `Manual` (they still start when needed). Startup entries are turned off through `...\Explorer\StartupApproved` (byte `03`), the same mechanism as Task Manager, so they can be switched back on. Always provide `undo.ps1`.
6. **Never touch:** `Windows\Installer`, `$PatchCache$`, WinSxS (only DISM `/StartComponentCleanup`), DriverStore, `pagefile.sys`, Recovery, `ProgramData\Package Cache`, WindowsApps (uninstall only), VC++ Redistributables (every year and both x86/x64 are needed), VS **Build Tools** + Windows Kits + `.rustup` when the user compiles Rust/C++, antivirus/Defender, audio/OEM drivers (Realtek, Nahimic on Legion, Lenovo Fn keys/Vantage), WSL/Hyper-V/HNS when Docker is used, anti-cheat (Riot Vanguard) when the user games, Print Spooler when a printer is present.
7. **Debloat with Win11Debloat, never with hand-rolled `Remove-AppxPackage` loops.** It is a well-known open-source tool (github.com/Raphire/Win11Debloat) that keeps a registry backup and has an undo path. Download it, keep a copy + hash for the user to read, create a restore point first, and don't run it from a one-liner the user hasn't seen (see Phase 2b).
8. **A Windows service that is already Manual does not need to be disabled.** Windows starts and stops it itself. The real RAM savings come from third-party services, startup apps, and big apps the user leaves open (Electron apps, WizTree, browsers).

## Phase 1: Survey (fast, parallel)

Spawn **5 Explore agents at once** (one message, five `Agent` calls, `subagent_type: "Explore"`, medium breadth). Each one is read-only and returns a ranked table with real numbers. Scripts are in this skill's `scripts/` folder. Give each agent the absolute path, and run them with `pwsh` (PowerShell 7) when available:

| Agent | Script | Look for |
|---|---|---|
| A, Disk | `survey.ps1 -Section disk` + `bigfiles.ps1 -Path C:\ -MinMB 500` | Size of `%LOCALAPPDATA%\Temp` (especially hundreds of `edge-*` folders of ~0.5 GB each = leftover browser-automation profiles), npm/pnpm/bun/cargo/pip caches, Docker `docker_data.vhdx`, WSL `ext4.vhdx`, Claude `vm_bundles`, `C:\AMD`, NVIDIA Downloader/`UpdateFramework\ota-artifacts` (driver installers already installed), `SoftwareDistribution\Download`, Steam workshop. `bigfiles.ps1` scans ~1.8 million files in ~2 minutes and groups the big files by category (game, VM, ISO, installer, archive, log, video, do-not-touch) |
| B, Dev projects | `find-regen.ps1 -Root <code folder>` | node_modules, .next, target, dist, .turbo, .venv, also inside `.claude\worktrees\*` (often 10× node_modules); huge logs (e.g. `mongod.log`), forgotten `.zip` copies of projects |
| C, RAM & startup | `survey.ps1 -Section ram` | Top processes by RAM, Run/RunOnce/Startup folder entries + their StartupApproved state, running third-party services (not in `\Windows\`), duplicate tools (e.g. Lightshot + Snipaste + Snipping Tool), preinstalled bloat still present (`Get-AppxPackage -AllUsers`: Candy Crush, TikTok, Clipchamp, Copilot, Teams, News, Xbox extras, OEM trial apps), whether Recall/Copilot/Bing search are on |
| D, Health & speed | `survey.ps1 -Section health` + `speedcheck.ps1` | `Get-PhysicalDisk` health, TRIM, NTFS event 98 ("Spot Fix"/"Full Chkdsk"), recurring 7000/7009 errors (a service failing at every boot = 45 s slower boot), BSOD 41/6008, Windows Update failures, GPU driver date, BIOS version, `winget upgrade` list, duplicate products (e.g. 9 SQL Server instances). **Is the speed normal?** Disk class (NVMe/SATA/HDD) vs measured speed, RAM configured vs rated MHz + channel count, CPU boosting under load, power plan, on battery or AC |
| E, IDE & extensions | `ide-audit.ps1` | How many editors are installed (VS Code, Cursor, Windsurf, Antigravity, Zed, JetBrains, Visual Studio, Eclipse, Sublime, Android Studio); app size, extensions size and data size per editor with a normal/large/heavy verdict; heavy extensions (>150 MB); **orphan folders / old versions** that are not listed in the editor's `extensions.json` (safe to delete); extensions duplicated across editors; caches `workspaceStorage`, `CachedExtensionVSIXs`, `logs` |

Combine the results into one ranked report. Present it in **three categories**:
- ✅ **Safe, changes nothing** (caches, leftover installers, build artifacts)
- ⚠️ **Optional, the user decides** (unused apps, WSL distro, Docker data, cache VMs, games)
- ⛔ **Do not delete** (with a one-line reason)

Ask the user to choose. Don't delete anything before they choose.

## Phase 2: Act

Do it yourself (no admin needed, user-level):
- Dev artifacts: `scripts/remove-regen.ps1 -Root <folder>` (node_modules/.next/target/dist; `.venv` is kept and reported). Afterwards check `git status` in each repo.
- User caches: `.bun\install\cache`, `npm-cache`, `pnpm`, `.cargo\registry`, `.cache\*` the user agreed to.
- **IDE & extensions** (close the editor first; all user-level):
  - Orphan extension folders / old versions reported by `ide-audit.ps1`: delete the folder (`cmd /c rmdir /s /q`). The editor never loads them.
  - `CachedExtensionVSIXs`, `logs`, `Cache`, `Code Cache`, `CachedData` of each editor: safe to delete.
  - `User\workspaceStorage`: only delete subfolders whose `LastWriteTime` is older than 90 days. They hold per-project UI state, so a project that is opened again just starts fresh.
  - Extensions the user no longer uses: show the list (heaviest first, plus duplicates across editors), let the user pick, then `<cli> --uninstall-extension <publisher.name>` (`code`, `cursor`, `windsurf`, `antigravity`, `codium`). Don't uninstall an extension the user hasn't picked.
  - Duplicate editors (e.g. VS Code + Cursor + Antigravity + Windsurf): suggest keeping 1–2, and uninstall the rest through the official uninstaller (admin script).
  - Sizes to judge: extensions folder <1.5 GB normal, 1.5–3 GB large, >3 GB heavy. A single extension >150 MB usually ships a runtime (C/C++ tools, Java, Python env, AI assistants like ChatGPT/Gemini, which keep their old versions behind).
- Tell the user what needs reinstalling afterwards (`npm install`, `cargo build`, venv tooling under `target/`).

Generate a script for the user to run as Administrator (save it to `%USERPROFILE%\Documents\windows-debloat\`):
- `optimize.ps1` + `undo.ps1`: third-party services → Manual, startup → off. Services some vendors lock (ChatGPT Codex, Claude Cowork) fail even for admin. Report that honestly and leave them.
- `cleanup-cache.ps1`: Temp older than 2 days (skip the `claude` folder), `C:\AMD`, NVIDIA Downloader, SoftwareDistribution\Download (stop wuauserv/bits first), CrashDumps, JetBrains caches, browser caches (Chrome/Edge/Arc: `Cache`, `Code Cache`, `GPUCache`, `Service Worker\CacheStorage|ScriptCache`, `ShaderCache`, `GrShaderCache`, `component_crx_cache`). Skip a browser that is running.
- Duplicate or unwanted uninstalls: use the official uninstaller (`UninstallString` + `/S` or `/quiet`, `msiexec /x {GUID} /qn` in 2–3 passes for multi-component products like SQL Server, `vs_installer.exe uninstall --installPath ... --passive`). Then delete leftover folders and orphan entries in the Uninstall registry.
- `maintenance.ps1`:
  1. `Repair-Volume C -Scan`
  2. `Dism /Online /Cleanup-Image /RestoreHealth`
  3. `sfc /scannow`
  4. Set a service that fails at boot to Manual
  5. `Update-MpSignature`
  6. `winget upgrade --id <id> --exact --silent` for a **curated** list: security fixes (WinRAR, Git, VLC, Java, Zoom), runtime patches, dev tools, utilities. **Don't** auto-upgrade database majors (MongoDB/MySQL), language majors (Go, Anaconda), licensed IDEs, or game launchers.
- Docker: purge only after listing containers and the user agrees. Docker Desktop → Troubleshoot (bug/help icon) → **Clean up data** → tick **WSL 2** only. Use computer use (request access for `Docker Desktop` **and** `docker desktop.exe`).

## Phase 2b: Debloat Windows (Win11Debloat)

Removes preinstalled apps and switches off telemetry, ads/suggestions, Copilot, Recall, Click to Do, Bing web search in Start, widgets and Edge ads. Run it through `scripts/debloat.ps1`, which downloads Win11Debloat, saves a copy + SHA256 to `Documents\windows-debloat\`, asks for confirmation, creates a restore point, runs it unattended and scans the output for failures. It needs **Administrator**, so the user runs it (rule 2).

1. **Ask which level** before generating the command:
   - **Lite** (default, `-Preset Lite`): tweaks only, **no apps removed**. Zero regret.
   - **Defaults** (`-Preset Defaults`): tweaks + Win11Debloat's default app removal.
   - **Custom** (`-Preset Custom -Features ... -Apps ...`): pick exact switches/apps. Switch names are in the Win11Debloat wiki "Command-line Interface" (e.g. `DisableTelemetry`, `DisableBing`, `DisableCopilot`, `DisableRecall`, `DisableWidgets`, `DisableSuggestions`, `DisableEdgeAds`, `ShowKnownFileExt`, `ShowHiddenFolders`, `TaskbarAlignLeft`, `RevertContextMenu`).
2. **Show the user what will be removed** before running. Use `-DryRun` first if they want to read the script and parameters. Apps people often regret removing: Sticky Notes, To Do, Sound Recorder, Clipchamp, Maps, Alarms, Quick Assist, Power Automate, Phone Link, OneDrive. Ask about each one the user might use.
3. **Never** pass `-ForceRemoveEdge` (breaks WebView2 apps and updates). `-RemoveGamingApps` only when the user doesn't game or use Xbox/Game Bar. `-RemoveHPApps` only on HP machines. Keep Terminal, Store, Photos, Calculator, Notepad, Paint unless asked.
4. The user runs it in an **elevated** PowerShell, e.g. `.\scripts\debloat.ps1 -Preset Lite`. Save a ready command in `Documents\windows-debloat\`.
5. **Read the result honestly.** Win11Debloat prints "Script completed" even with partial failures. Known harmless ones on very new builds: `Failed to disable Scheduled Task ... task XML ... incorrectly formatted` (that telemetry task stays enabled; the registry telemetry setting still applies) and `Invoke-NonBlocking: The system cannot find the path specified` during app removal (that one app was already gone). Report the counts; don't call it a clean success if lines say failed.
6. **After it:** restart, then check Start, search, Settings and taskbar work. Tell the user which removed apps they can reinstall from the Microsoft Store.

**Undo** (give these if anything feels wrong): System Restore point; registry backup `%TEMP%\Win11Debloat\Backups\Win11Debloat-RegistryBackup-*.json` (Win11Debloat → Options → Restore backup); rerun Win11Debloat with "Detect applied tweaks" on and untick what to undo; per-setting `.reg` files in its `Regfiles\Undo` folder; reinstall apps from the Store. Widgets need Start Experiences App + Widgets Platform Runtime + Windows Web Experience Pack reinstalled. Store and Xbox services are hard to reinstall, so never remove them.

## Phase 3: Repair the C: disk if NTFS 98 shows "Spot Fix"

On recent builds, `chkdsk C: /spotfix`, `Repair-Volume -SpotFix/-OfflineScanAndFix` and `fsutil dirty set` can all fail or not run at boot. The approach that has been proven to work:
1. In an admin cmd: `shutdown /r /o /t 0` (or Shift + Restart).
2. Troubleshoot → Advanced options → Command Prompt (the prompt starts with `X:\`; check the drive with `dir C:\Users`).
3. `chkdsk C: /f` → `exit` → Continue.
4. Verify: NTFS event 98 after boot = "Volume C: is healthy". WinRE doesn't write a Wininit report; that's normal.

## Things for the user to do themselves (give short steps)

- GPU driver: **NVIDIA App** from nvidia.com. Make sure the file is **not** `arm64` on an x64 CPU. Drivers → Download → Custom → Clean installation when the version jump is large.
- OEM: Lenovo Vantage / MyASUS / Dell Update for BIOS and drivers (with the charger plugged in).
- Laptop thermal mode: Balance + AI Engine as the default; Performance for heavy builds or gaming on AC; Quiet on battery.
- Electron apps (Logi Options+, Teams, etc.): close the window, the agent keeps running; or uninstall when the custom feature isn't needed.

## Is the speed normal? (speedcheck.ps1)

| Component | Normal | Action when below |
|---|---|---|
| NVMe PCIe 3 / 4 | write 1000–3000 / 3000–7000 MB/s, read 2000–3500 / 5000–7000 | free up space (<10% free = slow), check temperature, Balance/Performance mode, update the storage driver/firmware through the OEM |
| SATA SSD | ~400–550 MB/s | same as above |
| HDD | ~100–180 MB/s | recommend migrating to an SSD |
| RAM | configured MHz = rated MHz, 2 sticks (dual channel) | desktop: enable XMP/EXPO in BIOS; a single stick = suggest adding a matching one |
| CPU | `% Processor Performance` >100% under load (boost) | plug in the charger, leave Quiet/Battery saver, clean dust from the fans |

The write test without admin is only **indicative**: Defender scanning each new file plus PowerShell overhead caps it around 350–1400 MB/s even on fast NVMe, and the number varies from run to run. Don't call the disk slow from that number alone. Run `speedcheck.ps1` as Administrator so winsat measures the real read/write speed.

## winget exit code cheat sheet

| Code | Meaning |
|---|---|
| `0` | OK |
| `0x8A15002B` (-1978335189) | No update applies; often already updated by another package |
| `0x8A150006` (-1978335226) | Installer failed; usually the app is running. Update from inside the app |
| others | Report as failed; don't call it a success |

## Final report

Close with a before/after table measured live: C: free, RAM free at idle, number of startup entries and services changed, apps removed and tweaks applied by the debloat, disk health (event 98), updated apps (OK/failed). List what is still pending, and what the user has to reinstall or start manually (e.g. `net start postgresql-x64-18`, open Docker before using it).
