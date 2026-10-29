# Read-only Windows survey for the windows-debloat skill. Nothing is changed.
# Usage: powershell -ExecutionPolicy Bypass -File survey.ps1 -Section disk|dev|ram|health|all [-CodeRoot <folder>]
param(
  [ValidateSet('disk','dev','ram','health','all')][string]$Section = 'all',
  [string]$CodeRoot = "$env:USERPROFILE\Documents\programming"
)
$inv = [Globalization.CultureInfo]::InvariantCulture
function GB([double]$b) { ($b / 1GB).ToString('0.00', $inv) + ' GB' }
function Size([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  (Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
}
function Row([string]$p, [string]$label = '') {
  $s = Size $p
  if ($null -ne $s -and $s -gt 50MB) { '{0,10}  {1}{2}' -f (GB $s), $p, $(if ($label) { "  ($label)" } else { '' }) }
}
function Head([string]$t) { "`n===== $t =====" }

if ($Section -in 'disk','all') {
  Head 'DISK'
  Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -and $_.Name.Length -eq 1 } | ForEach-Object { '{0}: free {1} of {2}' -f $_.Name, (GB $_.Free), (GB ($_.Used + $_.Free)) }
  $L = $env:LOCALAPPDATA; $H = $env:USERPROFILE
  $t = "$L\Temp"
  $edge = @(Get-ChildItem $t -Directory -Force -Filter 'edge-*' -ErrorAction SilentlyContinue)
  'Temp total: {0}; edge-* folders: {1}' -f (GB (Size $t)), $edge.Count
  @(
    @("$L\npm-cache",'npm cache'), @("$L\pnpm",'pnpm store'), @("$H\.bun\install\cache",'bun cache'),
    @("$H\.cargo\registry",'cargo registry'), @("$L\pip\Cache",'pip cache'), @("$H\.cache",'misc caches'),
    @("$L\Docker\wsl",'Docker WSL disk'), @('C:\AMD','AMD installer leftovers'),
    @("$env:ProgramData\NVIDIA Corporation\Downloader",'old NVIDIA installers'),
    @("$env:SystemRoot\SoftwareDistribution\Download",'installed Windows Update files'),
    @("$L\CrashDumps",'crash dumps'), @("$L\JetBrains",'JetBrains caches'),
    @("${env:ProgramFiles(x86)}\Steam\steamapps\workshop",'Steam workshop'),
    @("$env:ProgramData\Package Cache",'KEEP - needed for repair/uninstall')
  ) | ForEach-Object { Row $_[0] $_[1] }
  Get-ChildItem "$L\Packages" -Directory -ErrorAction SilentlyContinue | ForEach-Object { Row $_.FullName 'Store app data' }
  Get-ChildItem $L -Recurse -Force -Filter *.vhdx -ErrorAction SilentlyContinue | ForEach-Object { '{0,10}  {1}  (virtual disk)' -f (GB $_.Length), $_.FullName }
}

if ($Section -in 'dev','all') {
  Head "DEV ARTIFACTS under $CodeRoot"
  & (Join-Path $PSScriptRoot 'find-regen.ps1') -Root $CodeRoot
}

if ($Section -in 'ram','all') {
  Head 'RAM'
  $os = Get-CimInstance Win32_OperatingSystem
  'RAM free {0} of {1}' -f (GB ($os.FreePhysicalMemory * 1KB)), (GB ($os.TotalVisibleMemorySize * 1KB))
  Get-Process | Group-Object ProcessName | ForEach-Object {
    [pscustomobject]@{ MB = [int](($_.Group | Measure-Object WorkingSet64 -Sum).Sum / 1MB); N = $_.Count; Name = $_.Name }
  } | Sort-Object MB -Descending | Select-Object -First 25 | Format-Table -AutoSize | Out-String -Width 120
  Head 'STARTUP (03 = off)'
  $approved = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
  $state = @{}
  foreach ($k in "HKCU:\$approved\Run","HKLM:\$approved\Run","HKLM:\$approved\Run32","HKCU:\$approved\StartupFolder","HKLM:\$approved\StartupFolder") {
    if (Test-Path $k) { (Get-ItemProperty $k).PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { $state[$_.Name] = $_.Value[0] } }
  }
  foreach ($k in 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run') {
    if (Test-Path $k) { (Get-ItemProperty $k).PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { '{0,-4} {1,-6} {2}' -f $k.Substring(0,4), $(if ($state[$_.Name] -eq 3) { 'off' } else { 'ON' }), $_.Name } }
  }
  Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup","$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp" -File -ErrorAction SilentlyContinue |
    ForEach-Object { 'dir  {0,-6} {1}' -f $(if ($state[$_.Name] -eq 3) { 'off' } else { 'ON' }), $_.Name }
  Head 'THIRD-PARTY SERVICES (running or Auto)'
  Get-CimInstance Win32_Service | Where-Object { ($_.State -eq 'Running' -or $_.StartMode -eq 'Auto') -and $_.PathName -notmatch '\\Windows\\(system32|SysWOW64)\\' -and $_.PathName -notmatch 'Windows Defender' } |
    Sort-Object Name | ForEach-Object { '{0,-40} {1,-7} {2,-8} {3}' -f $_.Name, $_.StartMode, $_.State, $_.DisplayName }
}

if ($Section -in 'health','all') {
  Head 'HEALTH'
  Get-PhysicalDisk | ForEach-Object { '{0} | {1} | {2} | health={3}' -f $_.FriendlyName, $_.MediaType, (GB $_.Size), $_.HealthStatus }
  'TRIM: ' + (fsutil behavior query DisableDeleteNotify | Select-Object -First 1)
  $cs = Get-CimInstance Win32_ComputerSystem; $bios = Get-CimInstance Win32_BIOS; $os = Get-CimInstance Win32_OperatingSystem
  '{0} {1} | BIOS {2} ({3:yyyy-MM-dd}) | {4} build {5}' -f $cs.Manufacturer, $cs.Model, $bios.SMBIOSBIOSVersion, $bios.ReleaseDate, $os.Caption, $os.BuildNumber
  (Get-CimInstance Win32_Processor).Name
  Get-CimInstance Win32_VideoController | ForEach-Object { 'GPU {0} | driver {1} ({2:yyyy-MM-dd})' -f $_.Name, $_.DriverVersion, $_.DriverDate }
  $since = (Get-Date).AddDays(-30)
  Head 'NTFS 98 (30 days)'
  Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Ntfs'; Id=98; StartTime=$since} -ErrorAction SilentlyContinue |
    ForEach-Object { $_.Message.Split("`n")[0].Trim() } | Group-Object | ForEach-Object { '{0,4}x {1}' -f $_.Count, $_.Name }
  Head 'TOP SYSTEM ERRORS (30 days)'
  Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=$since} -ErrorAction SilentlyContinue |
    ForEach-Object { "$($_.ProviderName) $($_.Id): " + $_.Message.Split("`n")[0].Trim() } | Group-Object | Sort-Object Count -Descending | Select-Object -First 12 | ForEach-Object { '{0,4}x {1}' -f $_.Count, $_.Name }
  'Unexpected shutdowns (41/6008): ' + @(Get-WinEvent -FilterHashtable @{LogName='System'; Id=41,6008; StartTime=$since} -ErrorAction SilentlyContinue).Count
  Head 'PENDING WINDOWS UPDATES'
  try { $r = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher().Search('IsInstalled=0 and IsHidden=0'); $r.Updates | ForEach-Object { $_.Title } } catch { 'query failed' }
  Head 'WINGET UPGRADES'
  winget upgrade --include-unknown --accept-source-agreements 2>&1 | Select-String -Pattern 'winget$|msstore$|upgrades available' | ForEach-Object { $_.Line }
}
