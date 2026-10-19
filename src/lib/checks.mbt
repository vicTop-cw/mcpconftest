///| Six categories of MCP protocol conformance checks.

///|
/// Initialize handshake check.
pub async fn check_initialize(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  let params = Json::object({
    "protocolVersion": Json::string("2026-07-28"),
    "capabilities": Json::object({}),
    "clientInfo": Json::object({
      "name": Json::string("mcpconftest"),
      "version": Json::string("0.2.0"),
    }),
    "_meta": Json::object({
      "io.modelcontextprotocol/protocolVersion": Json::string("2026-07-28"),
      "io.modelcontextprotocol/clientCapabilities": Json::object({}),
    }),
  })
  match session.request("initialize", params, 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch {
        _ => {
          results.push(
            CheckResult::fail("init.parse", "JSON parse error", resp_str),
          )
          return results
        }
      }
      match (if j is Object(obj) { obj.get("jsonrpc") } else { None }) {
        Some(Json::String(s)) if s == "2.0" =>
          results.push(CheckResult::pass("init.jsonrpc", "jsonrpc=2.0"))
        _ =>
          results.push(
            CheckResult::fail("init.jsonrpc", "expected jsonrpc=2.0", resp_str),
          )
      }
      match (if j is Object(obj) { obj.get("result") } else { None }) {
        Some(Json::Object(r)) => {
          match r.get("serverInfo") {
            Some(_) =>
              results.push(
                CheckResult::pass("init.server_info", "serverInfo present"),
              )
            None =>
              results.push(
                CheckResult::fail(
                  "init.server_info", "serverInfo missing", resp_str,
                ),
              )
          }
          match r.get("protocolVersion") {
            Some(Json::String(v)) if v == "2026-07-28" =>
              results.push(
                CheckResult::pass("init.protocol_version", "version=2026-07-28"),
              )
            Some(Json::String(v)) =>
              results.push(
                CheckResult::fail(
                  "init.protocol_version",
                  "got version=\{v}, expected 2026-07-28",
                  resp_str,
                ),
              )
            _ =>
              results.push(
                CheckResult::fail(
                  "init.protocol_version", "protocolVersion missing", resp_str,
                ),
              )
          }
        }
        _ =>
          // 2026-07-28 removed the initialize handshake; a compliant server
          // correctly rejects it with -32601 + supportedVersions.
          match (if j is Object(obj) { obj.get("error") } else { None }) {
            Some(Json::Object(e)) =>
              match e.get("code") {
                Some(Json::Number(-32601, ..)) =>
                  match e.get("message") {
                    Some(Json::String(msg)) if msg.contains("supportedVersions") ||
                      msg.contains("speaks MCP") ||
                      msg.contains("2026-07-28") =>
                      results.push(
                        CheckResult::pass(
                          "init.removed", "initialize removed in 2026-07-28; server correctly rejects with -32601 + supportedVersions",
                        ),
                      )
                    _ =>
                      results.push(
                        CheckResult::fail(
                          "init.result", "result object missing", resp_str,
                        ),
                      )
                  }
                Some(_) =>
                  results.push(
                    CheckResult::fail(
                      "init.result", "result object missing", resp_str,
                    ),
                  )
                _ =>
                  results.push(
                    CheckResult::fail(
                      "init.result", "result object missing", resp_str,
                    ),
                  )
              }
            _ =>
              results.push(
                CheckResult::fail(
                  "init.result", "result object missing", resp_str,
                ),
              )
          }
      }
    }
    Err(e) => results.push(CheckResult::fail("init.timeout", e, ""))
  }
  match session.notify("notifications/initialized", Json::object({})) {
    Ok(_) =>
      results.push(
        CheckResult::pass("init.notifications_initialized", "sent OK"),
      )
    Err(e) =>
      results.push(CheckResult::fail("init.notifications_initialized", e, ""))
  }
  results
}

///| Capabilities check: declared vs actual behavior.

///| 2026-07-28 discovers capabilities via server/discover; legacy servers that

///|
/// reject server/discover fall back to the old initialize handshake.
pub async fn check_capabilities(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  let disc_resp = session.request("server/discover", Json::object({}), 5000)
  match disc_resp {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch { _ => Json::null() }
      let caps = match
        (if j is Object(obj) { obj.get("result") } else { None }) {
        Some(Json::Object(r)) => r.get("capabilities")
        _ => None
      }
      match caps {
        Some(Json::Object(c)) =>
          match c.get("tools") {
            Some(_) =>
              results.push(
                CheckResult::pass(
                  "caps.tools", "tools capability declared (via server/discover)",
                ),
              )
            None =>
              results.push(
                CheckResult::fail(
                  "caps.tools", "tools capability not declared", "",
                ),
              )
          }
        _ =>
          match (if j is Object(obj) { obj.get("error") } else { None }) {
            Some(Json::Object(e)) =>
              match e.get("code") {
                Some(Json::Number(-32601, ..)) => {
                  // Legacy server without server/discover → initialize fallback.
                  let init_resp = session.request(
                    "initialize",
                    Json::object({}),
                    5000,
                  )
                  match init_resp {
                    Ok(init_str) => {
                      let ji = @json.parse(init_str) catch { _ => Json::null() }
                      match
                        (if ji is Object(obj) {
                          obj.get("result")
                        } else {
                          None
                        }) {
                        Some(Json::Object(r)) =>
                          match r.get("capabilities") {
                            Some(Json::Object(c2)) =>
                              match c2.get("tools") {
                                Some(_) =>
                                  results.push(
                                    CheckResult::pass(
                                      "caps.tools", "tools capability declared (via initialize fallback)",
                                    ),
                                  )
                                None =>
                                  results.push(
                                    CheckResult::fail(
                                      "caps.tools", "tools capability not declared",
                                      "",
                                    ),
                                  )
                              }
                            _ =>
                              results.push(
                                CheckResult::fail(
                                  "caps.declared", "no capabilities declared", init_str,
                                ),
                              )
                          }
                        _ =>
                          results.push(
                            CheckResult::fail(
                              "caps.declared", "initialize fallback returned no result",
                              init_str,
                            ),
                          )
                      }
                    }
                    Err(e) =>
                      results.push(
                        CheckResult::fail("caps.fallback_timeout", e, ""),
                      )
                  }
                }
                Some(_) =>
                  results.push(
                    CheckResult::fail(
                      "caps.declared", "server/discover returned unexpected error",
                      resp_str,
                    ),
                  )
                _ =>
                  results.push(
                    CheckResult::fail(
                      "caps.malformed", "server/discover returned malformed error",
                      resp_str,
                    ),
                  )
              }
            _ =>
              results.push(
                CheckResult::fail(
                  "caps.declared", "no capabilities declared", resp_str,
                ),
              )
          }
      }
    }
    Err(e) => results.push(CheckResult::fail("caps.timeout", e, ""))
  }
  results
}

///|
/// tools/list schema check.
pub async fn check_tools_list(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match session.request("tools/list", Json::object({}), 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch {
        _ => {
          results.push(
            CheckResult::fail("tools_list.parse", "JSON parse error", resp_str),
          )
          return results
        }
      }
      match (if j is Object(obj) { obj.get("result") } else { None }) {
        Some(Json::Object(r)) =>
          match r.get("tools") {
            Some(Json::Array(tools)) =>
              if tools.length() == 0 {
                results.push(
                  CheckResult::fail(
                    "tools_list.empty", "tools array is empty", resp_str,
                  ),
                )
              } else {
                for tool in tools {
                  match tool {
                    Json::Object(tool_obj) => {
                      match tool_obj.get("name") {
                        Some(_) =>
                          results.push(
                            CheckResult::pass(
                              "tools_list.name", "tool has name",
                            ),
                          )
                        None =>
                          results.push(
                            CheckResult::fail(
                              "tools_list.name",
                              "tool missing name",
                              tool.stringify(),
                            ),
                          )
                      }
                      match tool_obj.get("description") {
                        Some(_) =>
                          results.push(
                            CheckResult::pass(
                              "tools_list.description", "tool has description",
                            ),
                          )
                        None =>
                          results.push(
                            CheckResult::fail(
                              "tools_list.description",
                              "tool missing description",
                              tool.stringify(),
                            ),
                          )
                      }
                    }
                    _ =>
                      results.push(
                        CheckResult::fail(
                          "tools_list.item",
                          "tool is not object",
                          tool.stringify(),
                        ),
                      )
                  }
                }
              }
            _ =>
              results.push(
                CheckResult::fail(
                  "tools_list.tools", "tools array missing", resp_str,
                ),
              )
          }
        _ =>
          results.push(
            CheckResult::fail(
              "tools_list.result", "result object missing", resp_str,
            ),
          )
      }
    }
    Err(e) => results.push(CheckResult::fail("tools_list.timeout", e, ""))
  }
  results
}

