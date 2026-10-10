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
///
/// JSON-RPC 2.0 deep-check behaviors (default compliant):
///   - batch array requests are answered with a response array (one item per
///     request with a defined id)
///   - unknown methods return -32601 with a schema-valid error object
///
/// Opt-in switches (via environment variables):
///   MCP_FIXTURE_BATCH_SHUFFLE=1  -> batch responses are shuffled out of order
///   MCP_FIXTURE_INVALID_ERROR=1  -> unknown-method errors become schema-
///                                   invalid (non-integer code, empty message,
///                                   result+error coexistence)

const readline = require('node:readline')
const rl = readline.createInterface({ input: process.stdin })

const SHUFFLE_BATCH = process.env.MCP_FIXTURE_BATCH_SHUFFLE === '1'
const INVALID_ERROR = process.env.MCP_FIXTURE_INVALID_ERROR === '1'

function send(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n')
}

function makeError(id, code, message) {
  if (INVALID_ERROR) {
    // Injected violations: non-integer code, empty message, result+error
    // coexistence in the same response.
    return {
      jsonrpc: '2.0',
      id,
      result: { injected: true },
      error: { code: 0.5, message: '' },
    }
  }
  return { jsonrpc: '2.0', id, error: { code, message } }
}

function buildResponse(method, params, id) {
  if (method === 'initialize') {
    // Support multiple protocol versions for negotiation testing
    let protoVer = '2026-07-28'
    if (params && params.protocolVersion) {
      const requested = params.protocolVersion
      // Only support known versions; reject unknown with error
      if (requested === '2026-07-28' || requested === '2025-06-18' || requested === '2025-03-26') {
        protoVer = requested
      } else {
        return makeError(id, -32600, 'Unsupported protocol version')
      }
    }
    return {
      jsonrpc: '2.0',
      id,
      result: {
        protocolVersion: protoVer,
        serverInfo: { name: 'mcp-fixture', version: '0.1.0' },
        capabilities: { tools: {}, resources: {}, prompts: {} },
      },
    }
  } else if (method === 'tools/list') {
    return {
      jsonrpc: '2.0',
      id,
      result: {
        tools: [
          { name: 'echo', description: 'Echoes input' },
          { name: 'no_desc_tool' },
        ],
      },
    }
  } else if (method === 'tools/call') {
    if (params.name === '__mcpconftest_nonexistent__') {
      return makeError(id, -32000, 'Custom error (wrong code, should be -32601)')
    }
    return {
      jsonrpc: '2.0',
      id,
      result: { content: [{ type: 'text', text: 'ok' }] },
    }
  } else if (method === 'resources/list') {
    return {
      jsonrpc: '2.0',
      id,
      result: {
        resources: [
          { uri: 'file:///__mcpconftest_sample__', name: 'sample' },
          { uri: 'file:///__mcpconftest_no_name__' },  // violation: missing name
        ],
      },
    }
  } else if (method === 'resources/read') {
    if (params.uri === 'file:///__mcpconftest_nonexistent__') {
      return makeError(id, -32600, 'Resource not found')
    }
    return {
      jsonrpc: '2.0',
      id,
      result: { contents: [{ uri: params.uri, text: 'content' }] },
    }
  } else if (method === 'prompts/list') {
    return {
      jsonrpc: '2.0',
      id,
      result: {
        prompts: [
          { name: 'greet', arguments: [{ name: 'name' }] },
          { arguments: [{ name: 'x' }] },  // violation: missing name
        ],
      },
    }
  } else if (method === 'ping') {
    // VIOLATION: spec says server MUST respond to ping with empty result
    return makeError(id, -32601, 'Method not found')
  } else {
    // Unknown method: default schema-valid -32601 error.
    return makeError(id, -32601, 'Method not found')
  }
}

rl.on('line', (line) => {
  try {
    const msg = JSON.parse(line)
    if (Array.isArray(msg)) {
      // Batch request: answer with a response array (one item per request
      // with a defined id). Optionally shuffle the items out of order.
      const responses = []
      for (const item of msg) {
        if (item && item.jsonrpc === '2.0' && item.method && item.id !== undefined) {
          const r = buildResponse(item.method, item.params || {}, item.id)
          if (r) responses.push(r)
        } else if (item && item.jsonrpc === '2.0' && item.method) {
          // notification inside batch: no response
        } else {
          responses.push({ jsonrpc: '2.0', id: null, error: { code: -32600, message: 'Invalid Request' } })
        }
      }
      if (responses.length > 0) {
        if (SHUFFLE_BATCH) {
          for (let i = responses.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1))
            ;[responses[i], responses[j]] = [responses[j], responses[i]]
          }
        }
        send(responses)
      }
      return
    }
    if (msg.jsonrpc === '2.0' && msg.method) {
      if (msg.id !== undefined) {
        const r = buildResponse(msg.method, msg.params || {}, msg.id)
        if (r) send(r)
      }
      // notifications: no response
    }
  } catch (e) {
    // ignore malformed
  }
})
