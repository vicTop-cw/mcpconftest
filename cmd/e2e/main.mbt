///| E2E integration entry: probes servers end-to-end and writes reports.
/// Run: moon run cmd/e2e [-- --server "<cmd>" | --report <dir>]
/// (moon test blocks cannot be async; this async main runs the full chain)

///| Bundle of one probe run: pass verdict + all check results.
struct ProbeRun {
  ok : Bool
  results : Array[@lib.CheckResult]
  cmd : String
}

///| Probe the built-in fixture with strict expectations.
async fn run_fixture() -> ProbeRun {
  let cmd = "node tests/fixtures/mcp_fixture_server.js"
  let session = @lib.Session::new(cmd)
  if !session.alive {
    return { ok: false, results: [], cmd }
  }
  let results : Array[@lib.CheckResult] = []
  let mut ok = true
  // 1. initialize
  let r1 = @lib.check_initialize(session)
  results.append(r1)
  if count(r1, "pass") < 3 { ok = false }
  // 2. capabilities
  let r2 = @lib.check_capabilities(session)
  results.append(r2)
  if count(r2, "pass") < 1 { ok = false }
  // 3. tools/list — fixture violates: tool without description
  let r3 = @lib.check_tools_list(session)
  results.append(r3)
  if count(r3, "fail") < 1 { ok = false }
  // 4. tools/call — fixture violates: wrong error code
  let r4 = @lib.check_tools_call(session)
  results.append(r4)
  if count_err(r4) > 0 { ok = false }
  // 5. notifications — session must stay alive
  let r5 = @lib.check_notifications(session)
  results.append(r5)
  if count(r5, "pass") < 2 { ok = false }
  // 6. idempotency
  let r6 = @lib.check_idempotency(session)
  results.append(r6)
  if count(r6, "pass") < 1 { ok = false }
  ignore(session.close())
  println("[fixture] \{count(results, "pass")}/\{results.length()} pass, \{count(results, "fail")} fail")
  { ok, results, cmd }
}

///| Probe an arbitrary MCP server (no fixture-specific violation expectations).
/// A server passes if: initialize handshake works, session stays alive,
/// and no check hits timeout/parse errors.
async fn probe_server(cmd : String) -> ProbeRun {
  let session = @lib.Session::new(cmd)
  if !session.alive {
    return { ok: false, results: [], cmd }
  }
  let results : Array[@lib.CheckResult] = []
  let mut ok = true
  let r1 = @lib.check_initialize(session)
  results.append(r1)
  if count(r1, "pass") < 3 { ok = false }
  let r2 = @lib.check_capabilities(session)
  results.append(r2)
  if count_err(r2) > 0 { ok = false }
  let r3 = @lib.check_tools_list(session)
  results.append(r3)
  if count_err(r3) > 0 { ok = false }
  let r4 = @lib.check_tools_call(session)
  results.append(r4)
  if count_err(r4) > 0 { ok = false }
  let r5 = @lib.check_notifications(session)
  results.append(r5)
  if count(r5, "pass") < 2 { ok = false }
  let r6 = @lib.check_idempotency(session)
  results.append(r6)
  if count(r6, "pass") < 1 { ok = false }
  ignore(session.close())
  println("[target] \{count(results, "pass")}/\{results.length()} pass, \{count(results, "fail")} fail, \{count_err(results)} err")
  { ok, results, cmd }
}

///| Count results by severity name ("pass"/"fail").
fn count(results : Array[@lib.CheckResult], sev : String) -> Int {
  var n = 0
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
  var n = 0
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
  // argv: moon run cmd/e2e -- [--server "<cmd>"] [--report <dir>]
  // Default: fixture regression; report dir ./mcpconftest-report; "" disables.
  let args = @env.args()
  var server_cmd = ""
  var report_dir = "./mcpconftest-report"
  var i = 2
  while i < args.length() {
    if args[i] == "--server" && i + 1 < args.length() {
      server_cmd = args[i + 1]
      i += 1
    } else if args[i] == "--report" && i + 1 < args.length() {
      report_dir = args[i + 1]
      i += 1
    }
    i += 1
  }
  println("mcpconftest v0.3.0 e2e")
  let run = if server_cmd.length() > 0 {
    println("probing: \{server_cmd}")
    probe_server(server_cmd)
  } else {
    println("probing fixture server")
    run_fixture()
  }
  // Report write (observation surface, not verdict surface — warn only)
  if report_dir.length() > 0 {
    let report = @lib.build_report(run.results, run.cmd, "2026-07-28", js_now_iso())
    match report.write_to_dir(report_dir) {
      Ok(_) => println("report written: \{report_dir}/report.{json,md}")
      Err(e) => println("WARN: report write failed: \{e}")
    }
  }
  if run.ok {
    println("E2E: ALL GREEN")
  } else {
    println("E2E: FAILURES DETECTED")
    e2e_exit(1)
  }
}

///| Real process exit for js target (process.exit).
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
