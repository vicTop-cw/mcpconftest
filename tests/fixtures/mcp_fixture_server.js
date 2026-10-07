///| A deliberately partially-compliant MCP server fixture.
///
/// Intentional violations for conformance validation:
///   - tools/list returns a tool without description
///   - tools/call on non-existent tool returns -32000 instead of -32601
///   - resources/list returns a resource without name
///   - prompts/list returns a prompt without name
///   - ping returns -32601 instead of empty result
///
/// Supported methods: initialize, tools/list, tools/call, resources/list,
/// resources/read, prompts/list, ping, notifications/initialized

const readline = require('node:readline')
const rl = readline.createInterface({ input: process.stdin })

function send(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n')
}

function handleRequest(method, params, id) {
  if (method === 'initialize') {
    // Support multiple protocol versions for negotiation testing
    let protoVer = '2026-07-28'
    if (params && params.protocolVersion) {
      const requested = params.protocolVersion
      // Only support known versions; reject unknown with error
      if (requested === '2026-07-28' || requested === '2025-06-18' || requested === '2025-03-26') {
        protoVer = requested
      } else {
        send({
          jsonrpc: '2.0',
          id,
          error: { code: -32600, message: 'Unsupported protocol version' },
        })
        return
      }
    }
    send({
      jsonrpc: '2.0',
      id,
      result: {
        protocolVersion: protoVer,
        serverInfo: { name: 'mcp-fixture', version: '0.1.0' },
        capabilities: { tools: {}, resources: {}, prompts: {} },
      },
    })
  } else if (method === 'tools/list') {
    send({
      jsonrpc: '2.0',
      id,
      result: {
        tools: [
          { name: 'echo', description: 'Echoes input' },
          { name: 'no_desc_tool' },
        ],
      },
    })
  } else if (method === 'tools/call') {
    if (params.name === '__mcpconftest_nonexistent__') {
      send({
        jsonrpc: '2.0',
        id,
        error: { code: -32000, message: 'Custom error (wrong code, should be -32601)' },
      })
    } else {
      send({
        jsonrpc: '2.0',
        id,
        result: { content: [{ type: 'text', text: 'ok' }] },
      })
    }
  } else if (method === 'resources/list') {
    send({
      jsonrpc: '2.0',
      id,
      result: {
        resources: [
          { uri: 'file:///__mcpconftest_sample__', name: 'sample' },
          { uri: 'file:///__mcpconftest_no_name__' },  // violation: missing name
        ],
      },
    })
  } else if (method === 'resources/read') {
    if (params.uri === 'file:///__mcpconftest_nonexistent__') {
      send({
        jsonrpc: '2.0',
        id,
        error: { code: -32600, message: 'Resource not found' },
      })
    } else {
      send({
        jsonrpc: '2.0',
        id,
        result: { contents: [{ uri: params.uri, text: 'content' }] },
      })
    }
  } else if (method === 'prompts/list') {
    send({
      jsonrpc: '2.0',
      id,
      result: {
        prompts: [
          { name: 'greet', arguments: [{ name: 'name' }] },
          { arguments: [{ name: 'x' }] },  // violation: missing name
        ],
      },
    })
  } else if (method === 'ping') {
    // VIOLATION: spec says server MUST respond to ping with empty result
    send({
      jsonrpc: '2.0',
      id,
      error: { code: -32601, message: 'Method not found' },
    })
  } else {
    send({
      jsonrpc: '2.0',
      id,
      error: { code: -32601, message: 'Method not found' },
    })
  }
}

rl.on('line', (line) => {
  try {
    const msg = JSON.parse(line)
    if (msg.jsonrpc === '2.0' && msg.method) {
      if (msg.id !== undefined) {
        handleRequest(msg.method, msg.params || {}, msg.id)
      }
      // notifications: no response
    }
  } catch (e) {
    // ignore malformed
  }
})
