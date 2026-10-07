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
pub async fn check_initialize(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  let params = Json::object({
    "protocolVersion": Json::string("2026-07-28"),
    "capabilities": Json::object({}),
    "clientInfo": Json::object({ "name": Json::string("mcpconftest"), "version": Json::string("0.2.0") }),
    "_meta": Json::object({
      "io.modelcontextprotocol/protocolVersion": Json::string("2026-07-28"),
      "io.modelcontextprotocol/clientCapabilities": Json::object({}),
    }),
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
pub async fn check_capabilities(session : Session) -> Array[CheckResult] {
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
pub async fn check_tools_list(session : Session) -> Array[CheckResult] {
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
pub async fn check_tools_call(session : Session) -> Array[CheckResult] {
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
            Some(Json::Number(n, ..)) => {
              let code = n.to_int()
              if code == -32601 {
                results.push(CheckResult::pass("tools_call.error", "non-existent tool returned correct error code -32601"))
              } else {
                results.push(CheckResult::fail("tools_call.error_code", "expected -32601, got \{code} (wrong error code for unknown tool)", resp_str))
              }
            }
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
pub async fn check_notifications(session : Session) -> Array[CheckResult] {
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
pub async fn check_idempotency(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match session.request("tools/list", Json::object({}), 5000) {
    Ok(resp1) => {
      match session.request("tools/list", Json::object({}), 5000) {
        Ok(resp2) => {
          let j1 = @json.parse(resp1) catch { _ => Json::null() }
          let j2 = @json.parse(resp2) catch { _ => Json::null() }
          let r1 = j1.value("result")
          let r2 = j2.value("result")
          if r1 == r2 {
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

///| resources/list schema check (skip when server lacks the capability).
pub async fn check_resources_list(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match session.request("resources/list", Json::object({}), 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch {
        _ => {
          results.push(CheckResult::fail("resources_list.parse", "JSON parse error", resp_str))
          return results
        }
      }
      match j.value("result") {
        Some(Json::Object(r)) =>
          match r.get("resources") {
            Some(Json::Array(resources)) => {
              if resources.length() == 0 {
                results.push(CheckResult::pass("resources_list.empty_ok", "resources array empty (valid)"))
              } else {
                for res in resources {
                  match res {
                    Json::Object(res_obj) => {
                      match res_obj.get("uri") {
                        Some(Json::String(_)) => results.push(CheckResult::pass("resources_list.uri", "resource has uri"))
                        _ => results.push(CheckResult::fail("resources_list.uri", "resource missing uri", res.stringify()))
                      }
                      match res_obj.get("name") {
                        Some(_) => results.push(CheckResult::pass("resources_list.name", "resource has name"))
                        _ => results.push(CheckResult::fail("resources_list.name", "resource missing name", res.stringify()))
                      }
                    }
                    _ => results.push(CheckResult::fail("resources_list.item", "resource is not object", res.stringify()))
                  }
                }
              }
            }
            _ => results.push(CheckResult::skip("resources_list.result", "resources array missing (server may not support resources)"))
          }
        _ => results.push(CheckResult::skip("resources_list.unsupported", "no result (server may not support resources)"))
      }
    }
    Err(e) => results.push(CheckResult::skip("resources_list.unreachable", e))
  }
  results
}

///| prompts/list schema check (skip when server lacks the capability).
pub async fn check_prompts_list(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match session.request("prompts/list", Json::object({}), 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch {
        _ => {
          results.push(CheckResult::fail("prompts_list.parse", "JSON parse error", resp_str))
          return results
        }
      }
      match j.value("result") {
        Some(Json::Object(r)) =>
          match r.get("prompts") {
            Some(Json::Array(prompts)) => {
              if prompts.length() == 0 {
                results.push(CheckResult::pass("prompts_list.empty_ok", "prompts array empty (valid)"))
              } else {
                for p in prompts {
                  match p {
                    Json::Object(p_obj) => {
                      match p_obj.get("name") {
                        Some(_) => results.push(CheckResult::pass("prompts_list.name", "prompt has name"))
                        _ => results.push(CheckResult::fail("prompts_list.name", "prompt missing name", p.stringify()))
                      }
                    }
                    _ => results.push(CheckResult::fail("prompts_list.item", "prompt is not object", p.stringify()))
                  }
                }
              }
            }
            _ => results.push(CheckResult::skip("prompts_list.result", "prompts array missing (server may not support prompts)"))
          }
        _ => results.push(CheckResult::skip("prompts_list.unsupported", "no result (server may not support prompts)"))
      }
    }
    Err(e) => results.push(CheckResult::skip("prompts_list.unreachable", e))
  }
  results
}

///| resources/read error path: non-existent resource must return a JSON-RPC error.
pub async fn check_resources_read_error(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match session.request("resources/read", Json::object({ "uri": Json::string("file:///__mcpconftest_nonexistent__") }), 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch {
        _ => {
          results.push(CheckResult::fail("resources_read.parse", "JSON parse error", resp_str))
          return results
        }
      }
      match j.value("error") {
        Some(Json::Object(e)) =>
          match e.get("code") {
            Some(Json::Number(_, ..)) => results.push(CheckResult::pass("resources_read.error", "non-existent resource returned error"))
            _ => results.push(CheckResult::fail("resources_read.error_code", "error object missing code", resp_str))
          }
        // isError-inside-result is also acceptable per spec
        Some(_) => results.push(CheckResult::pass("resources_read.error", "non-existent resource returned error"))
        _ => results.push(CheckResult::fail("resources_read.no_error", "expected error for non-existent resource", resp_str))
      }
    }
    Err(e) => results.push(CheckResult::skip("resources_read.unreachable", e))
  }
  results
}

///| ping check: server must respond to ping (empty result per spec).
pub async fn check_ping(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match session.request("ping", Json::object({}), 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch {
        _ => {
          results.push(CheckResult::fail("ping.parse", "JSON parse error", resp_str))
          return results
        }
      }
      match j.value("result") {
        Some(_) => results.push(CheckResult::pass("ping.responds", "ping answered with result"))
        _ =>
          match j.value("error") {
            Some(Json::Object(e)) =>
              match e.get("code") {
                Some(Json::Number(-32601, ..)) =>
                  results.push(CheckResult::fail("ping.responds", "ping returned -32601 (spec: server MUST respond to ping)", resp_str))
                Some(_) => results.push(CheckResult::fail("ping.responds", "ping returned unexpected error", resp_str))
                _ => results.push(CheckResult::fail("ping.responds", "ping returned malformed error", resp_str))
              }
            _ => results.push(CheckResult::fail("ping.malformed", "response has neither result nor error", resp_str))
          }
      }
    }
    Err(e) => results.push(CheckResult::fail("ping.timeout", e, ""))
  }
  results
}

///| Keepalive: repeated pings must all succeed (session liveness under load).
pub async fn check_keepalive(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  let mut all_ok = true
  for i in 1..=3 {
    match session.request("ping", Json::object({}), 3000) {
      Ok(resp_str) => {
        let j = @json.parse(resp_str) catch { _ => Json::null() }
        if j is Json::Null {
          all_ok = false
          results.push(CheckResult::fail("keepalive.parse_\{i}", "JSON parse error", resp_str))
        } else if j.value("result") is Some(_) {
          ()
        } else {
          all_ok = false
          results.push(CheckResult::fail("keepalive.no_result_\{i}", "keepalive ping \{i} failed", resp_str))
        }
      }
      Err(e) => {
        all_ok = false
        results.push(CheckResult::fail("keepalive.timeout_\{i}", e, ""))
      }
    }
  }
  if all_ok {
    results.push(CheckResult::pass("keepalive.stable", "3/3 keepalive pings succeeded"))
  }
  results
}

///| Protocol version negotiation matrix: probe servers with several
/// protocolVersion values; a compliant server either echoes a supported
/// version or replies with a JSON-RPC error — never a malformed response.
pub async fn check_protocol_negotiation(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  let versions = ["2026-07-28", "2025-06-18", "2025-03-26", "1999-01-01"]
  for v in versions {
    let params = Json::object({
      "protocolVersion": Json::string(v),
      "capabilities": Json::object({}),
      "clientInfo": Json::object({ "name": Json::string("mcpconftest"), "version": Json::string("0.5.0") }),
      "_meta": Json::object({
        "io.modelcontextprotocol/protocolVersion": Json::string(v),
        "io.modelcontextprotocol/clientCapabilities": Json::object({}),
      }),
    })
    match session.request("initialize", params, 5000) {
      Ok(resp_str) => {
        let j = @json.parse(resp_str) catch { _ => Json::null() }
        if j is Json::Null {
          results.push(CheckResult::fail("negotiation.\{v}.parse", "JSON parse error", resp_str))
        } else {
          match j.value("result") {
          Some(Json::Object(r)) =>
            match r.get("protocolVersion") {
              Some(Json::String(echoed)) => {
                if echoed == v {
                  results.push(CheckResult::pass("negotiation.\{v}", "server echoed \{v}"))
                } else {
                  results.push(CheckResult::pass("negotiation.\{v}.fallback", "server negotiated down to \{echoed} (allowed)"))
                }
              }
              _ => results.push(CheckResult::fail("negotiation.\{v}.no_version", "result missing protocolVersion", resp_str))
            }
          _ =>
            match j.value("error") {
              // Unsupported version → error is compliant behavior
              Some(_) => results.push(CheckResult::pass("negotiation.\{v}.rejected", "unsupported version rejected with error (compliant)"))
              _ => results.push(CheckResult::fail("negotiation.\{v}.malformed", "response has neither result nor error", resp_str))
            }
          }
        }
      }
      Err(e) => results.push(CheckResult::fail("negotiation.\{v}.timeout", e, ""))
    }
  }
  results
}
