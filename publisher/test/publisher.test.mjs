/**
 * The publisher, exercised against a stubbed content lake.
 *
 *   npm test
 *
 * No network, no Sanity, no listening socket: the handler is called directly
 * with a fake request and a response that records what was written. What is
 * being tested is the part that goes wrong quietly — which variants reach the
 * queue, whether a stale approval is refused, whether a retried decision writes
 * twice, and whether a forged preview link is accepted.
 */
import assert from 'node:assert/strict'
import {mkdtempSync, rmSync} from 'node:fs'
import {tmpdir} from 'node:os'
import {join} from 'node:path'
import {createApp} from '../server.mjs'
import {openDecisions} from '../decisions.mjs'
import {splitVariantId, variantId} from '../ids.mjs'
import {previewUrl} from '../preview.mjs'

const work = mkdtempSync(join(tmpdir(), 'publisher-test-'))
let passed = 0
const failures = []

function check(label, fn) {
  try {
    fn()
    passed++
  } catch (error) {
    failures.push(`${label}\n      ${error.message}`)
  }
}

async function checkAsync(label, fn) {
  try {
    await fn()
    passed++
  } catch (error) {
    failures.push(`${label}\n      ${error.message}`)
  }
}

const CONFIG = {
  host: '127.0.0.1',
  port: 3002,
  token: 'store-token-aaaaaaaaaaaaaaaa',
  previewSecret: 'preview-secret-bbbbbbbbbbbb',
  previewTtl: 900,
  publicUrl: 'https://www.everfluorescent.com/post-preview',
  decisionsPath: join(work, 'decisions.jsonl'),
  sanity: {projectId: 'p', dataset: 'production', token: 't', apiVersion: '2024-10-01'},
}

const IMAGE = {
  _key: 'a1',
  _type: 'image',
  ref: 'image-abc123-1080x1350-jpg',
  meta: {
    mimeType: 'image/jpeg',
    originalFilename: 'tee.jpg',
    metadata: {dimensions: {width: 1080, height: 1350}},
  },
}

function post(id, variants, {products = [], title = 'Flare Tee drop'} = {}) {
  return {_id: id, _rev: 'r1', _updatedAt: '2026-09-24T12:00:00Z', title, products, variants}
}

function variant(key, platform, status, extra = {}) {
  return {
    _key: key,
    platform,
    format: 'feed_image',
    caption: 'Glow up tonight. #uv',
    status,
    assets: [IMAGE],
    ...extra,
  }
}

const ACCOUNTS = [
  {platform: 'instagram', active: true, audited: false},
  {platform: 'tiktok', active: true, audited: false},
  {platform: 'linkedin', active: false, audited: false},
]

/** A client that answers from fixtures and records every mutation. */
function stubClient(data, {onQuery} = {}) {
  const mutations = []
  return {
    mutations,
    async query(groq, params = {}) {
      onQuery?.(groq, params)
      if (groq.includes('"post":')) {
        const found = (data.posts ?? []).find((p) => p._id === params.id) ?? null
        return {post: found, accounts: data.accounts ?? []}
      }
      return data
    },
    async mutate(list) {
      mutations.push(...[].concat(list))
      return {results: []}
    },
    assetUrl(ref) {
      if (typeof ref !== 'string') return null
      const parts = ref.split('-')
      if (parts[0] === 'image' && parts.length === 4) {
        return `https://cdn.sanity.io/images/p/production/${parts[1]}-${parts[2]}.${parts[3]}`
      }
      if (parts[0] === 'file' && parts.length === 3) {
        return `https://cdn.sanity.io/files/p/production/${parts[1]}.${parts[2]}`
      }
      return null
    },
  }
}

/** Calls the handler and returns {status, headers, json, text}. */
async function call(app, {method = 'GET', path = '/', token, body} = {}) {
  const chunks = body === undefined ? [] : [Buffer.from(JSON.stringify(body))]
  const req = {
    method,
    url: path,
    headers: {host: 'localhost', ...(token ? {authorization: `Bearer ${token}`} : {})},
    async *[Symbol.asyncIterator]() {
      for (const c of chunks) yield c
    },
  }

  let status = 0
  let headers = {}
  let text = ''
  const res = {
    setHeader() {},
    writeHead(code, h) {
      status = code
      headers = h ?? {}
    },
    end(payload) {
      text = payload ?? ''
    },
  }

  await app(req, res)
  let json = null
  try {
    json = JSON.parse(text)
  } catch {
    /* html */
  }
  return {status, headers, json, text}
}

