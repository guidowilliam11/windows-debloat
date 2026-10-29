# Read-mostly check: is this PC as fast as its hardware should be?
# Disk: bus type + a 1 GB write test (temp file, deleted afterwards) + read test via winsat when run as admin.
# RAM: configured speed vs rated speed, channel count. CPU: does it boost under load, power plan, on battery?
# Usage: pwsh -File speedcheck.ps1 [-TestGB 1] [-Drive C]
param([int]$TestGB = 1, [string]$Drive = 'C')

$inv = [Globalization.CultureInfo]::InvariantCulture
function N([double]$v, [string]$f = '0') { $v.ToString($f, $inv) }
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

"===== DISK ====="
$part = Get-Partition -DriveLetter $Drive -ErrorAction SilentlyContinue
$pd = if ($part) { Get-PhysicalDisk | Where-Object DeviceId -eq $part.DiskNumber } else { Get-PhysicalDisk | Select-Object -First 1 }
$bus = "$($pd.BusType)"; $media = "$($pd.MediaType)"
'{0} | bus {1} | {2} | health {3}' -f $pd.FriendlyName, $bus, $media, $pd.HealthStatus
$vol = Get-Volume -DriveLetter $Drive
$freePct = 100 * $vol.SizeRemaining / $vol.Size
'Ruang kosong {0}: {1}%' -f $Drive, (N $freePct)
if ($freePct -lt 10) { '>> SSD/HDD di bawah 10% kosong melambat. Kosongkan ruang dulu.' }

$expect = switch -Regex ("$bus $media") {
  'NVMe'  { @{ W = 700; R = 1500; Label = 'NVMe (PCIe 3: tulis ~1000-3000, baca ~2000-3500 MB/s; PCIe 4 lebih tinggi)' }; break }
  'SSD'   { @{ W = 300; R = 400;  Label = 'SATA SSD (tulis/baca ~400-550 MB/s)' }; break }
  'HDD'   { @{ W = 70;  R = 90;   Label = 'HDD (~100-180 MB/s)' }; break }
  default { @{ W = 250; R = 300;  Label = 'tidak dikenal' } }
}
'Patokan: ' + $expect.Label
function Judge([double]$v, [double]$ok) { if ($v -ge $ok) { 'WAJAR' } elseif ($v -ge $ok * 0.5) { 'agak lambat' } else { 'LAMBAT - cek suhu/ruang kosong/mode daya/driver storage' } }