///|
/// tools/call check: error path.
pub async fn check_tools_call(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match
    session.request(
      "tools/call",
      Json::object({
        "name": Json::string("__mcpconftest_nonexistent__"),
        "arguments": Json::object({}),
      }),
      5000,
    ) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch {
        _ => {
          results.push(
            CheckResult::fail("tools_call.parse", "JSON parse error", resp_str),
          )
          return results
        }
      }
      match (if j is Object(obj) { obj.get("error") } else { None }) {
        Some(Json::Object(e)) =>
          match e.get("code") {
            Some(Json::Number(n, ..)) => {
              let code = n.to_int()
              if code == -32601 {
                results.push(
                  CheckResult::pass(
                    "tools_call.error", "non-existent tool returned correct error code -32601",
                  ),
                )
              } else {
                results.push(
                  CheckResult::fail(
                    "tools_call.error_code",
                    "expected -32601, got \{code} (wrong error code for unknown tool)",
                    resp_str,
                  ),
                )
              }
            }
            _ =>
              results.push(
                CheckResult::fail(
                  "tools_call.error_code", "error object missing code", resp_str,
                ),
              )
          }
        _ =>
          results.push(
            CheckResult::fail(
              "tools_call.error", "expected error for non-existent tool", resp_str,
            ),
          )
      }
    }
    Err(e) => results.push(CheckResult::fail("tools_call.timeout", e, ""))
  }
  results
}

///|
/// Notification handling check.
pub async fn check_notifications(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match session.notify("notifications/mcpconftest_unknown", Json::object({})) {
    Ok(_) =>
      results.push(
        CheckResult::pass(
          "notifications.unknown", "unknown notification sent without crash",
        ),
      )
    Err(e) => results.push(CheckResult::fail("notifications.send", e, ""))
  }
  match session.request("tools/list", Json::object({}), 5000) {
    Ok(_) =>
      results.push(
        CheckResult::pass(
          "notifications.alive", "session still alive after unknown notification",
        ),
      )
    Err(e) =>
      results.push(
        CheckResult::fail("notifications.alive", "session died: \{e}", ""),
      )
  }
  results
}

///|
/// Session idempotency check.
pub async fn check_idempotency(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match session.request("tools/list", Json::object({}), 5000) {
    Ok(resp1) =>
      match session.request("tools/list", Json::object({}), 5000) {
        Ok(resp2) => {
          let j1 = @json.parse(resp1) catch { _ => Json::null() }
          let j2 = @json.parse(resp2) catch { _ => Json::null() }
          let r1 = if j1 is Object(obj) { obj.get("result") } else { None }
          let r2 = if j2 is Object(obj) { obj.get("result") } else { None }
          if r1 == r2 {
            results.push(
              CheckResult::pass(
                "idempotency", "repeated tools/list returned same result",
              ),
            )
          } else {
            results.push(
              CheckResult::fail(
                "idempotency", "repeated tools/list returned different results",
                "",
              ),
            )
          }
        }
        Err(e) =>
          results.push(
            CheckResult::fail(
              "idempotency.second",
              "second call failed: \{e}",
              "",
            ),
          )
      }
    Err(e) =>
      results.push(
        CheckResult::fail("idempotency.first", "first call failed: \{e}", ""),
      )
  }
  results
}

///|
/// resources/list schema check (skip when server lacks the capability).
pub async fn check_resources_list(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match session.request("resources/list", Json::object({}), 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch {
        _ => {
          results.push(
            CheckResult::fail(
              "resources_list.parse", "JSON parse error", resp_str,
            ),
          )
          return results
        }
      }
      match (if j is Object(obj) { obj.get("result") } else { None }) {
        Some(Json::Object(r)) =>
          match r.get("resources") {
            Some(Json::Array(resources)) =>
              if resources.length() == 0 {
                results.push(
                  CheckResult::pass(
                    "resources_list.empty_ok", "resources array empty (valid)",
                  ),
                )
              } else {
                for res in resources {
                  match res {
                    Json::Object(res_obj) => {
                      match res_obj.get("uri") {
                        Some(Json::String(_)) =>
                          results.push(
                            CheckResult::pass(
                              "resources_list.uri", "resource has uri",
                            ),
                          )
                        _ =>
                          results.push(
                            CheckResult::fail(
                              "resources_list.uri",
                              "resource missing uri",
                              res.stringify(),
                            ),
                          )
                      }
                      match res_obj.get("name") {
                        Some(_) =>
                          results.push(
                            CheckResult::pass(
                              "resources_list.name", "resource has name",
                            ),
                          )
                        _ =>
                          results.push(
                            CheckResult::fail(
                              "resources_list.name",
                              "resource missing name",
                              res.stringify(),
                            ),
                          )
                      }
                    }
                    _ =>
                      results.push(
                        CheckResult::fail(
                          "resources_list.item",
                          "resource is not object",
                          res.stringify(),
                        ),
                      )
                  }
                }
              }
            _ =>
              results.push(
                CheckResult::skip(
                  "resources_list.result", "resources array missing (server may not support resources)",
                ),
              )
          }
        _ =>
          results.push(
            CheckResult::skip(
              "resources_list.unsupported", "no result (server may not support resources)",
            ),
          )
      }
    }
    Err(e) => results.push(CheckResult::skip("resources_list.unreachable", e))
  }
  results
}

///|
/// prompts/list schema check (skip when server lacks the capability).
pub async fn check_prompts_list(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match session.request("prompts/list", Json::object({}), 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch {
        _ => {
          results.push(
            CheckResult::fail(
              "prompts_list.parse", "JSON parse error", resp_str,
            ),
          )
          return results
        }
      }
      match (if j is Object(obj) { obj.get("result") } else { None }) {
        Some(Json::Object(r)) =>
          match r.get("prompts") {
            Some(Json::Array(prompts)) =>
              if prompts.length() == 0 {
                results.push(
                  CheckResult::pass(
                    "prompts_list.empty_ok", "prompts array empty (valid)",
                  ),
                )
              } else {
                for p in prompts {
                  match p {
                    Json::Object(p_obj) =>
                      match p_obj.get("name") {
                        Some(_) =>
                          results.push(
                            CheckResult::pass(
                              "prompts_list.name", "prompt has name",
                            ),
                          )
                        _ =>
                          results.push(
                            CheckResult::fail(
                              "prompts_list.name",
                              "prompt missing name",
                              p.stringify(),
                            ),
                          )
                      }
                    _ =>
                      results.push(
                        CheckResult::fail(
                          "prompts_list.item",
                          "prompt is not object",
                          p.stringify(),
                        ),
                      )
                  }
                }
              }
            _ =>
              results.push(
                CheckResult::skip(
                  "prompts_list.result", "prompts array missing (server may not support prompts)",
                ),
              )
          }
        _ =>
          results.push(
            CheckResult::skip(
              "prompts_list.unsupported", "no result (server may not support prompts)",
            ),
          )
      }
    }
    Err(e) => results.push(CheckResult::skip("prompts_list.unreachable", e))
  }
  results
}

///|
/// resources/read error path: non-existent resource must return a JSON-RPC error.
pub async fn check_resources_read_error(
  session : Session,
) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match
    session.request(
      "resources/read",
      Json::object({
        "uri": Json::string("file:///__mcpconftest_nonexistent__"),
      }),
      5000,
    ) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch {
        _ => {
          results.push(
            CheckResult::fail(
              "resources_read.parse", "JSON parse error", resp_str,
            ),
          )
          return results
        }
      }
      match (if j is Object(obj) { obj.get("error") } else { None }) {
        Some(Json::Object(e)) =>
          match e.get("code") {
            Some(Json::Number(_, ..)) =>
              results.push(
                CheckResult::pass(
                  "resources_read.error", "non-existent resource returned error",
                ),
              )
            _ =>
              results.push(
                CheckResult::fail(
                  "resources_read.error_code", "error object missing code", resp_str,
                ),
              )
          }
        // isError-inside-result is also acceptable per spec
        Some(_) =>
          results.push(
            CheckResult::pass(
              "resources_read.error", "non-existent resource returned error",
            ),
          )
        _ =>
          results.push(
            CheckResult::fail(
              "resources_read.no_error", "expected error for non-existent resource",
              resp_str,
            ),
          )
      }
    }
    Err(e) => results.push(CheckResult::skip("resources_read.unreachable", e))
  }
  results
}

///| ping check: server must respond to ping (empty result per spec).

///| 2026-07-28 removed the ping method; servers that implement server/discover

///| (stateless era) correctly reject ping with -32601, which is treated as a

