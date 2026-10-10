///| Single source of truth for the mcpconftest version.
///| Used by the MCP server (`build_mcp_server`), the CLI (`cmd/main.mbt`)
///| and documented alongside `moon.mod`.

///| Current mcpconftest version string.
pub fn version() -> String {
  "0.7.0"
}
