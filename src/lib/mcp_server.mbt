///| MCP server builder — exposes mcpconftest as an MCP stdio server.
///| Registers three tools:
///|   - run_probe: run the conformance probe against one or more servers
///|   - list_checks: list the 15 conformance check categories
///|   - version: report the server version
///|
///| The returned `@mcp.MCPServer` is driven by the target-specific stdio
///| loop in `cmd/serve_io_js.mbt` / `cmd/serve_io_native.mbt`.

///| Metadata for the 15 conformance check categories exposed by list_checks.
///| Extracted from the check functions in checks.mbt.
pub fn list_checks_meta() -> Json {
  let items : Array[Json] = []
  let defs = [
    (
      "initialize",
      "Handshake: jsonrpc=2.0, serverInfo present, protocolVersion=2026-07-28",
    ),
    (
      "capabilities",
      "Declared capabilities match observed server behavior",
    ),
    ("tools/list", "Tool schema conformance (name/description mandatory)"),
    (
      "tools/call",
      "Tool invocation result and unknown-method error path (-32601)",
    ),
    (
      "notifications",
      "Session stays alive after unknown notifications (no response expected)",
    ),
    ("idempotency", "Repeated identical requests are handled consistently"),
    (
      "resources",
      "resources/list + resources/read schema and error path",
    ),
    ("prompts/list", "Prompt schema conformance (name mandatory)"),
    ("ping", "Spec-mandated ping request/response round-trip"),
    ("keepalive", "Session stability across an idle period"),
    (
      "protocol_negotiation",
      "Version matrix across supported protocol versions",
    ),
    ("logging", "Logging notification support (no crash, optional ack)"),
    ("batch", "JSON-RPC batch request handling"),
    ("id_matching", "JSON-RPC id matching between request and response"),
    ("error_schema", "Error response schema conformance (code/message)"),
  ]
  for (name, desc) in defs {
    items.push(
      Json::object({
        "name": Json::string(name),
        "description": Json::string(desc),
      }),
    )
  }
  Json::array(items)
}

///| Build the MCP server with the run_probe / list_checks / version tools.
pub fn build_mcp_server() -> @mcp.MCPServer {
  let s0 = @mcp.MCPServer::MCPServer("mcpconftest", version())
  let s1 = s0.tool(
    "run_probe",
    "Run the MCP protocol conformance probe against one or more servers. Parameters: servers (array of launch command strings, e.g. [\"node server.js\"]), report_dir (directory for report files), junit (boolean, also write JUnit XML). Returns JSON with per-server pass/fail/skip/warn counts, failed check names, and report path.",
    Json::object({
      "servers": Json::object({
        "type": Json::string("array"),
        "items": Json::object({"type": Json::string("string")}),
        "description": Json::string(
          "Server launch commands, e.g. [\"node server.js\"]",
        ),
      }),
      "report_dir": Json::object({
        "type": Json::string("string"),
        "description": Json::string(
          "Directory to write report files (report.json/md/html, optional JUnit)",
        ),
      }),
      "junit": Json::object({
        "type": Json::string("boolean"),
        "description": Json::string("Also write report-junit.xml"),
      }),
    }),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      let servers = parse_servers(args)
      if servers.length() == 0 {
        return Err(@mcp_types.ToolError("servers must be a non-empty array of strings"))
      }
      let report_dir = parse_string(args, "report_dir", "")
      let junit = parse_bool(args, "junit", false)
      let (ok, results, label) = run_probe(servers, report_dir, junit)
      let failed : Array[String] = []
      for r in results {
        if r.severity == Fail {
          failed.push(r.name)
        }
      }
      let m : Map[String, Json] = Map([])
      m.set("server", Json::string(label))
      m.set("ok", Json::boolean(ok))
      m.set("pass", Json::number(count(results, "pass").to_double()))
      m.set("fail", Json::number(count(results, "fail").to_double()))
      m.set("skip", Json::number(count(results, "skip").to_double()))
      m.set("warn", Json::number(count(results, "warn").to_double()))
      m.set("total", Json::number(results.length().to_double()))
      m.set("failed", Json::array(failed.map(fn(n) { Json::string(n) })))
      if report_dir.is_empty() {
        m.set("report_path", Json::null())
      } else {
        m.set(
          "report_path",
          Json::string(report_dir + "/report.json"),
        )
      }
      Ok(@mcp.ToolResult::text(Json::object(m).stringify()))
    },
  )
  let s2 = s1.tool(
    "list_checks",
    "List the conformance check categories that run_probe executes.",
    Json::object({}),
    fn(_args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      Ok(@mcp.ToolResult::text(list_checks_meta().stringify()))
    },
  )
  let s3 = s2.tool(
    "version",
    "Report the mcpconftest server version.",
    Json::object({}),
    fn(_args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      Ok(@mcp.ToolResult::text(Json::string(version()).stringify()))
    },
  )
  s3
}

///| Extract the servers array from tool arguments.
fn parse_servers(args : Json) -> Array[String] {
  match args {
    Object(m) =>
      match m.get("servers") {
        Some(Array(a)) => {
          let out : Array[String] = []
          for j in a {
            match j {
              String(s) => out.push(s)
              _ => ()
            }
          }
          out
        }
        _ => []
      }
    _ => []
  }
}

///| Extract a string field from tool arguments.
fn parse_string(args : Json, key : String, default : String) -> String {
  match args {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => s
        _ => default
      }
    _ => default
  }
}

///| Extract a boolean field from tool arguments.
fn parse_bool(args : Json, key : String, default : Bool) -> Bool {
  match args {
    Object(m) =>
      match m.get(key) {
        Some(True) => true
        Some(False) => false
        _ => default
      }
    _ => default
  }
}
