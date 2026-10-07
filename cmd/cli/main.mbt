///| CLI entry point for mcpconftest.

fn main {
  let args = @env.args()
  let mut server_cmd = ""
  let mut report_dir = "./mcpconftest-report"
  let mut ci_mode = false
  let mut i = 2
  while i < args.length() {
    match args[i] {
      "--server" => { i += 1; if i < args.length() { server_cmd = args[i] } }
      "--report" => { i += 1; if i < args.length() { report_dir = args[i] } }
      "--ci" => ci_mode = true
      _ => ()
    }
    i += 1
  }
  if server_cmd.length() == 0 {
    println("Usage: mcpconftest run --server <cmd> [--report <dir>] [--ci]")
    return
  }
  println("mcpconftest v0.1.0 — probing: \{server_cmd}")
  if ci_mode {
    println("CI GATE: PASS (stub)")
  }
  let _ = report_dir
}
