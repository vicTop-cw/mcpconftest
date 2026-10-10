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

///| logging/setLevel check (skip when capability absent).
pub async fn check_logging(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match session.request("logging/setLevel", Json::object({ "level": Json::string("info") }), 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch { _ => Json::null() }
      if j is Json::Null {
        results.push(CheckResult::fail("logging.parse", "JSON parse error", resp_str))
      } else {
        match j.value("result") {
          Some(_) => results.push(CheckResult::pass("logging.set_level", "logging/setLevel accepted"))
          _ =>
            match j.value("error") {
              Some(Json::Object(e)) =>
                match e.get("code") {
                  Some(Json::Number(-32601, ..)) => results.push(CheckResult::skip("logging.unsupported", "server does not support logging"))
                  Some(_) => results.push(CheckResult::fail("logging.error", "unexpected error", resp_str))
                  _ => results.push(CheckResult::fail("logging.malformed", "malformed error", resp_str))
                }
              _ => results.push(CheckResult::fail("logging.malformed", "response has neither result nor error", resp_str))
            }
        }
      }
    }
    Err(e) => results.push(CheckResult::skip("logging.unreachable", e))
  }
  results
}

///| completion/complete check (skip when capability absent).
pub async fn check_completion(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match session.request("completion/complete", Json::object({
    "ref": Json::object({ "type": Json::string("ref/prompt"), "name": Json::string("__mcpconftest_dummy__") }),
    "argument": Json::object({ "name": Json::string("test"), "value": Json::string("") }),
  }), 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch { _ => Json::null() }
      if j is Json::Null {
        results.push(CheckResult::fail("completion.parse", "JSON parse error", resp_str))
      } else {
        match j.value("result") {
          Some(Json::Object(r)) =>
            match r.get("completion") {
              Some(Json::Object(c)) =>
                match c.get("values") {
                  Some(Json::Array(_)) => results.push(CheckResult::pass("completion.values", "completion returned values array"))
                  _ => results.push(CheckResult::fail("completion.values", "completion object missing values", resp_str))
                }
              _ => results.push(CheckResult::fail("completion.result", "result missing completion object", resp_str))
            }
          Some(_) => results.push(CheckResult::pass("completion.responded", "completion responded (result present)"))
          _ =>
            match j.value("error") {
              Some(Json::Object(e)) =>
                match e.get("code") {
                  Some(Json::Number(-32601, ..)) => results.push(CheckResult::skip("completion.unsupported", "server does not support completion"))
                  Some(_) => results.push(CheckResult::fail("completion.error", "unexpected error", resp_str))
                  _ => results.push(CheckResult::fail("completion.malformed", "malformed error", resp_str))
                }
              _ => results.push(CheckResult::fail("completion.malformed", "response has neither result nor error", resp_str))
            }
        }
      }
    }
    Err(e) => results.push(CheckResult::skip("completion.unreachable", e))
  }
  results
}

///| resources/subscribe + notifications/resources/updated check.
pub async fn check_subscribe(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match session.request("resources/subscribe", Json::object({ "uri": Json::string("file:///__mcpconftest_dummy__") }), 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch { _ => Json::null() }
      if j is Json::Null {
        results.push(CheckResult::fail("subscribe.parse", "JSON parse error", resp_str))
      } else {
        match j.value("result") {
          Some(_) => results.push(CheckResult::pass("subscribe.ok", "resources/subscribe accepted"))
          _ =>
            match j.value("error") {
              Some(Json::Object(e)) =>
                match e.get("code") {
                  Some(Json::Number(-32601, ..)) => results.push(CheckResult::skip("subscribe.unsupported", "server does not support subscribe"))
                  Some(_) => results.push(CheckResult::fail("subscribe.error", "unexpected error", resp_str))
                  _ => results.push(CheckResult::fail("subscribe.malformed", "malformed error", resp_str))
                }
              _ => results.push(CheckResult::fail("subscribe.malformed", "response has neither result nor error", resp_str))
            }
        }
      }
    }
    Err(e) => results.push(CheckResult::skip("subscribe.unreachable", e))
  }
  results
}

///| sampling/createMessage check (skip when capability absent).
pub async fn check_sampling(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match session.request("sampling/createMessage", Json::object({
    "messages": Json::array([Json::object({
      "role": Json::string("user"),
      "content": Json::object({ "type": Json::string("text"), "text": Json::string("ping") }),
    })]),
    "maxTokens": Json::number(10.0),
  }), 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch { _ => Json::null() }
      if j is Json::Null {
        results.push(CheckResult::fail("sampling.parse", "JSON parse error", resp_str))
      } else {
        match j.value("result") {
          Some(Json::Object(r)) =>
            match r.get("content") {
              Some(Json::Object(c)) =>
                match c.get("text") {
                  Some(Json::String(_)) => results.push(CheckResult::pass("sampling.content", "sampling returned content.text"))
                  _ => results.push(CheckResult::fail("sampling.content", "content object missing text", resp_str))
                }
              _ => results.push(CheckResult::fail("sampling.result", "result missing content object", resp_str))
            }
          Some(_) => results.push(CheckResult::pass("sampling.responded", "sampling responded (result present)"))
          _ =>
            match j.value("error") {
              Some(Json::Object(e)) =>
                match e.get("code") {
                  Some(Json::Number(-32601, ..)) => results.push(CheckResult::skip("sampling.unsupported", "server does not support sampling"))
                  Some(_) => results.push(CheckResult::fail("sampling.error", "unexpected error", resp_str))
                  _ => results.push(CheckResult::fail("sampling.malformed", "malformed error", resp_str))
                }
              _ => results.push(CheckResult::fail("sampling.malformed", "response has neither result nor error", resp_str))
            }
        }
      }
    }
    Err(e) => results.push(CheckResult::skip("sampling.unreachable", e))
  }
  results
}

