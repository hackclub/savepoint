import { Controller } from "@hotwired/stimulus"

// The project page's "you've earned it" popup. It rides on prize_sheet_controller (same element), which owns the dialog, the
// claim step and the sounds. This one opens it a moment after the page is up, and tells the server it was shown for this
// goal, so it never opens twice for the same one (GoalSeensController).
export default class extends Controller {
  static values = { seenUrl: String, delay: { type: Number, default: 700 } }

  connect() {
    this.timer = setTimeout(() => this.#show(), this.delayValue)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  #show() {
    const sheet = this.application.getControllerForElementAndIdentifier(this.element, "prize-sheet")
    if (!sheet || sheet.dialogTarget.open) return

    sheet.open()
    fetch(this.seenUrlValue, {
      method: "POST",
      credentials: "same-origin",
      headers: { "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || "", Accept: "application/json" }
    }).catch(() => {})
  }
}
