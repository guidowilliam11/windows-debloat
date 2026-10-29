# Fast read-only scan for the biggest files on a drive or folder.
# Uses .NET file enumeration (skips inaccessible folders and junctions), keeps only files >= -MinMB,
# then groups them by category so it is obvious what is safe to review.
# Usage: pwsh -File bigfiles.ps1 [-Path C:\] [-MinMB 500] [-Top 40]
# Needs PowerShell 7+ (pwsh) for EnumerationOptions; falls back to a slower scan on 5.1.
param([string]$Path = 'C:\', [int]$MinMB = 500, [int]$Top = 40)

$inv = [Globalization.CultureInfo]::InvariantCulture
$min = [int64]$MinMB * 1MB
$sw = [Diagnostics.Stopwatch]::StartNew()
$hits = New-Object System.Collections.Generic.List[object]
$count = 0L

if ($PSVersionTable.PSVersion.Major -ge 7) {
  $o = [IO.EnumerationOptions]::new()
  $o.RecurseSubdirectories = $true; $o.IgnoreInaccessible = $true
  $o.AttributesToSkip = [IO.FileAttributes]::ReparsePoint
  $di = [IO.DirectoryInfo]::new($Path)
  foreach ($f in $di.EnumerateFiles('*', $o)) {
    $count++
    try { if ($f.Length -ge $min) { $hits.Add($f) } } catch {}
  }
} else {
  Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
    ForEach-Object { $count++; if ($_.Length -ge $min) { $hits.Add($_) } }
}
$sw.Stop()

function Category($f) {
  $p = $f.FullName; $x = $f.Extension.ToLower()
  switch -Regex ($p) {
    '\\(pagefile|hiberfil|swapfile)\.sys$' { return 'JANGAN - file sistem' }
    '\\Windows\\(Installer|WinSxS|System32)\\' { return 'JANGAN - Windows' }
    '\\(Riot Games|Steam|Epic Games|Ubisoft|EA Games)\\' { return 'GAME - hapus via launcher' }
    '\\Docker\\|docker_data' { return 'DOCKER - purge via Docker Desktop' }
    'ext4\.vhdx$' { return 'WSL - wsl --unregister bila tak dipakai' }
    '\\vm_bundles\\|claudevm' { return 'VM cache aplikasi - unduh ulang bila perlu' }
    '\\Downloads\\' { return 'DOWNLOADS - cek & hapus manual' }
    '\\(Temp|tmp)\\' { return 'TEMP - aman dihapus' }
  }
  switch -Regex ($x) {
    '^\.(iso|img)$' { return 'IMAGE OS/disk - biasanya bisa dihapus' }
    '^\.(zip|rar|7z|tar|gz)$' { return 'ARSIP - cek isinya' }
    '^\.(mp4|mkv|mov|avi)$' { return 'VIDEO - pindah ke drive lain/cloud' }
    '^\.(exe|msi)$' { return 'INSTALLER - hapus bila sudah terpasang' }
    '^\.(vhd|vhdx|vmdk|vdi)$' { return 'VIRTUAL DISK - VM' }
    '^\.(bak|dmp|log|etl)$' { return 'BACKUP/DUMP/LOG - biasanya aman dihapus' }
    '^\.(pst|ost)$' { return 'OUTLOOK - jangan hapus sembarangan' }
  }
  'LAINNYA - lihat dulu'
}

$secs = [math]::Max($sw.Elapsed.TotalSeconds, 0.01)
'Scan {0}: {1} file dalam {2} detik ({3} file/detik). File >= {4} MB: {5}' -f $Path, $count.ToString('N0', $inv), $secs.ToString('0.0', $inv), ([int]($count / $secs)).ToString('N0', $inv), $MinMB, $hits.Count
$tot = ($hits | Measure-Object Length -Sum).Sum
'Total ukuran file besar: {0} GB' -f ($tot / 1GB).ToString('0.0', $inv)
"`n-- per kategori --"
$hits | Group-Object { Category $_ } | ForEach-Object {
  [pscustomobject]@{ Cat = $_.Name; N = $_.Count; GB = (($_.Group | Measure-Object Length -Sum).Sum / 1GB) }
} | Sort-Object GB -Descending | ForEach-Object { '{0,8} GB  {1,3} file  {2}' -f $_.GB.ToString('0.0', $inv), $_.N, $_.Cat }
"`n-- $Top file terbesar --"
$hits | Sort-Object Length -Descending | Select-Object -First $Top | ForEach-Object {
  '{0,8} GB  {1:yyyy-MM-dd}  {2}  [{3}]' -f ($_.Length / 1GB).ToString('0.00', $inv), $_.LastWriteTime, $_.FullName, (Category $_)
}
