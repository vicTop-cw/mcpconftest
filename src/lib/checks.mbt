///| Six categories of MCP protocol conformance checks.

///| Parse a JSON-RPC response string, push a Fail on error.
fn parse_resp(resp_str : String, label : String, results : Array[CheckResult]) -> Option[Json] {
  let j = @json.parse(resp_str) catch {
    _ => {
      results.push(CheckResult::fail(label + ".parse", "JSON parse error", resp_str))
      return None
    }
  }
  Some(j)
}

///| Initialize handshake check.
pub fn check_initialize(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  let params = Json::object({
    "protocolVersion": Json::string("2026-07-28"),
    "capabilities": Json::object({}),
    "clientInfo": Json::object({ "name": Json::string("mcpconftest"), "version": Json::string("0.1.0") }),
  })
  match session.request("initialize", params, 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch {
        _ => {
          results.push(CheckResult::fail("init.parse", "JSON parse error", resp_str))
          return results
        }
      }
      match j.value("jsonrpc") {
        Some(Json::String(s)) if s == "2.0" => results.push(CheckResult::pass("init.jsonrpc", "jsonrpc=2.0"))
        _ => results.push(CheckResult::fail("init.jsonrpc", "expected jsonrpc=2.0", resp_str))
      }
      match j.value("result") {
        Some(Json::Object(r)) => {
          match r.get("serverInfo") {
            Some(_) => results.push(CheckResult::pass("init.server_info", "serverInfo present"))
            None => results.push(CheckResult::fail("init.server_info", "serverInfo missing", resp_str))
          }
          match r.get("protocolVersion") {
            Some(Json::String(v)) if v == "2026-07-28" => results.push(CheckResult::pass("init.protocol_version", "version=2026-07-28"))
            Some(Json::String(v)) => results.push(CheckResult::fail("init.protocol_version", "got version=\{v}, expected 2026-07-28", resp_str))
            _ => results.push(CheckResult::fail("init.protocol_version", "protocolVersion missing", resp_str))
          }
        }
        _ => results.push(CheckResult::fail("init.result", "result object missing", resp_str))
      }
    }
    Err(e) => results.push(CheckResult::fail("init.timeout", e, ""))
  }
  match session.notify("notifications/initialized", Json::object({})) {
    Ok(_) => results.push(CheckResult::pass("init.notifications_initialized", "sent OK"))
    Err(e) => results.push(CheckResult::fail("init.notifications_initialized", e, ""))
  }
  results
}

///| Capabilities check: declared vs actual behavior.
pub fn check_capabilities(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match session.request("initialize", Json::object({}), 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch {
        _ => {
          results.push(CheckResult::fail("caps.parse", "JSON parse error", resp_str))
          return results
        }
      }
      let caps = match j.value("result") {
        Some(Json::Object(r)) => r.get("capabilities")
        _ => None
      }
      match caps {
        Some(Json::Object(c)) => {
          match c.get("tools") {
            Some(_) => results.push(CheckResult::pass("caps.tools", "tools capability declared"))
            None => results.push(CheckResult::fail("caps.tools", "tools capability not declared", ""))
          }
        }
        _ => results.push(CheckResult::fail("caps.declared", "no capabilities declared", resp_str))
      }
    }
    Err(e) => results.push(CheckResult::fail("caps.timeout", e, ""))
  }
  results
}

///| tools/list schema check.
pub fn check_tools_list(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match session.request("tools/list", Json::object({}), 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch {
        _ => {
          results.push(CheckResult::fail("tools_list.parse", "JSON parse error", resp_str))
          return results
        }
      }
      match j.value("result") {
        Some(Json::Object(r)) => {
          match r.get("tools") {
            Some(Json::Array(tools)) => {
              if tools.length() == 0 {
                results.push(CheckResult::fail("tools_list.empty", "tools array is empty", resp_str))
              } else {
                for tool in tools {
                  match tool {
                    Json::Object(tool_obj) => {
                      match tool_obj.get("name") {
                        Some(_) => results.push(CheckResult::pass("tools_list.name", "tool has name"))
                        None => results.push(CheckResult::fail("tools_list.name", "tool missing name", tool.stringify()))
                      }
                      match tool_obj.get("description") {
                        Some(_) => results.push(CheckResult::pass("tools_list.description", "tool has description"))
                        None => results.push(CheckResult::fail("tools_list.description", "tool missing description", tool.stringify()))
                      }
                    }
                    _ => results.push(CheckResult::fail("tools_list.item", "tool is not object", tool.stringify()))
                  }
                }
              }
            }
            _ => results.push(CheckResult::fail("tools_list.tools", "tools array missing", resp_str))
          }
        }
        _ => results.push(CheckResult::fail("tools_list.result", "result object missing", resp_str))
      }
    }
    Err(e) => results.push(CheckResult::fail("tools_list.timeout", e, ""))
  }
  results
}

///| tools/call check: error path.
pub fn check_tools_call(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match session.request("tools/call", Json::object({ "name": Json::string("__mcpconftest_nonexistent__"), "arguments": Json::object({}) }), 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch {
        _ => {
          results.push(CheckResult::fail("tools_call.parse", "JSON parse error", resp_str))
          return results
        }
      }
      match j.value("error") {
        Some(Json::Object(e)) => {
          match e.get("code") {
            Some(Json::Number(n, ..)) => results.push(CheckResult::pass("tools_call.error", "non-existent tool returned error code \{n.to_int()}"))
            _ => results.push(CheckResult::fail("tools_call.error_code", "error object missing code", resp_str))
          }
        }
        _ => results.push(CheckResult::fail("tools_call.error", "expected error for non-existent tool", resp_str))
      }
    }
    Err(e) => results.push(CheckResult::fail("tools_call.timeout", e, ""))
  }
  results
}

///| Notification handling check.
pub fn check_notifications(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match session.notify("notifications/mcpconftest_unknown", Json::object({})) {
    Ok(_) => results.push(CheckResult::pass("notifications.unknown", "unknown notification sent without crash"))
    Err(e) => results.push(CheckResult::fail("notifications.send", e, ""))
  }
  match session.request("tools/list", Json::object({}), 5000) {
    Ok(_) => results.push(CheckResult::pass("notifications.alive", "session still alive after unknown notification"))
    Err(e) => results.push(CheckResult::fail("notifications.alive", "session died: \{e}", ""))
  }
  results
}

///| Session idempotency check.
pub fn check_idempotency(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match session.request("tools/list", Json::object({}), 5000) {
    Ok(resp1) => {
      match session.request("tools/list", Json::object({}), 5000) {
        Ok(resp2) => {
          if resp1 == resp2 {
            results.push(CheckResult::pass("idempotency", "repeated tools/list returned same result"))
          } else {
            results.push(CheckResult::fail("idempotency", "repeated tools/list returned different results", ""))
          }
        }
        Err(e) => results.push(CheckResult::fail("idempotency.second", "second call failed: \{e}", ""))
      }
    }
    Err(e) => results.push(CheckResult::fail("idempotency.first", "first call failed: \{e}", ""))
  }
  results
}
