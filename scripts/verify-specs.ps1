# L1 规格即真源门禁：比对 specs/ 与 list-checks 输出
# 用法: powershell -File scripts/verify-specs.ps1 [path-to-cmd.js]
param(
  [string]$CmdJs = "_build\js\release\build\cmd\cmd.js"
)
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

$manifest = Get-Content "specs\manifest.json" -Raw | ConvertFrom-Json
$specIds = @($manifest | ForEach-Object { $_.check_id })
Write-Host "[L1] specs manifest entries: $($specIds.Count)"

if (-not (Test-Path $CmdJs)) {
  Write-Host "[L1] SKIP: $CmdJs not built. Run 'moon build --target js' first."
  exit 0
}

function Normalize([string]$s) {
  return ($s.ToLowerInvariant() -replace '[_\-\s/]', '')
}

$out = node $CmdJs list-checks --json 2>&1 | Out-String
$names = @()
foreach ($line in ($out -split "`n")) {
  $trimmed = $line.Trim()
  if ($trimmed -eq "" -or $trimmed -match "^\*\*") { continue }
  if ($trimmed -match '^\-\s+(.+?)(?:\s*—|\s*$)' -or $trimmed -match '^\d+\.\s+(.+?)(?:\s*—|\s*$)') {
    $names += $Matches[1].Trim()
  } else {
    $names += $trimmed
  }
}
$normNames = @($names | ForEach-Object { Normalize $_ })
Write-Host "[L1] list-checks names parsed: $($normNames.Count)"

$failures = New-Object System.Collections.Generic.List[string]
foreach ($m in $manifest) {
  $name = ($m.check_id -split "\.")[-1]
  $norm = Normalize $name
  $hit = $normNames | Where-Object { $_ -like "*$norm*" }
  if (-not $hit) { $failures.Add($m.check_id) }
}
if ($failures.Count -gt 0) {
  Write-Host "[L1] FAIL: specs without list-checks coverage:"
  foreach ($f in $failures) { Write-Host "  - $f" }
  exit 1
}
Write-Host "[L1] OK: all $($manifest.Count) spec entries covered by list-checks"
exit 0