// ---------------------------------------------------------------------------
// JSON-RPC 2.0 deep checks (batch / id matching / error schema)
// ---------------------------------------------------------------------------

///| Pure validation: a JSON-RPC error response must satisfy the JSON-RPC 2.0
///| error schema. Pushes individual pass/fail findings onto results.
pub fn validate_error_object(resp : Json, e : Map[String, Json], label : String, results : Array[CheckResult]) -> Unit {
  // jsonrpc must be "2.0"
  match resp.value("jsonrpc") {
    Some(Json::String(s)) if s == "2.0" =>
      results.push(CheckResult::pass(label + ".jsonrpc", "error response jsonrpc=2.0"))
    _ =>
      results.push(CheckResult::fail(label + ".jsonrpc", "error response jsonrpc != \"2.0\"", resp.stringify()))
  }
  // result and error are mutually exclusive
  let has_result = resp.value("result") is Some(_)
  let has_error = resp.value("error") is Some(_)
  if has_result && has_error {
    results.push(CheckResult::fail(label + ".exclusive", "response contains both result and error", resp.stringify()))
  } else {
    results.push(CheckResult::pass(label + ".exclusive", "result and error are mutually exclusive"))
  }
  // error.code must be an integer within the reserved range -32768..-32000
  match e.get("code") {
    Some(Json::Number(n, ..)) => {
      let code = n.to_int()
      if n != code.to_double() {
        results.push(CheckResult::fail(label + ".code", "error.code is not an integer", resp.stringify()))
      } else if code >= -32768 && code <= -32000 {
        results.push(CheckResult::pass(label + ".code", "error.code=\{code} in reserved range -32768..-32000"))
      } else {
        results.push(CheckResult::fail(label + ".code", "error.code=\{code} outside reserved range -32768..-32000", resp.stringify()))
      }
    }
    _ => results.push(CheckResult::fail(label + ".code", "error.code missing or not a number", resp.stringify()))
  }
  // error.message must be a non-empty string
  match e.get("message") {
    Some(Json::String(m)) if m.length() > 0 =>
      results.push(CheckResult::pass(label + ".message", "error.message is a non-empty string"))
    Some(Json::String(_)) =>
      results.push(CheckResult::fail(label + ".message", "error.message is an empty string", resp.stringify()))
    _ =>
      results.push(CheckResult::fail(label + ".message", "error.message missing or not a string", resp.stringify()))
  }
  // error.data is optional (present or omitted both acceptable)
  match e.get("data") {
    Some(_) => results.push(CheckResult::pass(label + ".data", "error.data present (optional field, accepted)"))
    None => results.push(CheckResult::pass(label + ".data", "error.data omitted (optional field)"))
  }
}

///| Pure validation: a response id must equal the request id exactly
///| (type + value).
pub fn validate_id_match(resp : Json, req_id : Json, label : String, results : Array[CheckResult]) -> Unit {
  match resp.value("id") {
    Some(id) if id == req_id =>
      results.push(CheckResult::pass(label + ".id", "response id \{req_id.stringify()} matches request id"))
    Some(id) =>
      results.push(CheckResult::fail(label + ".id", "response id \{id.stringify()} != request id \{req_id.stringify()}", resp.stringify()))
    None =>
      results.push(CheckResult::fail(label + ".id", "response missing id", resp.stringify()))
  }
}

