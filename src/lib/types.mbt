///| Shared types for mcpconftest.

///| Severity of a check finding.
pub(all) enum Severity {
  Pass
  Fail
  Skip
  Warn
} derive(Eq, Debug)

pub extend Severity with Eq::{not_equal, equal}
pub extend Severity with @moonbitlang/core/debug.Debug::{to_repr}

///| A single check result.
pub(all) struct CheckResult {
  mut name : String
  mut severity : Severity
  mut message : String
  mut evidence : Option[String]
  mut timing_ms : Int
}

///| Full report for one server probe.
pub(all) struct Report {
  mut server_cmd : String
  mut protocol_version : String
  mut results : Array[CheckResult]
  mut summary : Map[String, Int]
  mut timestamp : String
  mut total_timing_ms : Int
  mut avg_timing_ms : Int
}

///| Create a passing result.
pub fn CheckResult::pass(name : String, msg : String) -> CheckResult {
  { name, severity: Pass, message: msg, evidence: None, timing_ms: 0 }
}

///| Create a failing result.
pub fn CheckResult::fail(name : String, msg : String, ev : String) -> CheckResult {
  { name, severity: Fail, message: msg, evidence: Some(ev), timing_ms: 0 }
}

///| Create a skipped result.
pub fn CheckResult::skip(name : String, msg : String) -> CheckResult {
  { name, severity: Skip, message: msg, evidence: None, timing_ms: 0 }
}

///| Count results by severity.
pub fn Report::summarize(self : Report) -> Map[String, Int] {
  let m : Map[String, Int] = Map([])
  for r in self.results {
    let k = match r.severity {
      Pass => "pass"
      Fail => "fail"
      Skip => "skip"
      Warn => "warn"
    }
    let cur = match m.get(k) {
      Some(n) => n
      None => 0
    }
    ignore(m.set(k, cur + 1))
  }
  m
}

///| True if any result is Fail.
pub fn Report::has_failures(self : Report) -> Bool {
  for r in self.results {
    if r.severity == Fail { return true }
  }
  false
}


