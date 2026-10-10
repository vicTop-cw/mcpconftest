///| JSON-RPC session driver — supports stdio and WebSocket transports on both
///| the js and native backends. All low-level I/O goes through the `io_*`
///| abstraction (session_io_js.mbt / session_io_native.mbt), so the driver
///| itself is fully platform-agnostic.
///
/// stdio: spawn child process, speak JSON-RPC over stdin/stdout.
/// WebSocket: connect to ws:// or wss:// URL, speak JSON-RPC over messages.

///| Transport kind.
pub(all) enum Transport {
  Stdio
  WebSocket
}

///| A running session (stdio or WebSocket).
pub(all) struct Session {
  mut next_id : Int
  mut alive : Bool
  mut handle_id : Int
  mut transport : Transport
}

///| Spawn a new stdio session with the given command (e.g. "node server.js").
pub async fn Session::new(cmd : String) -> Session {
  let parts = cmd.split(" ")
  let argv : Array[String] = []
  for p in parts {
    argv.push(p.to_string())
  }
  let handle_id = io_spawn(argv, ".") catch { _ => -1 }
  { next_id: 1, alive: handle_id >= 0, handle_id, transport: Stdio }
}

///| Connect to a WebSocket MCP server.
pub async fn Session::new_ws(url : String) -> Session {
  let handle_id = io_ws_connect(url) catch { _ => -1 }
  { next_id: 1, alive: handle_id >= 0, handle_id, transport: WebSocket }
}

///| Send a JSON-RPC request, wait for response with timeout.
pub async fn Session::request(
  self : Session,
  meth : String,
  params : Json,
  timeout_ms : Int,
) -> Result[String, String] {
  let id = self.next_id
  self.next_id += 1
  let req_str = match self.transport {
    Stdio => {
      (match params {
        Json::Object(m) => {
          let m2 = m.copy()
          if m2.get("_meta") is Some(_) {
            ()
          } else {
            m2.set("_meta", Json::object({ "io.modelcontextprotocol/protocolVersion": Json::string("2026-07-28") }))
          }
          Json::object({
            "jsonrpc": Json::string("2.0"),
            "id": Json::number(id.to_double()),
            "method": Json::string(meth),
            "params": Json::object(m2),
          }).stringify()
        }
        _ => Json::object({
          "jsonrpc": Json::string("2.0"),
          "id": Json::number(id.to_double()),
          "method": Json::string(meth),
          "params": Json::object({
            "_meta": Json::object({ "io.modelcontextprotocol/protocolVersion": Json::string("2026-07-28") }),
          }),
        }).stringify()
      }) + "\n"
    }
    WebSocket => {
      Json::object({
        "jsonrpc": Json::string("2.0"),
        "id": Json::number(id.to_double()),
        "method": Json::string(meth),
        "params": params,
      }).stringify()
    }
  }
  match self.transport {
    Stdio => {
      ignore(io_write(self.handle_id, req_str) catch {
        _ => -1
      })
      let line = io_read_line(self.handle_id, timeout_ms) catch {
        _ => return Err("read failed")
      }
      if line == "__MCP_TIMEOUT__" {
        Err("timeout after \{timeout_ms}ms")
      } else if line == "__MCP_ERROR__" {
        Err("read error (session invalid)")
      } else {
        Ok(line)
      }
    }
    WebSocket => {
      ignore(io_ws_write(self.handle_id, req_str) catch {
        _ => return Err("write failed")
      })
      let resp = io_ws_read(self.handle_id, timeout_ms) catch {
        _ => return Err("read failed")
      }
      if resp == "__MCP_TIMEOUT__" {
        Err("timeout after \{timeout_ms}ms")
      } else if resp == "__MCP_ERROR__" {
        Err("read error (session invalid)")
      } else {
        Ok(resp)
      }
    }
  }
}

///| Send a raw JSON-RPC message (single object or batch array) and read one
///| response line. Used by checks that need explicit control over id values
///| (id-matching, batch) which the auto-incrementing `request` cannot provide.
pub async fn Session::request_raw(
  self : Session,
  raw : String,
  timeout_ms : Int,
) -> Result[String, String] {
  match self.transport {
    Stdio => {
      ignore(io_write(self.handle_id, raw + "\n") catch { _ => -1 })
      let line = io_read_line(self.handle_id, timeout_ms) catch {
        _ => return Err("read failed")
      }
      if line == "__MCP_TIMEOUT__" {
        Err("timeout after \{timeout_ms}ms")
      } else if line == "__MCP_ERROR__" {
        Err("read error (session invalid)")
      } else {
        Ok(line)
      }
    }
    WebSocket => {
      ignore(io_ws_write(self.handle_id, raw) catch { _ => return Err("write failed") })
      let resp = io_ws_read(self.handle_id, timeout_ms) catch {
        _ => return Err("read failed")
      }
      if resp == "__MCP_TIMEOUT__" {
        Err("timeout after \{timeout_ms}ms")
      } else if resp == "__MCP_ERROR__" {
        Err("read error (session invalid)")
      } else {
        Ok(resp)
      }
    }
  }
}

///| Send a JSON-RPC notification (no response expected).
pub async fn Session::notify(
  self : Session,
  meth : String,
  params : Json,
) -> Result[Unit, String] {
  let s = Json::object({
    "jsonrpc": Json::string("2.0"),
    "method": Json::string(meth),
    "params": params,
  }).stringify()
  match self.transport {
    Stdio => {
      let s2 = s + "\n"
      ignore(io_write(self.handle_id, s2) catch {
        _ => -1
      })
    }
    WebSocket => {
      ignore(io_ws_write(self.handle_id, s) catch {
        _ => return Err("write failed")
      })
    }
  }
  Ok(())
}

///| Close the session (kill child or close WebSocket).
pub async fn Session::close(self : Session) -> Result[Unit, String] {
  match self.transport {
    Stdio => {
      ignore(io_close(self.handle_id) catch { _ => -1 })
    }
    WebSocket => {
      ignore(io_ws_close(self.handle_id) catch { _ => -1 })
    }
  }
  self.alive = false
  Ok(())
}
