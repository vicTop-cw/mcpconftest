///|
/// Probe orchestration: runs checks against servers and writes reports.
/// This module is transport-agnostic — callers provide a Session factory.
pub struct ProbeRun {
  ok : Bool
  results : Array[CheckResult]
  cmd : String
}

///|
/// Push all items from a CheckResult array into results.
pub fn push_all(
  results : Array[CheckResult],
  items : Array[CheckResult],
) -> Unit {
  for x in items {
    results.push(x)
  }
}

///|
/// Run an async check function and set timing_ms on all returned results.
async fn timed_check(f : async () -> Array[CheckResult]) -> Array[CheckResult] {
  let start = now_ms()
  let results = f()
  let elapsed = now_ms() - start
  for r in results {
    r.timing_ms = elapsed
  }
  results
}

///|
/// Count results by severity name ("pass"/"fail").
pub fn count(results : Array[CheckResult], sev : String) -> Int32 {
  let mut n = 0
  for r in results {
    match r.severity {
      Pass => if sev == "pass" { n += 1 }
      Fail => if sev == "fail" { n += 1 }
      _ => ()
    }
  }
  n
}

///|
/// Count transport-level errors (timeout / parse failures).
pub fn count_err(results : Array[CheckResult]) -> Int32 {
  let mut n = 0
  for r in results {
    if r.name.has_suffix(".timeout") ||
      (r.name.has_suffix(".parse") && r.severity == Fail) {
      n += 1
    }
  }
  n
}

///|
/// Probe the built-in fixture with strict expectations.
pub async fn run_fixture() -> ProbeRun {
  let cmd = "node tests/fixtures/mcp_fixture_server.js"
  let session = Session::new(cmd)
  if !session.alive {
    return { ok: false, results: [], cmd, }
  }
  let results : Array[CheckResult] = []
  let mut ok = true
  let r1 = timed_check(async fn() { check_initialize(session) })
  push_all(results, r1)
  if count(r1, "pass") < 3 {
    ok = false
  }
  let r2 = timed_check(async fn() { check_capabilities(session) })
  push_all(results, r2)
  if count(r2, "pass") < 1 {
    ok = false
  }
  let r3 = timed_check(async fn() { check_tools_list(session) })
  push_all(results, r3)
  if count(r3, "fail") < 1 {
    ok = false
  }
  let r4 = timed_check(async fn() { check_tools_call(session) })
  push_all(results, r4)
  if count_err(r4) > 0 {
    ok = false
  }
  let r5 = timed_check(async fn() { check_notifications(session) })
  push_all(results, r5)
  if count(r5, "pass") < 2 {
    ok = false
  }
  let r6 = timed_check(async fn() { check_idempotency(session) })
  push_all(results, r6)
  if count(r6, "pass") < 1 {
    ok = false
  }
  let r7 = timed_check(async fn() { check_resources_list(session) })
  push_all(results, r7)
  let r8 = timed_check(async fn() { check_prompts_list(session) })
  push_all(results, r8)
  let r9 = timed_check(async fn() { check_resources_read_error(session) })
  push_all(results, r9)
  let r10 = timed_check(async fn() { check_ping(session) })
  push_all(results, r10)
  let r11 = timed_check(async fn() { check_keepalive(session) })
  push_all(results, r11)
  let r12 = timed_check(async fn() { check_protocol_negotiation(session) })
  push_all(results, r12)
  let r13 = timed_check(async fn() { check_logging(session) })
  push_all(results, r13)
  let r14 = timed_check(async fn() { check_completion(session) })
  push_all(results, r14)
  let r15 = timed_check(async fn() { check_subscribe(session) })
  push_all(results, r15)
  let r16 = timed_check(async fn() { check_sampling(session) })
  push_all(results, r16)
  let r17 = timed_check(async fn() { check_batch(session) })
  push_all(results, r17)
  if count(r17, "pass") < 3 {
    ok = false
  }
  let r18 = timed_check(async fn() { check_id_matching(session) })
  push_all(results, r18)
  if count(r18, "pass") < 4 {
    ok = false
  }
  let r19 = timed_check(async fn() { check_error_schema(session) })
  push_all(results, r19)
  if count(r19, "fail") > 0 {
    ok = false
  }
  // 2026-07-28 stateless core checks — the fixture is a legacy stateful
  // server, so violations here are expected (they prove detection works).
  let r20 = timed_check(async fn() { check_stateless_discover(session) })
  push_all(results, r20)
  let r21 = timed_check(async fn() {
    check_stateless_version_negotiation(session)
  })
  push_all(results, r21)
  let r22 = timed_check(async fn() { check_stateless_self_describing(session) })
  push_all(results, r22)
  let r23 = timed_check(async fn() {
    check_stateless_missing_capability(session)
  })
  push_all(results, r23)
  let r24 = timed_check(async fn() { check_stateless_list_cache(session) })
  push_all(results, r24)
  let r25 = timed_check(async fn() { check_stateless_schema_2020_12(session) })
  push_all(results, r25)
  let r26 = timed_check(async fn() {
    check_stateless_resource_error_code(session)
  })
  push_all(results, r26)
  let r27 = timed_check(async fn() { check_stateless_mrtr(session) })
  push_all(results, r27)
  let r28 = timed_check(async fn() { check_stateless_deprecations(session) })
  push_all(results, r28)
  let stateless_err = count_err(r20) +
    count_err(r21) +
    count_err(r22) +
    count_err(r23) +
    count_err(r24) +
    count_err(r25) +
    count_err(r26) +
    count_err(r27) +
    count_err(r28)
  if stateless_err > 0 {
    ok = false
  }
  ignore(session.close())
  println(
    "[fixture] \{count(results, "pass")}/\{results.length()} pass, \{count(results, "fail")} fail",
  )
  { ok, results, cmd, }
}

