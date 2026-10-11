# 生成新检查项规格骨架（L1/L4 就绪）
# 用法: powershell -File scripts/new-check.ps1 -Id initialize -Category core -Title "initialize 握手检查"
param(
  [Parameter(Mandatory=$true)][string]$Id,
  [Parameter(Mandatory=$true)][string]$Category,
  [Parameter(Mandatory=$true)][string]$Title
)
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

$checkId = "mcp.$Category.$Id"
$dir = "specs\$Category\$Id"
New-Item -ItemType Directory -Force -Path "$dir\pass", "$dir\fail" | Out-Null

$spec = [ordered]@{
  check_id      = $checkId
  category      = $Category
  title         = $Title
  operations    = @()
  preconditions = @("server_is_stdio")
  laws          = @()
  backends      = @("js", "native")
  version       = "0.8.0"
}

# 确定性指纹：对规范化 JSON 序列计算 sha256（不含 fingerprint 字段本身）
$json = $spec | ConvertTo-Json -Depth 10 -Compress
$sorted = ($json -replace '\s+', '')
$sha = [System.Security.Cryptography.SHA256]::Create()
$bytes = [System.Text.Encoding]::UTF8.GetBytes($sorted)
$hash = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ""
$spec.fingerprint = "sha256:$hash"

$spec | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 "$dir\spec.json"
@("# $checkId", "", $Title, "", "规格真源：spec.json（L1 规格即真源）。") | Set-Content -Encoding UTF8 "$dir\README.md"
Write-Host "[new-check] created $dir\spec.json (fingerprint $($spec.fingerprint))"
Write-Host "[new-check] next: add corpus examples under corpus\$checkId\pass|fail, then implement in src/lib/checks.mbt"
