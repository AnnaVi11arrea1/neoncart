import { Controller } from "@hotwired/stimulus"

// Stripe Terminal point-of-sale for in-person card-present sales.
// Flow per https://docs.stripe.com/terminal/quickstart?platform=web :
//   1. StripeTerminal.create({ onFetchConnectionToken })
//   2. discoverReaders({ simulated }) -> connectReader(reader)
//   3. server creates a card_present PaymentIntent (manual capture)
//   4. collectPaymentMethod(clientSecret) -> processPayment(paymentIntent)
//   5. server captures the PaymentIntent and finalizes the order
export default class extends Controller {
  static targets = [
    "readerStatus", "connectButton", "simulated",
    "cart", "total", "email", "customLabel", "customAmount", "shipping",
    "chargeButton", "log", "receipt"
  ]

  connect() {
    this.terminal = null
    this.reader = null
    this.cart = []       // [{ key, slug, variant_id, title, unit, qty }]
    this.charging = false
    this.renderCart()
    this.setReaderStatus("Not connected", "pending")
  }

  // ---- SDK bootstrap -------------------------------------------------------

  // Load https://js.stripe.com/terminal/v1/ on demand so it survives Turbo
  // navigations (no reliance on a <script> tag being re-executed).
  loadSdk() {
    if (window.StripeTerminal) return Promise.resolve()
    if (this._sdkPromise) return this._sdkPromise
    this._sdkPromise = new Promise((resolve, reject) => {
      const s = document.createElement("script")
      s.src = "https://js.stripe.com/terminal/v1/"
      s.onload = () => resolve()
      s.onerror = () => reject(new Error("Could not load the Stripe Terminal SDK."))
      document.head.appendChild(s)
    })
    return this._sdkPromise
  }

  async ensureTerminal() {
    await this.loadSdk()
    if (this.terminal) return this.terminal
    this.terminal = window.StripeTerminal.create({
      onFetchConnectionToken: async () => {
        const res = await this.postJSON("/admin/terminal/connection_token")
        if (res.error) throw new Error(res.error)
        return res.secret
      },
      onUnexpectedReaderDisconnect: () => {
        this.reader = null
        this.setReaderStatus("Reader disconnected", "cancelled")
        this.log("⚠️ Reader disconnected unexpectedly.")
      }
    })
    return this.terminal
  }

  // ---- Reader connection ---------------------------------------------------

  async connectReader() {
    this.connectButtonTarget.disabled = true
    try {
      const terminal = await this.ensureTerminal()
      const simulated = this.hasSimulatedTarget ? this.simulatedTarget.checked : true
      this.setReaderStatus("Discovering readers…", "processing")

      const discovery = await terminal.discoverReaders({ simulated })
      if (discovery.error) throw new Error(discovery.error.message)
      if (!discovery.discoveredReaders || discovery.discoveredReaders.length === 0) {
        throw new Error(simulated ? "No simulated reader available." :
          "No readers found. Make sure a reader is registered, online, and on the same network.")
      }

      const reader = discovery.discoveredReaders[0]
      const conn = await terminal.connectReader(reader)
      if (conn.error) throw new Error(conn.error.message)

      this.reader = conn.reader
      this.setReaderStatus(`Connected: ${this.reader.label || this.reader.id}${simulated ? " (simulated)" : ""}`, "paid")
      this.log(`✅ Connected to reader ${this.reader.label || this.reader.id}.`)
    } catch (e) {
      this.setReaderStatus("Not connected", "cancelled")
      this.log(`❌ ${e.message}`)
    } finally {
      this.connectButtonTarget.disabled = false
      this.updateChargeButton()
    }
  }

  // ---- Cart building -------------------------------------------------------

  addItem(event) {
    const row = event.currentTarget.closest("[data-pos-product]")
    const select = row.querySelector("[data-pos-variant]")
    const opt = select ? select.selectedOptions[0] : null
    const slug = row.dataset.slug
    const qtyInput = row.querySelector("[data-pos-qty]")
    const qty = Math.max(parseInt(qtyInput?.value, 10) || 1, 1)

    const variantId = opt ? opt.value : ""
    const unit = opt ? parseInt(opt.dataset.price, 10) : parseInt(row.dataset.price, 10)
    const vTitle = opt && opt.dataset.title ? opt.dataset.title : ""
    const title = [row.dataset.title, vTitle].filter(Boolean).join(" — ")
    const key = `${slug}:${variantId}`

    const existing = this.cart.find((i) => i.key === key)
    if (existing) {
      existing.qty += qty
    } else {
      this.cart.push({ key, slug, variant_id: variantId, title, unit, qty })
    }
    this.renderCart()
  }

  removeItem(event) {
    const key = event.currentTarget.dataset.key
    this.cart = this.cart.filter((i) => i.key !== key)
    this.renderCart()
  }

  filterCatalog(event) {
    const q = event.target.value.toLowerCase()
    this.element.querySelectorAll("[data-pos-product]").forEach((row) => {
      row.hidden = q && !row.dataset.title.toLowerCase().includes(q)
    })
  }

  customAmountCents() {
    const dollars = parseFloat(this.hasCustomAmountTarget ? this.customAmountTarget.value : "")
    return Number.isFinite(dollars) && dollars > 0 ? Math.round(dollars * 100) : 0
  }