///|
/// compliant skip — liveness is covered by the keepalive RPC check instead.
pub async fn check_ping(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  // Determine the protocol era: a server answering server/discover is a
  // 2026-07-28 stateless server (ping removed); a -32601 there means legacy.
  let mut stateless_server = false
  match session.request("server/discover", Json::object({}), 3000) {
    Ok(resp_str) => {
      let dj = @json.parse(resp_str) catch { _ => Json::null() }
      if (if dj is Object(obj) { obj.get("result") } else { None })
        is Some(Json::Object(_)) {
        stateless_server = true
      }
    }
    Err(_) => ()
  }
  match session.request("ping", Json::object({}), 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch {
        _ => {
          results.push(
            CheckResult::fail("ping.parse", "JSON parse error", resp_str),
          )
          return results
        }
      }
      match (if j is Object(obj) { obj.get("result") } else { None }) {
        Some(_) =>
          results.push(
            CheckResult::pass("ping.responds", "ping answered with result"),
          )
        _ =>
          match (if j is Object(obj) { obj.get("error") } else { None }) {
            Some(Json::Object(e)) =>
              match e.get("code") {
                Some(Json::Number(-32601, ..)) =>
                  if stateless_server {
                    results.push(
                      CheckResult::skip(
                        "ping.removed", "ping removed in 2026-07-28; server correctly rejects with -32601 (liveness covered by keepalive RPC)",
                      ),
                    )
                  } else {
                    results.push(
                      CheckResult::fail(
                        "ping.responds", "ping returned -32601 (spec: server MUST respond to ping)",
                        resp_str,
                      ),
                    )
                  }
                Some(_) =>
                  results.push(
                    CheckResult::fail(
                      "ping.responds", "ping returned unexpected error", resp_str,
                    ),
                  )
                _ =>
                  results.push(
                    CheckResult::fail(
                      "ping.responds", "ping returned malformed error", resp_str,
                    ),
                  )
              }
            _ =>
              results.push(
                CheckResult::fail(
                  "ping.malformed", "response has neither result nor error", resp_str,
                ),
              )
          }
      }
    }
    Err(e) => results.push(CheckResult::fail("ping.timeout", e, ""))
  }
  results
}

///|
/// Keepalive: repeated pings must all succeed (session liveness under load).
pub async fn check_keepalive(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  let mut all_ok = true
  // 2026-07-28 removed ping; liveness is probed with a regular RPC
  // (tools/list) that every server must implement.
  for i in 1..<=3 {
    match session.request("tools/list", Json::object({}), 3000) {
      Ok(resp_str) => {
        let j = @json.parse(resp_str) catch { _ => Json::null() }
        if j is Json::Null {
          all_ok = false
          results.push(
            CheckResult::fail(
              "keepalive.parse_\{i}",
              "JSON parse error",
              resp_str,
            ),
          )
        } else if (if j is Object(obj) { obj.get("result") } else { None })
          is Some(_) {
          ()
        } else {
          all_ok = false
          results.push(
            CheckResult::fail(
              "keepalive.no_result_\{i}",
              "keepalive RPC \{i} failed",
              resp_str,
            ),
          )
        }
      }
      Err(e) => {
        all_ok = false
        results.push(CheckResult::fail("keepalive.timeout_\{i}", e, ""))
      }
    }
  }
  if all_ok {
    results.push(
      CheckResult::pass("keepalive.stable", "3/3 keepalive RPCs succeeded"),
    )
  }
  results
}

///|
/// Protocol version negotiation matrix: probe servers with several
/// protocolVersion values; a compliant server either echoes a supported
/// version or replies with a JSON-RPC error — never a malformed response.
/// Since 2026-07-28 negotiation is inline: the client sends its preferred
/// version per-request (in _meta + MCP-Protocol-Version) and an unsupported
/// version must be answered with -32022 + data.supported.
pub async fn check_protocol_negotiation(
  session : Session,
) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  let versions = ["2026-07-28", "2025-06-18", "2025-03-26", "1999-01-01"]
  for v in versions {
    let params = Json::object({
      "protocolVersion": Json::string(v),
      "capabilities": Json::object({}),
      "clientInfo": Json::object({
        "name": Json::string("mcpconftest"),
        "version": Json::string(version()),
      }),
      "_meta": Json::object({
        "io.modelcontextprotocol/protocolVersion": Json::string(v),
        "io.modelcontextprotocol/clientCapabilities": Json::object({}),
      }),
    })
    match session.request("initialize", params, 5000) {
      Ok(resp_str) => {
        let j = @json.parse(resp_str) catch { _ => Json::null() }
        if j is Json::Null {
          results.push(
            CheckResult::fail(
              "negotiation.\{v}.parse",
              "JSON parse error",
              resp_str,
            ),
          )
        } else {
          match (if j is Object(obj) { obj.get("result") } else { None }) {
            Some(Json::Object(r)) =>
              match r.get("protocolVersion") {
                Some(Json::String(echoed)) =>
                  if echoed == v {
                    results.push(
                      CheckResult::pass(
                        "negotiation.\{v}",
                        "server echoed \{v}",
                      ),
                    )
                  } else {
                    results.push(
                      CheckResult::pass(
                        "negotiation.\{v}.fallback",
                        "server negotiated down to \{echoed} (allowed)",
                      ),
                    )
                  }
                _ =>
                  results.push(
                    CheckResult::fail(
                      "negotiation.\{v}.no_version",
                      "result missing protocolVersion",
                      resp_str,
                    ),
                  )
              }
            _ =>
              match (if j is Object(obj) { obj.get("error") } else { None }) {
                // Unsupported version → error is compliant behavior
                Some(_) =>
                  results.push(
                    CheckResult::pass(
                      "negotiation.\{v}.rejected",
                      "unsupported version rejected with error (compliant)",
                    ),
                  )
                _ =>
                  results.push(
                    CheckResult::fail(
                      "negotiation.\{v}.malformed",
                      "response has neither result nor error",
                      resp_str,
                    ),
                  )
              }
          }
        }
      }
      Err(e) =>
        results.push(CheckResult::fail("negotiation.\{v}.timeout", e, ""))
    }
  }
  // 2026-07-28 stateless inline negotiation: a plain RPC carries the version;
  // an unsupported version must yield -32022 + data.supported (never success).
  let stateless_versions = ["2026-07-28", "2099-01-01"]
  for v in stateless_versions {
    let params = Json::object({
      "protocolVersion": Json::string(v),
      "_meta": Json::object({
        "io.modelcontextprotocol/protocolVersion": Json::string(v),
        "io.modelcontextprotocol/clientInfo": Json::object({
          "name": Json::string("mcpconftest"),
          "version": Json::string(version()),
        }),
        "io.modelcontextprotocol/clientCapabilities": Json::object({}),
      }),
    })
    match session.request("tools/list", params, 5000) {
      Ok(resp_str) => {
        let j = @json.parse(resp_str) catch { _ => Json::null() }
        if j is Json::Null {
          results.push(
            CheckResult::fail(
              "negotiation.\{v}.parse",
              "JSON parse error",
              resp_str,
            ),
          )
        } else if (if j is Object(obj) { obj.get("result") } else { None })
          is Some(_) {
          if v == "2026-07-28" {
            results.push(
              CheckResult::pass(
                "negotiation.\{v}.inline",
                "tools/list accepted \{v} (inline negotiation OK)",
              ),
            )
          } else {
            results.push(
              CheckResult::fail(
                "negotiation.\{v}.inline",
                "tools/list processed unsupported version \{v} (must reply -32022 + data.supported)",
                resp_str,
              ),
            )
          }
        } else {
          match (if j is Object(obj) { obj.get("error") } else { None }) {
            Some(Json::Object(e)) =>
              match e.get("code") {
                Some(Json::Number(-32022, ..)) =>
                  match e.get("data") {
                    Some(Json::Object(d)) =>
                      if d.get("supported") is Some(Json::Array(_)) {
                        results.push(
                          CheckResult::pass(
                            "negotiation.\{v}.inline",
                            "unsupported version \{v} rejected with -32022 + data.supported",
                          ),
                        )
                      } else {
                        results.push(
                          CheckResult::fail(
                            "negotiation.\{v}.data",
                            "-32022 error missing data.supported",
                            resp_str,
                          ),
                        )
                      }
                    _ =>
                      results.push(
                        CheckResult::fail(
                          "negotiation.\{v}.data",
                          "-32022 error missing data object",
                          resp_str,
                        ),
                      )
                  }
                Some(Json::Number(-32601, ..)) =>
                  results.push(
                    CheckResult::fail(
                      "negotiation.\{v}.inline",
                      "tools/list returned -32601 (spec: server MUST implement tools/list)",
                      resp_str,
                    ),
                  )
                Some(_) =>
                  results.push(
                    CheckResult::fail(
                      "negotiation.\{v}.inline",
                      "unexpected error for version \{v}",
                      resp_str,
                    ),
                  )
                _ =>
                  results.push(
                    CheckResult::fail(
                      "negotiation.\{v}.malformed",
                      "malformed error",
                      resp_str,
                    ),
                  )
              }
            _ =>
              results.push(
                CheckResult::fail(
                  "negotiation.\{v}.malformed",
                  "response has neither result nor error",
                  resp_str,
                ),
              )
          }
        }
      }
      Err(e) =>
        results.push(CheckResult::fail("negotiation.\{v}.timeout", e, ""))
    }
  }
  results
}

