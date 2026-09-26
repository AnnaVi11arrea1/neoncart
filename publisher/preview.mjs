/**
 * The preview the store embeds in a sandboxed iframe.
 *
 * It cannot be behind the bearer token: an iframe sends no Authorization header.
 * So it carries a signature and an expiry instead, and an unsigned or stale one
 * is refused. The signature covers both the id and the expiry, so neither can be
 * changed without invalidating it — an expiry that were not signed could simply
 * be edited to a later one.
 *
 * WHAT THIS IS NOT, yet: the contract's ideal is that the publisher renders the
 * preview "with the same components the CMS preview pane uses", so what you see
 * here is what you saw when you wrote it. Those components are React with
 * @sanity/ui and styled-components, and server-rendering them means pulling that
 * whole tree into this dependency-free service. This is a plain-HTML stand-in
 * that reads the SAME platform spec — so the caption ceiling, the hashtag count
 * and the frame the artwork sits in are all correct — but it is not pixel-for-
 * pixel the Studio's chrome. Swapping in the real components is the follow-up.
 */
import {createHmac, timingSafeEqual} from 'node:crypto'
import {getPlatform} from './vendor/platformSpec.js'

export class PreviewError extends Error {
  constructor(message, status = 403) {
    super(message)
    this.status = status
  }
}

function sign(id, exp, secret) {
  return createHmac('sha256', secret).update(`${id}.${exp}`).digest('base64url')
}

/** A signed, expiring URL, or null when no public base URL is configured. */
export function previewUrl(id, {publicUrl, previewSecret, previewTtl}) {
  if (!publicUrl) return null
  const exp = Math.floor(Date.now() / 1000) + previewTtl
  const sig = sign(id, exp, previewSecret)
  const params = new URLSearchParams({id, exp: String(exp), sig})
  return `${publicUrl}?${params}`
}

export function verifyPreview(params, {previewSecret}) {
  const id = params.get('id')
  const exp = params.get('exp')
  const sig = params.get('sig')

  if (!id || !exp || !sig) throw new PreviewError('This preview link is incomplete.')

  const expiry = Number(exp)
  if (!Number.isInteger(expiry)) throw new PreviewError('This preview link is malformed.')

  const expected = sign(id, exp, previewSecret)
  // Compare in constant time, and only when the lengths match — timingSafeEqual
  // throws on a length mismatch rather than returning false.
  const a = Buffer.from(sig)
  const b = Buffer.from(expected)
  if (a.length !== b.length || !timingSafeEqual(a, b)) {
    throw new PreviewError('This preview link is not signed correctly.')
  }

  // Checked after the signature, so an expired-but-valid link and a forged one
  // are not distinguishable by which error comes back.
  if (expiry * 1000 < Date.now()) {
    throw new PreviewError('This preview link has expired. Reload the queue.', 410)
  }

  return id
}

function escapeHtml(value) {
  return String(value ?? '').replace(
    /[&<>"']/g,
    (c) => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'})[c],
  )
}

/**
 * Renders one row as the platform will roughly show it. Self-contained: no
 * scripts, no external stylesheets, nothing the sandboxed iframe would be
 * refused anyway.
 */
export function renderPreview(row) {
  const spec = getPlatform(row.platform)
  const accent = spec?.accent ?? '#8b3dff'
  const label = spec?.label ?? 'Unknown platform'
  const caption = String(row.caption ?? '')
  const max = spec?.caption.max ?? 0
  const over = max > 0 && caption.length > max

  const media = (() => {
    if (!row.asset_url) return '<div class="media media--empty">no asset attached</div>'
    if (row.asset_kind === 'image') {
      return `<img class="media" src="${escapeHtml(row.asset_url)}" alt="">`
    }
    if (row.asset_kind === 'video') {
      // Muted and controlled, never autoplaying: this renders inside an admin
      // page that may hold a dozen of these.
      return `<video class="media" src="${escapeHtml(row.asset_url)}" controls muted preload="metadata"></video>`
    }
    return '<div class="media media--empty">asset of an unknown kind</div>'
  })()

  const errors = (row.verdict?.errors ?? []).map((e) => e.message)
  const warnings = (row.verdict?.warnings ?? []).map((w) => w.message)

  const notes = [
    ...errors.map((m) => `<li class="note note--error">${escapeHtml(m)}</li>`),
    ...warnings.map((m) => `<li class="note note--warning">${escapeHtml(m)}</li>`),
  ].join('')

  return `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escapeHtml(label)} preview</title>
<style>
  :root { color-scheme: dark; }
  body { margin: 0; padding: 12px; background: #0a0514; color: #e8e3f6;
         font: 14px/1.5 system-ui, -apple-system, sans-serif; }
  .card { max-width: 420px; margin: 0 auto; background: #140b28;
          border: 1px solid #2c1c52; border-radius: 12px; overflow: hidden; }
  .bar { display: flex; align-items: center; gap: 8px; padding: 10px 12px;
         border-bottom: 1px solid #2c1c52; }
  .dot { width: 26px; height: 26px; border-radius: 50%; background: ${accent}; flex: none; }
  .who { font-weight: 600; font-size: 13px; }
  .fmt { color: #8d83ad; font-size: 11px; text-transform: uppercase; letter-spacing: .06em; }
  .media { display: block; width: 100%; max-height: 520px; object-fit: cover; background: #080310; }
  .media--empty { display: flex; align-items: center; justify-content: center; height: 180px;
                  color: #8d83ad; font-size: 12px; }
  .caption { padding: 12px; white-space: pre-wrap; word-break: break-word; margin: 0; }
  .count { padding: 0 12px 12px; color: #8d83ad; font-size: 11px; font-variant-numeric: tabular-nums; }
  .count.over { color: #ff4d6d; }
  ul { list-style: none; margin: 0; padding: 0 12px 12px; display: grid; gap: 6px; }
  .note { font-size: 12px; padding-left: 12px; position: relative; }
  .note::before { content: ""; position: absolute; left: 0; top: .45em;
                  width: 6px; height: 6px; border-radius: 50%; }
  .note--error { color: #ffb3c1; } .note--error::before { background: #ff4d6d; }
  .note--warning::before { background: #ff2ea6; }
</style>
</head><body>
  <div class="card">
    <div class="bar">
      <span class="dot"></span>
      <span class="who">everfluorescent</span>
      <span class="fmt">${escapeHtml(label)} · ${escapeHtml(row.post_format ?? 'no format')}</span>
    </div>
    ${media}
    <p class="caption">${escapeHtml(caption) || '<em>no caption written yet</em>'}</p>
    <p class="count${over ? ' over' : ''}">${caption.length}${max ? ` / ${max}` : ''} characters${
      row.verdict ? '' : ' · not checked'
    }</p>
    ${notes ? `<ul>${notes}</ul>` : ''}
  </div>
</body></html>
`
}
