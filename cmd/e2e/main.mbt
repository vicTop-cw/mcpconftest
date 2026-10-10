///| E2E integration entry: probes servers end-to-end and writes reports.
/// Run: moon run cmd/e2e [-- --server "<cmd>" [--server "<cmd2>"] | --report <dir>] [--junit]
/// (moon test blocks cannot be async; this async main runs the full chain)

///| Bundle of one probe run: pass verdict + all check results.
struct ProbeRun {
  ok : Bool
  results : Array[@lib.CheckResult]
}

///| Push all items from a CheckResult array into results.
fn push_all(results : Array[@lib.CheckResult], items : Array[@lib.CheckResult]) -> Unit {
  for x in items { results.push(x) }
}

///| Probe the built-in fixture with strict expectations.
async fn run_fixture() -> ProbeRun {
  let cmd = "node tests/fixtures/mcp_fixture_server.js"
  let session = @lib.Session::new(cmd)
  if !session.alive {
    return { ok: false, results: [] }
  }
  let results : Array[@lib.CheckResult] = []
  let mut ok = true
  let r1 = @lib.check_initialize(session)
  push_all(results, r1)
  if count(r1, "pass") < 3 { ok = false }
  let r2 = @lib.check_capabilities(session)
  push_all(results, r2)
  if count(r2, "pass") < 1 { ok = false }
  let r3 = @lib.check_tools_list(session)
  push_all(results, r3)
  if count(r3, "fail") < 1 { ok = false }
  let r4 = @lib.check_tools_call(session)
  push_all(results, r4)
  if count_err(r4) > 0 { ok = false }
  let r5 = @lib.check_notifications(session)
  push_all(results, r5)
  if count(r5, "pass") < 2 { ok = false }
  let r6 = @lib.check_idempotency(session)
  push_all(results, r6)
  if count(r6, "pass") < 1 { ok = false }
  let r7 = @lib.check_resources_list(session)
  push_all(results, r7)
  let r8 = @lib.check_prompts_list(session)
  push_all(results, r8)
  let r9 = @lib.check_resources_read_error(session)
  push_all(results, r9)
  let r10 = @lib.check_ping(session)
  push_all(results, r10)
  let r11 = @lib.check_keepalive(session)
  push_all(results, r11)
  let r12 = @lib.check_protocol_negotiation(session)
  push_all(results, r12)
  ignore(session.close())
  println("[fixture] \{count(results, "pass")}/\{results.length()} pass, \{count(results, "fail")} fail")
  { ok, results }
}

///| Probe an arbitrary MCP server (no fixture-specific violation expectations).
/// ws:// or wss:// targets use the WebSocket transport, others stdio.
async fn probe_server(cmd : String) -> ProbeRun {
  let is_ws = cmd.has_prefix("ws://") || cmd.has_prefix("wss://")
  let session = if is_ws {
    @lib.Session::new_ws(cmd)
  } else {
    @lib.Session::new(cmd)
  }
  if !session.alive {
    return { ok: false, results: [] }
  }
  let results : Array[@lib.CheckResult] = []
  let mut ok = true
  let r1 = @lib.check_initialize(session)
  push_all(results, r1)
  if count(r1, "pass") < 3 { ok = false }
  let r2 = @lib.check_capabilities(session)
  push_all(results, r2)
  if count_err(r2) > 0 { ok = false }
  let r3 = @lib.check_tools_list(session)
  push_all(results, r3)
  if count_err(r3) > 0 { ok = false }
  let r4 = @lib.check_tools_call(session)
  push_all(results, r4)
  if count_err(r4) > 0 { ok = false }
  let r5 = @lib.check_notifications(session)
  push_all(results, r5)
  if count(r5, "pass") < 2 { ok = false }
  let r6 = @lib.check_idempotency(session)
  push_all(results, r6)
  if count(r6, "pass") < 1 { ok = false }
  let r7 = @lib.check_resources_list(session)
  push_all(results, r7)
  let r8 = @lib.check_prompts_list(session)
  push_all(results, r8)
  let r9 = @lib.check_resources_read_error(session)
  push_all(results, r9)
  let r10 = @lib.check_ping(session)
  push_all(results, r10)
  let r11 = @lib.check_keepalive(session)
  push_all(results, r11)
  let r12 = @lib.check_protocol_negotiation(session)
  push_all(results, r12)
  ignore(session.close())
  println("[target] \{cmd}: \{count(results, "pass")}/\{results.length()} pass, \{count(results, "fail")} fail, \{count_err(results)} err")
  { ok, results }
}

///| Count results by severity name ("pass"/"fail").
fn count(results : Array[@lib.CheckResult], sev : String) -> Int {
  let mut n = 0
  for r in results {
    match r.severity {
      @lib.Pass => if sev == "pass" { n += 1 }
      @lib.Fail => if sev == "fail" { n += 1 }
      _ => ()
    }
  }
  n
}

///| Count transport-level errors (timeout / parse / write failures).
fn count_err(results : Array[@lib.CheckResult]) -> Int {
  let mut n = 0
  for r in results {
    if r.name.contains("timeout") || r.name.contains("parse") {
      n += 1
    }
  }
  n
}

///| Current UTC time as ISO string (js target).
extern "js" fn js_now_iso() -> String =
  #| () => new Date().toISOString()

///|
async fn main {
  let args = @env.args()
  let servers : Array[String] = []
  let mut report_dir = "./mcpconftest-report"
  let mut junit = false
  let mut i = 2
  while i < args.length() {
    if args[i] == "--server" && i + 1 < args.length() {
      servers.push(args[i + 1])
      i += 1
    } else if args[i] == "--report" && i + 1 < args.length() {
      report_dir = args[i + 1]
      i += 1
    } else if args[i] == "--junit" {
      junit = true
    }
    i += 1
  }
  println("mcpconftest v0.5.0 e2e")
  let runs : Array[ProbeRun] = if servers.length() > 0 {
    println("probing \{servers.length()} server(s) in parallel")
    let tasks : Array[async () -> ProbeRun] = servers.map(fn(cmd) {
      async fn () -> ProbeRun { probe_server(cmd) }
    })
    @async.all(tasks)
  } else {
    println("probing fixture server")
    [run_fixture()]
  }
  let all_results : Array[@lib.CheckResult] = []
  let mut all_ok = true
  for run in runs {
    if !run.ok { all_ok = false }
    for r in run.results { all_results.push(r) }
  }
  if report_dir.length() > 0 {
    let server_label = if servers.length() > 0 {
      servers.join(", ")
    } else {
      "fixture"
    }
    let report = @lib.build_report(all_results, server_label, "2026-07-28", js_now_iso())
    match report.write_to_dir(report_dir, junit) {
      Ok(_) => println("report written: \{report_dir}/report.{json,md,html}")
      Err(e) => println("WARN: report write failed: \{e}")
    }
  }
  if all_ok {
    println("E2E: ALL GREEN (\{runs.length()} server(s), \{all_results.length()} checks)")
  } else {
    println("E2E: FAILURES DETECTED (\{runs.length()} server(s))")
    e2e_exit(1)
  }
}

extern "js" fn js_try_exit(code : Int) -> Bool =
  #| function(code) {
  #|   if (typeof process !== "undefined" && typeof process.exit === "function") {
  #|     process.exit(code);
  #|     return true;
  #|   }
  #|   return false;
  #| }

fn e2e_exit(code : Int) -> Unit {
  if !js_try_exit(code) {
    abort("cannot set exit code \{code} in this runtime")
  }
}
