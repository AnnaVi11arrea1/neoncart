import { Controller } from "@hotwired/stimulus"

// Copy text to the clipboard. Put on a button:
//   <button data-controller="clipboard" data-action="clipboard#copy"
//           data-clipboard-text="...">Copy</button>
export default class extends Controller {
  async copy() {
    const text = this.element.dataset.clipboardText || ""
    try {
      await navigator.clipboard.writeText(text)
    } catch {
      const ta = document.createElement("textarea")
      ta.value = text
      ta.style.position = "fixed"
      ta.style.opacity = "0"
      document.body.appendChild(ta)
      ta.select()
      document.execCommand("copy")
      ta.remove()
    }
    const original = this.element.textContent
    this.element.textContent = "Copied ✓"
    setTimeout(() => { this.element.textContent = original }, 1500)
  }
}