# Write test: buffered writes, then FlushFileBuffers (fsync). Timing includes the flush, so the OS
# cache cannot inflate the number. Small writes with WriteThrough under-report NVMe, so it is not used.
$tmp = Join-Path $env:TEMP ("debloat-speedtest-{0}.bin" -f [guid]::NewGuid().ToString('N').Substring(0,8))
if ($env:TEMP -notlike "$($Drive):*") { $tmp = Join-Path "$($Drive):\" (Split-Path $tmp -Leaf) }
$buf = New-Object byte[] (16MB); (New-Object Random 42).NextBytes($buf)
$total = [int64]$TestGB * 1GB
try {
  $fs = [IO.FileStream]::new($tmp, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None, 1, [IO.FileOptions]::SequentialScan)
  $sw = [Diagnostics.Stopwatch]::StartNew()
  for ($w = 0L; $w -lt $total; $w += $buf.Length) { $fs.Write($buf, 0, $buf.Length) }
  $fs.Flush($true); $sw.Stop(); $fs.Dispose()
  $wMBs = ($total / 1MB) / $sw.Elapsed.TotalSeconds
  # Antivirus real-time scanning + PowerShell overhead cap this test around 500-900 MB/s even on fast NVMe,
  # so it is only indicative: flag it only when it is far below the device class. winsat (admin) is authoritative.
  $floor = [math]::Min($expect.W, 300) * 0.5
  'Tulis berurutan ({0} GB + fsync, indikatif): {1} MB/s  -> {2}' -f $TestGB, (N $wMBs), $(if ($wMBs -ge $floor) { 'tidak ada tanda masalah (angka pasti: jalankan sebagai admin)' } else { 'LAMBAT - cek suhu/ruang kosong/mode daya/driver storage' })
} catch { "Tes tulis gagal: $($_.Exception.Message)" }
finally { if ($fs) { $fs.Dispose() }; Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }

# Read test needs an uncached path: winsat (admin only) reads the raw device.
if ($isAdmin) {
  foreach ($mode in 'read','write') {
    $line = winsat disk -drive $Drive -seq -$mode 2>&1 | Select-String 'Disk\s+Sequential' | Select-Object -First 1
    if ($line -and "$line" -match '([\d\.]+)\s*MB/s') {
      $v = [double]::Parse($Matches[1], $inv)
      'winsat {0}: {1} MB/s  -> {2}' -f $mode, (N $v), (Judge $v $(if ($mode -eq 'read') { $expect.R } else { $expect.W }))
    } else { "winsat ${mode}: tidak terbaca" }
  }
} else { 'Tes baca (winsat): jalankan sebagai Administrator untuk angka baca yang akurat.' }

"`n===== RAM ====="
$sticks = @(Get-CimInstance Win32_PhysicalMemory)
$sticks | ForEach-Object { '{0} GB | jalan {1} MHz | rating {2} MHz | {3} {4}' -f ($_.Capacity / 1GB), $_.ConfiguredClockSpeed, $_.Speed, $_.Manufacturer, $_.BankLabel }
$slow = $sticks | Where-Object { $_.Speed -and $_.ConfiguredClockSpeed -and $_.ConfiguredClockSpeed -lt $_.Speed * 0.95 }
if ($slow) { '>> RAM jalan di bawah rating. Di desktop: aktifkan XMP/EXPO di BIOS. Di laptop biasanya memang dikunci pabrik.' } else { 'Kecepatan RAM sesuai rating.' }
if ($sticks.Count -eq 1) { '>> Hanya 1 keping RAM (single channel). Menambah 1 keping identik bisa menaikkan performa iGPU/CPU 10-30%.' } else { "$($sticks.Count) keping, kemungkinan dual channel." }
$os = Get-CimInstance Win32_OperatingSystem
'Pemakaian RAM sekarang: {0}%' -f (N (100 - 100 * $os.FreePhysicalMemory / $os.TotalVisibleMemorySize))

"`n===== CPU & DAYA ====="
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
'{0} | {1} core / {2} thread | base {3} MHz' -f $cpu.Name.Trim(), $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors, $cpu.MaxClockSpeed
'Power plan: ' + ((powercfg /getactivescheme) -replace '^.*\(|\).*$','')
$bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
if ($bat) { 'Baterai: {0}% | {1}' -f $bat.EstimatedChargeRemaining, $(if ($bat.BatteryStatus -eq 2) { 'dicas (AC)' } else { 'PAKAI BATERAI - performa sengaja diturunkan' }) }
# Boost test: spin all cores for ~4 s and read "% Processor Performance" (>100 = turbo boost)
$ctr = '\Processor Information(_Total)\% Processor Performance'
$idle = try { (Get-Counter $ctr -ErrorAction Stop).CounterSamples[0].CookedValue } catch { $null }
$jobs = 1..$cpu.NumberOfLogicalProcessors | ForEach-Object { Start-Job { $end = (Get-Date).AddSeconds(5); while ((Get-Date) -lt $end) { [math]::Sqrt(12345.678) | Out-Null } } }
Start-Sleep -Milliseconds 2500
$load = try { (Get-Counter $ctr -SampleInterval 1 -MaxSamples 2 -ErrorAction Stop).CounterSamples | Measure-Object CookedValue -Average | ForEach-Object Average } catch { $null }
$jobs | Wait-Job | Remove-Job
if ($null -ne $load) {
  $mhz = $cpu.MaxClockSpeed * $load / 100
  'Saat beban: {0}% dari base (~{1} MHz){2}' -f (N $load), (N $mhz), $(if ($null -ne $idle) { "; saat idle $(N $idle)%" } else { '' })
  if ($load -ge 100) { 'Boost jalan -> CPU WAJAR.' }
  elseif ($load -ge 80) { 'Tidak boost penuh. Cek mode daya (Performance/Balance), colok charger.' }
  else { 'CPU TERTAHAN (throttling). Cek: charger, mode Quiet/Battery saver, suhu/debu kipas, power plan.' }
} else { 'Counter performa CPU tidak tersedia.' }
