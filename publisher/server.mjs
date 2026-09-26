/**
 * The publisher's HTTP surface. Three routes, and the contract in
 * docs/post-queue-contract.md is the specification for two of them.
 *
 *   GET  /api/posts/pending          the queue, bearer-authenticated
 *   POST /api/posts/{id}/decision    approve or reject, bearer-authenticated
 *   GET  /preview                    signature-authenticated, for the iframe
 *   GET  /healthz                    unauthenticated liveness, no data
 *
 * Binds to loopback by default: on the Jetson the store calls it over 127.0.0.1
 * and only the preview route is exposed through nginx.
 *
 * NOTHING IS SENT TO ANY PLATFORM from here. This half serves the queue and
 * records decisions; the sending half does not exist yet.
 */
import {createServer} from 'node:http'
import {load} from './config.mjs'
import {createClient, SanityError} from './sanity.mjs'
import {openDecisions, DECISIONS} from './decisions.mjs'
import {buildQueue, fetchQueueData, findRow, recheck} from './queue.mjs'
import {PreviewError, renderPreview, verifyPreview} from './preview.mjs'
import {splitVariantId} from './ids.mjs'

const MAX_BODY = 64 * 1024

export function createApp({config, client, decisions}) {
  function sendJson(res, status, payload) {
    const body = JSON.stringify(payload)
    res.writeHead(status, {
      // The store tells "unreadable" from "empty" by the shape of what comes
      // back, so every API answer is JSON with a JSON content type — including
      // the errors. A 200 carrying HTML is the failure it is written around.
      'Content-Type': 'application/json; charset=utf-8',
      'Content-Length': Buffer.byteLength(body),
      'Cache-Control': 'no-store',
    })
    res.end(body)
  }

  function sendHtml(res, status, html) {
    res.writeHead(status, {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-store',
      // The store frames this. Nothing else should, and it needs nothing of its
      // own — no scripts, no forms, no outbound requests but the asset.
      'Content-Security-Policy':
        "default-src 'none'; img-src https://cdn.sanity.io; media-src https://cdn.sanity.io; style-src 'unsafe-inline'",
      'Referrer-Policy': 'no-referrer',
      'X-Content-Type-Options': 'nosniff',
    })
    res.end(html)
  }

  function authorized(req) {
    const header = req.headers.authorization ?? ''
    const prefix = 'Bearer '
    if (!header.startsWith(prefix)) return false
    const offered = header.slice(prefix.length)
    // Length-then-content, so a wrong-length token does not throw.
    if (offered.length !== config.token.length) return false
    let same = 0
    for (let i = 0; i < offered.length; i++) same |= offered.charCodeAt(i) ^ config.token.charCodeAt(i)
    return same === 0
  }

  async function readJsonBody(req) {
    const chunks = []
    let size = 0
    for await (const chunk of req) {
      size += chunk.length
      if (size > MAX_BODY) throw new Error('that request body is too large')
      chunks.push(chunk)
    }
    if (!chunks.length) return {}
    const text = Buffer.concat(chunks).toString('utf8')
    try {
      const parsed = JSON.parse(text)
      return parsed && typeof parsed === 'object' ? parsed : {}
    } catch {
      throw new Error('that request body is not JSON')
    }
  }

  async function pending(res) {
    const data = await fetchQueueData(client)
    const posts = buildQueue({data, client, decisions, config})
    sendJson(res, 200, {posts})
  }

  async function decide(req, res, id) {
    const parts = splitVariantId(id)
    if (!parts) {
      return sendJson(res, 400, {
        error: 'that id does not name a variant — it should be the document id, then __, then the variant key',
      })
    }

    let body
    try {
      body = await readJsonBody(req)
    } catch (error) {
      return sendJson(res, 400, {error: error.message})
    }

    const {decision, actor, note} = body
    if (!DECISIONS.includes(decision)) {
      return sendJson(res, 400, {error: `decision must be one of ${DECISIONS.join(', ')}`})
    }

    const already = decisions.get(id)
    if (already && already.decision === decision) {
      // Idempotent: the store retrying a request whose answer it never saw must
      // not produce a second record, and must not look like a failure either.
      return sendJson(res, 200, {ok: true, decision: already, repeated: true})
    }

    const fresh = await recheck({client, documentId: parts.documentId, variantKey: parts.variantKey})

    if (!fresh.found) {
      return sendJson(res, 404, {
        error: 'that variant is no longer in the CMS, so nothing was recorded',
      })
    }

    // A blocked post can still be rejected — that is how it gets cleared — but
    // an approval is re-checked against the CMS as it is NOW, not as the page
    // showed it. Whatever verdict the queue rendered is advisory.
    if (decision === 'approved' && !fresh.verdict.ok) {
      const why = fresh.verdict.errors[0]?.message ?? 'it no longer passes the checks'
      return sendJson(res, 409, {
        error: `${fresh.platformLabel} cannot be approved: ${why}`,
        verdict: fresh.verdict,
      })
    }

    const {record, written} = decisions.record({id, decision, actor, note})

    // Rejecting hands the variant back as a draft, with the note kept here.
    // Approving deliberately leaves the status alone: `approved` is the state
    // the sending half will read, and a human's yes is recorded separately so
    // the two never get confused for one another.
    let handedBack = false
    if (decision === 'rejected' && fresh.status !== 'draft') {
      try {
        await client.mutate([
          {
            patch: {
              id: parts.documentId,
              set: {[`variants[_key=="${parts.variantKey}"].status`]: 'draft'},
            },
          },
        ])
        handedBack = true
      } catch (error) {
        // The decision is already recorded, so say what did not happen rather
        // than pretending the whole thing failed and inviting a retry that
        // would be a no-op.
        return sendJson(res, 200, {
          ok: true,
          decision: record,
          warning: `recorded, but the variant could not be set back to draft: ${error.message}`,
        })
      }
    }

    sendJson(res, 200, {ok: true, decision: record, written, handed_back: handedBack})
  }

  function preview(res, url) {
    let id
    try {
      id = verifyPreview(url.searchParams, config)
    } catch (error) {
      const status = error instanceof PreviewError ? error.status : 403
      return sendHtml(res, status, `<!doctype html><meta charset="utf-8"><p>${error.message}</p>`)
    }

    // Rendering reads the queue rather than trusting the URL for anything but
    // the id, so a signed link cannot be used to render arbitrary content.
    return fetchQueueData(client).then(
      (data) => {
        const row = findRow(buildQueue({data, client, decisions, config}), id)
        if (!row) {
          return sendHtml(
            res,
            404,
            `<!doctype html><meta charset="utf-8"><p>This post is no longer in the queue.</p>`,
          )
        }
        sendHtml(res, 200, renderPreview(row))
      },
      (error) =>
        sendHtml(
          res,
          502,
          `<!doctype html><meta charset="utf-8"><p>Could not load this preview: ${error.message}</p>`,
        ),
    )
  }

  return async function handle(req, res) {
    const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`)
    const path = url.pathname.replace(/\/+$/, '') || '/'

    try {
      if (req.method === 'GET' && path === '/healthz') {
        return sendJson(res, 200, {ok: true, queued: decisions.size})
      }

      if (path === '/preview' || path === '/post-preview') {
        if (req.method !== 'GET') return sendJson(res, 405, {error: 'use GET'})
        return preview(res, url)
      }

      if (path.startsWith('/api/')) {
        if (!authorized(req)) {
          res.setHeader('WWW-Authenticate', 'Bearer')
          return sendJson(res, 401, {error: 'a bearer token is required'})
        }

        if (req.method === 'GET' && path === '/api/posts/pending') return await pending(res)

        const decisionPath = path.match(/^\/api\/posts\/(.+)\/decision$/)
        if (decisionPath && req.method === 'POST') {
          return await decide(req, res, decodeURIComponent(decisionPath[1]))
        }

        return sendJson(res, 404, {error: 'no such route'})
      }

      return sendJson(res, 404, {error: 'no such route'})
    } catch (error) {
      const upstream = error instanceof SanityError
      // Say what actually went wrong. The store shows this text verbatim, so it
      // has to read as one sentence a person can act on.
      return sendJson(res, upstream ? 502 : 500, {
        error: upstream ? error.message : `the publisher failed: ${error.message}`,
      })
    }
  }
}

// --- startup ---------------------------------------------------------------

const isMain = import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith('server.mjs')

if (isMain) {
  let config
  try {
    config = load()
  } catch (error) {
    console.error(error.message)
    process.exit(1)
  }

  const client = createClient(config.sanity)
  const decisions = openDecisions(config.decisionsPath)
  if (decisions.skipped) {
    console.warn(`[publisher] ${decisions.skipped} unreadable line(s) in ${config.decisionsPath}`)
  }

  const server = createServer(createApp({config, client, decisions}))
  server.listen(config.port, config.host, () => {
    console.log(`[publisher] listening on http://${config.host}:${config.port}`)
    console.log(`[publisher] project ${config.sanity.projectId}/${config.sanity.dataset}`)
    console.log(`[publisher] ${decisions.size} decision(s) on file at ${config.decisionsPath}`)
    console.log(
      config.publicUrl
        ? `[publisher] previews advertised at ${config.publicUrl}`
        : `[publisher] PUBLISHER_PUBLIC_URL unset — previews are served but not advertised, so the store shows the asset instead`,
    )
  })

  for (const signal of ['SIGINT', 'SIGTERM']) {
    process.on(signal, () => server.close(() => process.exit(0)))
  }
}