function build(data, decisionsFile = CONFIG.decisionsPath) {
  const client = stubClient(data)
  const decisions = openDecisions(decisionsFile)
  const config = {...CONFIG, decisionsPath: decisionsFile}
  return {app: createApp({config, client, decisions}), client, decisions, config}
}

// --- ids --------------------------------------------------------------------

console.log('\nids')
check('a variant id is document + __ + key', () => {
  assert.equal(variantId('drafts.post-8f21', 'ig'), 'drafts.post-8f21__ig')
})
check('and splits on the LAST __', () => {
  assert.deepEqual(splitVariantId('drafts.post__odd__ig'), {
    documentId: 'drafts.post__odd',
    variantKey: 'ig',
  })
})
check('a document id keeps its dot', () => {
  assert.equal(splitVariantId('drafts.post-8f21__ig').documentId, 'drafts.post-8f21')
})
check('something that is not an id is rejected', () => {
  assert.equal(splitVariantId('no-separator-here'), null)
  assert.equal(splitVariantId('__leading'), null)
  assert.equal(splitVariantId('trailing__'), null)
})

// --- the queue ---------------------------------------------------------------

console.log('\nGET /api/posts/pending')

const QUEUE = {
  posts: [
    post('p1', [variant('ig', 'instagram', 'needs_review'), variant('tt', 'tiktok', 'draft')]),
    post('p2', [variant('ig', 'instagram', 'published')]),
    post('p3', [variant('ig', 'instagram', 'approved')]),
  ],
  accounts: ACCOUNTS,
}

await checkAsync('it needs a bearer token', async () => {
  const {app} = build(QUEUE, join(work, 'd1.jsonl'))
  const res = await call(app, {path: '/api/posts/pending'})
  assert.equal(res.status, 401)
  assert.equal(res.json.error, 'a bearer token is required')
})

await checkAsync('a wrong token is refused', async () => {
  const {app} = build(QUEUE, join(work, 'd1.jsonl'))
  const res = await call(app, {path: '/api/posts/pending', token: 'nope'})
  assert.equal(res.status, 401)
})

await checkAsync('it answers JSON, with a JSON content type', async () => {
  const {app} = build(QUEUE, join(work, 'd1.jsonl'))
  const res = await call(app, {path: '/api/posts/pending', token: CONFIG.token})
  assert.equal(res.status, 200)
  assert.match(res.headers['Content-Type'], /application\/json/)
  assert.ok(Array.isArray(res.json.posts))
})

await checkAsync('one row per variant awaiting a decision, not one per post', async () => {
  const {app} = build(QUEUE, join(work, 'd1.jsonl'))
  const {json} = await call(app, {path: '/api/posts/pending', token: CONFIG.token})
  assert.deepEqual(
    json.posts.map((p) => p.id),
    ['p1__ig', 'p1__tt'],
  )
})

await checkAsync('published and approved variants are not awaiting anything', async () => {
  const {app} = build(QUEUE, join(work, 'd1.jsonl'))
  const {json} = await call(app, {path: '/api/posts/pending', token: CONFIG.token})
  assert.ok(!json.posts.some((p) => p.id.startsWith('p2') || p.id.startsWith('p3')))
})

await checkAsync('every row carries a verdict', async () => {
  const {app} = build(QUEUE, join(work, 'd1.jsonl'))
  const {json} = await call(app, {path: '/api/posts/pending', token: CONFIG.token})
  for (const row of json.posts) {
    assert.ok(row.verdict, `${row.id} has no verdict`)
    assert.equal(typeof row.verdict.ok, 'boolean')
    assert.ok(Array.isArray(row.verdict.errors))
    assert.ok(Array.isArray(row.verdict.warnings))
  }
})

