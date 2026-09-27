/**
 * The seasonal draft agent: Claude reads the shop through Sanity Context and
 * proposes posts for the season ahead.
 *
 *   npm run draft                     propose drafts, print them, write nothing
 *   npm run draft -- --weeks 10       look further ahead (default 8)
 *   npm run draft -- --max 3          fewer proposals (default 5)
 *   npm run draft -- --write          also create them as drafts for review
 *   npm run draft -- --no-cache       no prompt caching, to compare cost and speed
 *
 * Without --write it only prints. With it, each proposal is checked against the
 * dataset as it is now (planAgentDrafts) and what passes is created as a draft
 * post at needs_review, where it reaches the store's queue like any other. Every
 * run, written or not, is appended to data/agent-runs.jsonl with its sources.
 *
 * The tool loop runs here rather than through the API's MCP connector, so the
 * Context token never leaves this machine: Claude asks for a tool, this process
 * calls Sanity Context and hands back what it said. Context is read-only, and
 * the only other tool Claude has is `submit_drafts`, which ends the run.
 *
 * Tool names are prefixed by the endpoint they go to, because both serve an
 * `initial_context`: `shop__` is products and campaigns, `kb__` the Knowledge
 * Base (the website and the vault notes).
 */
import {appendFileSync, mkdirSync} from 'node:fs'
import {dirname} from 'node:path'
import {connect} from './context.mjs'
import {key, ref} from './generate.mjs'
import {preflight} from './vendor/preflight.js'
import {publishedId} from './ids.mjs'

const MODEL = 'claude-opus-5'
const MAX_TURNS = 25
// Days before an occasion a made-to-order item must be ordered to arrive in time.
const LEAD_DAYS = 21
const HOLIDAY_LEAD_DAYS = 30

const ENDPOINTS = [
  {prefix: 'shop', env: 'SANITY_CONTEXT_MCP_URL', what: 'the shop dataset: products, campaigns, and knowledgeNote documents including the Events and Holidays and Occasions calendar'},
  {prefix: 'kb', env: 'SANITY_CONTEXT_KB_URL', what: 'the Knowledge Base: the everfluorescent website, brand voice and supplier notes'},
]

const SUBMIT_DRAFTS = {
  name: 'submit_drafts',
  description:
    'Submit the proposed posts. Call this exactly once, when you are done researching. Every factual claim in a caption must come from a source listed on that draft.',
  strict: true,
  input_schema: {
    type: 'object',
    additionalProperties: false,
    required: ['season', 'seasonKey', 'drafts'],
    properties: {
      season: {type: 'string', description: 'The season or occasion these posts are for, and its dates, as the calendar gives them.'},
      seasonKey: {type: 'string', description: 'A short lowercase slug naming the season and year, e.g. "fall-2026" or "halloween-2026". The same season must always get the same key.'},
      drafts: {
        type: 'array',
        items: {
          type: 'object',
          additionalProperties: false,
          required: ['productId', 'productTitle', 'angle', 'hook', 'instagram', 'facebook', 'sources', 'conflicts'],
          properties: {
            productId: {type: 'string', description: 'The product document _id, exactly as the dataset has it.'},
            productTitle: {type: 'string'},
            angle: {type: 'string', description: 'One sentence: why this product, for this season.'},
            hook: {type: 'string', description: 'The post title: 5 words or fewer, describing this product.'},
            instagram: {type: 'string', description: 'Hook, at most two short sentences, "Link in bio", at most three hashtags.'},
            facebook: {type: 'string', description: 'Hook, at most two short sentences, then the product store URL.'},
            sources: {
              type: 'array',
              description: 'Every document or Knowledge Base entry a claim in the captions rests on.',
              items: {
                type: 'object',
                additionalProperties: false,
                required: ['title', 'ref'],
                properties: {
                  title: {type: 'string'},
                  ref: {type: 'string', description: 'A document _id, or the Knowledge Base path or source URL.'},
                },
              },
            },
            conflicts: {
              type: 'array',
              description: 'Where two sources disagreed about something the captions touch: both claims, both sources, and which the caption follows and why. Empty when none.',
              items: {type: 'string'},
            },
          },
        },
      },
    },
  },
}

