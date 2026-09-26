/**
 * The Sanity content lake, over its HTTP API. No SDK: two endpoints and two URL
 * shapes are the whole surface this needs, and a dependency-free service is one
 * that installs on the Jetson with `git pull` and nothing else.
 *
 * Reads go to api.sanity.io, not apicdn.sanity.io. The CDN serves a cached copy
 * and cannot see drafts, and the queue is mostly drafts — a post being reviewed
 * is a post someone is still editing.
 */

export class SanityError extends Error {}

export function createClient({projectId, dataset, token, apiVersion}) {
  const base = `https://${projectId}.api.sanity.io/v${apiVersion}`

  async function call(path, body, {method = 'POST'} = {}) {
    let response
    try {
      response = await fetch(`${base}${path}`, {
        method,
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
          'User-Agent': 'everfluorescent-publisher/1.0',
        },
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(20_000),
      })
    } catch (error) {
      if (error?.name === 'TimeoutError') throw new SanityError('Sanity did not answer within 20 seconds')
      throw new SanityError(`could not reach Sanity (${error?.name || 'network error'})`)
    }

    const text = await response.text()
    let payload
    try {
      payload = text ? JSON.parse(text) : {}
    } catch {
      // A 200 carrying HTML is a proxy or an error page, never a query result.
      throw new SanityError(`Sanity answered with something that is not JSON (HTTP ${response.status})`)
    }

    if (!response.ok) {
      const detail = payload?.message || payload?.error?.description || payload?.error || ''
      const hint =
        response.status === 401
          ? ' — SANITY_API_TOKEN is missing, expired or wrong'
          : response.status === 403
            ? ` — that token cannot write to the '${dataset}' dataset`
            : response.status === 404
              ? ` — no project '${projectId}' or dataset '${dataset}'`
              : ''
      throw new SanityError(`Sanity returned ${response.status}${hint}${detail ? `: ${detail}` : ''}`)
    }

    return payload
  }

  return {
    /** Run a GROQ query. Always pass values as $params, never interpolate. */
    async query(groq, params = {}) {
      // POSTed rather than GET: the queue query with its dereferences clears
      // Sanity's URL length ceiling comfortably.
      const body = await call(`/data/query/${dataset}`, {query: groq, params})
      return body.result
    },

    /** Apply mutations as one transaction — all of them land, or none do. */
    async mutate(mutations) {
      const list = [].concat(mutations)
      if (!list.length) return {results: []}
      return call(`/data/mutate/${dataset}`, {mutations: list})
    },

    /**
     * Asset references carry everything the URL needs:
     *   image-ab12…-1080x1350-jpg → …/images/<project>/<dataset>/ab12…-1080x1350.jpg
     *   file-ab12…-mp4            → …/files/<project>/<dataset>/ab12….mp4
     * A reference that does not parse returns null rather than a broken URL.
     */
    assetUrl(ref) {
      if (typeof ref !== 'string') return null
      const parts = ref.split('-')
      if (parts[0] === 'image' && parts.length === 4) {
        const [, id, dimensions, ext] = parts
        return `https://cdn.sanity.io/images/${projectId}/${dataset}/${id}-${dimensions}.${ext}`
      }
      if (parts[0] === 'file' && parts.length === 3) {
        const [, id, ext] = parts
        return `https://cdn.sanity.io/files/${projectId}/${dataset}/${id}.${ext}`
      }
      return null
    },
  }
}