await checkAsync('the verdict is the Studio gate: a too-long caption blocks', async () => {
  const data = {
    posts: [post('p9', [variant('ig', 'instagram', 'needs_review', {caption: 'x'.repeat(2500)})])],
    accounts: ACCOUNTS,
  }
  const {app} = build(data, join(work, 'd2.jsonl'))
  const {json} = await call(app, {path: '/api/posts/pending', token: CONFIG.token})
  assert.equal(json.posts[0].verdict.ok, false)
  assert.match(json.posts[0].verdict.errors[0].message, /2500 characters; Instagram allows 2200/)
})

await checkAsync('an incomplete product blocks every platform', async () => {
  const data = {
    posts: [
      post('p10', [variant('ig', 'instagram', 'needs_review')], {
        products: [{_id: 'x', title: 'Flare Tee', storeId: 412, incomplete: ['a price']}],
      }),
    ],
    accounts: ACCOUNTS,
  }
  const {app} = build(data, join(work, 'd3.jsonl'))
  const {json} = await call(app, {path: '/api/posts/pending', token: CONFIG.token})
  assert.equal(json.posts[0].verdict.ok, false)
  assert.match(json.posts[0].verdict.errors[0].message, /Flare Tee is missing a price/)
  assert.deepEqual(json.posts[0].products, [{store_id: 412, title: 'Flare Tee'}])
})

await checkAsync('a disabled platform account counts as no account', async () => {
  const data = {
    posts: [post('p11', [variant('li', 'linkedin', 'needs_review', {format: 'text', assets: []})])],
    accounts: ACCOUNTS,
  }
  const {app} = build(data, join(work, 'd4.jsonl'))
  const {json} = await call(app, {path: '/api/posts/pending', token: CONFIG.token})
  assert.ok(json.posts[0].verdict.errors.some((e) => /No LinkedIn account is configured/.test(e.message)))
})

await checkAsync('the draft is shown and the published copy dropped', async () => {
  const data = {
    posts: [
      post('drafts.p1', [variant('ig', 'instagram', 'needs_review', {caption: 'Newer text. #uv'})]),
      post('p1', [variant('ig', 'instagram', 'needs_review', {caption: 'Older text. #uv'})]),
    ],
    accounts: ACCOUNTS,
  }
  const {app} = build(data, join(work, 'd5.jsonl'))
  const {json} = await call(app, {path: '/api/posts/pending', token: CONFIG.token})
  assert.equal(json.posts.length, 1)
  assert.equal(json.posts[0].id, 'drafts.p1__ig')
  assert.equal(json.posts[0].caption, 'Newer text. #uv')
})

await checkAsync('the asset becomes a CDN url and a kind', async () => {
  const {app} = build(QUEUE, join(work, 'd6.jsonl'))
  const {json} = await call(app, {path: '/api/posts/pending', token: CONFIG.token})
  assert.equal(json.posts[0].asset_url, 'https://cdn.sanity.io/images/p/production/abc123-1080x1350.jpg')
  assert.equal(json.posts[0].asset_kind, 'image')
})

await checkAsync('a video asset is marked as one', async () => {
  const data = {
    posts: [
      post('p12', [
        variant('tt', 'tiktok', 'needs_review', {
          format: 'video',
          assets: [{_key: 'v', _type: 'file', ref: 'file-def456-mp4', meta: {mimeType: 'video/mp4'}}],
        }),
      ]),
    ],
    accounts: ACCOUNTS,
  }
  const {app} = build(data, join(work, 'd7.jsonl'))
  const {json} = await call(app, {path: '/api/posts/pending', token: CONFIG.token})
  assert.equal(json.posts[0].asset_kind, 'video')
  assert.equal(json.posts[0].asset_url, 'https://cdn.sanity.io/files/p/production/def456.mp4')
})

await checkAsync('a decided variant leaves the queue', async () => {
  const file = join(work, 'd8.jsonl')
  const {app, decisions} = build(QUEUE, file)
  decisions.record({id: 'p1__ig', decision: 'approved', actor: 'anna@example.com'})
  const {json} = await call(app, {path: '/api/posts/pending', token: CONFIG.token})
  assert.deepEqual(
    json.posts.map((p) => p.id),
    ['p1__tt'],
  )
})

