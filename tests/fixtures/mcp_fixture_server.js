///| A deliberately partially-compliant MCP server fixture.
///
/// Intentional violations for conformance validation:
///   - tools/list returns a tool without description
///   - tools/call on non-existent tool returns -32000 instead of -32601
///
/// Usage: node tests/fixtures/mcp_fixture_server.js

const readline = require('node:readline')
const rl = readline.createInterface({ input: process.stdin })

function send(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n')
}

function handleRequest(method, params, id) {
  if (method === 'initialize') {
    send({
      jsonrpc: '2.0',
      id,
      result: {
        protocolVersion: '2026-07-28',
        serverInfo: { name: 'mcp-fixture', version: '0.1.0' },
        capabilities: { tools: {} },
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
        error: { code: -32601, message: 'Method not found' },
      })
    } else {
      send({
        jsonrpc: '2.0',
        id,
        result: { content: [{ type: 'text', text: 'ok' }] },
      })
    }
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