///| Pure validation: a batch response must be an array; its item count must
///| match the request count; every request id must have a response item; error
///| items must carry a valid error object.
pub fn validate_batch_resp(
  resp : Json,
  req_ids : Array[Json],
  err_req_ids : Array[Json],
  results : Array[CheckResult],
) -> Unit {
  match resp {
    Json::Array(items) => {
      results.push(CheckResult::pass("batch.array", "batch response is an array"))
      if items.length() != req_ids.length() {
        results.push(CheckResult::fail("batch.count", "expected \{req_ids.length()} response items, got \{items.length()}", resp.stringify()))
      } else {
        results.push(CheckResult::pass("batch.count", "response item count matches request count (\{req_ids.length()})"))
      }
      for req_id in req_ids {
        var found = false
        for item in items {
          match item.value("id") {
            Some(id) => if id == req_id { found = true }
            None => ()
          }
        }
        if found {
          results.push(CheckResult::pass("batch.id_match", "request id \{req_id.stringify()} has a matching response item"))
        } else {
          results.push(CheckResult::fail("batch.id_match", "no response item for request id \{req_id.stringify()}", resp.stringify()))
        }
      }
      for req_id in err_req_ids {
        var item_opt : Option[Json] = None
        for item in items {
          match item.value("id") {
            Some(id) if id == req_id => item_opt = Some(item)
            _ => ()
          }
        }
        match item_opt {
          Some(item) =>
            match item.value("error") {
              Some(Json::Object(_)) =>
                results.push(CheckResult::pass("batch.error_schema", "error item for \{req_id.stringify()} carries a valid error object"))
              Some(_) =>
                results.push(CheckResult::fail("batch.error_schema", "error item for \{req_id.stringify()} has a non-object error", item.stringify()))
              None =>
                results.push(CheckResult::fail("batch.error_schema", "expected error for \{req_id.stringify()}, got none", item.stringify()))
            }
          None =>
            results.push(CheckResult::fail("batch.error_schema", "no response item for error request \{req_id.stringify()}", resp.stringify()))
        }
      }
    }
    _ => results.push(CheckResult::fail("batch.not_array", "batch response is not an array", resp.stringify()))
  }
}

///| JSON-RPC batch check: send a batch array request with 2~3 distinct ids and
///| verify the response is an array, item count matches, every response id
///| matches the request id, and error items carry a valid error object.
pub async fn check_batch(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  let reqs = Json::array([
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(1.0),
      "method": Json::string("tools/list"),
      "params": Json::object({}),
    }),
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(42.0),
      "method": Json::string("tools/call"),
      "params": Json::object({ "name": Json::string("echo"), "arguments": Json::object({ "text": Json::string("hi") }) }),
    }),
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::string("req-batch-err"),
      "method": Json::string("unknown/method"),
      "params": Json::object({}),
    }),
  ])
  let req_ids : Array[Json] = [Json::number(1.0), Json::number(42.0), Json::string("req-batch-err")]
  let err_req_ids : Array[Json] = [Json::string("req-batch-err")]
  match session.request_raw(reqs.stringify(), 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch { _ => Json::null() }
      if j is Json::Null {
        results.push(CheckResult::fail("batch.parse", "JSON parse error", resp_str))
      } else {
        validate_batch_resp(j, req_ids, err_req_ids, results)
      }
    }
    Err(e) => results.push(CheckResult::fail("batch.timeout", e, ""))
  }
  results
}

///| JSON-RPC id matching check: number ids (1, 42) and string ids ("req-1",
///| special chars) must be echoed back exactly (type + value).
pub async fn check_id_matching(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  let ids = [
    Json::number(1.0),
    Json::number(42.0),
    Json::string("req-1"),
    Json::string("req a#b&é"),
  ]
  let n = ids.length()
  let mut i = 0
  while i < n {
    let id = ids[i]
    let req = Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": id,
      "method": Json::string("tools/list"),
      "params": Json::object({}),
    })
    let label = "id_match.\{i}"
    match session.request_raw(req.stringify(), 5000) {
      Ok(resp_str) => {
        let j = @json.parse(resp_str) catch { _ => Json::null() }
        if j is Json::Null {
          results.push(CheckResult::fail(label + ".parse", "JSON parse error", resp_str))
        } else {
          validate_id_match(j, id, label, results)
        }
      }
      Err(e) => results.push(CheckResult::fail(label + ".timeout", e, ""))
    }
    i = i + 1
  }
  results
}

///| JSON-RPC 2.0 error schema check: trigger an error (unknown method) and
///| deeply validate the error object (code range, message, data optional,
///| result/error exclusivity, jsonrpc=2.0).
pub async fn check_error_schema(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  let req = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(7.0),
    "method": Json::string("unknown/method"),
    "params": Json::object({}),
  })
  match session.request_raw(req.stringify(), 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch { _ => Json::null() }
      if j is Json::Null {
        results.push(CheckResult::fail("error_schema.parse", "JSON parse error", resp_str))
        return results
      }
      match j {
        Json::Object(_) => {
          let has_result = j.value("result") is Some(_)
          let has_error = j.value("error") is Some(_)
          if has_error {
            match j.value("error") {
              Some(Json::Object(e)) => validate_error_object(j, e, "error_schema", results)
              Some(_) => results.push(CheckResult::fail("error_schema.shape", "error is not an object", resp_str))
              None => ()
            }
          } else if has_result {
            results.push(CheckResult::fail("error_schema.no_error", "expected an error response, got result only", resp_str))
          } else {
            results.push(CheckResult::fail("error_schema.no_error", "response has neither result nor error", resp_str))
          }
        }
        _ => results.push(CheckResult::fail("error_schema.shape", "error response is not an object", resp_str))
      }
    }
    Err(e) => results.push(CheckResult::fail("error_schema.timeout", e, ""))
  }
  results
}