// --- decisions ---------------------------------------------------------------

console.log('\nPOST /api/posts/{id}/decision')

await checkAsync('a bad decision word is refused before anything is written', async () => {
  const file = join(work, 'd9.jsonl')
  const {app, client} = build(QUEUE, file)
  const res = await call(app, {
    method: 'POST',
    path: '/api/posts/p1__ig/decision',
    token: CONFIG.token,
    body: {decision: 'maybe', actor: 'anna@example.com'},
  })
  assert.equal(res.status, 400)
  assert.equal(client.mutations.length, 0)
})

await checkAsync('an id that names no variant is refused', async () => {
  const {app} = build(QUEUE, join(work, 'd10.jsonl'))
  const res = await call(app, {
    method: 'POST',
    path: '/api/posts/nonsense/decision',
    token: CONFIG.token,
    body: {decision: 'approved', actor: 'anna@example.com'},
  })
  assert.equal(res.status, 400)
  assert.match(res.json.error, /does not name a variant/)
})

await checkAsync('approving a clean variant records who and when', async () => {
  const file = join(work, 'd11.jsonl')
  const {app, decisions} = build(QUEUE, file)
  const res = await call(app, {
    method: 'POST',
    path: '/api/posts/p1__ig/decision',
    token: CONFIG.token,
    body: {decision: 'approved', actor: 'anna@example.com'},
  })
  assert.equal(res.status, 200)
  assert.equal(res.json.decision.actor, 'anna@example.com')
  assert.ok(res.json.decision.at)
  assert.equal(decisions.get('p1__ig').decision, 'approved')
})

await checkAsync('approving does NOT move the variant status', async () => {
  const file = join(work, 'd12.jsonl')
  const {app, client} = build(QUEUE, file)
  await call(app, {
    method: 'POST',
    path: '/api/posts/p1__ig/decision',
    token: CONFIG.token,
    body: {decision: 'approved', actor: 'anna@example.com'},
  })
  assert.equal(client.mutations.length, 0, 'approving wrote to the CMS')
})

await checkAsync('a stale approval is refused with the reason', async () => {
  // The queue said fine; the CMS now says the product has no price.
  const data = {
    posts: [
      post('p13', [variant('ig', 'instagram', 'needs_review')], {
        products: [{_id: 'x', title: 'Flare Tee', storeId: 412, incomplete: ['a price']}],
      }),
    ],
    accounts: ACCOUNTS,
  }
  const file = join(work, 'd13.jsonl')
  const {app, decisions} = build(data, file)
  const res = await call(app, {
    method: 'POST',
    path: '/api/posts/p13__ig/decision',
    token: CONFIG.token,
    body: {decision: 'approved', actor: 'anna@example.com'},
  })
  assert.equal(res.status, 409)
  assert.match(res.json.error, /Instagram cannot be approved: Flare Tee is missing a price/)
  assert.equal(decisions.has('p13__ig'), false, 'it recorded a decision it refused')
})

await checkAsync('a blocked variant can still be rejected', async () => {
  const data = {
    posts: [
      post('p14', [variant('ig', 'instagram', 'needs_review')], {
        products: [{_id: 'x', title: 'Flare Tee', storeId: 412, incomplete: ['a price']}],
      }),
    ],
    accounts: ACCOUNTS,
  }
  const file = join(work, 'd14.jsonl')
  const {app, client} = build(data, file)
  const res = await call(app, {
    method: 'POST',
    path: '/api/posts/p14__ig/decision',
    token: CONFIG.token,
    body: {decision: 'rejected', actor: 'anna@example.com', note: 'wrong photo'},
  })
  assert.equal(res.status, 200)
  assert.equal(res.json.decision.note, 'wrong photo')
  assert.equal(res.json.handed_back, true)
  assert.equal(client.mutations[0].patch.set['variants[_key=="ig"].status'], 'draft')
})

