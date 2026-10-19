///| Shared types for mcpconftest.

///|
/// Severity of a check finding.
pub(all) enum Severity {
  Pass
  Fail
  Skip
  Warn
} derive(Eq, Debug)

///|
pub extend Severity with Eq::{not_equal, equal}

///|
pub extend Severity with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A single check result.
pub(all) struct CheckResult {
  mut name : String
  mut severity : Severity
  mut message : String
  mut evidence : String?
  mut timing_ms : Int32
  mut skip_reason : String
  mut hard : Bool
}

///| Full report for one server probe.

///| IRON LAW R2/R6: spec_fingerprint is the deterministic joint fingerprint

///| of the spec tree the probe was validated against; verdict() classifies

///|
/// the run (pass / fail / inconclusive).
pub(all) struct Report {
  mut server_cmd : String
  mut protocol_version : String
  mut results : Array[CheckResult]
  mut summary : Map[String, Int32]
  mut timestamp : String
  mut total_timing_ms : Int32
  mut avg_timing_ms : Int32
  mut spec_fingerprint : String
}

///|
/// Create a passing result.
pub fn CheckResult::pass(name : String, msg : String) -> CheckResult {
  {
    name,
    severity: Pass,
    message: msg,
    evidence: None,
    timing_ms: 0,
    skip_reason: "",
    hard: false,
  }
}

///| Create a failing result (legacy constructor, kept for compatibility).

///| Deprecated: prefer `hard_fail` / `soft_fail` (IRON LAW R1). Legacy `fail`

///|
/// keeps the original strict semantics and is treated as a HARD violation.
pub fn CheckResult::fail(
  name : String,
  msg : String,
  ev : String,
) -> CheckResult {
  {
    name,
    severity: Fail,
    message: msg,
    evidence: Some(ev),
    timing_ms: 0,
    skip_reason: "",
    hard: true,
  }
}

///| Create a skipped result (legacy constructor, kept for compatibility).

///| Deprecated: prefer `skip_with_reason` (IRON LAW R1). Legacy `skip` has an

///|
/// empty skip_reason, so any verdict derived from it is inconclusive.
pub fn CheckResult::skip(name : String, msg : String) -> CheckResult {
  {
    name,
    severity: Skip,
    message: msg,
    evidence: None,
    timing_ms: 0,
    skip_reason: "",
    hard: false,
  }
}

///| Create a HARD failure (IRON LAW R1): a spec violation that must block

///|
/// a "pass" verdict.
pub fn CheckResult::hard_fail(
  name : String,
  msg : String,
  ev : String,
) -> CheckResult {
  {
    name,
    severity: Fail,
    message: msg,
    evidence: Some(ev),
    timing_ms: 0,
    skip_reason: "",
    hard: true,
  }
}

///| Create a SOFT failure (IRON LAW R1): a violation worth reporting but

///|
/// not blocking for a "pass" verdict on its own.
pub fn CheckResult::soft_fail(
  name : String,
  msg : String,
  ev : String,
) -> CheckResult {
  {
    name,
    severity: Fail,
    message: msg,
    evidence: Some(ev),
    timing_ms: 0,
    skip_reason: "",
    hard: false,
  }
}

///| Create a skipped result with a mandatory reason (IRON LAW R1).

///|
/// A Skip without a reason makes the overall verdict inconclusive.
pub fn CheckResult::skip_with_reason(
  name : String,
  msg : String,
  reason : String,
) -> CheckResult {
  {
    name,
    severity: Skip,
    message: msg,
    evidence: None,
    timing_ms: 0,
    skip_reason: reason,
    hard: false,
  }
}

///|
/// Count results by severity.
pub fn Report::summarize(self : Report) -> Map[String, Int32] {
  let m : Map[String, Int32] = Map([])
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

///|
/// True if any result is Fail.
pub fn Report::has_failures(self : Report) -> Bool {
  for r in self.results {
    if r.severity == Fail {
      return true
    }
  }
  false
}
