///| A fully MCP-compliant server for demo purposes.
///
/// Compliant with 2026-07-28 spec:
/// - Proper initialize response with serverInfo, protocolVersion, capabilities
/// - tools/list returns tools with name + description
/// - tools/call returns -32601 for unknown tools
/// - ping returns empty result (spec-mandated)
/// - resources/list + prompts/list return proper schemas
/// - Accepts notifications/initialized

const readline = require('node:readline')
const rl = readline.createInterface({ input: process.stdin })

function send(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n')
}

function handleRequest(method, params, id) {
  if (method === 'initialize') {
    let protoVer = '2026-07-28'
    if (params && params.protocolVersion) {
      const requested = params.protocolVersion
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
        serverInfo: { name: 'mcp-compliant-demo', version: '1.0.0' },
        capabilities: {
          tools: {},
          resources: {},
          prompts: {},
          logging: {},
        },
      },
    })
  } else if (method === 'tools/list') {
    send({
      jsonrpc: '2.0',
      id,
      result: {
        tools: [
          { name: 'echo', description: 'Echoes input text back to the caller' },
          { name: 'add', description: 'Adds two numbers and returns the sum' },
        ],
      },
    })
  } else if (method === 'tools/call') {
    if (params.name === 'echo') {
      send({
        jsonrpc: '2.0',
        id,
        result: { content: [{ type: 'text', text: params.arguments?.text || '' }] },
      })
    } else if (params.name === 'add') {
      const a = params.arguments?.a || 0
      const b = params.arguments?.b || 0
      send({
        jsonrpc: '2.0',
        id,
        result: { content: [{ type: 'text', text: String(a + b) }] },
      })
    } else {
      // Unknown tool → proper -32601 error
      send({
        jsonrpc: '2.0',
        id,
        error: { code: -32601, message: 'Method not found' },
      })
    }
  } else if (method === 'resources/list') {
    send({
      jsonrpc: '2.0',
      id,
      result: {
        resources: [
          { uri: 'file:///demo/sample.txt', name: 'sample', description: 'Sample resource' },
        ],
      },
    })
  } else if (method === 'resources/read') {
    send({
      jsonrpc: '2.0',
      id,
      result: {
        contents: [{ uri: params.uri, text: 'Hello from demo resource' }],
      },
    })
  } else if (method === 'prompts/list') {
    send({
      jsonrpc: '2.0',
      id,
      result: {
        prompts: [
          { name: 'greet', description: 'Greets the user', arguments: [{ name: 'name', description: 'Name to greet' }] },
        ],
      },
    })
  } else if (method === 'ping') {
    // Spec: server MUST respond to ping with empty result
    send({
      jsonrpc: '2.0',
      id,
      result: {},
    })
  } else if (method === 'logging/setLevel') {
    send({
      jsonrpc: '2.0',
      id,
      result: {},
    })
  } else if (method === 'completion/complete') {
    send({
      jsonrpc: '2.0',
      id,
      result: {
        completion: {
          values: [{ name: 'greet' }, { name: 'echo' }, { name: 'add' }],
        },
      },
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
      // notifications: no response expected
    }
  } catch (e) {
    // ignore malformed
  }
})