export function systemPrompt({today, weeks, max}) {
  return `You draft social posts for everfluorescent, a shop selling fluorescent and UV-reactive clothing and goods. A person reviews every draft before anything is posted, so a wrong claim costs their time and trust.

Today is ${today}. Find the season or occasion in the next ${weeks} weeks that the calendar says to post for, then choose up to ${max} products that suit it and propose one post for each, with an Instagram and a Facebook caption.

How to work:
- The calendar is two knowledgeNote documents in the shop dataset, titled "Events" (festivals, kind "event") and "Holidays and Occasions" (kind "seasonal"). Read them with a GROQ query on the shop endpoint, e.g. *[_type == "knowledgeNote" && title in ["Events", "Holidays and Occasions"] && archived != true]{_id, title, body}, and cite them by _id. Ignore the older notes "Festivals and markets, 2026" and "Returns, shipping and turnaround": they are empty templates from an earlier sync. The season dates in the Context instructions only say which season it is; an occasion's date comes from the calendar. A holiday listed without a year is this year's, or next year's if it has passed.
- Start with the calendar, then the Knowledge Base for brand voice, product details and any supplier or restock notes. Then query the shop dataset for products and campaigns.
- Only propose products that are active in the store and have at least one image.
- Every fact in a caption (price, availability, shipping or delivery timing, materials, how or under what light it glows) must come from a source you read, and that source goes in the draft's sources.
- A size range in a caption must match the sizes in the product's variants, not only its description: the description is written once and the variants are what can actually be bought.
- When sources disagree about something a caption touches, record it in conflicts with both claims and both sources, and write the caption so it does not state the disputed claim.
- Write in the brand voice the notes describe. No invented discounts, dates or promises.

Order-by dates. Everything is made to order, so a customer must order at least ${LEAD_DAYS} days before the occasion for it to arrive in time, or ${HOLIDAY_LEAD_DAYS} days for Christmas and New Year's. Using the occasion's date from the calendar:
- Work out the last safe order date (the occasion's date minus the lead time) and put it in both captions, e.g. "Order by Oct 9 for Halloween". Cite the calendar entry the date came from.
- If that date is before today, the occasion is too close: choose a later one instead.
- If the calendar gives no date for the occasion, leave the order-by date out rather than guess one.

Keep every post brief and upbeat, to get people excited about the product:
- A hook of 5 words or fewer. It opens both captions, and the post's image is the product's photo, so the hook must describe that product.
- After the hook, at most two short sentences: the one or two things that make this product exciting now. Not a spec sheet: no fabric percentages, weights or care instructions unless one of them is the point.
- Instagram ends with "Link in bio" and at most three hashtags. Facebook ends with the product's store URL.
- Only products that suit the season. A swimsuit is not fall clothing.

When you have the drafts, call submit_drafts once.`
}

/** MCP tool definitions → Messages API tools, named by endpoint. */
export function toApiTools(prefix, mcpTools) {
  return mcpTools.map((tool) => ({
    name: `${prefix}__${tool.name}`,
    description: tool.description ?? '',
    input_schema: tool.inputSchema ?? {type: 'object', properties: {}},
  }))
}

/** Split `shop__groq_query` back into its endpoint and tool. */
export function routeToolName(name) {
  const at = name.indexOf('__')
  return at < 0 ? null : {prefix: name.slice(0, at), tool: name.slice(at + 2)}
}

function mcpResultText(result) {
  return (result?.content ?? []).map((c) => (c.type === 'text' ? c.text : `[${c.type} omitted]`)).join('\n')
}

async function callClaude(body) {
  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': process.env.ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01',
      // A declined request is re-run server-side on the model Anthropic
      // recommends for that category, instead of coming back as a refusal.
      'anthropic-beta': 'server-side-fallback-2026-07-01',
      // Only for a key not scoped to a workspace, which must name one.
      ...(process.env.ANTHROPIC_WORKSPACE_ID?.trim() ? {'anthropic-workspace-id': process.env.ANTHROPIC_WORKSPACE_ID.trim()} : {}),
    },
    body: JSON.stringify({fallbacks: 'default', ...body}),
    signal: AbortSignal.timeout(10 * 60_000),
  })
  const payload = await response.json().catch(() => null)
  if (!response.ok) {
    const detail = payload?.error?.message ?? `HTTP ${response.status}`
    const hint = response.status === 401 ? ' — ANTHROPIC_API_KEY is missing or wrong' : ''
    throw new Error(`Claude: ${detail}${hint}`)
  }
  return payload
}

/**
 * Products that already have a post of any kind. The Context endpoint cannot
 * see posts, so without this the agent proposes products that planAgentDrafts
 * would only skip afterwards, and the tokens spent on them are wasted.
 */
