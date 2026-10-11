# L3 有规必有语料门禁：统计 corpus 覆盖率
# 用法: powershell -File scripts/verify-corpus.ps1 [-Threshold 60]
param(
  [int]$Threshold = 60
)
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

$manifest = Get-Content "specs\manifest.json" -Raw | ConvertFrom-Json
$total = $manifest.Count
$covered = 0
$missing = @()
foreach ($m in $manifest) {
  $id = $m.check_id
  $passDir = "corpus\$id\pass"
  $failDir = "corpus\$id\fail"
  $nPass = if (Test-Path $passDir) { (Get-ChildItem $passDir -File -ErrorAction SilentlyContinue).Count } else { 0 }
  $nFail = if (Test-Path $failDir) { (Get-ChildItem $failDir -File -ErrorAction SilentlyContinue).Count } else { 0 }
  if ($nPass -ge 1 -and $nFail -ge 1) { $covered++ } else { $missing += "$id (pass=$nPass fail=$nFail)" }
}
$pct = [math]::Round(100.0 * $covered / $total, 1)
Write-Host "[L3] corpus coverage: $covered/$total = $pct% (threshold $Threshold%)"
if ($missing.Count -gt 0) {
  Write-Host "[L3] missing corpus:"
  $missing | ForEach-Object { Write-Host "  - $_" }
}
if ($pct -lt $Threshold) {
  Write-Host "[L3] FAIL: coverage below threshold"
  exit 1
}
Write-Host "[L3] OK"
exit 0
