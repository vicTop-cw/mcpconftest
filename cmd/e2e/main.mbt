///| E2E integration entry: probes the real fixture server end-to-end.
/// Run: moon run cmd/e2e/main
/// (moon test blocks cannot be async; this async main runs the full chain)

async fn run_all_checks(label : String, cmd : String) -> Bool {
  let session = @lib.Session::new(cmd)
  if !session.alive {
    println("[\{label}] FAIL: session spawn failed")
    return false
  }
  let mut ok = true
  // 1. initialize
  let r1 = @lib.check_initialize(session)
  let p1 = count(r1, "pass")
  println("[\{label}] initialize: \{r1.length()} checks, \{p1} pass")
  if p1 < 3 { ok = false }
  // 2. capabilities
  let r2 = @lib.check_capabilities(session)
  println("[\{label}] capabilities: \{r2.length()} checks, \{count(r2, "pass")} pass")
  if count(r2, "pass") < 1 { ok = false }
  // 3. tools/list — fixture violates: tool without description
  let r3 = @lib.check_tools_list(session)
  let f3 = count(r3, "fail")
  println("[\{label}] tools/list: \{r3.length()} checks, \{f3} fail (expect >=1: missing description)")
  if f3 < 1 { ok = false }
  // 4. tools/call — fixture violates: wrong error code
  let r4 = @lib.check_tools_call(session)
  println("[\{label}] tools/call: \{r4.length()} checks, \{count(r4, "pass")} pass")
  // 5. notifications — session must stay alive
  let r5 = @lib.check_notifications(session)
  let p5 = count(r5, "pass")
  println("[\{label}] notifications: \{r5.length()} checks, \{p5} pass")
  if p5 < 2 { ok = false }
  // 6. idempotency
  let r6 = @lib.check_idempotency(session)
  let p6 = count(r6, "pass")
  println("[\{label}] idempotency: \{r6.length()} checks, \{p6} pass")
  if p6 < 1 { ok = false }
  ignore(session.close())
  ok
}

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

///|
async fn main {
  // Optional argv: moon run cmd/e2e -- --server "<cmd>" [fixture-tolerance]
  // Default: probe the built-in fixture (strict expectations).
  // With --server: probe an arbitrary MCP server (no violation expectations).
  let args = @env.args()
  var server_cmd = ""
  var i = 2
  while i < args.length() {
    if args[i] == "--server" && i + 1 < args.length() {
      server_cmd = args[i + 1]
      i += 1
    }
    i += 1
  }
  let ok = if server_cmd.length() > 0 {
    println("mcpconftest e2e — probing: \{server_cmd}")
    probe_server("target", server_cmd)
  } else {
    println("mcpconftest e2e — probing fixture server")
    run_all_checks("fixture", "node tests/fixtures/mcp_fixture_server.js")
  }
  if ok {
    println("E2E: ALL GREEN")
  } else {
    println("E2E: FAILURES DETECTED")
    e2e_exit(1)
  }
}

///| Probe an arbitrary MCP server (no fixture-specific violation expectations).
/// A server passes if: initialize handshake works, session stays alive,
/// and no check hits timeout/parse errors.
async fn probe_server(label : String, cmd : String) -> Bool {
  let session = @lib.Session::new(cmd)
  if !session.alive {
    println("[\{label}] FAIL: session spawn failed")
    return false
  }
  let mut ok = true
  let r1 = @lib.check_initialize(session)
  let p1 = count(r1, "pass")
  let t1 = count_err(r1)
  println("[\{label}] initialize: \{r1.length()} checks, \{p1} pass, \{t1} err")
  if p1 < 3 { ok = false }
  let r2 = @lib.check_capabilities(session)
  println("[\{label}] capabilities: \{count(r2, "pass")}/\{r2.length()} pass")
  if count_err(r2) > 0 { ok = false }
  let r3 = @lib.check_tools_list(session)
  println("[\{label}] tools/list: \{count(r3, "pass")}/\{r3.length()} pass, \{count(r3, "fail")} fail")
  if count_err(r3) > 0 { ok = false }
  let r5 = @lib.check_notifications(session)
  let p5 = count(r5, "pass")
  println("[\{label}] notifications: \{p5}/\{r5.length()} pass")
  if p5 < 2 { ok = false }
  let r6 = @lib.check_idempotency(session)
  println("[\{label}] idempotency: \{count(r6, "pass")}/\{r6.length()} pass")
  if count(r6, "pass") < 1 { ok = false }
  ignore(session.close())
  ok
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
