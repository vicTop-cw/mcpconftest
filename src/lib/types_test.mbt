///| Test suite for mcpconftest (in-package tests).

///| Test: CheckResult constructors work correctly.
test "check_result_pass" {
  let r = CheckResult::pass("name", "message")
  assert_eq(r.name, "name")
  assert_eq(r.severity, Pass)
  assert_eq(r.evidence, None)
}

///| Test: CheckResult fail constructor works.
test "check_result_fail" {
  let r = CheckResult::fail("name", "message", "evidence")
  assert_eq(r.severity, Fail)
  match r.evidence {
    Some(e) => assert_eq(e, "evidence")
    None => assert_eq("evidence", "should be Some")
  }
}

///| Test: Report summarize works.
test "report_summarize" {
  let results : Array[CheckResult] = [
    CheckResult::pass("a", "msg"),
    CheckResult::pass("b", "msg"),
    CheckResult::fail("c", "msg", "ev"),
  ]
  let report = build_report(results, "test", "2026-07-28", "now")
  let summary = report.summarize()
  assert_eq(summary.get("pass"), Some(2))
  assert_eq(summary.get("fail"), Some(1))
}

///| Test: Report has_failures works.
test "report_has_failures" {
  let results : Array[CheckResult] = [CheckResult::pass("a", "msg")]
  let report = build_report(results, "test", "2026-07-28", "now")
  assert_eq(report.has_failures(), false)
}
