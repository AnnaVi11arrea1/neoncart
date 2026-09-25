# The post queue contract

Two halves talk to each other: this store and the **publisher**, the service that
drafts social posts from the catalog and sends them. This file is the contract
between them. The store half is built (`Admin::PostQueueController`,
`PostQueue::Client`), and the publisher half now answers it from `publisher/` —
`GET /posts/pending`, the decision endpoint and the preview, with its own README.
What it still does not do is send: see **What the publisher still owes** at the
bottom, which is unchanged.

## Why the store calls out instead of reading the CMS itself

The posts live in the CMS, and this app deliberately holds **no CMS credential**.
A Sanity token cannot be narrowed to one dataset or one document type without an
Enterprise plan, so a token kept here would also read the private knowledge-base
notes that sit in the same project. The publisher already holds that credential
because it has to, so it serves the queue and takes the decisions, and the store
holds exactly one secret: a token for the publisher.

## Configuration on the store side

| Variable | Meaning |
| --- | --- |
| `POST_WORKER_URL` | Base URL of the publisher's API, e.g. `https://publish.everfluorescent.com/api` |
| `POST_WORKER_TOKEN` | Bearer token the store sends on every call |
| `CMS_STUDIO_URL` | Where the Studio is reachable, for the "Open in the CMS" link. Defaults to `http://localhost:3333` |

With either of the first two unset, the queue page says the publisher is not
connected and nothing can be approved. It does not show an empty queue, because
an empty queue reads as "nothing to approve".

Every request carries `Authorization: Bearer $POST_WORKER_TOKEN`. Timeouts are 8
seconds to connect and 15 seconds in total; past that the page says the publisher
did not answer and no decision has been recorded.

## `GET {base}/posts/pending`

Returns the posts awaiting a decision, in the order they should be shown —
the store does not re-sort them.

```json
{
  "posts": [
    {
      "id": "drafts.post-8f21",
      "caption": "the moth print is back, 40 made",
      "platform": "instagram",
      "post_format": "reel",
      "asset_url": "https://cdn.sanity.io/files/…/clip.mp4",
      "asset_kind": "video",
      "preview_url": "https://publish.everfluorescent.com/api/preview?id=…&exp=…&sig=…",
      "updated_at": "2026-09-21T18:04:00Z",
      "products": [{ "store_id": 412, "title": "Neon Moth print" }],
      "verdict": {
        "ok": false,
        "errors": [{ "message": "No price on Neon Moth print, so the shop link cannot be built" }],
        "warnings": [{ "message": "Clip is 91s; Instagram reels allow 90s" }]
      }
    }
  ]
}
```

A bare JSON array is accepted too.

**Answer with a JSON content-type.** The store tells "unreadable" from "empty" by
the shape of what comes back, so a `200` carrying HTML — a sign-in page, a
deployment-protection interstitial, a proxy notice — is the failure that reads as
success. Anything that is not a JSON array, or an object with an array under
`posts`, raises and the page says it could not load the queue; it never renders as
"nothing waiting".

Every field except `id` is optional, and the page is built to survive any of them
missing — a queue that 500s because one post has no caption is worse than one that
shows the caption blank. An entry with no `id` is dropped and logged, because
there is nothing to address a decision to.

- `id` — addresses ONE variant, and is the one field that must be there. A post
  with a Facebook and an Instagram variant is two rows with two captions and two
  previews, so the id is the CMS document id, then `__`, then the variant key:
  `drafts.post-8f21__ig`. The document id contains a dot, which the store escapes
  and routes around; send the whole thing exactly as the publisher formed it. The
  store splits on the LAST `__` when it needs the document on its own, to link
  into the Studio.
- `preview_url` — a page rendering this variant as the platform will show it,
  which the store embeds in a sandboxed iframe. It is not behind the bearer
  token, because an iframe sends no Authorization header; it carries a signature
  and an expiry instead, and the publisher refuses an unsigned or stale one.
  Optional: without it the store falls back to showing the asset.
- `asset_kind` — `image` or `video`. Anything else is ignored and the asset is
  offered as a link rather than shown inline.
- `products[].store_id` — this store's numeric product id, which the CMS already
  tracks as `storeId`. It is what makes the queue able to link to the real
  product here. A post whose product is no longer in the store still lists it, by
  title, without a link.
- `verdict.ok: false`, or any entry in `verdict.errors`, marks the post
  **blocked**: the page shows what is wrong and offers no approve button, only
  reject. That is deliberate — a post missing a required field is flagged and
  held, never quietly skipped.
- `verdict.warnings` are shown and do not block.
- **No `verdict` at all is not a clean one.** The page says so rather than
  showing a green tick.

## `POST {base}/posts/{id}/decision`

```json
{ "decision": "approved", "actor": "anna@everfluorescent.com", "note": null }
```

`decision` is `approved` or `rejected`; the store refuses anything else before it
sends. `actor` is the signed-in admin's email. `note` is omitted when blank.

Any 2xx is success. On a non-2xx, the store shows the status and, if the body
carries `{"error": "…"}` or `{"message": "…"}`, that text verbatim (truncated to
200 characters) — so a refusal should say why in one sentence a person can read.

## What a decision does today

Approving records that Anna said yes — who and when — and leaves the variant's
status alone, because `approved` is the state the sending half will read and
overloading it to mean two things is how a post ends up somewhere nothing is
looking. A decided variant leaves this queue because it has been decided, not
because its status moved. Rejecting hands it back as a draft, with the note.

The publisher re-runs the checks before it accepts an approval rather than
trusting what this page showed, so a post that went stale between the page
loading and the button being pressed is refused with a reason. A blocked post can
still be rejected; that is how it gets cleared.

**Nothing is sent to any platform.** That half does not exist yet.

The publisher does re-run the checks at decision time, as below, and refuses a
stale approval with the reason. Two caveats on what that verdict is worth: video
duration is never checked, because Sanity stores no duration and the publisher
has no decoder, so a clip the Studio would refuse can be approved here; and the
preview is plain HTML from the same platform spec rather than the Studio's own
React components, so the limits are right and the chrome is approximate.

## What the publisher still owes

- **Re-run the checks at send time.** Whatever verdict the queue showed is
  advisory: a product's price or image can change between the check and the send,
  and a green tick that cannot notice that is the bug it was meant to prevent.
- **Record what went out.** After a successful send, `POST /api/v1/published_posts`
  on this store with an API key carrying the `posts:write` scope. That endpoint is
  documented in the admin under **API docs**, and it is idempotent on
  `sanity_attempt_id`, so retrying a send that may already have landed is safe.
