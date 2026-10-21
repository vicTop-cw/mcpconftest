# L1 规格即真源门禁：比对 specs/ 与 list-checks 输出；R3 实现<->规格双向闭合。
# 用法: powershell -File scripts/verify-specs.ps1 [path-to-cmd.js]
param(
  [string]$CmdJs = ""
)
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

$manifest = Get-Content "specs\manifest.json" -Raw | ConvertFrom-Json
$specIds = @($manifest | ForEach-Object { $_.check_id })
Write-Host "[L1] specs manifest entries: $($specIds.Count)"

if ($CmdJs -eq "") {
  $candidates = @(
    "_build\js\release\build\cmd\cmd.js",
    "_build\js\debug\build\cmd\cmd.js"
  )
  foreach ($c in $candidates) { if (Test-Path $c) { $CmdJs = $c; break } }
}
$l1Ok = $true
if (-not (Test-Path $CmdJs)) {
  Write-Host "[L1] SKIP: cmd.js not built ($candidates -join ' / '). Run 'moon build --target js' first. R3 仍执行。"
  $l1Ok = $false
}

function Normalize([string]$s) {
  return ($s.ToLowerInvariant() -replace '[_\-\s/]', '')
}

$out = node $CmdJs list-checks --json 2>&1 | Out-String
$names = @()
foreach ($line in ($out -split "`n")) {
  $trimmed = $line.Trim()
  if ($trimmed -eq "" -or $trimmed -match "^\*\*") { continue }
  if ($trimmed -match "mcpconftest check categories") { continue }
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

# ==================== R3 双向闭合（IRON LAW R3，轻量版） ====================
# 静态扫描 src/lib/checks.mbt 与 src/lib/fist_ops.mbt 中的 check_id 字面量，
# 与 specs/**/spec.json（manifest.json 为索引）双向对应。
# 命名体系：实现用 "场景.检查名"（init.jsonrpc），规格用 "mcp.类别.检查名"（mcp.core.initialize）。
# 对应关系按 主题前缀 -> 规格类别 人工复核映射（下方 $ThemeToCategory，2026-10-19 复核）。
# mcpcf.* 为自实现 OpsEngine（src/lib/ops_*.mbt，路线 A 已移除 fist-mbt 包依赖）内部工具，
# 非协议检查项，豁免入规格树（IRON-LAWS.md R3 豁免声明）；下方对 'mcpcf' 前缀按 internal 计数。
$srcFiles = @('src\lib\checks.mbt', 'src\lib\fist_ops.mbt')
$ThemeToCategory = @{
  'init' = 'core'; 'caps' = 'core';
  'tools_list' = 'tools'; 'tools_call' = 'tools';
  'notifications' = 'session'; 'idempotency' = 'session';
  'resources_list' = 'resources'; 'resources_read' = 'resources'; 'subscribe' = 'resources';
  'prompts_list' = 'prompts';
  'ping' = 'transport'; 'keepalive' = 'transport';
  'batch' = 'protocol'; 'error_schema' = 'protocol';
  'logging' = 'logging'; 'completion' = 'completion'; 'sampling' = 'sampling';
  'discover' = 'stateless'; 'list_cache' = 'stateless'; 'missing_capability' = 'stateless'; 'mrtr' = 'stateless';
  'resource_error_code' = 'stateless'; 'schema_2020_12' = 'stateless'; 'self_describing' = 'stateless';
  'version_negotiation' = 'stateless'; 'deprecations' = 'stateless'
}
$CategoryToThemes = @{}
foreach ($k in $ThemeToCategory.Keys) {
  $c = $ThemeToCategory[$k]
  if (-not $CategoryToThemes.ContainsKey($c)) { $CategoryToThemes[$c] = New-Object System.Collections.Generic.List[string] }
  $CategoryToThemes[$c].Add($k)
}
$manifestCats = @($manifest | ForEach-Object { ($_.check_id -split '\.')[1] } | Sort-Object -Unique)
$specCatDirs = @(Get-ChildItem (Join-Path (Split-Path $PSScriptRoot -Parent) 'specs') -Directory | Select-Object -ExpandProperty Name)

$srcText = ''
foreach ($f in $srcFiles) {
  $p = Join-Path (Split-Path $PSScriptRoot -Parent) $f
  if (Test-Path $p) { $srcText += "`n" + (Get-Content $p -Raw -Encoding UTF8) }
}
$checkIds = @([regex]::Matches($srcText, '"([a-z_][a-z0-9_]*(?:\.[a-z0-9_.]+)+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)

# R3-FWD: 实现字面量 -> 规格类别存在
$fwdFail = New-Object System.Collections.Generic.List[string]
$internal = New-Object System.Collections.Generic.List[string]
$unmapped = New-Object System.Collections.Generic.List[string]
foreach ($id in $checkIds) {
  $head = ($id -split '\.')[0]
  if ($head -eq 'mcpcf') { $internal.Add($id); continue }
  if (-not $ThemeToCategory.ContainsKey($head)) { $unmapped.Add($id); continue }
  $cat = $ThemeToCategory[$head]
  if ($manifestCats -notcontains $cat -or $specCatDirs -notcontains $cat) {
    $fwdFail.Add("$id -> $cat")
  }
}
# R3-REV: 规格类别 -> 实现主题字面量存在
$revFail = New-Object System.Collections.Generic.List[string]
foreach ($cat in $manifestCats) {
  if (-not $CategoryToThemes.ContainsKey($cat)) { $revFail.Add("$cat (无映射)"); continue }
  $any = $false
  foreach ($th in $CategoryToThemes[$cat]) {
    if (@($checkIds | Where-Object { ($_ -split '\.')[0] -eq $th }).Count -gt 0) { $any = $true; break }
  }
  if (-not $any) { $revFail.Add($cat) }
}
$r3Ok = ($fwdFail.Count -eq 0) -and ($revFail.Count -eq 0) -and ($unmapped.Count -eq 0)
Write-Host "[R3-FWD] 实现 check_id 字面量 -> 规格类别: $($checkIds.Count - $internal.Count) mapped / $($internal.Count) internal(mcpcf)"
if ($unmapped.Count -gt 0) { Write-Host "  [R3-FWD] UNMAPPED 主题（需人工复核/加 EXEMPT）: $($unmapped -join ', ')" }
if ($fwdFail.Count -gt 0) { Write-Host "  [R3-FWD] FAIL: $($fwdFail -join '; ')" }
Write-Host "[R3-REV] 规格类别 -> 实现主题: $($manifestCats.Count) categories"
if ($revFail.Count -gt 0) { Write-Host "  [R3-REV] FAIL: $($revFail -join ', ')" }
if ($r3Ok) { Write-Host "[R3] OK: 实现<->规格 双向闭合通过" }
else {
  Write-Host "[R3] FAIL: 双向闭合未通过（见上）" -ForegroundColor Red
  exit 1
}
exit 0
