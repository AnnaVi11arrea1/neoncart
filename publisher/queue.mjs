/**
 * The queue: which variants are waiting on a decision, and what is wrong with
 * each of them.
 *
 * The verdict comes from vendor/preflight.js, which is compiled from the CMS's
 * own lib/preflight.ts — the same code behind the Studio's publish button. So a
 * post the Studio would refuse is a post this marks blocked, with the same
 * words, and there is no second set of rules to keep in step.
 */
import {preflight} from './vendor/preflight.js'
import {getPlatform} from './vendor/platformSpec.js'
import {isDraftId, publishedId, variantId} from './ids.mjs'
import {previewUrl} from './preview.mjs'

/**
 * Statuses that mean "nobody has decided about this yet" — the same pair the
 * Studio's own button treats as candidates. A variant already `approved`,
 * `publishing`, `published` or `failed` is not awaiting a first decision.
 */
export const AWAITING = ['draft', 'needs_review']

const QUEUE_QUERY = `
{
  "posts": *[_type == "post" && defined(variants)] | order(_updatedAt desc) [0...300] {
    _id, _rev, _updatedAt, title,
    "products": products[]->{_id, title, storeId, incomplete, storeStatus},
    "variants": variants[]{
      _key, platform, format, caption, status, scheduledAt,
      "assets": assets[]{
        _key, _type,
        "ref": asset._ref,
        "meta": asset->{mimeType, originalFilename, metadata{dimensions}}
      }
    }
  },
  "accounts": *[_type == "platformAccount"]{platform, handle, active, audited}
}
`

/**
 * Sanity stores an edited document twice: `drafts.abc` while it is being written
 * and `abc` once published. Both come back from that query, and the draft is the
 * one worth reviewing because it is the current text. The published copy is
 * dropped when a draft of it exists.
 */
function preferDrafts(posts) {
  const drafts = new Set(posts.filter((p) => isDraftId(p._id)).map((p) => publishedId(p._id)))
  return posts.filter((p) => isDraftId(p._id) || !drafts.has(p._id))
}

function assetInfo(asset, client) {
  const meta = asset?.meta ?? {}
  const mimeType = meta.mimeType ?? null
  const isVideo = String(mimeType ?? '').startsWith('video/') || asset?._type === 'file'
  return {
    url: client.assetUrl(asset?.ref),
    filename: meta.originalFilename ?? null,
    mimeType,
    width: meta.metadata?.dimensions?.width ?? null,
    height: meta.metadata?.dimensions?.height ?? null,
    isVideo,
    // Nothing here can measure a video's length: Sanity stores no duration in
    // asset metadata and this process has no decoder. preflight treats an
    // unknown duration as unchecked-and-warned rather than as fine, which is
    // why this is left undefined rather than set to 0.
    durationSeconds: undefined,
  }
}

/**
 * The contract requires a verdict on every row — "no verdict at all is not a
 * clean one" — so this never returns undefined. `errors` non-empty, or
 * `ok: false`, blocks approval in the store.
 */
function verdictFor(variant, assets, products, account) {
  const result = preflight({
    platform: variant.platform,
    format: variant.format,
    caption: variant.caption ?? '',
    assets,
    products: (products ?? []).map((p) => ({
      title: p?.title,
      incomplete: p?.incomplete,
      storeStatus: p?.storeStatus,
    })),
    accountConfigured: Boolean(account),
    accountAudited: account ? account.audited === true : false,
  })

  return {
    ok: result.ok,
    errors: result.errors.map((i) => ({field: i.field, message: i.message})),
    warnings: result.warnings.map((i) => ({field: i.field, message: i.message})),
  }
}

/**
 * Build the rows for GET /posts/pending.
 *
 * `decisions` is consulted rather than the variant's status, because a decision
 * does not move the status — that is the contract's rule, and the reason a
 * decided variant leaves this queue at all.
 */
export function buildQueue({data, client, decisions, config, notes = null}) {
  const accounts = (data?.accounts ?? []).filter((a) => a && a.active !== false)
  const accountFor = (platform) => accounts.find((a) => a.platform === platform) ?? null

  const rows = []

  for (const post of preferDrafts(data?.posts ?? [])) {
    for (const variant of post.variants ?? []) {
      if (!variant?._key) continue
      if (!AWAITING.includes(variant.status ?? 'draft')) continue

      const id = variantId(post._id, variant._key)
      if (!id || decisions.has(id)) continue

      const assets = (variant.assets ?? []).map((a) => assetInfo(a, client))
      const cover = assets[0] ?? null
      const verdict = verdictFor(variant, assets, post.products, accountFor(variant.platform))
      // Only posts the draft agent wrote have these. Optional in the contract,
      // so a hand-made post's row simply goes without.
      const note = notes?.get(publishedId(post._id))

      rows.push({
        id,
        caption: variant.caption ?? '',
        platform: variant.platform ?? null,
        post_format: variant.format ?? null,
        // The cover only. The store shows one asset per row and falls back to it
        // when there is no preview; the preview shows the same one.
        asset_url: cover?.url ?? null,
        asset_kind: cover ? (cover.isVideo ? 'video' : 'image') : null,
        preview_url: previewUrl(id, config),
        updated_at: post._updatedAt ?? null,
        title: post.title ?? null,
        products: (post.products ?? [])
          .filter(Boolean)
          .map((p) => ({store_id: p.storeId ?? null, title: p.title ?? null})),
        verdict,
        ...(note ? {sources: note.sources, conflicts: note.conflicts} : {}),
      })
    }
  }

  return rows
}

/** One row, for re-checking at decision time. */
export function findRow(rows, id) {
  return rows.find((r) => r.id === id) ?? null
}

export async function fetchQueueData(client) {
  return client.query(QUEUE_QUERY)
}

/**
 * Re-run the checks for one variant, reading it fresh. The contract requires
 * this at decision time rather than trusting what the page showed: a product's
 * price or image can change between the queue rendering and the button being
 * pressed, and a green tick that cannot notice that is the bug the whole gate
 * exists to prevent.
 */
export async function recheck({client, documentId, variantKey}) {
  const data = await client.query(
    `{
      "post": *[_id == $id][0]{
        _id, _updatedAt, title,
        "products": products[]->{_id, title, storeId, incomplete, storeStatus},
        "variants": variants[]{
          _key, platform, format, caption, status,
          "assets": assets[]{
            _key, _type,
            "ref": asset._ref,
            "meta": asset->{mimeType, originalFilename, metadata{dimensions}}
          }
        }
      },
      "accounts": *[_type == "platformAccount"]{platform, active, audited}
    }`,
    {id: documentId},
  )

  const post = data?.post
  if (!post) return {found: false}

  const variant = (post.variants ?? []).find((v) => v?._key === variantKey)
  if (!variant) return {found: false}

  const account =
    (data.accounts ?? []).find((a) => a && a.active !== false && a.platform === variant.platform) ?? null
  const assets = (variant.assets ?? []).map((a) => assetInfo(a, client))

  return {
    found: true,
    status: variant.status ?? 'draft',
    platformLabel: getPlatform(variant.platform)?.label ?? 'Unknown platform',
    verdict: verdictFor(variant, assets, post.products, account),
  }
}