///|
/// Probe an arbitrary MCP server (no fixture-specific violation expectations).
/// If the target starts with ws:// or wss:// it is treated as a WebSocket URL,
/// otherwise as a stdio command line.
pub async fn probe_server(cmd : String) -> ProbeRun {
  let is_ws = cmd.has_prefix("ws://") || cmd.has_prefix("wss://")
  let session = if is_ws { Session::new_ws(cmd) } else { Session::new(cmd) }
  if !session.alive {
    return { ok: false, results: [], cmd, }
  }
  let results : Array[CheckResult] = []
  let mut ok = true
  let r1 = timed_check(async fn() { check_initialize(session) })
  push_all(results, r1)
  if count(r1, "pass") < 3 {
    ok = false
  }
  let r2 = timed_check(async fn() { check_capabilities(session) })
  push_all(results, r2)
  if count_err(r2) > 0 {
    ok = false
  }
  let r3 = timed_check(async fn() { check_tools_list(session) })
  push_all(results, r3)
  if count_err(r3) > 0 {
    ok = false
  }
  let r4 = timed_check(async fn() { check_tools_call(session) })
  push_all(results, r4)
  if count_err(r4) > 0 {
    ok = false
  }
  let r5 = timed_check(async fn() { check_notifications(session) })
  push_all(results, r5)
  if count(r5, "pass") < 2 {
    ok = false
  }
  let r6 = timed_check(async fn() { check_idempotency(session) })
  push_all(results, r6)
  if count(r6, "pass") < 1 {
    ok = false
  }
  let r7 = timed_check(async fn() { check_resources_list(session) })
  push_all(results, r7)
  let r8 = timed_check(async fn() { check_prompts_list(session) })
  push_all(results, r8)
  let r9 = timed_check(async fn() { check_resources_read_error(session) })
  push_all(results, r9)
  let r10 = timed_check(async fn() { check_ping(session) })
  push_all(results, r10)
  let r11 = timed_check(async fn() { check_keepalive(session) })
  push_all(results, r11)
  let r12 = timed_check(async fn() { check_protocol_negotiation(session) })
  push_all(results, r12)
  let r13 = timed_check(async fn() { check_logging(session) })
  push_all(results, r13)
  let r14 = timed_check(async fn() { check_completion(session) })
  push_all(results, r14)
  let r15 = timed_check(async fn() { check_subscribe(session) })
  push_all(results, r15)
  let r16 = timed_check(async fn() { check_sampling(session) })
  push_all(results, r16)
  let r17 = timed_check(async fn() { check_batch(session) })
  push_all(results, r17)
  if count_err(r17) > 0 {
    ok = false
  }
  let r18 = timed_check(async fn() { check_id_matching(session) })
  push_all(results, r18)
  if count_err(r18) > 0 {
    ok = false
  }
  let r19 = timed_check(async fn() { check_error_schema(session) })
  push_all(results, r19)
  if count_err(r19) > 0 {
    ok = false
  }
  // 2026-07-28 stateless core checks: violations are hard fails; transport
  // errors (timeout / parse) also invalidate the run.
  let r20 = timed_check(async fn() { check_stateless_discover(session) })
  push_all(results, r20)
  let r21 = timed_check(async fn() {
    check_stateless_version_negotiation(session)
  })
  push_all(results, r21)
  let r22 = timed_check(async fn() { check_stateless_self_describing(session) })
  push_all(results, r22)
  let r23 = timed_check(async fn() {
    check_stateless_missing_capability(session)
  })
  push_all(results, r23)
  let r24 = timed_check(async fn() { check_stateless_list_cache(session) })
  push_all(results, r24)
  let r25 = timed_check(async fn() { check_stateless_schema_2020_12(session) })
  push_all(results, r25)
  let r26 = timed_check(async fn() {
    check_stateless_resource_error_code(session)
  })
  push_all(results, r26)
  let r27 = timed_check(async fn() { check_stateless_mrtr(session) })
  push_all(results, r27)
  let r28 = timed_check(async fn() { check_stateless_deprecations(session) })
  push_all(results, r28)
  let stateless_err = count_err(r20) +
    count_err(r21) +
    count_err(r22) +
    count_err(r23) +
    count_err(r24) +
    count_err(r25) +
    count_err(r26) +
    count_err(r27) +
    count_err(r28)
  if stateless_err > 0 {
    ok = false
  }
  ignore(session.close())
  println(
    "[target] \{cmd}: \{count(results, "pass")}/\{results.length()} pass, \{count(results, "fail")} fail, \{count_err(results)} err",
  )
  { ok, results, cmd, }
}