export async function productsWithPosts(client) {
  return client.query(
    `*[_type == "product" && _id in array::unique(*[_type == "post"].products[]._ref)]{_id, title} | order(title asc)`,
  )
}

export function userMessage(today, exclude = []) {
  const lines = [`Propose the posts for the season ahead. Today is ${today}.`]
  if (exclude.length) {
    lines.push('', 'These products already have a post. Do not propose them:', ...exclude.map((p) => `- ${p.title} (${p._id})`))
  }
  return lines.join('\n')
}

export async function runAgent({today, weeks = 8, max = 5, exclude = [], cache = true, log = () => {}} = {}) {
  const token = process.env.SANITY_CONTEXT_TOKEN?.trim()
  const missing = ['ANTHROPIC_API_KEY', 'SANITY_CONTEXT_TOKEN', ...ENDPOINTS.map((e) => e.env)].filter((k) => !process.env[k]?.trim())
  if (missing.length) throw new Error(`Not configured. Missing in publisher/.env: ${missing.join(', ')}`)

  const clients = {}
  const tools = []
  for (const endpoint of ENDPOINTS) {
    const client = connect(process.env[endpoint.env].trim(), token)
    await client.initialize()
    clients[endpoint.prefix] = client
    for (const tool of toApiTools(endpoint.prefix, await client.listTools())) {
      tools.push({...tool, description: `[${endpoint.what}] ${tool.description}`})
    }
  }
  tools.push(SUBMIT_DRAFTS)

  const messages = [{role: 'user', content: userMessage(today, exclude)}]
  const usage = {input: 0, cacheWrite: 0, cacheRead: 0, output: 0}
  // Every turn resends everything before it. The marker on the system prompt
  // caches tools + instructions (the part that never changes within a run), and
  // the top-level cache_control moves a second breakpoint to the end of the
  // conversation each turn, so turn N reads turns 1..N-1 at a tenth of the price.
  // --no-cache drops both markers, to measure what caching saves.
  const cacheMarker = cache ? {cache_control: {type: 'ephemeral'}} : {}
  const system = [{type: 'text', text: systemPrompt({today, weeks, max}), ...cacheMarker}]

  for (let turn = 1; turn <= MAX_TURNS; turn++) {
    const started = performance.now()
    const response = await callClaude({
      model: MODEL,
      max_tokens: 16000,
      thinking: {type: 'adaptive'},
      system,
      ...cacheMarker,
      tools,
      messages,
    })
    usage.input += response.usage?.input_tokens ?? 0
    usage.cacheWrite += response.usage?.cache_creation_input_tokens ?? 0
    usage.cacheRead += response.usage?.cache_read_input_tokens ?? 0
    usage.output += response.usage?.output_tokens ?? 0
    // One line per request, so cache hits can be read against how long it took.
    const u = response.usage ?? {}
    log(`  [turn ${turn}] ${((performance.now() - started) / 1000).toFixed(1)}s — ${u.input_tokens ?? 0} in, ${u.cache_creation_input_tokens ?? 0} cache-write, ${u.cache_read_input_tokens ?? 0} cache-read, ${u.output_tokens ?? 0} out`)

    if (response.stop_reason === 'refusal') throw new Error('Claude declined the request, and the fallback model did too.')
    if (response.stop_reason === 'max_tokens') throw new Error('Claude ran out of output room mid-turn; nothing was submitted.')

    // The whole content goes back, thinking blocks included, so the next turn
    // continues from exactly what the model produced.
    messages.push({role: 'assistant', content: response.content})

    const calls = response.content.filter((block) => block.type === 'tool_use')
    const submitted = calls.find((call) => call.name === SUBMIT_DRAFTS.name)
    if (submitted) return {...submitted.input, usage, turns: turn}
    if (!calls.length) throw new Error('Claude stopped without calling submit_drafts.')

    // Every result goes back in one message, errors included, so parallel
    // calls stay parallel and a failed read is something Claude can react to.
    const results = await Promise.all(
      calls.map(async (call) => {
        const route = routeToolName(call.name)
        const client = route && clients[route.prefix]
        log(`  ${call.name} ${JSON.stringify(call.input).slice(0, 140)}`)
        if (!client) return {type: 'tool_result', tool_use_id: call.id, is_error: true, content: `No such tool: ${call.name}`}
        try {
          const result = await client.callTool(route.tool, call.input)
          return {type: 'tool_result', tool_use_id: call.id, is_error: Boolean(result?.isError), content: mcpResultText(result) || '(empty)'}
        } catch (error) {
          return {type: 'tool_result', tool_use_id: call.id, is_error: true, content: error.message}
        }
      }),
    )
    messages.push({role: 'user', content: results})
  }
  throw new Error(`No drafts after ${MAX_TURNS} turns.`)
}