await checkAsync('rejecting something already a draft writes no patch', async () => {
  const file = join(work, 'd15.jsonl')
  const {app, client} = build(QUEUE, file)
  const res = await call(app, {
    method: 'POST',
    path: '/api/posts/p1__tt/decision',
    token: CONFIG.token,
    body: {decision: 'rejected', actor: 'anna@example.com'},
  })
  assert.equal(res.status, 200)
  assert.equal(res.json.handed_back, false)
  assert.equal(client.mutations.length, 0)
})

await checkAsync('the same decision twice records once', async () => {
  const file = join(work, 'd16.jsonl')
  const {app, decisions} = build(QUEUE, file)
  const body = {decision: 'approved', actor: 'anna@example.com'}
  const first = await call(app, {method: 'POST', path: '/api/posts/p1__ig/decision', token: CONFIG.token, body})
  const second = await call(app, {method: 'POST', path: '/api/posts/p1__ig/decision', token: CONFIG.token, body})
  assert.equal(first.status, 200)
  assert.equal(second.status, 200)
  assert.equal(second.json.repeated, true)
  assert.equal(first.json.decision.at, second.json.decision.at, 'the second one re-timestamped it')
  assert.equal(decisions.size, 1)
})

await checkAsync('a decision survives a restart', async () => {
  const file = join(work, 'd17.jsonl')
  const first = build(QUEUE, file)
  await call(first.app, {
    method: 'POST',
    path: '/api/posts/p1__ig/decision',
    token: CONFIG.token,
    body: {decision: 'approved', actor: 'anna@example.com'},
  })
  const second = build(QUEUE, file) // re-reads the file, as a restart would
  const {json} = await call(second.app, {path: '/api/posts/pending', token: CONFIG.token})
  assert.deepEqual(
    json.posts.map((p) => p.id),
    ['p1__tt'],
  )
})

await checkAsync('a variant that has left the CMS records nothing', async () => {
  const file = join(work, 'd18.jsonl')
  const {app, decisions} = build(QUEUE, file)
  const res = await call(app, {
    method: 'POST',
    path: '/api/posts/p1__gone/decision',
    token: CONFIG.token,
    body: {decision: 'approved', actor: 'anna@example.com'},
  })
  assert.equal(res.status, 404)
  assert.equal(decisions.has('p1__gone'), false)
})

// --- previews -----------------------------------------------------------------

console.log('\nGET /preview')

await checkAsync('rows advertise a signed preview url', async () => {
  const {app} = build(QUEUE, join(work, 'd19.jsonl'))
  const {json} = await call(app, {path: '/api/posts/pending', token: CONFIG.token})
  const url = new URL(json.posts[0].preview_url)
  assert.equal(url.origin + url.pathname, CONFIG.publicUrl)
  assert.ok(url.searchParams.get('sig'))
  assert.ok(Number(url.searchParams.get('exp')) > Date.now() / 1000)
})

await checkAsync('no public url means no preview_url, and the store falls back', async () => {
  const client = stubClient(QUEUE)
  const decisions = openDecisions(join(work, 'd20.jsonl'))
  const app = createApp({config: {...CONFIG, publicUrl: '', decisionsPath: join(work, 'd20.jsonl')}, client, decisions})
  const {json} = await call(app, {path: '/api/posts/pending', token: CONFIG.token})
  assert.equal(json.posts[0].preview_url, null)
  assert.ok(json.posts[0].asset_url)
})

await checkAsync('a valid link renders the caption', async () => {
  const {app} = build(QUEUE, join(work, 'd21.jsonl'))
  const url = new URL(previewUrl('p1__ig', CONFIG))
  const res = await call(app, {path: `/preview?${url.searchParams}`})
  assert.equal(res.status, 200)
  assert.match(res.headers['Content-Type'], /text\/html/)
  assert.match(res.text, /Glow up tonight/)
})

await checkAsync('it needs no bearer token, because an iframe sends none', async () => {
  const {app} = build(QUEUE, join(work, 'd22.jsonl'))
  const url = new URL(previewUrl('p1__ig', CONFIG))
  const res = await call(app, {path: `/preview?${url.searchParams}`})
  assert.equal(res.status, 200)
})