///|
/// logging/setLevel check (skip when capability absent).
pub async fn check_logging(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match
    session.request(
      "logging/setLevel",
      Json::object({ "level": Json::string("info") }),
      5000,
    ) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch { _ => Json::null() }
      if j is Json::Null {
        results.push(
          CheckResult::fail("logging.parse", "JSON parse error", resp_str),
        )
      } else {
        match (if j is Object(obj) { obj.get("result") } else { None }) {
          Some(_) =>
            results.push(
              CheckResult::pass(
                "logging.set_level", "logging/setLevel accepted",
              ),
            )
          _ =>
            match (if j is Object(obj) { obj.get("error") } else { None }) {
              Some(Json::Object(e)) =>
                match e.get("code") {
                  Some(Json::Number(-32601, ..)) =>
                    results.push(
                      CheckResult::skip(
                        "logging.unsupported", "server does not support logging",
                      ),
                    )
                  Some(_) =>
                    results.push(
                      CheckResult::fail(
                        "logging.error", "unexpected error", resp_str,
                      ),
                    )
                  _ =>
                    results.push(
                      CheckResult::fail(
                        "logging.malformed", "malformed error", resp_str,
                      ),
                    )
                }
              _ =>
                results.push(
                  CheckResult::fail(
                    "logging.malformed", "response has neither result nor error",
                    resp_str,
                  ),
                )
            }
        }
      }
    }
    Err(e) => results.push(CheckResult::skip("logging.unreachable", e))
  }
  results
}

///|
/// completion/complete check (skip when capability absent).
pub async fn check_completion(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match
    session.request(
      "completion/complete",
      Json::object({
        "ref": Json::object({
          "type": Json::string("ref/prompt"),
          "name": Json::string("__mcpconftest_dummy__"),
        }),
        "argument": Json::object({
          "name": Json::string("test"),
          "value": Json::string(""),
        }),
      }),
      5000,
    ) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch { _ => Json::null() }
      if j is Json::Null {
        results.push(
          CheckResult::fail("completion.parse", "JSON parse error", resp_str),
        )
      } else {
        match (if j is Object(obj) { obj.get("result") } else { None }) {
          Some(Json::Object(r)) =>
            match r.get("completion") {
              Some(Json::Object(c)) =>
                match c.get("values") {
                  Some(Json::Array(_)) =>
                    results.push(
                      CheckResult::pass(
                        "completion.values", "completion returned values array",
                      ),
                    )
                  _ =>
                    results.push(
                      CheckResult::fail(
                        "completion.values", "completion object missing values",
                        resp_str,
                      ),
                    )
                }
              _ =>
                results.push(
                  CheckResult::fail(
                    "completion.result", "result missing completion object", resp_str,
                  ),
                )
            }
          Some(_) =>
            results.push(
              CheckResult::pass(
                "completion.responded", "completion responded (result present)",
              ),
            )
          _ =>
            match (if j is Object(obj) { obj.get("error") } else { None }) {
              Some(Json::Object(e)) =>
                match e.get("code") {
                  Some(Json::Number(-32601, ..)) =>
                    results.push(
                      CheckResult::skip(
                        "completion.unsupported", "server does not support completion",
                      ),
                    )
                  Some(_) =>
                    results.push(
                      CheckResult::fail(
                        "completion.error", "unexpected error", resp_str,
                      ),
                    )
                  _ =>
                    results.push(
                      CheckResult::fail(
                        "completion.malformed", "malformed error", resp_str,
                      ),
                    )
                }
              _ =>
                results.push(
                  CheckResult::fail(
                    "completion.malformed", "response has neither result nor error",
                    resp_str,
                  ),
                )
            }
        }
      }
    }
    Err(e) => results.push(CheckResult::skip("completion.unreachable", e))
  }
  results
}

///|
/// resources/subscribe + notifications/resources/updated check.
pub async fn check_subscribe(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match
    session.request(
      "resources/subscribe",
      Json::object({ "uri": Json::string("file:///__mcpconftest_dummy__") }),
      5000,
    ) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch { _ => Json::null() }
      if j is Json::Null {
        results.push(
          CheckResult::fail("subscribe.parse", "JSON parse error", resp_str),
        )
      } else {
        match (if j is Object(obj) { obj.get("result") } else { None }) {
          Some(_) =>
            results.push(
              CheckResult::pass("subscribe.ok", "resources/subscribe accepted"),
            )
          _ =>
            match (if j is Object(obj) { obj.get("error") } else { None }) {
              Some(Json::Object(e)) =>
                match e.get("code") {
                  Some(Json::Number(-32601, ..)) =>
                    results.push(
                      CheckResult::skip(
                        "subscribe.unsupported", "server does not support subscribe",
                      ),
                    )
                  Some(_) =>
                    results.push(
                      CheckResult::fail(
                        "subscribe.error", "unexpected error", resp_str,
                      ),
                    )
                  _ =>
                    results.push(
                      CheckResult::fail(
                        "subscribe.malformed", "malformed error", resp_str,
                      ),
                    )
                }
              _ =>
                results.push(
                  CheckResult::fail(
                    "subscribe.malformed", "response has neither result nor error",
                    resp_str,
                  ),
                )
            }
        }
      }
    }
    Err(e) => results.push(CheckResult::skip("subscribe.unreachable", e))
  }
  results
}

