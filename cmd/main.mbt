///|
/// mcpconftest CLI entry — subcommands: run, list-checks, version, serve
fn cli_exit(code : Int32) -> Unit {
  @sys.exit(code)
}

///|
/// Print available check categories (spec-driven, L1).
fn list_checks() -> Unit {
  let checks = @lib.list_checks_spec()
  println("mcpconftest check categories:")
  for c in checks {
    println("  - \{c}")
  }
}

///| Run probe against servers (or built-in fixture if --fixture given).

///|
/// IRON LAW R6: prints the verdict; a non-"pass" verdict exits non-zero.
async fn cmd_run(
  servers : Array[String],
  report_dir : String,
  junit : Bool,
  fixture : Bool,
) -> Result[Unit, String] {
  let (all_ok, results, label) = if fixture {
    let r = @lib.run_fixture()
    (r.ok, r.results, r.cmd)
  } else {
    @lib.run_probe(servers, report_dir, junit)
  }
  let report = @lib.build_report(results, label, "2026-07-28", @lib.now_iso())
  if fixture && report_dir.length() > 0 {
    match report.write_to_dir(report_dir, junit) {
      Ok(_) => println("report written: \{report_dir}/report.{json,md,html}")
      Err(e) => println("WARN: report write failed: \{e}")
    }
  }
  if all_ok {
    println("mcpconftest: ALL GREEN (\{label})")
  } else {
    println("mcpconftest: FAILURES DETECTED (\{label})")
  }
  let verdict = report.verdict()
  println("VERDICT: \{verdict}")
  if verdict != "pass" || !all_ok {
    cli_exit(1)
  }
  Ok(())
}

///|
async fn main {
  let args = @env.args()
  // argv layout differs between backends:
  //   js:     [node, bundle.js, <subcmd>, ...]
  //   native: [exe, <subcmd>, ...]
  // Locate the first positional subcommand keyword.
  let mut sub_i = -1
  for k in 1..<args.length() {
    if args[k] == "run" ||
      args[k] == "list-checks" ||
      args[k] == "version" ||
      args[k] == "serve" {
      sub_i = k
      break
    }
  }
  if sub_i < 0 {
    println("mcpconftest v\{@lib.version()}")
    println("Usage:")
    println(
      "  moon run cmd -- run [--server <cmd>]+ [--report <dir>] [--junit] [--fixture]",
    )
    println("  moon run cmd -- list-checks")
    println("  moon run cmd -- version")
    println("  moon run cmd -- serve")
    return
  }
  let subcmd = args[sub_i]
  let mut i = sub_i + 1
  if subcmd == "version" {
    println("mcpconftest v\{@lib.version()}")
  } else if subcmd == "list-checks" {
    list_checks()
  } else if subcmd == "serve" {
    let s = @lib.build_mcp_server() catch {
      _ => panic()
    }
    run_stdio_target(s)
  } else if subcmd == "run" {
    let servers : Array[String] = []
    let mut report_dir = "./mcpconftest-report"
    let mut junit = false
    let mut fixture = false
    while i < args.length() {
      if args[i] == "--server" && i + 1 < args.length() {
        servers.push(args[i + 1])
        i += 1
      } else if args[i] == "--report" && i + 1 < args.length() {
        report_dir = args[i + 1]
        i += 1
      } else if args[i] == "--junit" {
        junit = true
      } else if args[i] == "--fixture" {
        fixture = true
      }
      i += 1
    }
    match cmd_run(servers, report_dir, junit, fixture) {
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
