///| stdio JSON-RPC session driver.
///
/// Spawns the target MCP server as a child process, speaks JSON-RPC
/// over stdin/stdout with configurable timeouts.

///| A running stdio session.
pub(all) struct Session {
  mut next_id : Int
  mut alive : Bool
}

///| Spawn a new session with the given command.
pub fn Session::new(cmd : String) -> Session {
  // In a real implementation, this would spawn a child process.
  // For now, just record the command.
  { next_id: 1, alive: cmd.length() > 0 }
}

///| Send a JSON-RPC request, wait for response with timeout.
pub fn Session::request(self : Session, meth : String, params : Json, timeout_ms : Int) -> Result[String, String] {
  let id = self.next_id
  self.next_id += 1
  let req = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string(meth),
    "params": params,
  })
  let req_str = req.stringify() + "\n"
  // In a real implementation, write to child's stdin and read response.
  // For now, return a stub.
  if self.alive {
    Ok(req_str)
  } else {
    Err("session not initialized")
  }
}

///| Send a JSON-RPC notification (no response expected).
pub fn Session::notify(self : Session, meth : String, params : Json) -> Result[Unit, String] {
  let notif = Json::object({
    "jsonrpc": Json::string("2.0"),
    "method": Json::string(meth),
    "params": params,
  })
  let s = notif.stringify() + "\n"
  if self.alive {
    Ok(())
  } else {
    Err("session not initialized")
  }
}

///| Close the session.
pub fn Session::close(self : Session) -> Result[Unit, String] {
  Ok(())
}