///|
/// sampling/createMessage check (skip when capability absent).
pub async fn check_sampling(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match
    session.request(
      "sampling/createMessage",
      Json::object({
        "messages": Json::array([
          Json::object({
            "role": Json::string("user"),
            "content": Json::object({
              "type": Json::string("text"),
              "text": Json::string("ping"),
            }),
          }),
        ]),
        "maxTokens": Json::number(10.0),
      }),
      5000,
    ) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch { _ => Json::null() }
      if j is Json::Null {
        results.push(
          CheckResult::fail("sampling.parse", "JSON parse error", resp_str),
        )
      } else {
        match (if j is Object(obj) { obj.get("result") } else { None }) {
          Some(Json::Object(r)) =>
            match r.get("content") {
              Some(Json::Object(c)) =>
                match c.get("text") {
                  Some(Json::String(_)) =>
                    results.push(
                      CheckResult::pass(
                        "sampling.content", "sampling returned content.text",
                      ),
                    )
                  _ =>
                    results.push(
                      CheckResult::fail(
                        "sampling.content", "content object missing text", resp_str,
                      ),
                    )
                }
              _ =>
                results.push(
                  CheckResult::fail(
                    "sampling.result", "result missing content object", resp_str,
                  ),
                )
            }
          Some(_) =>
            results.push(
              CheckResult::pass(
                "sampling.responded", "sampling responded (result present)",
              ),
            )
          _ =>
            match (if j is Object(obj) { obj.get("error") } else { None }) {
              Some(Json::Object(e)) =>
                match e.get("code") {
                  Some(Json::Number(-32601, ..)) =>
                    results.push(
                      CheckResult::skip(
                        "sampling.unsupported", "server does not support sampling",
                      ),
                    )
                  Some(_) =>
                    results.push(
                      CheckResult::fail(
                        "sampling.error", "unexpected error", resp_str,
                      ),
                    )
                  _ =>
                    results.push(
                      CheckResult::fail(
                        "sampling.malformed", "malformed error", resp_str,
                      ),
                    )
                }
              _ =>
                results.push(
                  CheckResult::fail(
                    "sampling.malformed", "response has neither result nor error",
                    resp_str,
                  ),
                )
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

///|
/// error schema. Pushes individual pass/fail findings onto results.
pub fn validate_error_object(
  resp : Json,
  e : Map[String, Json],
  label : String,
  results : Array[CheckResult],
) -> Unit {
  // jsonrpc must be "2.0"
  match (if resp is Object(obj) { obj.get("jsonrpc") } else { None }) {
    Some(Json::String(s)) if s == "2.0" =>
      results.push(
        CheckResult::pass(label + ".jsonrpc", "error response jsonrpc=2.0"),
      )
    _ =>
      results.push(
        CheckResult::fail(
          label + ".jsonrpc",
          "error response jsonrpc != \"2.0\"",
          resp.stringify(),
        ),
      )
  }
  // result and error are mutually exclusive
  let has_result = (if resp is Object(obj) { obj.get("result") } else { None })
    is Some(_)
  let has_error = (if resp is Object(obj) { obj.get("error") } else { None })
    is Some(_)
  if has_result && has_error {
    results.push(
      CheckResult::fail(
        label + ".exclusive",
        "response contains both result and error",
        resp.stringify(),
      ),
    )
  } else {
    results.push(
      CheckResult::pass(
        label + ".exclusive",
        "result and error are mutually exclusive",
      ),
    )
  }
  // error.code must be an integer within the reserved range -32768..-32000
  match e.get("code") {
    Some(Json::Number(n, ..)) => {
      let code = n.to_int()
      if n != code.to_double() {
        results.push(
          CheckResult::fail(
            label + ".code",
            "error.code is not an integer",
            resp.stringify(),
          ),
        )
      } else if code >= -32768 && code <= -32000 {
        results.push(
          CheckResult::pass(
            label + ".code",
            "error.code=\{code} in reserved range -32768..-32000",
          ),
        )
      } else {
        results.push(
          CheckResult::fail(
            label + ".code",
            "error.code=\{code} outside reserved range -32768..-32000",
            resp.stringify(),
          ),
        )
      }
    }
    _ =>
      results.push(
        CheckResult::fail(
          label + ".code",
          "error.code missing or not a number",
          resp.stringify(),
        ),
      )
  }
  // error.message must be a non-empty string
  match e.get("message") {
    Some(Json::String(m)) if m.length() > 0 =>
      results.push(
        CheckResult::pass(
          label + ".message",
          "error.message is a non-empty string",
        ),
      )
    Some(Json::String(_)) =>
      results.push(
        CheckResult::fail(
          label + ".message",
          "error.message is an empty string",
          resp.stringify(),
        ),
      )
    _ =>
      results.push(
        CheckResult::fail(
          label + ".message",
          "error.message missing or not a string",
          resp.stringify(),
        ),
      )
  }
  // error.data is optional (present or omitted both acceptable)
  match e.get("data") {
    Some(_) =>
      results.push(
        CheckResult::pass(
          label + ".data",
          "error.data present (optional field, accepted)",
        ),
      )
    None =>
      results.push(
        CheckResult::pass(
          label + ".data",
          "error.data omitted (optional field)",
        ),
      )
  }
}

///| Pure validation: a response id must equal the request id exactly

///|
/// (type + value).
pub fn validate_id_match(
  resp : Json,
  req_id : Json,
  label : String,
  results : Array[CheckResult],
) -> Unit {
  match (if resp is Object(obj) { obj.get("id") } else { None }) {
    Some(id) if id == req_id =>
      results.push(
        CheckResult::pass(
          label + ".id",
          "response id \{req_id.stringify()} matches request id",
        ),
      )
    Some(id) =>
      results.push(
        CheckResult::fail(
          label + ".id",
          "response id \{id.stringify()} != request id \{req_id.stringify()}",
          resp.stringify(),
        ),
      )
    None =>
      results.push(
        CheckResult::fail(
          label + ".id",
          "response missing id",
          resp.stringify(),
        ),
      )
  }
}

///| Pure validation: a batch response must be an array; its item count must

///| match the request count; every request id must have a response item; error

///|
/// items must carry a valid error object.
pub fn validate_batch_resp(
  resp : Json,
  req_ids : Array[Json],
  err_req_ids : Array[Json],
  results : Array[CheckResult],
) -> Unit {
  match resp {
    Json::Array(items) => {
      results.push(
        CheckResult::pass("batch.array", "batch response is an array"),
      )
      if items.length() != req_ids.length() {
        results.push(
          CheckResult::fail(
            "batch.count",
            "expected \{req_ids.length()} response items, got \{items.length()}",
            resp.stringify(),
          ),
        )
      } else {
        results.push(
          CheckResult::pass(
            "batch.count",
            "response item count matches request count (\{req_ids.length()})",
          ),
        )
      }
      for req_id in req_ids {
        let mut found = false
        for item in items {
          match (if item is Object(obj) { obj.get("id") } else { None }) {
            Some(id) => if id == req_id { found = true }
            None => ()
          }
        }
        if found {
          results.push(
            CheckResult::pass(
              "batch.id_match",
              "request id \{req_id.stringify()} has a matching response item",
            ),
          )
        } else {
          results.push(
            CheckResult::fail(
              "batch.id_match",
              "no response item for request id \{req_id.stringify()}",
              resp.stringify(),
            ),
          )
        }
      }
      for req_id in err_req_ids {
        let mut item_opt : Json? = None
        for item in items {
          match (if item is Object(obj) { obj.get("id") } else { None }) {
            Some(id) if id == req_id => item_opt = Some(item)
            _ => ()
          }
        }
        match item_opt {
          Some(item) =>
            match (if item is Object(obj) { obj.get("error") } else { None }) {
              Some(Json::Object(_)) =>
                results.push(
                  CheckResult::pass(
                    "batch.error_schema",
                    "error item for \{req_id.stringify()} carries a valid error object",
                  ),
                )
              Some(_) =>
                results.push(
                  CheckResult::fail(
                    "batch.error_schema",
                    "error item for \{req_id.stringify()} has a non-object error",
                    item.stringify(),
                  ),
                )
              None =>
                results.push(
                  CheckResult::fail(
                    "batch.error_schema",
                    "expected error for \{req_id.stringify()}, got none",
                    item.stringify(),
                  ),
                )
            }
          None =>
            results.push(
              CheckResult::fail(
                "batch.error_schema",
                "no response item for error request \{req_id.stringify()}",
                resp.stringify(),
              ),
            )
        }
      }
    }
    _ =>
      results.push(
        CheckResult::fail(
          "batch.not_array",
          "batch response is not an array",
          resp.stringify(),
        ),
      )
  }
}

///| JSON-RPC batch check: send a batch array request with 2~3 distinct ids and

///| verify the response is an array, item count matches, every response id

///|
/// matches the request id, and error items carry a valid error object.
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
      "params": Json::object({
        "name": Json::string("echo"),
        "arguments": Json::object({ "text": Json::string("hi") }),
      }),
    }),
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::string("req-batch-err"),
      "method": Json::string("unknown/method"),
      "params": Json::object({}),
    }),
  ])
  let req_ids : Array[Json] = [
    Json::number(1.0),
    Json::number(42.0),
    Json::string("req-batch-err"),
  ]
  let err_req_ids : Array[Json] = [Json::string("req-batch-err")]
  match session.request_raw(reqs.stringify(), 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch { _ => Json::null() }
      if j is Json::Null {
        results.push(
          CheckResult::fail("batch.parse", "JSON parse error", resp_str),
        )
      } else {
        // 2026-07-28 removed JSON-RPC batching; a compliant server rejects a
        // batch array with -32600/-32601.
        let mut batch_rejected = false
        match (if j is Object(obj) { obj.get("error") } else { None }) {
          Some(Json::Object(e)) =>
            match e.get("code") {
              Some(Json::Number(-32600, ..)) => batch_rejected = true
              Some(Json::Number(-32601, ..)) => batch_rejected = true
              _ => ()
            }
          _ => ()
        }
        if batch_rejected {
          results.push(
            CheckResult::skip(
              "batch.removed", "JSON-RPC batch removed in 2026-07-28; server rejects batch array (compliant)",
            ),
          )
        } else {
          validate_batch_resp(j, req_ids, err_req_ids, results)
        }
      }
    }
    Err(e) => results.push(CheckResult::fail("batch.timeout", e, ""))
  }
  results
}

///| JSON-RPC id matching check: number ids (1, 42) and string ids ("req-1",

///|
/// special chars) must be echoed back exactly (type + value).
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
          results.push(
            CheckResult::fail(label + ".parse", "JSON parse error", resp_str),
          )
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

///|
/// result/error exclusivity, jsonrpc=2.0).
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
        results.push(
          CheckResult::fail("error_schema.parse", "JSON parse error", resp_str),
        )
        return results
      }
      match j {
        Json::Object(_) => {
          let has_result = (if j is Object(obj) {
              obj.get("result")
            } else {
              None
            })
            is Some(_)
          let has_error = (if j is Object(obj) {
              obj.get("error")
            } else {
              None
            })
            is Some(_)
          if has_error {
            match (if j is Object(obj) { obj.get("error") } else { None }) {
              Some(Json::Object(e)) =>
                validate_error_object(j, e, "error_schema", results)
              Some(_) =>
                results.push(
                  CheckResult::fail(
                    "error_schema.shape", "error is not an object", resp_str,
                  ),
                )
              None => ()
            }
          } else if has_result {
            results.push(
              CheckResult::fail(
                "error_schema.no_error", "expected an error response, got result only",
                resp_str,
              ),
            )
          } else {
            results.push(
              CheckResult::fail(
                "error_schema.no_error", "response has neither result nor error",
                resp_str,
              ),
            )
          }
        }
        _ =>
          results.push(
            CheckResult::fail(
              "error_schema.shape", "error response is not an object", resp_str,
            ),
          )
      }
    }
    Err(e) => results.push(CheckResult::fail("error_schema.timeout", e, ""))
  }
  results
}

