/**
 * Campaign drafts: a campaign with `autoGenerate` on gets one draft post per
 * product, and those drafts reach the queue like any other post.
 *
 *   npm run generate      one pass, now
 *
 * The server also runs a pass at startup and every PUBLISHER_GENERATE_INTERVAL
 * seconds. It only ever CREATES DRAFTS: nothing is published, nothing is sent,
 * and an existing post is never edited, so a caption you rewrote in the Studio
 * is never overwritten by the template.
 *
 * Which campaigns: published ones (a campaign still in draft is still being
 * written, and its brief is the caption) that have not ended. A campaign that
 * has not started yet still generates, because the point is to review the posts
 * before it starts.
 *
 * Which products: every product on the campaign that has no post in that
 * campaign yet — generated or made by hand. A product that is not active in the
 * store, or has no image, is skipped and logged rather than drafted into a post
 * the gate would block anyway.
 *
 * Deleting a generated post in the Studio does not stop it coming back on the
 * next pass. Take the product off the campaign, or turn autoGenerate off.
 */
import {randomBytes} from 'node:crypto'
import {publishedId} from './ids.mjs'

const PLATFORMS = ['instagram', 'facebook']

const GENERATION_QUERY = `
{
  "campaigns": *[_type == "campaign" && autoGenerate == true && !(_id in path("drafts.**"))
                 && (!defined(endsAt) || endsAt > $now)]{
    _id, title, brief,
    "products": products[]->{_id, title, storeUrl, storeStatus, "image": images[0].asset._ref}
  },
  "posts": *[_type == "post" && defined(campaign._ref)]{_id, "campaign": campaign._ref, "products": products[]._ref}
}
`

export const key = () => randomBytes(6).toString('hex')

/** Sanity ids allow letters, digits, `_` and `-`; a dot would make it a path. */
export function generatedId(campaignId, productId) {
  const clean = (s) => String(s).replace(/[^a-zA-Z0-9_-]/g, '-')
  return `gen-${clean(campaignId)}-${clean(productId)}`
}

export function ref(id, type) {
  // The shape the Studio writes on a draft: weak until published, so a draft
  // post does not stop its campaign or product being deleted.
  return {_type: 'reference', _ref: id, _weak: true, _strengthenOnPublish: {type}}
}

export function captionFor(platform, campaign, product) {
  const brief = (campaign.brief ?? '').trim()
  const lines = [product.title]
  if (brief) lines.push('', brief)
  if (platform === 'instagram') {
    // Links in an Instagram caption are not clickable.
    lines.push('', 'Shop it at everfluorescent.com — link in bio.', '', '#everfluorescent')
  } else if (product.storeUrl) {
    lines.push('', product.storeUrl)
  }
  return lines.join('\n')
}

/**
 * Decide what to create. Pure: no network, so it is what the tests exercise.
 * Returns {create: [document], skipped: [{campaign, product, reason}]}.
 */
export function planGeneration(data) {
  const create = []
  const skipped = []

  const covered = new Set()
  for (const post of data?.posts ?? []) {
    covered.add(publishedId(post._id))
    for (const productId of post.products ?? []) covered.add(`${post.campaign}|${productId}`)
  }

  for (const campaign of data?.campaigns ?? []) {
    for (const found of campaign.products ?? []) {
      // A reference to a product that no longer exists dereferences to null.
      if (!found?._id) continue
      // Synced titles can carry stray whitespace, which would land in captions.
      const product = {...found, title: (found.title ?? '').trim() || found._id}
      const id = generatedId(campaign._id, product._id)
      if (covered.has(id) || covered.has(`${campaign._id}|${product._id}`)) continue

      const skip = (reason) => skipped.push({campaign: campaign.title, product: product.title ?? product._id, reason})
      if (product.storeStatus && product.storeStatus !== 'active') {
        skip(`it is ${product.storeStatus} in the store`)
        continue
      }
      if (!product.image) {
        skip('it has no image')
        continue
      }

      create.push({
        _id: `drafts.${id}`,
        _type: 'post',
        title: `${campaign.title}: ${product.title}`,
        campaign: ref(campaign._id, 'campaign'),
        products: [{_key: key(), ...ref(product._id, 'product')}],
        hook: product.title,
        body: campaign.brief ?? '',
        cta: 'Shop now',
        link: product.storeUrl ?? undefined,
        variants: PLATFORMS.map((platform) => ({
          _key: key(),
          _type: 'variant',
          platform,
          format: 'feed_image',
          caption: captionFor(platform, campaign, product),
          status: 'needs_review',
          assets: [{_key: key(), _type: 'image', asset: {_type: 'reference', _ref: product.image}}],
        })),
      })
    }
  }

  return {create, skipped}
}

/** One pass against the content lake. Returns what it did, for logging. */
export async function runGeneration(client, {now = new Date()} = {}) {
  const data = await client.query(GENERATION_QUERY, {now: now.toISOString()})
  const plan = planGeneration(data)
  // createIfNotExists: two passes racing, or a pass racing an edit, cannot
  // write the same post twice or overwrite one.
  if (plan.create.length) await client.mutate(plan.create.map((doc) => ({createIfNotExists: doc})))
  return plan
}

export function logPlan(plan) {
  for (const doc of plan.create) console.log(`[publisher] drafted "${doc.title}" for review`)
  for (const s of plan.skipped) console.log(`[publisher] skipped ${s.product} in "${s.campaign}": ${s.reason}`)
}

const isMain = process.argv[1]?.endsWith('generate.mjs')

if (isMain) {
  const {load} = await import('./config.mjs')
  const {createClient} = await import('./sanity.mjs')
  try {
    const plan = await runGeneration(createClient(load().sanity))
    logPlan(plan)
    console.log(`[publisher] ${plan.create.length} post(s) drafted, ${plan.skipped.length} skipped`)
  } catch (error) {
    console.error(error.message)
    process.exit(1)
  }
}
