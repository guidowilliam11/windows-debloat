# Read-only audit of installed code editors / IDEs and their extensions.
# Reports: which IDEs exist (duplicates), install + data size, extensions size/count, heavy extensions,
# stale old versions of the same extension, extensions duplicated across editors, and big caches
# (workspaceStorage, CachedExtensionVSIXs, logs) - with a "normal?" verdict.
# Usage: powershell -ExecutionPolicy Bypass -File ide-audit.ps1 [-HeavyMB 150] [-Top 15]
param([int]$HeavyMB = 150, [int]$Top = 15)

$inv = [Globalization.CultureInfo]::InvariantCulture
$H = $env:USERPROFILE; $R = $env:APPDATA; $L = $env:LOCALAPPDATA
function Bytes([string]$p) {
  if (-not $p -or -not (Test-Path -LiteralPath $p)) { return 0 }
  $o = [IO.EnumerationOptions]::new(); $o.RecurseSubdirectories = $true; $o.IgnoreInaccessible = $true
  $o.AttributesToSkip = [IO.FileAttributes]::ReparsePoint
  $sum = 0L
  try { foreach ($f in [IO.Directory]::EnumerateFiles($p, '*', $o)) { try { $sum += [IO.FileInfo]::new($f).Length } catch {} } } catch {}
  $sum
}
function GB([double]$b) { ($b / 1GB).ToString('0.00', $inv) + ' GB' }
function MB([double]$b) { ($b / 1MB).ToString('0', $inv) + ' MB' }
function Verdict([double]$b, [double]$okGB, [double]$heavyGB) {
  if ($b -lt $okGB * 1GB) { 'normal' } elseif ($b -lt $heavyGB * 1GB) { 'agak besar' } else { 'BERAT' }
}

# VS Code family: extensions dir, user data dir, install dirs, CLI name
$vsFamily = @(
  @{ Name='VS Code';     Ext="$H\.vscode\extensions";      Data="$R\Code";        Install=@("$L\Programs\Microsoft VS Code","$env:ProgramFiles\Microsoft VS Code"); Cli='code' },
  @{ Name='VS Code Insiders'; Ext="$H\.vscode-insiders\extensions"; Data="$R\Code - Insiders"; Install=@("$L\Programs\Microsoft VS Code Insiders"); Cli='code-insiders' },
  @{ Name='Cursor';      Ext="$H\.cursor\extensions";      Data="$R\Cursor";      Install=@("$L\Programs\cursor","$L\Programs\Cursor"); Cli='cursor' },
  @{ Name='Windsurf';    Ext="$H\.windsurf\extensions";    Data="$R\Windsurf";    Install=@("$L\Programs\Windsurf"); Cli='windsurf' },
  @{ Name='Antigravity'; Ext="$H\.antigravity\extensions"; Data="$R\Antigravity"; Install=@("$L\Programs\Antigravity"); Cli='antigravity' },
  @{ Name='VSCodium';    Ext="$H\.vscode-oss\extensions";  Data="$R\VSCodium";    Install=@("$L\Programs\VSCodium","$env:ProgramFiles\VSCodium"); Cli='codium' },
  @{ Name='Trae';        Ext="$H\.trae\extensions";        Data="$R\Trae";        Install=@("$L\Programs\Trae"); Cli='trae' },
  @{ Name='Kiro';        Ext="$H\.kiro\extensions";        Data="$R\Kiro";        Install=@("$L\Programs\Kiro"); Cli='kiro' }
)

"===== EDITOR / IDE TERPASANG ====="
$present = @()
foreach ($e in $vsFamily) {
  $inst = $e.Install | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $inst -and -not (Test-Path $e.Ext)) { continue }
  $present += $e
  $iB = Bytes $inst; $xB = Bytes $e.Ext; $dB = Bytes $e.Data
  $e.InstB = $iB; $e.ExtB = $xB; $e.DataB = $dB
  '{0,-17} app {1,9} | extensions {2,9} [{3}] | data {4,9} [{5}]' -f $e.Name, (GB $iB), (GB $xB), (Verdict $xB 1.5 3), (GB $dB), (Verdict $dB 1 3)
}

# Other IDEs (install dirs)
$others = @(
  @{ Name='JetBrains (semua)'; Paths=@("$env:ProgramFiles\JetBrains","$L\Programs\JetBrains","$L\JetBrains","$R\JetBrains") },
  @{ Name='Android Studio';    Paths=@("$env:ProgramFiles\Android\Android Studio","$L\Google\AndroidStudio*","$L\Android\Sdk") },
  @{ Name='Visual Studio';     Paths=@("$env:ProgramFiles\Microsoft Visual Studio","${env:ProgramFiles(x86)}\Microsoft Visual Studio") },
  @{ Name='Eclipse';           Paths=@("$H\eclipse","$H\.p2") },
  @{ Name='Sublime Text';      Paths=@("$env:ProgramFiles\Sublime Text","$R\Sublime Text") },
  @{ Name='Zed';               Paths=@("$L\Programs\Zed","$L\Zed","$R\Zed") },
  @{ Name='Arduino IDE';       Paths=@("$L\Programs\arduino-ide","$L\Arduino15") },
  @{ Name='NetBeans';          Paths=@("$env:ProgramFiles\NetBeans*","$R\NetBeans") }
)
foreach ($o in $others) {
  $paths = $o.Paths | ForEach-Object { Get-Item $_ -ErrorAction SilentlyContinue } | ForEach-Object FullName
  if (-not $paths) { continue }
  $b = ($paths | ForEach-Object { Bytes $_ } | Measure-Object -Sum).Sum
  '{0,-17} total {1,9}' -f $o.Name, (GB $b)
  if ($o.Name -eq 'Visual Studio') {
    Get-ChildItem $paths -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d{4}$' } |
      ForEach-Object { Get-ChildItem $_.FullName -Directory | ForEach-Object { '    - {0} {1}' -f $_.Parent.Name, $_.Name } }
  }
  if ($o.Name -like 'JetBrains*') {
    $paths | ForEach-Object { Get-ChildItem $_ -Directory -ErrorAction SilentlyContinue } | Select-Object -ExpandProperty Name -Unique |
      Where-Object { $_ -match '\d{4}\.\d' } | Sort-Object | ForEach-Object { "    - $_" }
  }
}
if ($present.Count -gt 1) { "`n>> $($present.Count) editor keluarga VS Code terpasang. Biasanya cukup 1-2; sisanya kandidat uninstall." }