await checkAsync('a tampered id is refused', async () => {
  const {app} = build(QUEUE, join(work, 'd23.jsonl'))
  const url = new URL(previewUrl('p1__ig', CONFIG))
  url.searchParams.set('id', 'p1__tt')
  const res = await call(app, {path: `/preview?${url.searchParams}`})
  assert.equal(res.status, 403)
})

await checkAsync('an extended expiry is refused, because the expiry is signed too', async () => {
  const {app} = build(QUEUE, join(work, 'd24.jsonl'))
  const url = new URL(previewUrl('p1__ig', CONFIG))
  url.searchParams.set('exp', String(Math.floor(Date.now() / 1000) + 99999))
  const res = await call(app, {path: `/preview?${url.searchParams}`})
  assert.equal(res.status, 403)
})

await checkAsync('an expired link says so', async () => {
  const {app, config} = build(QUEUE, join(work, 'd25.jsonl'))
  const expired = {...config, previewTtl: -10}
  const url = new URL(previewUrl('p1__ig', expired).replace('-10', ''))
  // Build it by hand: previewUrl refuses to make a negative TTL readable.
  const past = Math.floor(Date.now() / 1000) - 10
  const {createHmac} = await import('node:crypto')
  const sig = createHmac('sha256', CONFIG.previewSecret).update(`p1__ig.${past}`).digest('base64url')
  const res = await call(app, {path: `/preview?id=p1__ig&exp=${past}&sig=${sig}`})
  assert.equal(res.status, 410)
  assert.match(res.text, /expired/)
  void url
})

await checkAsync('an unsigned link is refused', async () => {
  const {app} = build(QUEUE, join(work, 'd26.jsonl'))
  const res = await call(app, {path: '/preview?id=p1__ig'})
  assert.equal(res.status, 403)
})

await checkAsync('the preview escapes what it renders', async () => {
  const data = {
    posts: [
      post('p15', [variant('ig', 'instagram', 'needs_review', {caption: '<script>alert(1)</script>'})]),
    ],
    accounts: ACCOUNTS,
  }
  const {app} = build(data, join(work, 'd27.jsonl'))
  const url = new URL(previewUrl('p15__ig', CONFIG))
  const res = await call(app, {path: `/preview?${url.searchParams}`})
  assert.ok(!res.text.includes('<script>alert(1)</script>'))
  assert.match(res.text, /&lt;script&gt;/)
})

// --- misc ---------------------------------------------------------------------

console.log('\nother')

await checkAsync('health needs no token and leaks nothing', async () => {
  const {app} = build(QUEUE, join(work, 'd28.jsonl'))
  const res = await call(app, {path: '/healthz'})
  assert.equal(res.status, 200)
  assert.equal(res.json.ok, true)
})

await checkAsync('an unknown api route is a JSON 404, not HTML', async () => {
  const {app} = build(QUEUE, join(work, 'd29.jsonl'))
  const res = await call(app, {path: '/api/nope', token: CONFIG.token})
  assert.equal(res.status, 404)
  assert.match(res.headers['Content-Type'], /application\/json/)
})

await checkAsync('an upstream failure is a 502 saying what happened', async () => {
  const {SanityError} = await import('../sanity.mjs')
  const client = {
    async query() {
      throw new SanityError('Sanity returned 401 — SANITY_API_TOKEN is missing, expired or wrong')
    },
    assetUrl: () => null,
    async mutate() {},
  }
  const decisions = openDecisions(join(work, 'd30.jsonl'))
  const app = createApp({config: CONFIG, client, decisions})
  const res = await call(app, {path: '/api/posts/pending', token: CONFIG.token})
  assert.equal(res.status, 502)
  assert.match(res.json.error, /SANITY_API_TOKEN/)
})

// --- report --------------------------------------------------------------------

rmSync(work, {recursive: true, force: true})

console.log()
if (failures.length) {
  console.error(`${failures.length} FAILED, ${passed} passed:\n`)
  for (const f of failures) console.error(`  ✗ ${f}`)
  process.exit(1)
}
console.log(`publisher: ${passed} assertions passed`)