///|
/// Run all checks against servers (parallel) and generate report.
/// Returns (all_ok, all_results, server_label).
pub async fn run_probe(
  servers : Array[String],
  report_dir : String,
  junit : Bool,
) -> (Bool, Array[CheckResult], String) {
  let probe_start = now_ms()
  let runs : Array[ProbeRun] = if servers.length() > 0 {
    println("probing \{servers.length()} server(s) in parallel")
    let tasks : Array[async () -> ProbeRun] = servers.map(fn(cmd) {
      async fn() -> ProbeRun { probe_server(cmd) }
    })
    @async.all(tasks)
  } else {
    println("probing fixture server")
    [run_fixture()]
  }
  let all_results : Array[CheckResult] = []
  let mut all_ok = true
  for run in runs {
    if !run.ok {
      all_ok = false
    }
    for r in run.results {
      all_results.push(r)
    }
  }
  let total_timing = now_ms() - probe_start
  let server_label = if servers.length() > 0 {
    servers.join(", ")
  } else {
    "fixture"
  }
  if report_dir.length() > 0 {
    let report = build_report(
      all_results,
      server_label,
      "2026-07-28",
      now_iso(),
    )
    report.total_timing_ms = total_timing
    report.avg_timing_ms = if all_results.length() > 0 {
      total_timing / all_results.length()
    } else {
      0
    }
    match report.write_to_dir(report_dir, junit) {
      Ok(_) => println("report written: \{report_dir}/report.{json,md,html}")
      Err(e) => println("WARN: report write failed: \{e}")
    }
  }
  (all_ok, all_results, server_label)
}