  shippingParams() {
    const out = {}
    if (this.hasShippingTarget) {
      this.shippingTarget.querySelectorAll("input[name]").forEach((i) => {
        if (i.value.trim()) out[i.name] = i.value.trim()
      })
    }
    return out
  }

  totalCents() {
    return this.cart.reduce((sum, i) => sum + i.unit * i.qty, 0) + this.customAmountCents()
  }

  renderCart() {
    if (this.hasCartTarget) {
      if (this.cart.length === 0) {
        this.cartTarget.innerHTML = `<p class="hint">No items yet — add products or enter a custom amount.</p>`
      } else {
        this.cartTarget.innerHTML = this.cart.map((i) => `
          <div class="pos-line">
            <span class="pos-line__title">${this.escape(i.title)} <span class="hint">×${i.qty}</span></span>
            <span class="pos-line__price mono">${this.money(i.unit * i.qty)}</span>
            <button type="button" class="btn btn--ghost btn--sm" data-action="terminal#removeItem" data-key="${i.key}">✕</button>
          </div>`).join("")
      }
    }
    if (this.hasTotalTarget) this.totalTarget.textContent = this.money(this.totalCents())
    this.updateChargeButton()
  }

  updateChargeButton() {
    if (!this.hasChargeButtonTarget) return
    this.chargeButtonTarget.disabled = this.charging || !this.reader || this.totalCents() <= 0
  }

  // ---- Charge (collect -> process -> capture) ------------------------------

  async charge() {
    if (this.charging) return
    if (!this.reader) { this.log("Connect a reader first."); return }
    const amount = this.totalCents()
    if (amount <= 0) { this.log("Add something to charge."); return }

    this.charging = true
    this.updateChargeButton()
    if (this.hasReceiptTarget) this.receiptTarget.hidden = true

    try {
      // 1) Order + PaymentIntent on the server (amount computed server-side)
      this.log(`Creating payment for ${this.money(amount)}…`)
      const intentRes = await this.postJSON("/admin/terminal/payment_intent", {
        items: this.cart.map((i) => ({ slug: i.slug, variant_id: i.variant_id, quantity: i.qty })),
        custom_cents: this.customAmountCents(),
        custom_label: this.hasCustomLabelTarget ? this.customLabelTarget.value : "",
        email: this.hasEmailTarget ? this.emailTarget.value : "",
        shipping: this.shippingParams()
      })
      if (intentRes.error) throw new Error(intentRes.error)

      // 2) Collect the card on the reader
      this.log("Present card on the reader…")
      const collect = await this.terminal.collectPaymentMethod(intentRes.client_secret)
      if (collect.error) throw new Error(collect.error.message)

      // 3) Process the payment (authorizes -> requires_capture)
      this.log("Processing payment…")
      const process = await this.terminal.processPayment(collect.paymentIntent)
      if (process.error) throw new Error(process.error.message)

      const pi = process.paymentIntent
      // 4) Capture server-side
      if (pi.status === "requires_capture" || pi.status === "requires_confirmation") {
        this.log("Capturing…")
        const cap = await this.postJSON("/admin/terminal/capture", { payment_intent_id: pi.id })
        if (cap.error) throw new Error(cap.error)
        this.succeed(cap.order_number, amount)
      } else if (pi.status === "succeeded") {
        this.succeed(intentRes.order_number, amount)
      } else {
        throw new Error(`Unexpected payment status: ${pi.status}`)
      }
    } catch (e) {
      this.log(`❌ ${e.message}`)
    } finally {
      this.charging = false
      this.updateChargeButton()
    }
  }

  succeed(orderNumber, amount) {
    this.log(`✅ Paid ${this.money(amount)} — order ${orderNumber}.`)
    if (this.hasReceiptTarget) {
      this.receiptTarget.hidden = false
      this.receiptTarget.innerHTML =
        `<strong>Payment successful</strong> · ${this.money(amount)} · order <span class="mono">${orderNumber}</span>`
    }
    // reset the sale
    this.cart = []
    if (this.hasCustomAmountTarget) this.customAmountTarget.value = ""
    if (this.hasCustomLabelTarget) this.customLabelTarget.value = ""
    if (this.hasEmailTarget) this.emailTarget.value = ""
    if (this.hasShippingTarget) {
      this.shippingTarget.querySelectorAll("input[name]").forEach((i) => { i.value = i.name === "country" ? "US" : "" })
    }
    this.renderCart()
  }

  // ---- helpers -------------------------------------------------------------

  async postJSON(url, body = {}) {
    const res = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": this.csrfToken()
      },
      body: JSON.stringify(body)
    })
    try { return await res.json() } catch { return { error: `Request failed (HTTP ${res.status}).` } }
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  setReaderStatus(text, kind) {
    if (!this.hasReaderStatusTarget) return
    this.readerStatusTarget.textContent = text
    this.readerStatusTarget.className = `chip chip--${kind}`
  }

  log(message) {
    if (!this.hasLogTarget) return
    const time = new Date().toLocaleTimeString()
    this.logTarget.insertAdjacentHTML("afterbegin", `<div>${time} — ${this.escape(message)}</div>`)
  }

  money(cents) { return `$${(cents / 100).toFixed(2)}` }

  escape(str) {
    const d = document.createElement("div")
    d.textContent = str == null ? "" : String(str)
    return d.innerHTML
  }
}
