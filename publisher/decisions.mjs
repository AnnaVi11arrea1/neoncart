/**
 * What Anna decided, and when.
 *
 * The contract is specific that approving must NOT move the variant's status:
 * `approved` is the state the sending half will read, and overloading it to also
 * mean "a human said yes" is how a post ends up somewhere nothing is looking. So
 * the decision is recorded here instead, and a decided variant leaves the queue
 * because it has been decided rather than because its status moved.
 *
 * Append-only JSON Lines, not SQLite. A native SQLite module has to compile on
 * arm64 on a Jetson, and node:sqlite needs a Node newer than that box is likely
 * to have; a text file needs neither, survives being read by hand, and is a
 * plain audit trail. This is a queue one person works through, so the whole file
 * fits in memory and is re-read at startup.
 *
 * Later writes win, so a decision can be corrected by appending another.
 */
import {appendFileSync, existsSync, mkdirSync, readFileSync} from 'node:fs'
import {dirname} from 'node:path'

export const DECISIONS = ['approved', 'rejected']

export function openDecisions(path) {
  /** @type {Map<string, {id: string, decision: string, actor: string, note: string|null, at: string}>} */
  const byId = new Map()
  let skipped = 0

  if (existsSync(path)) {
    for (const line of readFileSync(path, 'utf8').split('\n')) {
      const trimmed = line.trim()
      if (!trimmed) continue
      try {
        const row = JSON.parse(trimmed)
        if (row && typeof row.id === 'string' && row.id) byId.set(row.id, row)
        else skipped++
      } catch {
        // A torn last line — power cut mid-append — must not stop the service
        // from starting. Counted so it is not silent.
        skipped++
      }
    }
  }

  return {
    get size() {
      return byId.size
    },

    /** Lines that could not be read at startup. Reported, never ignored. */
    get skipped() {
      return skipped
    },

    get(id) {
      return byId.get(id) ?? null
    },

    has(id) {
      return byId.has(id)
    },

    /**
     * Record a decision. Idempotent on (id, decision): deciding the same way
     * twice returns the first record and writes nothing, so the store retrying
     * a request whose response it never saw cannot produce two rows. Deciding
     * the OTHER way is a correction and is appended.
     */
    record({id, decision, actor, note = null}) {
      if (!id) throw new Error('a post id is required')
      if (!DECISIONS.includes(decision)) {
        throw new Error(`decision must be one of ${DECISIONS.join(', ')}`)
      }

      const existing = byId.get(id)
      if (existing && existing.decision === decision) {
        return {record: existing, written: false}
      }

      const row = {
        id,
        decision,
        actor: actor || 'unknown',
        note: note || null,
        at: new Date().toISOString(),
      }

      mkdirSync(dirname(path), {recursive: true})
      appendFileSync(path, JSON.stringify(row) + '\n')
      byId.set(id, row)
      return {record: row, written: true}
    },
  }
}
