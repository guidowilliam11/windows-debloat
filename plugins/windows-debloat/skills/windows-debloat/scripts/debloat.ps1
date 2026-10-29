# Runs Win11Debloat (https://github.com/Raphire/Win11Debloat) in a controlled way. MUST run as Administrator.
# It downloads the script, saves a copy + SHA256 for review, asks for confirmation, creates a restore point, runs it unattended and
# scans the output for failures (Win11Debloat exits "successfully" even when parts failed).
# Usage (elevated PowerShell):
#   .\debloat.ps1 -Preset Lite                                   # tweaks only (telemetry, ads, Copilot/Recall...), removes NO apps
#   .\debloat.ps1 -Preset Defaults                               # tweaks + Win11Debloat's default app removal
#   .\debloat.ps1 -Preset Custom -Features DisableTelemetry,DisableBing,ShowKnownFileExt -Apps Microsoft.Todos,Clipchamp.Clipchamp
#   .\debloat.ps1 -Preset Lite -DryRun                           # download + show what would run, change nothing
# -Features = Win11Debloat switch names without the dash (see its wiki "Command-line Interface"). -Apps = app ids to remove.
param(
    [ValidateSet('Lite', 'Defaults', 'Custom')] [string]$Preset = 'Lite',
    [string[]]$Features = @(),
    [string[]]$Apps = @(),
    [switch]$DryRun,
    [switch]$Yes
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host 'GAGAL / FAILED: jalankan PowerShell sebagai Administrator (klik kanan -> Run as administrator).' -ForegroundColor Red; exit 1 }

$out = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'windows-debloat'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$file = Join-Path $out "Win11Debloat-$stamp.ps1"
$log = Join-Path $out "debloat-run-$stamp.log"

# Build the Win11Debloat parameter set
$p = [ordered]@{ Silent = $true; CreateRestorePoint = $true }
switch ($Preset) {
    'Lite'     { $p.RunDefaultsLite = $true }
    'Defaults' { $p.RunDefaults = $true }
}
foreach ($f in $Features) { $p[$f.TrimStart('-')] = $true }
if ($Apps.Count -gt 0) { $p.RemoveApps = $true; $p.Apps = ($Apps -join ',') }

Write-Host "Mengunduh Win11Debloat dari https://debloat.raphi.re/ ..."
try {
    $ProgressPreference = 'SilentlyContinue'
    $code = Invoke-RestMethod 'https://debloat.raphi.re/' -ErrorAction Stop
    Set-Content -Path $file -Value $code -Encoding UTF8
} catch {
    Write-Host "GAGAL / FAILED: tidak bisa mengunduh Win11Debloat ($($_.Exception.Message))" -ForegroundColor Red
    exit 1
}
$hash = (Get-FileHash $file -Algorithm SHA256).Hash
Write-Host "Salinan untuk dibaca dulu : $file"
Write-Host "SHA256                    : $hash"
Write-Host "Parameter yang akan dipakai:"
$p.GetEnumerator() | ForEach-Object { '  -{0}{1}' -f $_.Key, $(if ($_.Value -is [bool]) { '' } else { " $($_.Value)" }) }

if ($DryRun) { Write-Host "`nDryRun: tidak ada yang dijalankan." -ForegroundColor Yellow; exit 0 }
if (-not $Yes) {
    $a = Read-Host "`nLanjut jalankan? (y/N)"
    if ($a -notmatch '^(y|ya|yes)$') { Write-Host 'Dibatalkan.'; exit 0 }
}

Write-Host "`nMenjalankan Win11Debloat (log: $log) ..."
$sb = [scriptblock]::Create((Get-Content $file -Raw))
try {
    & $sb @p *>&1 | Tee-Object -FilePath $log
} catch {
    Write-Host "GAGAL / FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

# Win11Debloat reports "completed" even with partial failures, so scan the output.
$bad = Select-String -Path $log -Pattern 'failed|error|cannot find|gagal' -SimpleMatch:$false -ErrorAction SilentlyContinue
Write-Host ''
if ($bad) {
    Write-Host "PERHATIAN: $($bad.Count) baris menyebut kegagalan (biasanya aman, mis. app sudah tidak ada atau scheduled task format baru):" -ForegroundColor Yellow
    $bad | Select-Object -First 15 | ForEach-Object { '  ' + $_.Line.Trim() }
} else {
    Write-Host 'Tidak ada kegagalan terdeteksi di output.' -ForegroundColor Green
}
Write-Host "`nSelesai. Restart PC supaya semua perubahan berlaku."
Write-Host "Undo: restore point terbaru, backup registry di %TEMP%\Win11Debloat\Backups, atau jalankan ulang Win11Debloat dan batalkan tweak (centang 'Detect applied tweaks')."
