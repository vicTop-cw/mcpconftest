///| mcpconftest CLI entry — subcommands: run, list-checks, version

///| Real process exit for js target (process.exit).
extern "js" fn js_try_exit(code : Int) -> Bool =
  #| function(code) {
  #|   if (typeof process !== "undefined" && typeof process.exit === "function") {
  #|     process.exit(code);
  #|     return true;
  #|   }
  #|   return false;
  #| }

fn cli_exit(code : Int) -> Unit {
  if !js_try_exit(code) {
    abort("cannot set exit code \{code} in this runtime")
  }
}

///| Print available check categories.
fn list_checks() -> Unit {
  let checks = [
    "initialize — jsonrpc, server_info, protocol_version",
    "capabilities — response structure",
    "tools/list — tool schema (name, description mandatory)",
    "tools/call — error path (-32601 for unknown tool)",
    "notifications — session liveness after unknown notifications",
    "idempotency — repeated identical requests",
    "resources/list, resources/read — resource schema + error path",
    "prompts/list — prompt schema (name mandatory)",
    "ping, keepalive — spec-mandated ping + session stability",
    "protocol negotiation — version matrix (4 protocols)",
  ]
  println("mcpconftest check categories:")
  for c in checks {
    println("  - \{c}")
  }
}

///| Run probe against servers (or fixture if none given).
async fn cmd_run(servers : Array[String], report_dir : String, junit : Bool) -> Result[Unit, String] {
  let (all_ok, _results, label) = @lib.run_probe(servers, report_dir, junit)
  if all_ok {
    println("mcpconftest: ALL GREEN (\{label})")
  } else {
    println("mcpconftest: FAILURES DETECTED (\{label})")
    cli_exit(1)
  }
  Ok(())
}

///|
async fn main raise {
  let args = @env.args()
  // args[0]=node, args[1]=script_path; user args start at args[2]
  if args.length() < 3 {
    println("mcpconftest v0.6.0")
    println("Usage:")
    println("  moon run cmd -- run [--server <cmd>]+ [--report <dir>] [--junit]")
    println("  moon run cmd -- list-checks")
    println("  moon run cmd -- version")
    return
  }
  let subcmd = args[2]
  if subcmd == "version" {
    println("mcpconftest v0.6.0")
  } else if subcmd == "list-checks" {
    list_checks()
  } else if subcmd == "run" {
    let servers : Array[String] = []
    var report_dir = "./mcpconftest-report"
    var junit = false
    var i = 3
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
    match cmd_run(servers, report_dir, junit) {
      Ok(_) => ()
      Err(e) => {
        println("ERROR: \{e}")
        cli_exit(2)
      }
    }
  } else {
    println("unknown subcommand: \{subcmd}")
    cli_exit(2)
  }
}
