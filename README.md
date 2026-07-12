# Neoncart — self-hosted store for Ever Fluorescent

Rails 7.1 ecommerce app: Stripe Checkout (card / Google Pay / Apple Pay),
dropshipper integrations (Printify wired end-to-end; ThisNew, ArtsAdd,
Yoycol via configurable adapters + manual queue), branded shipping
emails with free tracking links, support ticket desk, and a partner
REST API + signed webhooks for FestConnect / goVend.

No paid add-on services: jobs run on GoodJob (Postgres — your Neon DB),
images on local disk via Active Storage, tracking via free carrier links,
email over plain SMTP.

## Stack
Rails 7.1 · PostgreSQL (Neon) · Puma · Hotwire (importmap, no Node) ·
Devise · Stripe · GoodJob · Faraday

## First-time setup

```bash
sudo apt install libvips            # image variants
bundle install
cp .env.example .env                # then fill it in
bin/setup                           # installs GoodJob tables, migrates, seeds
bin/rails s
```

Seeds create the admin user from `ADMIN_EMAIL` / `ADMIN_PASSWORD`, four
suppliers (Printify auto, the other three manual), and base categories.
Sign in at `/admin`.

## Wiring things up

**Stripe** — put `sk_live_…` in `.env`. In the Stripe Dashboard create a
webhook endpoint pointing at `https://YOUR_HOST/webhooks/stripe` with
events `checkout.session.completed`, `checkout.session.async_payment_succeeded`,
`checkout.session.async_payment_failed`; copy its signing secret to
`STRIPE_WEBHOOK_SECRET`. Google Pay / Apple Pay toggle on in Dashboard →
Payment methods — Checkout picks them up automatically.

**Printify** — Printify → My Profile → Connections → generate a Personal
Access Token. Admin → Suppliers → Printify → paste as API key → *Test
connection* (auto-detects your shop) → *Sync now*. Synced products land
as **drafts**; review pricing, flip to active.

**ThisNew / ArtsAdd / Yoycol** — their APIs are partner-gated (no public
docs; they mainly ship Shopify apps). Until you're granted access they
run in **manual mode**: paid items for them appear in Admin →
Fulfillment queue; you place the order on their site, paste their order
ID, and add tracking from the order page when it ships — customer
emails/webhooks stay fully automated. When credentials arrive, set the
supplier's base URL + key, adjust endpoint paths/JSON keys in Settings
JSON (see `app/services/dropshipping/generic_pod_adapter.rb`), switch to
auto.

**Adding another dropshipper** — subclass `BaseAdapter` or
`GenericPodAdapter`, register it in `Dropshipping::Registry`, create the
supplier in admin. Nothing else changes.

## Order lifecycle (all automated)

1. Checkout → Stripe session → webhook confirms payment
2. `SubmitOrderToSuppliersJob` pushes items to auto suppliers / queues manual ones
3. Confirmation email + `order.paid` webhook fire
4. `SyncTrackingJob` (every 30 min) pulls shipments → shipped email with
   tracking links (free carrier URLs, 17TRACK fallback) → `order.shipped` webhook
5. All delivered → order marked delivered, status email

Customers track at `/track` with order number + email — no account needed.
Support tickets: customer replies and your admin replies both trigger emails.

## Partner API (FestConnect / goVend)

Admin → API keys → generate a key (token shown once). Docs live at
Admin → API docs: list products, create orders (hosted-checkout or
already-paid modes), poll status, plus HMAC-signed outbound webhooks.
Add partner domains to `ALLOWED_ORIGINS` for browser calls.

## Deploying on the Jetson

```bash
RAILS_ENV=production bundle exec rails assets:precompile
sudo cp deploy/neoncart.service deploy/neoncart-worker.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now neoncart neoncart-worker
```

Nginx sample in `deploy/nginx.conf.example` (same shape as your goVend
config — works behind a Cloudflare Tunnel too). The **worker service is
required**: without it nothing gets submitted, synced, or emailed.

Heads-up on Neon: GoodJob polls the database, so the Neon compute stays
awake continuously — fine on the free/launch plans, just don't expect
scale-to-zero.

## Env reference
See `.env.example` — every setting is documented inline.
