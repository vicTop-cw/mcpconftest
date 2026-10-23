# verify-fixture.ps1 — IRON LAW R5：fixture 实跑报告与期望快照 diff
# 用法:
#   moon run cmd -- run --fixture --report <dir>
#   pwsh -File scripts/verify-fixture.ps1 -ReportJson <dir>/report.json [-ExpectedJson scripts/fixture-expected.json]
# 退出码: 0 = 与快照一致; 1 = 不一致（计数/verdict 漂移）
param(
  [string]$ReportJson = '',
  [string]$ExpectedJson = ''
)
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
if ($ExpectedJson -eq '') { $ExpectedJson = Join-Path $PSScriptRoot 'fixture-expected.json' }
if ($ReportJson -eq '') {
  $ReportJson = Join-Path (Join-Path $env:TEMP 'mcpconftest-fixture-report') 'report.json'
}
if (-not (Test-Path $ExpectedJson)) { Write-Host "[R5] FAIL: 期望快照缺失 $ExpectedJson"; exit 1 }
if (-not (Test-Path $ReportJson)) { Write-Host "[R5] FAIL: 实跑报告缺失 $ReportJson"; exit 1 }

$exp = Get-Content $ExpectedJson -Raw -Encoding UTF8 | ConvertFrom-Json
$rep = Get-Content $ReportJson -Raw -Encoding UTF8 | ConvertFrom-Json
$sum = $rep.summary
if ($null -eq $sum) {
  $sum = [pscustomobject]@{ pass = 0; fail = 0; skip = 0; warn = 0 }
  foreach ($r in $rep.results) {
    switch ($r.severity) {
      'pass' { $sum.pass++ }
      'fail' { $sum.fail++ }
      'skip' { $sum.skip++ }
      'warn' { $sum.warn++ }
    }
  }
}
$total = $sum.pass + $sum.fail + $sum.skip + $sum.warn

$issues = New-Object System.Collections.Generic.List[string]
if ($rep.verdict -ne $exp.verdict) { $issues.Add("verdict $($rep.verdict) != $($exp.verdict)") }
if ($sum.pass -ne $exp.summary.pass) { $issues.Add("pass $($sum.pass) != $($exp.summary.pass)") }
if ($sum.fail -ne $exp.summary.fail) { $issues.Add("fail $($sum.fail) != $($exp.summary.fail)") }
if ($sum.skip -ne $exp.summary.skip) { $issues.Add("skip $($sum.skip) != $($exp.summary.skip)") }
if ($sum.warn -ne $exp.summary.warn) { $issues.Add("warn $($sum.warn) != $($exp.summary.warn)") }
if ($total -ne $exp.total) { $issues.Add("total $total != $($exp.total)") }

# R1 铁律补充：所有 skip 项必须带 skip_reason（SKIP_WITH_REASON），无理由 skip 判 inconclusive
$noReasonSkips = @()
foreach ($r in $rep.results) {
  if ($r.severity -eq 'skip' -and [string]::IsNullOrEmpty($r.skip_reason)) {
    $noReasonSkips += $r.name
  }
}
if ($noReasonSkips.Count -gt 0) {
  $issues.Add("R1: $($noReasonSkips.Count) skip 项无 skip_reason（违反 SKIP_WITH_REASON）: $($noReasonSkips -join ', ')")
}

if ($issues.Count -eq 0) {
  Write-Host "[R5] OK: fixture 与快照一致 (verdict=$($rep.verdict) $($sum.pass)p/$($sum.fail)f/$($sum.skip)s/$($sum.warn)w)"
  exit 0
} else {
  Write-Host "[R5] FAIL: $($issues -join '; ')"
  exit 1
}