foreach ($e in $present) {
  if (-not (Test-Path $e.Ext)) { continue }
  "`n===== EKSTENSI: $($e.Name) ====="
  $dirs = Get-ChildItem $e.Ext -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '^\.' }
  $rows = foreach ($d in $dirs) {
    # folder name: publisher.name-1.2.3[-platform]
    if ($d.Name -match '^(?<id>[^-]+(?:-[^\d][^-]*)*)-(?<ver>\d[\w\.\-+]*)$') { $id = $Matches.id; $ver = $Matches.ver } else { $id = $d.Name; $ver = '' }
    [pscustomobject]@{ Id = $id.ToLower(); Ver = $ver; Bytes = (Bytes $d.FullName); Modified = $d.LastWriteTime; Dir = $d.FullName }
  }
  $e.Ids = @($rows | Select-Object -ExpandProperty Id -Unique)
  'jumlah folder: {0} | ekstensi unik: {1} | total {2}' -f @($rows).Count, $e.Ids.Count, (GB (($rows | Measure-Object Bytes -Sum).Sum))
  "-- terberat (>= $HeavyMB MB) --"
  $rows | Where-Object { $_.Bytes -ge $HeavyMB * 1MB } | Sort-Object Bytes -Descending | Select-Object -First $Top |
    ForEach-Object { '{0,8}  {1} {2}  (folder {3:yyyy-MM-dd})' -f (MB $_.Bytes), $_.Id, $_.Ver, $_.Modified }
  "-- folder yatim / versi lama (tidak tercatat aktif oleh editor, aman dihapus) --"
  # The editor records the active folder of every installed extension in extensions.json.
  # A folder that is not listed there is a leftover; without that file, fall back to "older duplicate".
  $manifest = Join-Path $e.Ext 'extensions.json'
  $active = $null
  if (Test-Path $manifest) {
    try { $active = @((Get-Content $manifest -Raw | ConvertFrom-Json) | ForEach-Object { $_.relativeLocation } | Where-Object { $_ }) } catch { $active = $null }
  }
  if ($active) {
    $stale = $rows | Where-Object { $active -notcontains (Split-Path $_.Dir -Leaf) }
  } else {
    $stale = $rows | Group-Object Id | Where-Object Count -gt 1 | ForEach-Object { $_.Group | Sort-Object Modified -Descending | Select-Object -Skip 1 }
  }
  if ($stale) { $stale | ForEach-Object { '{0,8}  {1}' -f (MB $_.Bytes), $_.Dir }; 'total versi lama: ' + (GB (($stale | Measure-Object Bytes -Sum).Sum)) } else { '(tidak ada)' }
  if (Test-Path "$($e.Ext)\.obsolete") { "file .obsolete ada (ekstensi yang sudah di-uninstall tapi foldernya belum dibersihkan editor)" }
  "-- cache editor --"
  foreach ($c in 'User\workspaceStorage','CachedExtensionVSIXs','CachedData','Cache','Code Cache','logs','User\History') {
    $p = Join-Path $e.Data $c; $b = Bytes $p
    if ($b -gt 50MB) { '{0,9}  {1}' -f (GB $b), $p }
  }
}

# Extensions installed in more than one editor
if ($present.Count -gt 1) {
  "`n===== EKSTENSI DOBEL DI BEBERAPA EDITOR ====="
  $all = foreach ($e in $present) { foreach ($i in $e.Ids) { [pscustomobject]@{ Id = $i; Editor = $e.Name } } }
  $dup = $all | Group-Object Id | Where-Object Count -gt 1 | Sort-Object Count -Descending
  "$(@($dup).Count) ekstensi terpasang di lebih dari satu editor."
  $dup | Select-Object -First $Top | ForEach-Object { '{0} -> {1}' -f $_.Name, (($_.Group.Editor) -join ', ') }
}

"`nPatokan wajar: folder ekstensi <1.5 GB normal, 1.5-3 GB agak besar, >3 GB berat. Satu ekstensi >150 MB biasanya membawa runtime/binary (C/C++, Java, Python env, AI assistant)."
"Uninstall ekstensi: <cli> --uninstall-extension <publisher.name>   (cli: code, cursor, windsurf, antigravity, ...)"
