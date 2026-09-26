# The publisher

The other half of the post queue. `docs/post-queue-contract.md` is the
specification; this is the implementation of the two endpoints the store calls,
plus the preview it frames.

**It approves nothing on its own and sends nothing anywhere.** It serves the
posts awaiting a decision, records what Anna decided, and re-runs the checks
before it accepts an approval. The half that actually posts to Instagram does
not exist yet.

## Why it is a separate process

The store deliberately holds no CMS credential. A Sanity token cannot be
narrowed to one dataset or one document type without an Enterprise plan, so a
token kept in the store would also read the private knowledge-base notes in the
same project. This service holds it instead, and the store holds exactly one
secret: a bearer token for this service.

It runs on the same Jetson as the store, so the store reaches it over loopback.
Only the preview route is exposed through nginx, because a browser has to load it.

## Running it

```bash
cd publisher
cp .env.example .env        # then fill in the three secrets
node server.mjs
```

No dependencies and no build step — `node server.mjs` is the whole thing. Node 18
or newer; nothing here needs type stripping or a native module, which is
deliberate given what it runs on.

```bash
npm test                    # 39 assertions, no network, no Sanity
```

## The routes

| | |
| --- | --- |
| `GET /api/posts/pending` | the queue. Bearer token. |
| `POST /api/posts/{id}/decision` | approve or reject. Bearer token. |
| `GET /preview?id=&exp=&sig=` | the iframe. Signed, expiring, no token. |
| `GET /healthz` | liveness. No auth, no data. |

Everything under `/api` answers JSON with a JSON content type, errors included.
That is not incidental: the store tells "I could not read the queue" from "there
is nothing to approve" by the shape of the response, so a 200 carrying HTML is
the one failure that would read as success.

## The verdict, and where the rules live

Every row carries a `verdict`, because the contract is explicit that no verdict
is not a clean one. It comes from `vendor/preflight.js`, which is **compiled
from `lib/preflight.ts` in the everfluorescent-cms repository** — the same code
behind the Studio's publish button, reading the same `lib/platformSpec.ts`. So a
post the Studio would refuse is a post this marks blocked, in the same words.

`vendor/` is generated. Never edit it.

```bash
npm run vendor    # regenerate from the CMS checkout beside this one
npm run verify    # exit 1 if what is committed is out of date
```

Point it elsewhere with `CMS_PATH=/path/to/everfluorescent-cms`. `npm run verify`
only works where the CMS is present, so it is a guard for the machine the files
are generated on, not for the Jetson.

The reason this is vendored rather than imported: the CMS is a separate working
copy and is **not under version control**, so nothing in this repository can
reach it at run time. Compiling it in keeps one implementation of the rules and a
build of it, rather than two implementations that drift. If the CMS ever becomes
a git repository, the better arrangement is to import those two files directly
and delete `vendor/` and `tools/` along with this paragraph.

## Campaign drafts

A published campaign with `autoGenerate` on, that has not ended, gets one draft
post per product, with an Instagram and a Facebook `feed_image` variant at
`needs_review`, the product's first image, and a caption templated from the
product title and the campaign brief. They reach the queue like any other post.
`generate.mjs` has the rules.

The server runs a pass at startup and every `PUBLISHER_GENERATE_INTERVAL`
seconds (default 300, `0` turns it off); `npm run generate` runs one now. It
only creates drafts and never edits an existing post, and a product that already
has a post in the campaign — generated or made by hand — is left alone. Deleting
a generated post does not stop it coming back; take the product off the campaign
instead.

## Seasonal drafts (the agent)

`npm run draft` asks Claude to find the season ahead and propose short posts for
products that suit it. It reads the shop and the Knowledge Base through Sanity
Context, and it **writes nothing yet**: it prints the proposals, each with the
sources behind its claims and any place two sources disagreed.

