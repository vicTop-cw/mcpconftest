///| stdio JSON-RPC session driver (JS target only).
///
/// Spawns the target MCP server as a child process, speaks JSON-RPC
/// over stdin/stdout with configurable timeouts.
/// All methods are async (js_async Promise bridge).

///| A running stdio session.
pub(all) struct Session {
  mut next_id : Int
  mut alive : Bool
  mut handle_id : Int
}

///| Spawn a new session with the given command (e.g. "node server.js").
pub async fn Session::new(cmd : String) -> Session {
  let parts = cmd.split(" ")
  let argv : Array[String] = []
  for p in parts {
    argv.push(p.to_string())
  }
  let handle_id = js_spawn_mcp(argv, ".").wait() catch { _ => -1 }
  { next_id: 1, alive: handle_id >= 0, handle_id }
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
  let req = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string(meth),
    "params": params,
  })
  let req_str = (match params {
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
  ignore(js_mcp_write(self.handle_id, req_str).wait() catch {
    _ => -1
  })
  let line = js_mcp_read_line(self.handle_id, timeout_ms).wait() catch {
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

///| Send a JSON-RPC notification (no response expected).
pub async fn Session::notify(
  self : Session,
  meth : String,
  params : Json,
) -> Result[Unit, String] {
  let notif = Json::object({
    "jsonrpc": Json::string("2.0"),
    "method": Json::string(meth),
    "params": params,
  })
  let s = notif.stringify() + "\n"
  ignore(js_mcp_write(self.handle_id, s).wait() catch {
    _ => -1
  })
  Ok(())
}

///| Close the session (kills the child process).
pub async fn Session::close(self : Session) -> Result[Unit, String] {
  ignore(js_mcp_close(self.handle_id).wait() catch { _ => -1 })
  self.alive = false
  Ok(())
}

extern "js" fn js_spawn_mcp(
  argv : Array[String],
  workdir : String,
) -> @js_async.Promise[Int] =
  #| async (argv, workdir) => {
  #|   const { spawn } = await import('node:child_process')
  #|   if (!globalThis.__mcp_sessions) globalThis.__mcp_sessions = []
  #|   try {
  #|     const cmd = argv[0]
  #|     const args = argv.slice(1)
  #|     const child = spawn(cmd, args, { cwd: workdir || '.', stdio: ['pipe', 'pipe', 'pipe'] })
  #|     child.on('error', () => {})
  #|     child.on('exit', () => {})
  #|     const id = globalThis.__mcp_sessions.length
  #|     globalThis.__mcp_sessions[id] = { child, stdoutBuf: '' }
  #|     return id
  #|   } catch (e) {
  #|     return -1
  #|   }
  #| }

extern "js" fn js_mcp_write(
  handle_id : Int,
  line : String,
) -> @js_async.Promise[Int] =
  #| async (handle_id, line) => {
  #|   const session = globalThis.__mcp_sessions[handle_id]
  #|   if (!session || !session.child) return -1
  #|   return new Promise((resolve) => {
  #|     try {
  #|       session.child.stdin.write(line, () => { resolve(0) })
  #|     } catch (e) {
  #|       resolve(-1)
  #|     }
  #|   })
  #| }

extern "js" fn js_mcp_read_line(
  handle_id : Int,
  timeout_ms : Int,
) -> @js_async.Promise[String] =
  #| async (handle_id, timeout_ms) => {
  #|   const session = globalThis.__mcp_sessions[handle_id]
  #|   if (!session || !session.child) return '__MCP_ERROR__'
  #|   return new Promise((resolve) => {
  #|     let settled = false
  #|     const finish = (val) => {
  #|       if (settled) return
  #|       settled = true
  #|       cleanup()
  #|       resolve(val)
  #|     }
  #|     const onData = (chunk) => {
  #|       session.stdoutBuf += chunk.toString('utf8')
  #|       const idx = session.stdoutBuf.indexOf('\n')
  #|       if (idx >= 0) {
  #|         const line = session.stdoutBuf.slice(0, idx)
  #|         session.stdoutBuf = session.stdoutBuf.slice(idx + 1)
  #|         finish(line)
  #|       }
  #|     }
  #|     const cleanup = () => {
  #|       if (session.child && session.child.stdout) {
  #|         session.child.stdout.off('data', onData)
  #|       }
  #|       clearTimeout(timer)
  #|     }
  #|     const timer = setTimeout(() => { finish('__MCP_TIMEOUT__') }, timeout_ms)
  #|     session.child.stdout.on('data', onData)
  #|   })
  #| }

extern "js" fn js_mcp_close(handle_id : Int) -> @js_async.Promise[Int] =
  #| async (handle_id) => {
  #|   const session = globalThis.__mcp_sessions[handle_id]
  #|   if (!session) return 0
  #|   try {
  #|     if (session.child) {
  #|       session.child.stdout.removeAllListeners('data')
  #|       session.child.stderr.removeAllListeners('data')
  #|       session.child.stdin.removeAllListeners()
  #|       session.child.kill()
  #|     }
  #|   } catch (e) {}
  #|   globalThis.__mcp_sessions[handle_id] = null
  #|   return 0
  #| }
