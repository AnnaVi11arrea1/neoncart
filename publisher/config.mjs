/**
 * Configuration, and the refusal to start half-configured.
 *
 * This process holds the CMS credential, which is the reason it exists: the
 * store deliberately holds none, because a Sanity token cannot be narrowed
 * below the project without an Enterprise plan and one kept in the store would
 * also read the private knowledge-base notes. So the token lives here, in one
 * small service with one job, and the store holds only a bearer token for this.
 */

const DEFAULTS = {
  PUBLISHER_PORT: '3002',
  PUBLISHER_HOST: '127.0.0.1',
  SANITY_DATASET: 'production',
  SANITY_API_VERSION: '2024-10-01',
  PUBLISHER_PREVIEW_TTL: '900',
  PUBLISHER_DECISIONS_PATH: './data/decisions.jsonl',
  // Seconds between campaign generation passes. 0 turns generation off.
  PUBLISHER_GENERATE_INTERVAL: '300',
}

// Everything the process cannot do its job without. A missing one is a startup
// failure with a named cause, not a 500 on the first request.
const REQUIRED = [
  ['SANITY_PROJECT_ID', 'the Sanity project id — 70komvgl. Not a secret.'],
  ['SANITY_API_TOKEN', 'a Sanity token with read access. THE secret here.'],
  ['PUBLISHER_TOKEN', "the bearer the store sends; must equal the store's POST_WORKER_TOKEN."],
  ['PUBLISHER_PREVIEW_SECRET', 'signs preview URLs. Any long random string; not the same as PUBLISHER_TOKEN.'],
]

export function load(env = process.env) {
  const get = (key) => (env[key] ?? DEFAULTS[key] ?? '').toString().trim()

  const missing = REQUIRED.filter(([key]) => !get(key))
  if (missing.length) {
    const lines = missing.map(([key, why]) => `  ${key} — ${why}`).join('\n')
    throw new Error(`The publisher is not configured. Missing:\n${lines}`)
  }

  const port = Number(get('PUBLISHER_PORT'))
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error(`PUBLISHER_PORT is not a port: ${get('PUBLISHER_PORT')}`)
  }

  const ttl = Number(get('PUBLISHER_PREVIEW_TTL'))
  if (!Number.isInteger(ttl) || ttl < 30) {
    throw new Error(`PUBLISHER_PREVIEW_TTL must be at least 30 seconds; got ${get('PUBLISHER_PREVIEW_TTL')}`)
  }

  const generateInterval = Number(get('PUBLISHER_GENERATE_INTERVAL'))
  if (!Number.isInteger(generateInterval) || (generateInterval !== 0 && generateInterval < 60)) {
    throw new Error(`PUBLISHER_GENERATE_INTERVAL must be 0 (off) or at least 60 seconds; got ${get('PUBLISHER_GENERATE_INTERVAL')}`)
  }

  if (get('PUBLISHER_TOKEN') === get('PUBLISHER_PREVIEW_SECRET')) {
    // A preview URL is handed to a browser. Reusing the store's bearer token as
    // the signing key would put material derived from it in a query string.
    throw new Error('PUBLISHER_TOKEN and PUBLISHER_PREVIEW_SECRET must be different values.')
  }

  return {
    host: get('PUBLISHER_HOST'),
    port,
    token: get('PUBLISHER_TOKEN'),
    previewSecret: get('PUBLISHER_PREVIEW_SECRET'),
    previewTtl: ttl,
    // Where the browser reaches the preview route. Empty means "serve previews
    // but do not advertise them": preview_url is optional in the contract and
    // the store falls back to showing the asset, which is the right behaviour
    // when nginx has not been given the location block yet.
    publicUrl: get('PUBLISHER_PUBLIC_URL').replace(/\/+$/, ''),
    decisionsPath: get('PUBLISHER_DECISIONS_PATH'),
    generateInterval,
    sanity: {
      projectId: get('SANITY_PROJECT_ID'),
      dataset: get('SANITY_DATASET'),
      token: get('SANITY_API_TOKEN'),
      apiVersion: get('SANITY_API_VERSION'),
    },
  }
}