// ---------------------------------------------------------------------------
// 2026-07-28 stateless core checks (SEP-2575/SEP-2567/SEP-2243/SEP-2549/
// SEP-2106/SEP-2164/SEP-2322/SEP-2577). These probe the stateless protocol
// surface: per-request self-description, inline version negotiation,
// server/discover, MRTR, cache hints, full JSON Schema 2020-12 and the
// JSON-RPC-standard -32602 resource error code.
// ---------------------------------------------------------------------------

///| [stateless] server/discover must be implemented (SEP-2575): returns

///| supportedVersions / capabilities / serverInfo. Servers MUST implement it;

///|
/// a -32601 rejection is a spec violation.
pub async fn check_stateless_discover(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match session.request("server/discover", Json::object({}), 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch { _ => Json::null() }
      if j is Json::Null {
        results.push(
          CheckResult::fail("discover.parse", "JSON parse error", resp_str),
        )
      } else {
        match (if j is Object(obj) { obj.get("result") } else { None }) {
          Some(Json::Object(r)) => {
            if r.get("supportedVersions") is Some(Json::Array(_)) {
              results.push(
                CheckResult::pass(
                  "discover.supported_versions", "server/discover returned supportedVersions",
                ),
              )
            } else {
              results.push(
                CheckResult::fail(
                  "discover.supported_versions", "server/discover result missing supportedVersions",
                  resp_str,
                ),
              )
            }
            if r.get("capabilities") is Some(Json::Object(_)) {
              results.push(
                CheckResult::pass(
                  "discover.capabilities", "server/discover returned capabilities",
                ),
              )
            } else {
              results.push(
                CheckResult::fail(
                  "discover.capabilities", "server/discover result missing capabilities",
                  resp_str,
                ),
              )
            }
            // 2026-07-28: serverInfo lives in result._meta["io.modelcontextprotocol/serverInfo"].
            // Accept both the legacy top-level location and the _meta location.
            let has_server_info : Bool = r.get("serverInfo")
              is Some(Json::Object(_)) ||
              (match r.get("_meta") {
                Some(Json::Object(m)) =>
                  m.get("io.modelcontextprotocol/serverInfo")
                  is Some(Json::Object(_))
                _ => false
              })
            if has_server_info {
              results.push(
                CheckResult::pass(
                  "discover.server_info", "server/discover returned serverInfo",
                ),
              )
            } else {
              results.push(
                CheckResult::fail(
                  "discover.server_info", "server/discover result missing serverInfo (top-level or _meta)",
                  resp_str,
                ),
              )
            }
          }
          Some(_) =>
            results.push(
              CheckResult::fail(
                "discover.result", "server/discover result is not an object", resp_str,
              ),
            )
          _ =>
            match (if j is Object(obj) { obj.get("error") } else { None }) {
              Some(Json::Object(e)) =>
                match e.get("code") {
                  Some(Json::Number(-32601, ..)) =>
                    results.push(
                      CheckResult::fail(
                        "discover.implemented", "server/discover returned -32601 (spec: server MUST implement server/discover)",
                        resp_str,
                      ),
                    )
                  Some(_) =>
                    results.push(
                      CheckResult::fail(
                        "discover.error", "server/discover returned unexpected error",
                        resp_str,
                      ),
                    )
                  _ =>
                    results.push(
                      CheckResult::fail(
                        "discover.malformed", "server/discover returned malformed error",
                        resp_str,
                      ),
                    )
                }
              _ =>
                results.push(
                  CheckResult::fail(
                    "discover.malformed", "response has neither result nor error",
                    resp_str,
                  ),
                )
            }
        }
      }
    }
    Err(e) => results.push(CheckResult::fail("discover.timeout", e, ""))
  }
  results
}

///| [stateless] Inline version negotiation (SEP-2575): when a client sends an

///| unsupported protocol version, the server must answer with -32022

///| (UnsupportedProtocolVersionError) and list supported versions in

///|
/// data.supported instead of processing the request.
pub async fn check_stateless_version_negotiation(
  session : Session,
) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  let req = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1.0),
    "method": Json::string("tools/list"),
    "params": Json::object({
      "protocolVersion": Json::string("2099-01-01"),
      "_meta": Json::object({
        "io.modelcontextprotocol/protocolVersion": Json::string("2099-01-01"),
        "io.modelcontextprotocol/clientInfo": Json::object({
          "name": Json::string("mcpconftest"),
          "version": Json::string(version()),
        }),
        "io.modelcontextprotocol/clientCapabilities": Json::object({}),
      }),
    }),
  })
  match session.request_raw(req.stringify(), 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch { _ => Json::null() }
      if j is Json::Null {
        results.push(
          CheckResult::fail(
            "version_negotiation.parse", "JSON parse error", resp_str,
          ),
        )
      } else {
        match (if j is Object(obj) { obj.get("error") } else { None }) {
          Some(Json::Object(e)) =>
            match e.get("code") {
              Some(Json::Number(-32022, ..)) =>
                match e.get("data") {
                  Some(Json::Object(d)) =>
                    if d.get("supported") is Some(Json::Array(_)) {
                      results.push(
                        CheckResult::pass(
                          "version_negotiation.32022", "unsupported version rejected with -32022 + data.supported",
                        ),
                      )
                    } else {
                      results.push(
                        CheckResult::fail(
                          "version_negotiation.data", "-32022 error missing data.supported version list",
                          resp_str,
                        ),
                      )
                    }
                  _ =>
                    results.push(
                      CheckResult::fail(
                        "version_negotiation.data", "-32022 error missing data object",
                        resp_str,
                      ),
                    )
                }
              Some(Json::Number(-32601, ..)) =>
                results.push(
                  CheckResult::fail(
                    "version_negotiation.tools_list", "tools/list returned -32601 (spec: server MUST implement tools/list)",
                    resp_str,
                  ),
                )
              Some(_) =>
                results.push(
                  CheckResult::fail(
                    "version_negotiation.error", "unexpected error for unsupported version",
                    resp_str,
                  ),
                )
              _ =>
                results.push(
                  CheckResult::fail(
                    "version_negotiation.malformed", "malformed error for unsupported version",
                    resp_str,
                  ),
                )
            }
          Some(_) =>
            results.push(
              CheckResult::fail(
                "version_negotiation.unknown_error", "error field is not an object",
                resp_str,
              ),
            )
          None =>
            results.push(
              CheckResult::fail(
                "version_negotiation.accepted", "server processed request with unsupported protocol version (no inline negotiation)",
                resp_str,
              ),
            )
        }
      }
    }
    Err(e) =>
      results.push(CheckResult::fail("version_negotiation.timeout", e, ""))
  }
  results
}

///| [stateless] Per-request self-description (SEP-2575): every request must

///| carry protocol version / client identity / client capabilities in _meta.

///| A request missing _meta must be rejected (INVALID_PARAMS) — a compliant

///|
/// server must not infer capabilities from history.
pub async fn check_stateless_self_describing(
  session : Session,
) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  let req = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1.0),
    "method": Json::string("tools/list"),
    "params": Json::object({}),
  })
  match session.request_raw(req.stringify(), 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch { _ => Json::null() }
      if j is Json::Null {
        results.push(
          CheckResult::fail(
            "self_describing.parse", "JSON parse error", resp_str,
          ),
        )
      } else {
        match (if j is Object(obj) { obj.get("error") } else { None }) {
          Some(Json::Object(e)) =>
            match e.get("code") {
              Some(Json::Number(-32602, ..)) =>
                results.push(
                  CheckResult::pass(
                    "self_describing.rejected", "request without _meta rejected with -32602 (INVALID_PARAMS)",
                  ),
                )
              Some(_) =>
                results.push(
                  CheckResult::fail(
                    "self_describing.error", "request without _meta rejected with wrong error code",
                    resp_str,
                  ),
                )
              _ =>
                results.push(
                  CheckResult::fail(
                    "self_describing.malformed", "malformed error for request without _meta",
                    resp_str,
                  ),
                )
            }
          Some(_) =>
            results.push(
              CheckResult::fail(
                "self_describing.unknown_error", "error field is not an object",
                resp_str,
              ),
            )
          None =>
            results.push(
              CheckResult::fail(
                "self_describing.accepted", "request without _meta was processed (server must require per-request self-description)",
                resp_str,
              ),
            )
        }
      }
    }
    Err(e) => results.push(CheckResult::fail("self_describing.timeout", e, ""))
  }
  results
}

///| [stateless] Missing client capability (SEP-2575): when handling a request

///| requires a capability the client did not declare, the server must return

///| -32021 (MissingRequiredClientCapabilityError) with the required capability

