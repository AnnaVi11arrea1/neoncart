/**
 * Sanity Context, over MCP's HTTP transport. No SDK, for the same reason
 * sanity.mjs has none: this service installs with `git pull` and nothing else.
 *
 * MCP over HTTP is JSON-RPC in a POST. The server may answer as JSON or as a
 * server-sent event stream, so both are accepted.
 *
 * Context is read-only. What it can see is set in the Context app: the
 * `neoncart-drafts` endpoint reads products and campaigns, and the same URL
 * with ?mode=knowledge_base serves the Knowledge Base.
 */

export class ContextError extends Error {}

/** The JSON-RPC message in a response body, whichever way it was framed. */
export function parseRpcBody(text, contentType = '') {
  if (!contentType.includes('text/event-stream')) return JSON.parse(text)
  // Each event is `data:` lines; the reply is the last one carrying an id.
  const messages = text
    .split(/\r?\n\r?\n/)
    .map((event) => event.split(/\r?\n/).filter((l) => l.startsWith('data:')).map((l) => l.slice(5).trim()).join('\n'))
    .filter(Boolean)
    .map((data) => JSON.parse(data))
  const reply = messages.filter((m) => m.id !== undefined).at(-1)
  if (!reply) throw new ContextError('the event stream carried no reply')
  return reply
}

export function connect(url, token) {
  let session = null
  let nextId = 1

  async function send(method, params, {notification = false} = {}) {
    const message = {jsonrpc: '2.0', method, ...(params ? {params} : {})}
    if (!notification) message.id = nextId++

    let response
    try {
      response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json, text/event-stream',
          Authorization: `Bearer ${token}`,
          ...(session ? {'Mcp-Session-Id': session} : {}),
        },
        body: JSON.stringify(message),
        signal: AbortSignal.timeout(30_000),
      })
    } catch (error) {
      throw new ContextError(`could not reach ${new URL(url).host} (${error?.name || 'network error'})`)
    }

    session = response.headers.get('mcp-session-id') ?? session
    const text = await response.text()
    if (!response.ok) {
      const hint =
        response.status === 401
          ? ' — SANITY_CONTEXT_TOKEN is missing, expired or wrong'
          : response.status === 403
            ? ' — that token lacks Context Viewer on this organization'
            : response.status === 404
              ? ' — no endpoint at that URL; check the organization id and endpoint name'
              : ''
      throw new ContextError(`HTTP ${response.status}${hint}${text ? `: ${text.slice(0, 200)}` : ''}`)
    }
    if (notification) return null

    const reply = parseRpcBody(text, response.headers.get('content-type') ?? '')
    if (reply.error) throw new ContextError(`${method}: ${reply.error.message ?? JSON.stringify(reply.error)}`)
    return reply.result
  }

  return {
    async initialize() {
      const result = await send('initialize', {
        protocolVersion: '2025-06-18',
        capabilities: {},
        clientInfo: {name: 'everfluorescent-publisher', version: '1.0'},
      })
      await send('notifications/initialized', undefined, {notification: true})
      return result
    },
    listTools: () => send('tools/list', {}).then((r) => r.tools ?? []),
    callTool: (name, args = {}) => send('tools/call', {name, arguments: args}),
  }
}
