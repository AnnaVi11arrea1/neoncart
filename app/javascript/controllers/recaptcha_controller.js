import { Controller } from "@hotwired/stimulus"

// reCAPTCHA v2 "I'm not a robot" checkbox that keeps the submit button
// hidden until it's ticked, and hides it again if the tick expires.
//   <div data-controller="recaptcha" data-recaptcha-site-key-value="...">
//     <div data-recaptcha-target="widget"></div>
//     <input type="submit" hidden data-recaptcha-target="submit">
//   </div>
// Rendered explicitly rather than by api.js scanning the page: with Turbo,
// api.js only loads once, so a later visit or a 422 re-render of the form
// would otherwise come up with no checkbox at all.
let apiLoaded

function loadApi() {
  apiLoaded ||= new Promise((resolve, reject) => {
    window.recaptchaApiReady = resolve
    const script = document.createElement("script")
    script.src = "https://www.google.com/recaptcha/api.js?onload=recaptchaApiReady&render=explicit"
    script.async = true
    script.onerror = () => { apiLoaded = null; reject(new Error("reCAPTCHA failed to load")) }
    document.head.appendChild(script)
  })
  return apiLoaded
}

export default class extends Controller {
  static targets = ["widget", "submit"]
  static values = { siteKey: String }

  async connect() {
    this.submitTarget.hidden = true
    await loadApi()
    if (!this.element.isConnected) return
    // A Turbo cache snapshot can bring back a dead copy of an earlier widget.
    this.widgetTarget.innerHTML = ""
    window.grecaptcha.render(this.widgetTarget, {
      sitekey: this.siteKeyValue,
      callback: () => { this.submitTarget.hidden = false },
      "expired-callback": () => { this.submitTarget.hidden = true }
    })
  }
}
