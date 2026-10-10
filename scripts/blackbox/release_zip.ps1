#!/usr/bin/env pwsh
<#
scripts/blackbox/release_zip.ps1 —— 打包 mcpconftest JS 发行资产（mcpconftest-js-v<version>.zip）

用途：一行安装（install_onecmd.ps1 / install.sh）下载的资产就是本脚本产物。
内容：mcpconftest.js（moon build --target js --release 的可执行 bundle）
      + package.json（{"type":"module"}，ESM 目录下 bundle 全链路可用）
用法：powershell -ExecutionPolicy Bypass -File scripts/blackbox/release_zip.ps1
      （-Version 可覆盖；缺省从 moon.mod 解析）
#>
param(
    [string]$Version = "",
    [string]$OutDir = "$PSScriptRoot\..\..\_release"
)
$ErrorActionPreference = "Stop"
$REPO_ROOT = (Resolve-Path "$PSScriptRoot\..\..").Path

# 版本：缺省从 moon.mod 解析
if ($Version -eq "") {
    $mm = Get-Content (Join-Path $REPO_ROOT "moon.mod") -Raw -Encoding UTF8
    if ($mm -match '(?m)^\s*version\s*=\s*"([^"]+)"') { $Version = $matches[1] }
    else { Write-Host "[x] 无法从 moon.mod 解析版本，请用 -Version" -ForegroundColor Red; exit 1 }
}

Write-Host "=== mcpconftest release zip v$Version ===" -ForegroundColor Cyan

# 1. moon build js release
# PS 5.1 下 2>&1 会把 native stderr 转成 NativeCommandError 且与顶层 EAP=Stop 打架，
# 直接丢弃 stderr、以退出码为准（失败时重跑一次显示错误尾部）。
Write-Host "[build] moon build --target js --release ..." -ForegroundColor Yellow
Push-Location $REPO_ROOT
# PS 5.1：native stderr 在 EAP=Stop 下经 2>&1/2>$null 都会触发 NativeCommandError 终止，
# 必须临时降 EAP=Continue 再合并 stderr。
$prevErr = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$buildOut = (& moon build --target js --release 2>&1 | Out-String)
$ExitCode = $LASTEXITCODE
$ErrorActionPreference = $prevErr
Pop-Location
$buildOut -split "`r?`n" | Where-Object { $_ -ne "" } | Select-Object -Last 3 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
if ($ExitCode -ne 0) { Write-Host "[x] build failed (exit $ExitCode)" -ForegroundColor Red; exit 1 }

# 2. 定位 cmd.js（release 优先，fallback debug）
$candidates = @(
    "$REPO_ROOT\_build\js\release\build\cmd\cmd.js",
    "$REPO_ROOT\_build\js\debug\build\cmd\cmd.js"
)
$jsMain = $null
foreach ($c in $candidates) { if (Test-Path $c) { $jsMain = $c; break } }
if (-not $jsMain) { Write-Host "[x] cmd.js 产物未找到（候选：$($candidates -join ' / ')）" -ForegroundColor Red; exit 1 }
Write-Host "[ok] $jsMain" -ForegroundColor Green

# 3. 组装 stage
$stage = Join-Path $REPO_ROOT "_release_stage"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Copy-Item $jsMain "$stage\mcpconftest.js" -Force
'{"type":"module"}' | Set-Content "$stage\package.json" -Encoding ASCII

# 4. 打包
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$zip = Join-Path $OutDir "mcpconftest-js-v$Version.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path "$stage\*" -DestinationPath $zip -Force
$kb = [math]::Round((Get-Item $zip).Length / 1KB, 1)
Remove-Item -Recurse -Force $stage

# 5. 自检
Write-Host "[check] node mcpconftest.js version ..." -ForegroundColor Yellow
$prevErr = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$tmpEx = Join-Path $env:TEMP ("mct-zip-check-" + [guid]::NewGuid().ToString("N"))
Expand-Archive -Path $zip -DestinationPath $tmpEx -Force
$vOut = (& node (Join-Path $tmpEx "mcpconftest.js") version 2>$null | Out-String).Trim()
$ErrorActionPreference = $prevErr
if ($vOut) { Write-Host "  [ok] $vOut" -ForegroundColor Green }
else { Write-Host "  [x] 产物跑不出版本" -ForegroundColor Red; Remove-Item -Recurse -Force $tmpEx; exit 1 }
Remove-Item -Recurse -Force $tmpEx

Write-Host ""
Write-Host "[ok] $zip ($kb KB)" -ForegroundColor Green