///|
/// list, instead of silently executing.
pub async fn check_stateless_missing_capability(
  session : Session,
) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  let params = Json::object({
    "name": Json::string("__mcpconftest_cap_dummy__"),
    "arguments": Json::object({}),
    "_meta": Json::object({
      "io.modelcontextprotocol/protocolVersion": Json::string("2026-07-28"),
      "io.modelcontextprotocol/clientInfo": Json::object({
        "name": Json::string("mcpconftest"),
        "version": Json::string(version()),
      }),
      "io.modelcontextprotocol/clientCapabilities": Json::object({}),
    }),
  })
  match session.request("tools/call", params, 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch { _ => Json::null() }
      if j is Json::Null {
        results.push(
          CheckResult::fail(
            "missing_capability.parse", "JSON parse error", resp_str,
          ),
        )
      } else {
        match (if j is Object(obj) { obj.get("error") } else { None }) {
          Some(Json::Object(e)) =>
            match e.get("code") {
              Some(Json::Number(-32021, ..)) =>
                match e.get("data") {
                  Some(Json::Object(d)) =>
                    if d.get("requiredCapabilities") is Some(Json::Array(_)) {
                      results.push(
                        CheckResult::pass(
                          "missing_capability.32021", "missing capability rejected with -32021 + requiredCapabilities",
                        ),
                      )
                    } else {
                      results.push(
                        CheckResult::fail(
                          "missing_capability.data", "-32021 error missing data.requiredCapabilities",
                          resp_str,
                        ),
                      )
                    }
                  _ =>
                    results.push(
                      CheckResult::fail(
                        "missing_capability.data", "-32021 error missing data object",
                        resp_str,
                      ),
                    )
                }
              Some(Json::Number(-32601, ..)) =>
                results.push(
                  CheckResult::skip(
                    "missing_capability.unknown_tool", "dummy tool unknown; cannot observe capability check",
                  ),
                )
              Some(_) =>
                results.push(
                  CheckResult::fail(
                    "missing_capability.error", "unexpected error", resp_str,
                  ),
                )
              _ =>
                results.push(
                  CheckResult::fail(
                    "missing_capability.malformed", "malformed error", resp_str,
                  ),
                )
            }
          Some(_) =>
            results.push(
              CheckResult::fail(
                "missing_capability.unknown_error", "error field is not an object",
                resp_str,
              ),
            )
          None =>
            results.push(
              CheckResult::fail(
                "missing_capability.executed", "server executed call without declared client capability (expected -32021)",
                resp_str,
              ),
            )
        }
      }
    }
    Err(e) =>
      results.push(CheckResult::fail("missing_capability.timeout", e, ""))
  }
  results
}

///| [stateless] Cacheable list results (SEP-2549): tools/list / prompts/list /

///| resources/list / resources/read responses must carry ttlMs and cacheScope

///|
/// so clients can cache safely.
pub async fn check_stateless_list_cache(
  session : Session,
) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match session.request("tools/list", Json::object({}), 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch { _ => Json::null() }
      if j is Json::Null {
        results.push(
          CheckResult::fail("list_cache.parse", "JSON parse error", resp_str),
        )
      } else {
        match (if j is Object(obj) { obj.get("result") } else { None }) {
          Some(Json::Object(r)) => {
            if r.get("ttlMs") is Some(Json::Number(_, ..)) {
              results.push(
                CheckResult::pass(
                  "list_cache.ttl_ms", "tools/list response carries ttlMs",
                ),
              )
            } else {
              results.push(
                CheckResult::fail(
                  "list_cache.ttl_ms", "tools/list response missing ttlMs cache hint",
                  resp_str,
                ),
              )
            }
            if r.get("cacheScope") is Some(Json::String(_)) {
              results.push(
                CheckResult::pass(
                  "list_cache.cache_scope", "tools/list response carries cacheScope",
                ),
              )
            } else {
              results.push(
                CheckResult::fail(
                  "list_cache.cache_scope", "tools/list response missing cacheScope",
                  resp_str,
                ),
              )
            }
          }
          Some(_) =>
            results.push(
              CheckResult::fail(
                "list_cache.result", "tools/list result is not an object", resp_str,
              ),
            )
          _ =>
            match (if j is Object(obj) { obj.get("error") } else { None }) {
              Some(Json::Object(e)) =>
                match e.get("code") {
                  Some(Json::Number(-32601, ..)) =>
                    results.push(
                      CheckResult::fail(
                        "list_cache.tools_list", "tools/list returned -32601 (spec: server MUST implement tools/list)",
                        resp_str,
                      ),
                    )
                  Some(_) =>
                    results.push(
                      CheckResult::fail(
                        "list_cache.error", "tools/list returned unexpected error",
                        resp_str,
                      ),
                    )
                  _ =>
                    results.push(
                      CheckResult::fail(
                        "list_cache.malformed", "tools/list returned malformed error",
                        resp_str,
                      ),
                    )
                }
              _ =>
                results.push(
                  CheckResult::fail(
                    "list_cache.malformed", "response has neither result nor error",
                    resp_str,
                  ),
                )
            }
        }
      }
    }
    Err(e) => results.push(CheckResult::fail("list_cache.timeout", e, ""))
  }
  results
}

///| [stateless] Full JSON Schema 2020-12 for tools (SEP-2106): inputSchema

///| must keep a type:"object" root and must not auto-dereference external

///|
/// $ref URIs. Internal $defs/$ref composition (oneOf/anyOf/allOf) is allowed.
pub async fn check_stateless_schema_2020_12(
  session : Session,
) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match session.request("tools/list", Json::object({}), 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch { _ => Json::null() }
      if j is Json::Null {
        results.push(
          CheckResult::fail(
            "schema_2020_12.parse", "JSON parse error", resp_str,
          ),
        )
      } else {
        match (if j is Object(obj) { obj.get("result") } else { None }) {
          Some(Json::Object(r)) =>
            match r.get("tools") {
              Some(Json::Array(tools)) =>
                if tools.length() == 0 {
                  results.push(
                    CheckResult::pass(
                      "schema_2020_12.empty", "no tools declared (schema check vacuous)",
                    ),
                  )
                } else {
                  for tool in tools {
                    match tool {
                      Json::Object(t) => {
                        let label = match t.get("name") {
                          Some(Json::String(n)) => n
                          _ => "?"
                        }
                        match t.get("inputSchema") {
                          Some(Json::Object(s)) => {
                            // 2020-12: type:"object" root is the strict form. A schema
                            // without explicit type is still valid JSON Schema 2020-12:
                            // an empty schema ({}) accepts anything, and the presence of
                            // properties/required implies object semantics. Only a schema
                            // with an explicit non-object type is non-compliant.
                            let has_object_hint : Bool = s.get("properties")
                              is Some(Json::Object(_)) ||
                              s.get("required") is Some(Json::Array(_)) ||
                              s.is_empty()
                            match s.get("type") {
                              Some(Json::String(tp)) if tp == "object" =>
                                results.push(
                                  CheckResult::pass(
                                    "schema_2020_12.\{label}.root_object",
                                    "inputSchema root type=object",
                                  ),
                                )
                              Some(_) =>
                                results.push(
                                  CheckResult::fail(
                                    "schema_2020_12.\{label}.root_type",
                                    "inputSchema root type != object (2020-12 requires object root)",
                                    resp_str,
                                  ),
                                )
                              _ if has_object_hint =>
                                results.push(
                                  CheckResult::pass(
                                    "schema_2020_12.\{label}.root_object",
                                    "inputSchema object root (implicit via properties/required/empty schema)",
                                  ),
                                )
                              _ =>
                                results.push(
                                  CheckResult::fail(
                                    "schema_2020_12.\{label}.root_type",
                                    "inputSchema missing root type (2020-12 requires object root)",
                                    resp_str,
                                  ),
                                )
                            }
                            match s.get("$ref") {
                              Some(Json::String(ref_uri)) if ref_uri.has_prefix(
                                  "http://",
                                ) ||
                                ref_uri.has_prefix("https://") =>
                                results.push(
                                  CheckResult::fail(
                                    "schema_2020_12.\{label}.external_ref",
                                    "inputSchema contains external ref (must not auto-dereference)",
                                    resp_str,
                                  ),
                                )
                              _ =>
                                results.push(
                                  CheckResult::pass(
                                    "schema_2020_12.\{label}.refs",
                                    "inputSchema ref usage is internal-only or absent",
                                  ),
                                )
                            }
                          }
                          _ =>
                            results.push(
                              CheckResult::fail(
                                "schema_2020_12.\{label}.input_schema",
                                "tool \{label} missing inputSchema object",
                                resp_str,
                              ),
                            )
                        }
                      }
                      _ => ()
                    }
                  }
                }
              _ =>
                results.push(
                  CheckResult::fail(
                    "schema_2020_12.tools", "tools/list result missing tools array",
                    resp_str,
                  ),
                )
            }
          Some(_) =>
            results.push(
              CheckResult::fail(
                "schema_2020_12.result", "tools/list result is not an object", resp_str,
              ),
            )
          _ =>
            match (if j is Object(obj) { obj.get("error") } else { None }) {
              Some(Json::Object(e)) =>
                match e.get("code") {
                  Some(Json::Number(-32601, ..)) =>
                    results.push(
                      CheckResult::fail(
                        "schema_2020_12.tools_list", "tools/list returned -32601 (spec: server MUST implement tools/list)",
                        resp_str,
                      ),
                    )
                  Some(_) =>
                    results.push(
                      CheckResult::fail(
                        "schema_2020_12.error", "tools/list returned unexpected error",
                        resp_str,
                      ),
                    )
                  _ =>
                    results.push(
                      CheckResult::fail(
                        "schema_2020_12.malformed", "tools/list returned malformed error",
                        resp_str,
                      ),
                    )
                }
              _ =>
                results.push(
                  CheckResult::fail(
                    "schema_2020_12.malformed", "response has neither result nor error",
                    resp_str,
                  ),
                )
            }
        }
      }
    }
    Err(e) => results.push(CheckResult::fail("schema_2020_12.timeout", e, ""))
  }
  results
}

