/**
 * vendor-sync — copies the publish gate in from the CMS, compiled.
 *
 * `lib/platformSpec.ts` in the everfluorescent-cms repository is the only place
 * a platform limit is written down: the Studio's preview pane reads it and the
 * Studio's publish button reads it through `lib/preflight.ts`. This publisher
 * has to agree with both, because it computes the verdict the store admin shows
 * and then re-runs it at decision time.
 *
 * Ideally it would import those two files directly. It cannot: the CMS is a
 * separate working copy and is not version controlled, so nothing in this
 * repository can reach it at run time. So they are vendored here — compiled to
 * plain JavaScript by `tsc`, which also means the Jetson needs no TypeScript
 * toolchain and no Node new enough to strip types.
 *
 * What is vendored is COMPILED OUTPUT, never a rewrite. There is no second
 * implementation of the rules to drift from the first; there is one
 * implementation and a build of it. That distinction is the whole point.
 *
 *   npm run vendor          regenerate from the CMS checkout
 *   npm run verify          exit 1 if what is committed is out of date
 *
 * Point it at a CMS checkout elsewhere with CMS_PATH=/path/to/everfluorescent-cms.
 */
import {createHash} from 'node:crypto'
import {execFileSync} from 'node:child_process'
import {existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync} from 'node:fs'
import {tmpdir} from 'node:os'
import {dirname, join, resolve} from 'node:path'
import {fileURLToPath} from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const vendorDir = resolve(here, '../vendor')
const manifestPath = join(vendorDir, 'manifest.json')

// The two files, and nothing else. preflight.ts imports platformSpec.ts; both
// are pure and pull in nothing from Sanity, which is what makes this possible.
const SOURCES = ['lib/platformSpec.ts', 'lib/preflight.ts']

const check = process.argv.includes('--check')

const cmsPath = resolve(
  process.env.CMS_PATH ||
    // The layout on this machine: both checkouts under one Codestuff folder.
    resolve(here, '../../../everfluorescent-cms/everfluorescent-cms'),
)

function fail(message) {
  console.error(message)
  process.exit(1)
}

if (!existsSync(cmsPath)) {
  fail(
    `No CMS checkout at ${cmsPath}.\n` +
      `Set CMS_PATH to the everfluorescent-cms working copy and run again.\n` +
      (check
        ? `\nThis check can only run where the CMS is present, so skip it on the Jetson:\n` +
          `it is a guard for the machine the vendored files are generated on.`
        : ''),
  )
}

for (const rel of SOURCES) {
  if (!existsSync(join(cmsPath, rel))) fail(`${cmsPath} has no ${rel}.`)
}

// Hash the SOURCES, not the output: an edit to the TypeScript that happens to
// compile to the same JavaScript should still show up as "these were
// regenerated from something new".
const sourceHash = createHash('sha256')
for (const rel of SOURCES) {
  sourceHash.update(rel)
  sourceHash.update(readFileSync(join(cmsPath, rel)))
}
const digest = sourceHash.digest('hex').slice(0, 16)

// Run the CMS's own tsc through node rather than through npx: npx is a .cmd
// shim on Windows, which execFileSync cannot spawn without a shell.
const tsc = join(cmsPath, 'node_modules', 'typescript', 'bin', 'tsc')
if (!existsSync(tsc)) {
  fail(`No TypeScript in ${cmsPath}. Run \`npm install\` there first.`)
}

const out = mkdtempSync(join(tmpdir(), 'publisher-vendor-'))
try {
  // --rewriteRelativeImportExtensions (TypeScript 5.7+) turns the
  // `from './platformSpec.ts'` in preflight.ts into `.js` in the emitted code.
  // Without it tsc refuses the .ts specifier outright unless it is not emitting.
  execFileSync(
    process.execPath,
    [
      tsc,
      ...SOURCES,
      '--target', 'es2022',
      '--module', 'esnext',
      '--moduleResolution', 'bundler',
      '--rewriteRelativeImportExtensions',
      '--removeComments', 'false',
      '--outDir', out,
    ],
    {cwd: cmsPath, stdio: ['ignore', 'pipe', 'pipe']},
  )
} catch (error) {
  fail(`tsc failed:\n${error.stderr?.toString() || error.message}`)
}

const header = (rel) =>
  `// GENERATED FILE — do not edit.\n` +
  `//\n` +
  `// Compiled from ${rel} in the everfluorescent-cms repository, which is the\n` +
  `// single source of truth for every platform limit in both halves of the post\n` +
  `// queue. Change it THERE and run \`npm run vendor\` in publisher/.\n` +
  `//\n` +
  `// Source set hash: ${digest}\n\n`

const emitted = readdirSync(out).filter((f) => f.endsWith('.js')).sort()
const files = {}
for (const name of emitted) {
  const rel = SOURCES.find((s) => s.endsWith(`/${name.replace(/\.js$/, '.ts')}`))
  files[name] = header(rel ?? 'the CMS') + readFileSync(join(out, name), 'utf8')
}

const manifest =
  JSON.stringify(
    {
      generatedFrom: SOURCES,
      sourceHash: digest,
      files: Object.fromEntries(
        Object.entries(files).map(([name, body]) => [
          name,
          createHash('sha256').update(body).digest('hex').slice(0, 16),
        ]),
      ),
      warning: 'Generated by publisher/tools/vendor-sync.mjs. Do not edit vendor/ by hand.',
    },
    null,
    2,
  ) + '\n'

if (check) {
  const problems = []
  for (const [name, body] of Object.entries(files)) {
    const path = join(vendorDir, name)
    if (!existsSync(path)) problems.push(`${name} is missing`)
    else if (readFileSync(path, 'utf8') !== body) problems.push(`${name} is out of date`)
  }
  if (!existsSync(manifestPath)) problems.push('manifest.json is missing')
  else if (readFileSync(manifestPath, 'utf8') !== manifest) problems.push('manifest.json is out of date')

  if (problems.length) {
    fail(
      `The vendored gate no longer matches the CMS:\n` +
        problems.map((p) => `  · ${p}`).join('\n') +
        `\n\nRun: npm run vendor`,
    )
  }
  console.log(`vendor/ is current with the CMS (source set ${digest}).`)
  process.exit(0)
}

mkdirSync(vendorDir, {recursive: true})
for (const [name, body] of Object.entries(files)) {
  writeFileSync(join(vendorDir, name), body)
}
writeFileSync(manifestPath, manifest)

console.log(`Vendored from ${cmsPath}`)
for (const name of emitted) console.log(`  vendor/${name}`)
console.log(`  source set ${digest}`)

// The same warning the CMS prints, because this publisher enforces these
// numbers as hard limits rather than shading a preview with them.
const {PLATFORMS} = await import(join(out, 'platformSpec.js').replace(/\\/g, '/').replace(/^([A-Za-z]):/, 'file:///$1:'))
const unverified = []
for (const p of Object.values(PLATFORMS)) {
  if (!p.caption.verified) unverified.push(`${p.label} caption limit`)
  if (!p.hashtags.verified) unverified.push(`${p.label} hashtag limit`)
  for (const f of p.formats) {
    if (f.duration && !f.duration.verified) unverified.push(`${p.label} ${f.label} duration`)
  }
}
if (unverified.length) {
  console.log(`\n  ${unverified.length} of these values are still marked verified: false —`)
  for (const u of unverified) console.log(`    · ${u}`)
  console.log(`  This publisher blocks approval on them. Re-read the platform docs before trusting them.`)
}
