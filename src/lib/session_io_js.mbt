///|
/// JS-target implementations of the low-level session I/O primitives.
///
/// The session driver logic lives in `session.mbt` (all targets) and calls
/// the `io_*` async wrappers defined here; the native counterpart lives in
/// `session_io_native.mbt`. Keeping the `extern "js"` FFI in a js-only file
/// lets the `src/lib` package build for both `js` and `native` targets.
extern "js" fn js_spawn_mcp(
  argv : FixedArray[String],
  workdir : String,
) -> @js_async.Promise[Int32] =
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

///|
/// Spawn a stdio child MCP process. Returns session handle or -1 on failure.
pub async fn io_spawn(argv : Array[String], workdir : String) -> Int32 {
  js_spawn_mcp(FixedArray::from_array(argv), workdir).wait() catch {
    _ => -1
  }
}

///|
extern "js" fn js_mcp_write(
  handle_id : Int32,
  line : String,
) -> @js_async.Promise[Int32] =
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

///|
/// Write a line to the child's stdin. Returns 0 on success, -1 on failure.
pub async fn io_write(handle_id : Int32, line : String) -> Int32 {
  js_mcp_write(handle_id, line).wait() catch {
    _ => -1
  }
}

///|
extern "js" fn js_mcp_read_line(
  handle_id : Int32,
  timeout_ms : Int32,
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

///| Read one response line from the child's stdout with timeout.

///|
/// Returns `__MCP_TIMEOUT__` / `__MCP_ERROR__` sentinel values on failure.
pub async fn io_read_line(handle_id : Int32, timeout_ms : Int32) -> String {
  js_mcp_read_line(handle_id, timeout_ms).wait() catch {
    _ => "__MCP_ERROR__"
  }
}

///|
/// Current time in milliseconds (js target, monotonic).
extern "js" fn js_now_ms() -> Int32 =
  #| () => Date.now()

///|
extern "js" fn js_mcp_close(handle_id : Int32) -> @js_async.Promise[Int32] =
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

///|
/// Close / kill a stdio child session.
pub async fn io_close(handle_id : Int32) -> Int32 {
  js_mcp_close(handle_id).wait() catch {
    _ => -1
  }
}

// ---- WebSocket FFI ----

///|
extern "js" fn js_ws_connect(url : String) -> @js_async.Promise[Int32] =
  #| async (url) => {
  #|   try {
  #|     const WS = globalThis.WebSocket || (await import('ws')).WebSocket
  #|     if (!globalThis.__mcp_ws) globalThis.__mcp_ws = []
  #|     const id = globalThis.__mcp_ws.length
  #|     const ws = new WS(url)
  #|     globalThis.__mcp_ws[id] = { ws, pending: {}, buf: '' }
  #|     ws.onmessage = (ev) => {
  #|       try {
  #|         const msg = JSON.parse(ev.data)
  #|         if (msg.id !== undefined && globalThis.__mcp_ws[id].pending[msg.id]) {
  #|           globalThis.__mcp_ws[id].pending[msg.id](ev.data)
  #|           delete globalThis.__mcp_ws[id].pending[msg.id]
  #|         }
  #|       } catch (e) {}
  #|     }
  #|     await new Promise((resolve, reject) => {
  #|       ws.onopen = () => resolve()
  #|       ws.onerror = () => reject(-1)
  #|       setTimeout(() => reject(-1), 5000)
  #|     })
  #|     return id
  #|   } catch (e) {
  #|     return -1
  #|   }
  #| }

///|
/// Connect a WebSocket MCP session. Returns handle or -1 on failure.
pub async fn io_ws_connect(url : String) -> Int32 {
  js_ws_connect(url).wait() catch {
    _ => -1
  }
}

///|
extern "js" fn js_ws_write(
  handle_id : Int32,
  message : String,
) -> @js_async.Promise[Int32] =
  #| async (handle_id, message) => {
  #|   const session = globalThis.__mcp_ws[handle_id]
  #|   if (!session || !session.ws || session.ws.readyState !== 1) return -1
  #|   try {
  #|     session.ws.send(message)
  #|     return 0
  #|   } catch (e) {
  #|     return -1
  #|   }
  #| }

///|
/// Send a WebSocket message. Returns 0 on success, -1 on failure.
pub async fn io_ws_write(handle_id : Int32, message : String) -> Int32 {
  js_ws_write(handle_id, message).wait() catch {
    _ => -1
  }
}

///|
extern "js" fn js_ws_read(
  handle_id : Int32,
  timeout_ms : Int32,
) -> @js_async.Promise[String] =
  #| async (handle_id, timeout_ms) => {
  #|   const session = globalThis.__mcp_ws[handle_id]
  #|   if (!session || !session.ws) return '__MCP_ERROR__'
  #|   return new Promise((resolve) => {
  #|     let settled = false
  #|     const finish = (val) => {
  #|       if (settled) return
  #|       settled = true
  #|       clearTimeout(timer)
  #|       resolve(val)
  #|     }
  #|     const onMsg = (ev) => {
  #|       try {
  #|         const msg = JSON.parse(ev.data)
  #|         if (msg.id !== undefined || Array.isArray(msg)) {
  #|           finish(ev.data)
  #|         }
  #|       } catch (e) {}
  #|     }
  #|     session.ws.addEventListener('message', onMsg, { once: false })
  #|     const timer = setTimeout(() => {
  #|       session.ws.removeEventListener('message', onMsg)
  #|       finish('__MCP_TIMEOUT__')
  #|     }, timeout_ms)
  #|   })
  #| }

///|
/// Read one WebSocket response with timeout. Returns sentinel values on failure.
pub async fn io_ws_read(handle_id : Int32, timeout_ms : Int32) -> String {
  js_ws_read(handle_id, timeout_ms).wait() catch {
    _ => "__MCP_ERROR__"
  }
}

///|
extern "js" fn js_ws_close(handle_id : Int32) -> @js_async.Promise[Int32] =
  #| async (handle_id) => {
  #|   const session = globalThis.__mcp_ws[handle_id]
  #|   if (!session) return 0
  #|   try {
  #|     if (session.ws && session.ws.readyState <= 1) {
  #|       session.ws.close()
  #|     }
  #|   } catch (e) {}
  #|   globalThis.__mcp_ws[handle_id] = null
  #|   return 0
  #| }

///|
/// Close a WebSocket session.
pub async fn io_ws_close(handle_id : Int32) -> Int32 {
  js_ws_close(handle_id).wait() catch {
    _ => -1
  }
}