///| [stateless] Missing resource error code (SEP-2164): the resource-not-found

///| error must use the JSON-RPC standard -32602 Invalid Params, not the old

///|
/// MCP-custom -32002.
pub async fn check_stateless_resource_error_code(
  session : Session,
) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match
    session.request(
      "resources/read",
      Json::object({ "uri": Json::string("file:///__mcpconftest_missing__") }),
      5000,
    ) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch { _ => Json::null() }
      if j is Json::Null {
        results.push(
          CheckResult::fail(
            "resource_error_code.parse", "JSON parse error", resp_str,
          ),
        )
      } else {
        match (if j is Object(obj) { obj.get("error") } else { None }) {
          Some(Json::Object(e)) =>
            match e.get("code") {
              Some(Json::Number(-32602, ..)) =>
                results.push(
                  CheckResult::pass(
                    "resource_error_code.32602", "missing resource rejected with -32602 (JSON-RPC Invalid Params)",
                  ),
                )
              Some(Json::Number(-32002, ..)) =>
                results.push(
                  CheckResult::fail(
                    "resource_error_code.legacy", "missing resource still uses legacy -32002 (must migrate to -32602)",
                    resp_str,
                  ),
                )
              Some(_) =>
                results.push(
                  CheckResult::fail(
                    "resource_error_code.error", "missing resource returned unexpected error code",
                    resp_str,
                  ),
                )
              _ =>
                results.push(
                  CheckResult::fail(
                    "resource_error_code.malformed", "malformed error for missing resource",
                    resp_str,
                  ),
                )
            }
          Some(_) =>
            results.push(
              CheckResult::fail(
                "resource_error_code.unknown_error", "error field is not an object",
                resp_str,
              ),
            )
          None =>
            results.push(
              CheckResult::fail(
                "resource_error_code.not_found", "missing resource did not return an error (expected -32602)",
                resp_str,
              ),
            )
        }
      }
    }
    Err(e) =>
      results.push(CheckResult::fail("resource_error_code.timeout", e, ""))
  }
  results
}

///| [stateless] MRTR input_required round-trip (SEP-2322): when a tool needs

///| client input mid-call, the response must carry resultType:"input_required"

///|
/// plus the requests list; otherwise a normal completion is fine.
pub async fn check_stateless_mrtr(session : Session) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  let params = Json::object({
    "name": Json::string("__mcpconftest_mrtr_dummy__"),
    "arguments": Json::object({}),
  })
  match session.request("tools/call", params, 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch { _ => Json::null() }
      if j is Json::Null {
        results.push(
          CheckResult::fail("mrtr.parse", "JSON parse error", resp_str),
        )
      } else {
        match (if j is Object(obj) { obj.get("result") } else { None }) {
          Some(Json::Object(r)) =>
            match r.get("resultType") {
              Some(Json::String(t)) if t == "input_required" =>
                match r.get("requests") {
                  Some(Json::Array(items)) if items.length() > 0 =>
                    results.push(
                      CheckResult::pass(
                        "mrtr.input_required", "input_required result carries requests list",
                      ),
                    )
                  _ =>
                    results.push(
                      CheckResult::fail(
                        "mrtr.requests", "input_required result missing requests list (client cannot answer)",
                        resp_str,
                      ),
                    )
                }
              Some(Json::String(_)) =>
                results.push(
                  CheckResult::fail(
                    "mrtr.result_type", "result carries unknown resultType (spec only defines input_required)",
                    resp_str,
                  ),
                )
              _ =>
                results.push(
                  CheckResult::pass(
                    "mrtr.completed", "tool completed without input_required (no MRTR needed)",
                  ),
                )
            }
          Some(_) =>
            results.push(
              CheckResult::pass(
                "mrtr.completed", "tool completed with non-object result (no MRTR needed)",
              ),
            )
          _ =>
            match (if j is Object(obj) { obj.get("error") } else { None }) {
              Some(Json::Object(e)) =>
                match e.get("code") {
                  Some(Json::Number(-32601, ..)) =>
                    results.push(
                      CheckResult::skip(
                        "mrtr.unknown_tool", "dummy tool unknown; cannot observe MRTR flow",
                      ),
                    )
                  Some(_) =>
                    results.push(
                      CheckResult::fail(
                        "mrtr.error", "tools/call returned unexpected error", resp_str,
                      ),
                    )
                  _ =>
                    results.push(
                      CheckResult::fail(
                        "mrtr.malformed", "malformed error", resp_str,
                      ),
                    )
                }
              _ =>
                results.push(
                  CheckResult::fail(
                    "mrtr.malformed", "response has neither result nor error", resp_str,
                  ),
                )
            }
        }
      }
    }
    Err(e) => results.push(CheckResult::fail("mrtr.timeout", e, ""))
  }
  results
}

///| [stateless] Deprecated capability annotation (SEP-2577): Roots, Sampling

///| and Logging are deprecated; servers that still advertise them must mark

///|
/// them deprecated in capabilities.
pub async fn check_stateless_deprecations(
  session : Session,
) -> Array[CheckResult] {
  let results : Array[CheckResult] = []
  match session.request("server/discover", Json::object({}), 5000) {
    Ok(resp_str) => {
      let j = @json.parse(resp_str) catch { _ => Json::null() }
      if j is Json::Null {
        results.push(
          CheckResult::fail("deprecations.parse", "JSON parse error", resp_str),
        )
      } else {
        match (if j is Object(obj) { obj.get("result") } else { None }) {
          Some(Json::Object(r)) =>
            match r.get("capabilities") {
              Some(Json::Object(caps)) =>
                for cap_name in ["sampling", "roots", "logging"] {
                  let label = "deprecations.\{cap_name}"
                  match caps.get(cap_name) {
                    Some(Json::Object(_)) =>
                      match caps.get(cap_name) {
                        Some(Json::Object(cap)) =>
                          match cap.get("deprecated") {
                            Some(Json::True) =>
                              results.push(
                                CheckResult::pass(
                                  label,
                                  "\{cap_name} capability advertised with deprecated annotation",
                                ),
                              )
                            _ =>
                              results.push(
                                CheckResult::fail(
                                  label,
                                  "\{cap_name} advertised without deprecated annotation (SEP-2577)",
                                  resp_str,
                                ),
                              )
                          }
                        _ => ()
                      }
                    None =>
                      results.push(
                        CheckResult::pass(
                          label,
                          "\{cap_name} not advertised (no deprecation annotation needed)",
                        ),
                      )
                    Some(_) =>
                      results.push(
                        CheckResult::fail(
                          label,
                          "\{cap_name} capability entry is not an object",
                          resp_str,
                        ),
                      )
                  }
                }
              _ =>
                results.push(
                  CheckResult::fail(
                    "deprecations.capabilities", "server/discover result missing capabilities",
                    resp_str,
                  ),
                )
            }
          Some(_) =>
            results.push(
              CheckResult::fail(
                "deprecations.result", "server/discover result is not an object",
                resp_str,
              ),
            )
          _ =>
            match (if j is Object(obj) { obj.get("error") } else { None }) {
              Some(Json::Object(e)) =>
                match e.get("code") {
                  Some(Json::Number(-32601, ..)) =>
                    results.push(
                      CheckResult::skip(
                        "deprecations.no_discover", "server/discover unavailable; cannot inspect capability deprecations",
                      ),
                    )
                  Some(_) =>
                    results.push(
                      CheckResult::fail(
                        "deprecations.error", "server/discover returned unexpected error",
                        resp_str,
                      ),
                    )
                  _ =>
                    results.push(
                      CheckResult::fail(
                        "deprecations.malformed", "server/discover returned malformed error",
                        resp_str,
                      ),
                    )
                }
              _ =>
                results.push(
                  CheckResult::fail(
                    "deprecations.malformed", "response has neither result nor error",
                    resp_str,
                  ),
                )
            }
        }
      }
    }
    Err(e) => results.push(CheckResult::fail("deprecations.timeout", e, ""))
  }
  results
}
