/**
 * context-check — can this box reach Sanity Context, and what does it serve?
 *
 *   npm run context-check
 *
 * Connects to each configured Context MCP endpoint, lists its tools and calls
 * `initial_context`. It reads nothing else and writes nothing. It is the first
 * step of the seasonal draft agent: if this does not print tools, the agent
 * would not either, and the failure is easier to read here.
 *
 *   SANITY_CONTEXT_TOKEN     an organization token with Context Viewer. A
 *                            different token from SANITY_API_TOKEN.
 *   SANITY_CONTEXT_MCP_URL   the GROQ-mode endpoint (products, campaigns)
 *   SANITY_CONTEXT_KB_URL    optional: the endpoint in Knowledge Base mode
 */

import {connect} from '../context.mjs'

async function check(label, url, token) {
  console.log(`\n${label}\n  ${url.replace(/\?.*/, '?…')}`)
  const client = connect(url, token)
  const info = await client.initialize()
  console.log(`  server: ${info?.serverInfo?.name ?? '?'} ${info?.serverInfo?.version ?? ''}`.trimEnd())

  const tools = await client.listTools()
  console.log(`  tools:  ${tools.map((t) => t.name).join(', ') || '(none)'}`)

  if (tools.some((t) => t.name === 'initial_context')) {
    const result = await client.callTool('initial_context')
    const text = (result?.content ?? []).filter((c) => c.type === 'text').map((c) => c.text).join('\n')
    const lines = text.split('\n')
    console.log(`  initial_context (first ${Math.min(lines.length, 15)} of ${lines.length} lines):`)
    for (const line of lines.slice(0, 15)) console.log(`    ${line}`)
  }
}

const isMain = process.argv[1]?.endsWith('context-check.mjs')

if (isMain) {
  const token = process.env.SANITY_CONTEXT_TOKEN?.trim()
  const endpoints = [
    ['GROQ mode', process.env.SANITY_CONTEXT_MCP_URL?.trim()],
    ['Knowledge Base mode', process.env.SANITY_CONTEXT_KB_URL?.trim()],
  ].filter(([, url]) => url)

  if (!token || !endpoints.length) {
    console.error(
      'Sanity Context is not configured. Set in publisher/.env:\n' +
        '  SANITY_CONTEXT_TOKEN — an organization token with Context Viewer\n' +
        '  SANITY_CONTEXT_MCP_URL — https://api.sanity.io/v1/context/organizations/<org id>/mcp/<endpoint name>\n' +
        '  SANITY_CONTEXT_KB_URL — optional, the same URL with ?mode=knowledge_base&knowledgeBases=kb…',
    )
    process.exit(1)
  }

  let failed = false
  for (const [label, url] of endpoints) {
    try {
      await check(label, url, token)
    } catch (error) {
      failed = true
      console.error(`  FAILED: ${error.message}`)
    }
  }
  process.exit(failed ? 1 : 0)
}
