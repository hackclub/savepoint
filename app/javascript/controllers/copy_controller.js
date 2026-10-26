import { Controller } from "@hotwired/stimulus"

// Copies some text (a buddy invite link) and says so on the button for a moment.
export default class extends Controller {
  static targets = [ "button", "label" ]
  static values = { text: String }

  copy() {
    navigator.clipboard?.writeText(this.textValue).catch(() => {})
    this.before ??= this.labelTarget.textContent
    this.labelTarget.textContent = "Copied"
    clearTimeout(this.timer)
    this.timer = setTimeout(() => (this.labelTarget.textContent = this.before), 2000)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