```bash
npm run context-check        # both Context endpoints answer and list their tools
npm run draft                # propose up to 5, looking 8 weeks ahead
npm run draft -- --max 3 --weeks 10
```

The tool loop runs here, not through the API's MCP connector, so the Context
token never leaves this machine. `context.mjs` is the MCP client; Context is
read-only. It needs, in `.env`:

| | |
| --- | --- |
| `SANITY_CONTEXT_TOKEN` | an **organization** token with the Context role. A project token gets a 403. |
| `SANITY_CONTEXT_MCP_URL` | the `neoncart-drafts` endpoint: products and campaigns |
| `SANITY_CONTEXT_KB_URL` | the same URL with `?mode=knowledge_base&knowledgeBases=kb…`. Name the Knowledge Base here, not as an endpoint source: next to a dataset source it is ignored. |
| `ANTHROPIC_API_KEY` | and `ANTHROPIC_WORKSPACE_ID` if the key is not scoped to a workspace |

A run costs roughly $0.40 with prompt caching; the last line prints the tokens
and an estimate.

## What it writes

One file: `data/decisions.jsonl`, append-only.

Approving records that Anna said yes, who, and when — and **leaves the variant's
status alone**, because `approved` is the state the sending half will read and
overloading it to also mean "a human agreed" is how a post ends up somewhere
nothing is looking. A decided variant leaves the queue because it has been
decided, not because its status moved.

Rejecting records the decision and hands the variant back to `draft` in the CMS,
keeping the note here.

Decisions are idempotent on `(id, decision)`: the store retrying a request whose
answer it never saw cannot produce two records. Deciding the other way is a
correction and is appended, so the file is the audit trail.

It is JSON Lines rather than SQLite on purpose: a native SQLite module has to
compile on arm64, and `node:sqlite` needs a newer Node than that box is likely to
have. This is a queue one person works through; the file fits in memory.

## Deploying on the Jetson

```bash
# once
install -m 600 /dev/null /home/anna/neoncart/publisher/.env   # then fill it in
sudo cp deploy/publisher.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now publisher

# nginx already has the location block in deploy/neoncart.nginx
sudo cp deploy/neoncart.nginx /etc/nginx/sites-available/neoncart
sudo nginx -t && sudo systemctl reload nginx

# then in the store's .env
#   POST_WORKER_URL=http://127.0.0.1:3002/api
#   POST_WORKER_TOKEN=<the same value as PUBLISHER_TOKEN>
sudo systemctl restart neoncart
```

Check it:

```bash
curl -s localhost:3002/healthz
curl -s -H "Authorization: Bearer $PUBLISHER_TOKEN" localhost:3002/api/posts/pending | head -c 400
```

Leave `PUBLISHER_PUBLIC_URL` empty until the nginx location is actually serving.
The store falls back to showing the asset, which is better than framing a URL
that 404s.

## Known gaps

- **The preview is a stand-in.** The contract wants it rendered with the same
  components as the Studio's preview pane, so what you see is what you wrote.
  Those are React with `@sanity/ui` and styled-components, and server-rendering
  them means pulling that tree into a service that currently has no
  dependencies. `preview.mjs` renders plain HTML from the same platform spec —
  the caption ceiling and the frame are right, the chrome is approximate.
- **Video duration is never checked.** Sanity stores no duration in asset
  metadata and this process has no decoder, so `preflight` takes its
  "could not read how long this runs" branch and warns instead of blocking. The
  Studio measures it in the browser and will refuse a clip this lets through.
- **Nothing is sent.** No platform credentials, no OAuth, no posting. That is
  the next half, and it is also what owes the store a
  `POST /api/v1/published_posts` call after a successful send.
- **13 of the limits it enforces are still marked `verified: false`** in the
  CMS's `platformSpec.ts` — the caption and hashtag ceilings, the video
  durations, and all of Facebook. `npm run vendor` lists them. They were advisory
  when only a preview read them; here they block approval.
