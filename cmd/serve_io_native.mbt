///| native target 的 stdio 运行：直接复用 colmugx/mcp 原生 StdioTransport。

///| 仅 native target 编译（见 cmd/moon.pkg targets 配置）。

///| 错误不得写 stdout（stdio JSON-RPC 协议专用通道），保持静默。

///|
/// Run the stdio server loop for the native target.
async fn run_stdio_target(s1 : @mcp.MCPServer) -> Unit {
  s1.run_stdio() catch {
    _ => ()
  }
}
