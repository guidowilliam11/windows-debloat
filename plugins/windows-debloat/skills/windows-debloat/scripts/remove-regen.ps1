# Delete regenerable build/dependency folders under -Root (node_modules, target, .next, dist, .turbo, .vite, .parcel-cache).
# .venv/venv are NOT deleted (reinstall steps differ per project). Junction-safe: a junction is unlinked,
# never followed, and rmdir /s does not descend into junctions inside the tree.
# After running, check `git status` in each repo.
param([Parameter(Mandatory)][string]$Root, [switch]$WhatIf)
$names = @('node_modules','target','.next','dist','.turbo','.vite','.parcel-cache')
$found = New-Object System.Collections.Generic.List[string]
function Walk([string]$dir) {
  foreach ($d in [System.IO.Directory]::EnumerateDirectories($dir)) {
    $n = [System.IO.Path]::GetFileName($d)
    if ($n -eq '.git') { continue }
    if ($names -contains $n) { $found.Add($d) } else { try { Walk $d } catch {} }
  }
}
Walk $Root
if ($WhatIf) { $found | ForEach-Object { "would delete: $($_.Substring($Root.Length + 1))" }; return }
$before = (Get-PSDrive ($Root.Substring(0,1))).Free
foreach ($f in $found) {
  $item = Get-Item -LiteralPath $f -Force
  if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { [System.IO.Directory]::Delete($f, $false) }
  else { cmd /c "rmdir /s /q `"$f`"" 2>$null }
  if (Test-Path -LiteralPath $f) { "LEFT (long path or in use): $($f.Substring($Root.Length + 1))" }
}
$after = (Get-PSDrive ($Root.Substring(0,1))).Free
$inv = [Globalization.CultureInfo]::InvariantCulture
'folders: {0}; freed {1} GB' -f $found.Count, (($after - $before) / 1GB).ToString('0.0', $inv)