// ---------------------------------------------------------------------------
// Writing. Claude proposes; this decides. Everything a proposal claims about a
// product is checked against the dataset as it is now, not as the model read it.

const PLATFORMS = ['instagram', 'facebook']
const MAX_HOOK_WORDS = 5

const WRITE_QUERY = `
{
  "products": *[_type == "product" && _id in $ids]{
    _id, title, storeUrl, storeStatus, incomplete,
    "image": images[0].asset._ref,
    "meta": images[0].asset->{mimeType, originalFilename, metadata{dimensions}}
  },
  "posts": *[_type == "post" && references($ids)]{_id, "products": products[]._ref}
}
`

/** A Sanity-id-safe slug. The season key comes from the model, so it is cleaned, not trusted. */
export function slug(text) {
  return String(text ?? '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 40)
}

export function agentPostId(seasonKey, productId) {
  return `agent-${slug(seasonKey) || 'season'}-${String(productId).replace(/[^a-zA-Z0-9_-]/g, '-')}`
}

/** "fall-2026" → "Fall 2026", for the post title. */
export function seasonLabel(seasonKey) {
  return (slug(seasonKey) || 'season').split('-').map((w) => w[0].toUpperCase() + w.slice(1)).join(' ')
}

const words = (text) => String(text ?? '').trim().split(/\s+/).filter(Boolean).length

/**
 * Decide what to create. Pure: no network, so it is what the tests exercise.
 * Returns {create: [document], skipped: [{product, reason}]}.
 */
export function planAgentDrafts(proposal, data) {
  const create = []
  const skipped = []
  const products = new Map((data?.products ?? []).map((p) => [p._id, p]))

  // A product with any post already — generated from a campaign, made by hand,
  // or drafted by an earlier run — is left alone, so the queue never holds two
  // posts for one product.
  const covered = new Set()
  for (const post of data?.posts ?? []) {
    covered.add(publishedId(post._id))
    for (const id of post.products ?? []) covered.add(id)
  }

  for (const draft of proposal?.drafts ?? []) {
    const name = draft.productTitle || draft.productId
    const skip = (reason) => skipped.push({product: name, reason})
    const product = products.get(draft.productId)
    const id = agentPostId(proposal.seasonKey, draft.productId)

    if (!product) { skip(`no product ${draft.productId} in the dataset`); continue }
    if (covered.has(product._id) || covered.has(id)) { skip('it already has a post'); continue }
    if (product.storeStatus && product.storeStatus !== 'active') { skip(`it is ${product.storeStatus} in the store`); continue }
    if (!product.image) { skip('it has no image'); continue }
    if (words(draft.hook) > MAX_HOOK_WORDS) { skip(`the hook "${draft.hook}" is ${words(draft.hook)} words; the limit is ${MAX_HOOK_WORDS}`); continue }

    // The caption checks are the model's to pass, so a failure stops the write.
    // Anything else preflight finds (image ratio, accounts) is the same for a
    // hand-made post, and shows in the queue's verdict as it would for one.
    const captionErrors = PLATFORMS.flatMap((platform) =>
      preflight({
        platform,
        format: 'feed_image',
        caption: draft[platform] ?? '',
        assets: [],
        products: [],
        accountConfigured: true,
        accountAudited: true,
      })
        .errors.filter((issue) => issue.field === 'caption')
        .map((issue) => `${platform}: ${issue.message}`),
    )
    if (captionErrors.length) { skip(captionErrors.join('; ')); continue }

    create.push({
      _id: `drafts.${id}`,
      _type: 'post',
      title: `${seasonLabel(proposal.seasonKey)}: ${product.title.trim()}`,
      products: [{_key: key(), ...ref(product._id, 'product')}],
      hook: draft.hook,
      body: draft.angle,
      cta: 'Shop now',
      link: product.storeUrl ?? undefined,
      variants: PLATFORMS.map((platform) => ({
        _key: key(),
        _type: 'variant',
        platform,
        format: 'feed_image',
        caption: draft[platform],
        status: 'needs_review',
        assets: [{_key: key(), _type: 'image', asset: {_type: 'reference', _ref: product.image}}],
      })),
    })
  }

  return {create, skipped}
}

/**
 * Check the proposal against the dataset and create what passes, as drafts at
 * needs_review. createIfNotExists: a post that exists is never touched, so a
 * caption rewritten in the Studio is never overwritten by a later run.
 */
export async function writeAgentDrafts(client, proposal) {
  const ids = [...new Set((proposal.drafts ?? []).map((d) => d.productId))]
  const plan = planAgentDrafts(proposal, await client.query(WRITE_QUERY, {ids}))
  if (plan.create.length) await client.mutate(plan.create.map((doc) => ({createIfNotExists: doc})))
  return plan
}

/**
 * The sources and conflicts behind each draft have no field on a post yet
 * (that is Step 5), so each run is kept here, one JSON line per run.
 */
export function recordRun(path, proposal, plan) {
  mkdirSync(dirname(path), {recursive: true})
  appendFileSync(path, `${JSON.stringify({at: new Date().toISOString(), proposal, written: plan?.create.map((d) => d._id) ?? [], skipped: plan?.skipped ?? []})}\n`)
}

/** Token counts and what they cost at Opus 5 list prices ($5 in, $25 out per MTok). */
export function tokens({input, cacheWrite, cacheRead, output}) {
  const dollars = (input * 5 + cacheWrite * 6.25 + cacheRead * 0.5 + output * 25) / 1e6
  return `${input} input + ${cacheWrite} cache-write + ${cacheRead} cache-read / ${output} output tokens (~$${dollars.toFixed(2)})`
}

export function formatProposal(proposal) {
  const lines = [`Season: ${proposal.season}`, '']
  for (const [i, d] of proposal.drafts.entries()) {
    lines.push(`${i + 1}. ${d.productTitle}  (${d.productId})`, `   Hook: ${d.hook}`, `   ${d.angle}`, '')
    lines.push('   Instagram:', ...d.instagram.split('\n').map((l) => `     ${l}`), '')
    lines.push('   Facebook:', ...d.facebook.split('\n').map((l) => `     ${l}`), '')
    lines.push('   Sources:', ...d.sources.map((s) => `     - ${s.title} (${s.ref})`))
    if (d.conflicts.length) lines.push('   Conflicts:', ...d.conflicts.map((c) => `     ! ${c}`))
    lines.push('')
  }
  return lines.join('\n')
}

const isMain = process.argv[1]?.endsWith('draft-agent.mjs')

if (isMain) {
  const arg = (name, fallback) => {
    const at = process.argv.indexOf(`--${name}`)
    const value = at > 0 ? Number(process.argv[at + 1]) : fallback
    if (!Number.isInteger(value) || value < 1) throw new Error(`--${name} must be a whole number above 0`)
    return value
  }
  const write = process.argv.includes('--write')
  try {
    const today = new Date().toISOString().slice(0, 10)
    console.log(`[draft-agent] ${MODEL}, looking ${arg('weeks', 8)} weeks ahead from ${today}${write ? '' : ' (dry run: add --write to create drafts)'}`)
    const {load} = await import('./config.mjs')
    const {createClient} = await import('./sanity.mjs')
    const config = load()
    const client = createClient(config.sanity)
    const exclude = await productsWithPosts(client)
    if (exclude.length) console.log(`[draft-agent] ${exclude.length} product(s) already have a post and are excluded`)
    const proposal = await runAgent({today, weeks: arg('weeks', 8), max: arg('max', 5), exclude, cache: !process.argv.includes('--no-cache'), log: console.log})
    console.log(`\n${formatProposal(proposal)}`)
    console.log(`[draft-agent] ${proposal.drafts.length} proposal(s) in ${proposal.turns} turn(s), ${tokens(proposal.usage)}.`)

    let plan = null
    if (write) {
      plan = await writeAgentDrafts(client, proposal)
      for (const doc of plan.create) console.log(`[draft-agent] drafted "${doc.title}" for review (${doc._id})`)
      for (const s of plan.skipped) console.log(`[draft-agent] skipped ${s.product}: ${s.reason}`)
      console.log(`[draft-agent] ${plan.create.length} draft(s) written at needs_review, ${plan.skipped.length} skipped.`)
    } else {
      console.log('[draft-agent] Nothing was written.')
    }
    recordRun(config.agentLogPath, proposal, plan)
  } catch (error) {
    console.error(`[draft-agent] ${error.message}`)
    process.exit(1)
  }
}
