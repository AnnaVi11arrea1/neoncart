/**
 * What the draft agent based each of its posts on, for the review card.
 *
 * A post has no field for sources or conflicts, and adding one means a schema
 * change in the CMS that the Studio would show as an unknown field until it
 * lands. The agent already appends every run to data/agent-runs.jsonl, so the
 * queue reads them from there: post id → {sources, conflicts}.
 *
 * Read on every queue request rather than at startup, so a run made while the
 * server is up shows on the next page load. The file is one line per run.
 */
import {existsSync, readFileSync} from 'node:fs'
import {agentPostId} from './draft-agent.mjs'

/** Map of published post id → {sources: [{title, ref}], conflicts: [string]}. */
export function loadAgentNotes(path) {
  const notes = new Map()
  if (!path || !existsSync(path)) return notes

  for (const line of readFileSync(path, 'utf8').split('\n')) {
    if (!line.trim()) continue
    let run
    try {
      run = JSON.parse(line)
    } catch {
      continue // a torn last line from an interrupted run is not worth a 500
    }
    const written = new Set((run?.written ?? []).map((id) => String(id).replace(/^drafts\./, '')))
    for (const draft of run?.proposal?.drafts ?? []) {
      const id = agentPostId(run.proposal.seasonKey, draft.productId)
      if (!written.has(id)) continue
      // Later runs win, though createIfNotExists means a post is only ever
      // written by one run; this only matters if a post is deleted and redrafted.
      notes.set(id, {
        sources: (draft.sources ?? []).filter((s) => s?.title || s?.ref).map((s) => ({title: String(s.title ?? ''), ref: String(s.ref ?? '')})),
        conflicts: (draft.conflicts ?? []).map(String).filter(Boolean),
      })
    }
  }
  return notes
}
