import { Controller } from "@hotwired/stimulus"

// The NPS popup on the project page. It opens a moment after the page is up, unless it was skipped less than
// `hours` ago in this browser (localStorage, which may be blocked: then it just opens). Skip, Escape and a click
// on the backdrop all count as a skip. An answer spares the participant on the server (NpsResponse).
const KEY = "save-point:nps-skipped-at"

export default class extends Controller {
  static targets = [ "dialog" ]
  static values = { hours: { type: Number, default: 12 }, delay: { type: Number, default: 1500 } }

  connect() {
    this.onCancel = () => this.#remember()
    this.dialogTarget.addEventListener("cancel", this.onCancel)
    if (this.#skippedRecently()) return
    this.timer = setTimeout(() => {
      if (!document.querySelector("dialog[open]")) this.dialogTarget.showModal()
    }, this.delayValue)
  }

  disconnect() {
    clearTimeout(this.timer)
    this.dialogTarget.removeEventListener("cancel", this.onCancel)
  }

  skip() {
    this.#remember()
    this.dialogTarget.close()
  }

  closeOutside(event) {
    if (event.target === this.dialogTarget) this.skip()
  }

  #remember() {
    try { localStorage.setItem(KEY, String(Date.now())) } catch (_) { /* blocked: it asks again next visit */ }
  }

  #skippedRecently() {
    try {
      const at = Number(localStorage.getItem(KEY))
      return at > 0 && Date.now() - at < this.hoursValue * 3600 * 1000
    } catch (_) {
      return false
    }
  }
}
