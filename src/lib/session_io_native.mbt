///| Native-target implementations of the low-level session I/O primitives.
///
/// Real stdio transport over child-process pipes (moonbitlang/async/process):
///   - io_spawn     : create stdin/stdout pipes and spawn the child via
///                    `@process.spawn_orphan` (orphan mode avoids the TaskGroup
///                    lifetime coupling of `spawn(group, ...)`).
///   - io_write     : buffered write + flush to the child's stdin.
///   - io_read_line : read one newline-delimited line from the child's stdout
///                    with a timeout (`@async.with_timeout`).
///   - io_close     : close stdin (EOF) and close the stdout reader; the child
///                    observes EOF on stdin and exits by itself (graceful
///                    shutdown, same pattern as colmugx/mcp StdioClientTransport).
///
/// WebSocket operations remain stubs (connect returns -1): the native backend
/// does not support the WS transport yet, matching the js FFI sentinel contract.

///| A live native stdio child session.
priv struct NativeSession {
  reader : @process.ReadFromProcess
  raw_writer : @process.WriteToProcess
  writer : @io.BufferedWriter[@process.WriteToProcess]
}

///| Global session table (handle -> session). Grows on demand.
let sessions : Array[Option[NativeSession]] = Array::make(16, None)

fn ensure_capacity(id : Int) -> Unit {
  while sessions.length() <= id {
    sessions.push(None)
  }
}

///| Spawn a stdio child MCP process. Returns session handle or -1 on failure.
pub async fn io_spawn(argv : Array[String], workdir : String) -> Int {
  if argv.length() == 0 {
    return -1
  }
  let cmd = argv[0]
  let args = argv[1:]
  let (stdin_input, stdin_writer) = @process.write_to_process() catch {
    _ => return -1
  }
  errdefer stdin_writer.close()
  let (stdout_reader, stdout_output) = @process.read_from_process() catch {
    _ => return -1
  }
  errdefer stdout_reader.close()
  let _ = @process.spawn_orphan(
    cmd,
    args,
    stdin=stdin_input,
    stdout=stdout_output,
    cwd=workdir,
  ) catch {
    _ => return -1
  }
  let id = sessions.length()
  ensure_capacity(id)
  sessions.set(
    id,
    Some({
      reader: stdout_reader,
      raw_writer: stdin_writer,
      writer: @io.BufferedWriter::new(stdin_writer, size=8192),
    }),
  )
  id
}

///| Write a line to the child's stdin. Returns 0 on success, -1 on failure.
pub async fn io_write(handle_id : Int, line : String) -> Int {
  match sessions[handle_id] {
    None => -1
    Some(s) => {
      s.writer.write(line) catch { _ => return -1 }
      s.writer.write("\n") catch { _ => return -1 }
      s.writer.flush() catch { _ => return -1 }
      0
    }
  }
}

///| Read one response line from the child's stdout with timeout.
///| Returns `__MCP_TIMEOUT__` / `__MCP_ERROR__` sentinel values on failure.
pub async fn io_read_line(handle_id : Int, timeout_ms : Int) -> String {
  match sessions[handle_id] {
    None => "__MCP_ERROR__"
    Some(s) => {
      let line_opt : String? = try {
        @async.with_timeout(timeout_ms, async fn() {
          s.reader.read_until("\n") catch { _ => None }
        })
      } catch {
        _ => None
      }
      match line_opt {
        None => "__MCP_TIMEOUT__"
        Some(line) => line.trim().to_owned()
      }
    }
  }
}

///| Close a stdio child session (EOF on stdin + close reader).
pub async fn io_close(handle_id : Int) -> Int {
  match sessions[handle_id] {
    None => -1
    Some(s) => {
      s.raw_writer.close()
      s.reader.close()
      sessions.set(handle_id, None)
      0
    }
  }
}

///| Connect a WebSocket MCP session.
///| Native stub: returns -1 (WS transport not supported on native yet).
pub async fn io_ws_connect(_url : String) -> Int {
  -1
}

///| Send a WebSocket message.
///| Native stub: returns -1.
pub async fn io_ws_write(_handle_id : Int, _message : String) -> Int {
  -1
}

///| Read one WebSocket response with timeout.
///| Native stub: returns `__MCP_ERROR__`.
pub async fn io_ws_read(_handle_id : Int, _timeout_ms : Int) -> String {
  "__MCP_ERROR__"
}

///| Close a WebSocket session.
///| Native stub: returns -1.
pub async fn io_ws_close(_handle_id : Int) -> Int {
  -1
}
