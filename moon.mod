name = "vicTop-cw/mcpconftest"

version = "0.9.0"

readme = "README.md"

repository = "https://github.com/vicTop-cw/mcpconftest"

license = "Apache-2.0"

keywords = [ "mcp", "conformance", "test", "cli", "moonbit" ]

description = "MCP protocol conformance probe — checks any MCP server (stdio or WebSocket) against the spec. 15 check categories, 4 report formats (JSON/Markdown/HTML/JUnit), per-check timing, multi-server parallel probe, CI gate, MCP stdio server + CLI (js/native)."

preferred_target = "js"

import {
  "moonbitlang/async@0.22.3",
  "colmugx/mcp@0.18.1",
  "moonbitlang/x@0.5.5",
  "daqing/sqlite@0.4.0",
}
