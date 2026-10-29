# Read-only: list regenerable build/dependency folders (> 20 MB) under -Root, biggest first.
# Stops descending at each match and never enters .git, so it is fast even on large trees.
param([Parameter(Mandatory)][string]$Root)
$names = @('node_modules','target','.next','dist','.turbo','.vite','.parcel-cache','.venv','venv','__pycache__','.gradle','.dart_tool')
$found = New-Object System.Collections.Generic.List[string]
function Walk([string]$dir) {
  foreach ($d in [System.IO.Directory]::EnumerateDirectories($dir)) {
    $n = [System.IO.Path]::GetFileName($d)
    if ($n -eq '.git') { continue }
    if ($names -contains $n) { $found.Add($d) } else { try { Walk $d } catch {} }
  }
}
Walk $Root
$inv = [Globalization.CultureInfo]::InvariantCulture
$found | ForEach-Object {
  $s = (Get-ChildItem -LiteralPath $_ -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
  [pscustomobject]@{ Bytes = $s; Path = $_.Substring($Root.Length + 1) }
} | Where-Object Bytes -gt 20MB | Sort-Object Bytes -Descending | ForEach-Object {
  '{0,10}  {1}' -f (($_.Bytes / 1GB).ToString('0.00', $inv) + ' GB'), $_.Path
}
