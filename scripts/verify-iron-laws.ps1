# verify-iron-laws.ps1 — mcpconftest 自研铁律一键自检
# IRON LAW: R1-R6 (docs/IRON-LAWS.md)
# 全量门禁已接通：L0-L6 覆盖文档完整性 + R2 指纹实算 + R3 双向闭合 + R5 fixture 快照 diff（含 R1 skip_reason 检查）。
# R4 三重门禁（双端测试+指纹diff+语料覆盖率）由 scripts/ci.sh 承担，本脚本 L5/L6 为其子集。
# 用法: pwsh ./scripts/verify-iron-laws.ps1 [-SkipFingerprint] [-Verbose]
# 退出码: 0 = 全部通过; 1 = 任一铁律自检失败。

param(
  [switch]$SkipFingerprint,
  [switch]$Verbose
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$LawsDoc = Join-Path $RepoRoot 'docs\IRON-LAWS.md'
$SpecsDir = Join-Path $RepoRoot 'specs'
$Results = [System.Collections.Generic.List[object]]::new()

function Write-Step {
  param([string]$Name, [bool]$Ok, [string]$Detail = '')
  $status = if ($Ok) { 'PASS' } else { 'FAIL' }
  $line = "[$status] $Name"
  if ($Detail) { $line += " :: $Detail" }
  $Results.Add([pscustomobject]@{ Name = $Name; Ok = $Ok; Detail = $Detail })
  Write-Host $line
  if (-not $Ok) { Write-Host "  -> 违反 IRON LAW 门禁，请修复后重跑。" -ForegroundColor Red }
}

# ---- L0. 铁律文档存在 ----
$docExists = Test-Path $LawsDoc
Write-Step 'L0 IRON-LAWS.md 存在' $docExists ($(if ($docExists) { $LawsDoc } else { '缺失' }))

# ---- L1. 六条铁律完整 ----
$lawBlocks = 0
$missingLaws = @()
if ($docExists) {
  $doc = Get-Content $LawsDoc -Raw -Encoding UTF8
  foreach ($n in 1..6) {
    if ($doc -match "(?m)^## R$n ") { $lawBlocks++ } else { $missingLaws += "R$n" }
  }
}
$lawsComplete = $docExists -and ($lawBlocks -eq 6)
Write-Step 'L1 六条铁律完整 (R1-R6)' $lawsComplete ($(if ($missingLaws.Count -gt 0) { "缺失: $($missingLaws -join ',')" } else { "$lawBlocks/6" }))

# ---- L2. 每条铁律都有自检命令 ----
$cmdsOk = $true
$cmdNote = ''
if ($docExists) {
  $doc = Get-Content $LawsDoc -Raw -Encoding UTF8
  $noCmd = @()
  foreach ($n in 1..6) {
    # 每条铁律块内必须出现 "**自检命令**"（以 R1-R6 块为单位解析）
    $blockMatch = [regex]::Match($doc, "(?ms)^## R$n .*?(?=^## R|^## 自检命令总览)")
    if (-not $blockMatch.Success -or $blockMatch.Value -notmatch '自检命令') { $noCmd += "R$n" }
  }
  if ($noCmd.Count -gt 0) { $cmdsOk = $false; $cmdNote = "缺少自检命令: $($noCmd -join ',')" }
  else { $cmdNote = 'R1-R6 均有自检命令' }
}
Write-Step 'L2 每条铁律含自检命令' $cmdsOk $cmdNote

# ---- L3. specs 规格树存在（R2/R3 前置） ----
$specCount = if (Test-Path $SpecsDir) { (Get-ChildItem $SpecsDir -Recurse -Filter 'spec.json' -File).Count } else { 0 }
$specsOk = $specCount -gt 0
Write-Step 'L3 specs/**/spec.json 规格树存在' $specsOk "$specCount 个 spec.json"

# ---- L4. R2 指纹预检：报告含 spec_fingerprint（fixture 实跑，可跳过） ----
if ($SkipFingerprint) {
  Write-Step 'L4 R2 指纹预检 (skipped by -SkipFingerprint)' $true '用户跳过'
} else {
  $reportDir = Join-Path $env:TEMP 'mcpconftest-ironlaws-report'
  if (Test-Path $reportDir) { Remove-Item $reportDir -Recurse -Force }
  try {
    Push-Location $RepoRoot
    $prevErr = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    moon run cmd -- run --fixture --report $reportDir 2>&1 | Out-Null
    $ErrorActionPreference = $prevErr
    Pop-Location
    $jsonPath = Join-Path $reportDir 'report.json'
    $hasFp = $false
    $hasVerdict = $false
    if (Test-Path $jsonPath) {
      $raw = Get-Content $jsonPath -Raw -Encoding UTF8
      $hasFp = $raw -match '"spec_fingerprint"\s*:\s*"sha256:[0-9a-f]{64}"'
      $hasVerdict = $raw -match '"verdict"\s*:\s*"(pass|fail|inconclusive)"'
    }
    $fpOk = $hasFp -and $hasVerdict
    Write-Step 'L4 R2/R6 指纹与 verdict 预检 (fixture)' $fpOk "spec_fingerprint=$hasFp verdict=$hasVerdict (report.json)"
    if (Test-Path $reportDir) { Remove-Item $reportDir -Recurse -Force }
  } catch {
    Write-Step 'L4 R2/R6 指纹与 verdict 预检 (fixture)' $false "执行失败: $($_.Exception.Message)"
  }
}

# ---- L5. R3 实现<->规格双向闭合（verify-specs.ps1） ----
$specExit = -1
$specErr = ''
try {
  Push-Location $RepoRoot
  & (Join-Path $RepoRoot 'scripts\verify-specs.ps1') 2>&1 | Out-Null
  $specExit = $LASTEXITCODE
  Pop-Location
} catch {
  $specErr = $_.Exception.Message
  Pop-Location
}
$r3Ok = $specExit -eq 0
Write-Step 'L5 R3 实现<->规格双向闭合' $r3Ok ($(if ($r3Ok) { 'verify-specs PASS' } elseif ($specErr) { $specErr } else { "verify-specs exit=$specExit" }))

# ---- L6. R5 fixture 快照 diff（verify-fixture.ps1） ----
$fxExit = -1
$fxErr = ''
$fxDir = Join-Path $env:TEMP ("mcpconftest-fixture-" + [guid]::NewGuid().ToString('N'))
try {
  Push-Location $RepoRoot
  $prevErr = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  moon run cmd -- run --fixture --report $fxDir 2>&1 | Out-Null
  $ErrorActionPreference = $prevErr
  Pop-Location
  $repJson = Join-Path $fxDir 'report.json'
  & (Join-Path $RepoRoot 'scripts\verify-fixture.ps1') -ReportJson $repJson -ExpectedJson (Join-Path $RepoRoot 'scripts\fixture-expected.json') 2>&1 | Out-Null
  $fxExit = $LASTEXITCODE
} catch {
  $fxErr = $_.Exception.Message
  Pop-Location
}
if (Test-Path $fxDir) { Remove-Item $fxDir -Recurse -Force }
$r5Ok = $fxExit -eq 0
Write-Step 'L6 R5 fixture 快照 diff' $r5Ok ($(if ($r5Ok) { 'fixture 与快照一致' } elseif ($fxErr) { $fxErr } else { "verify-fixture exit=$fxExit" }))

# ---- 汇总 ----
$failed = @($Results | Where-Object { -not $_.Ok })
Write-Host ''
if ($failed.Count -eq 0) {
  Write-Host "IRON LAWS: ALL PASS ($($Results.Count)/$($Results.Count))" -ForegroundColor Green
  exit 0
} else {
  Write-Host "IRON LAWS: $($failed.Count) FAILED ($($Results.Count - $failed.Count)/$($Results.Count))" -ForegroundColor Red
  exit 1
}
