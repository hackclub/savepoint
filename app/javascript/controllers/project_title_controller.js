import { Controller } from "@hotwired/stimulus"

// Your project's name, renamable in place like the document's: click it, type, then Enter (or click away) to save
// it, or Escape to put it back.
export default class extends Controller {
  static targets = [ "view", "form", "input" ]

  edit() {
    this.before = this.inputTarget.value
    this.viewTarget.hidden = true
    this.formTarget.hidden = false
    this.inputTarget.focus()
    this.inputTarget.select()
  }

  key(event) {
    if (event.key === "Enter") {
      this.submitting = true // the form submits itself; don't again when the field blurs
    } else if (event.key === "Escape") {
      event.preventDefault()
      this.inputTarget.value = this.before
      this.#close()
    }
  }

  // Clicking away saves, unless nothing changed.
  commit() {
    if (this.formTarget.hidden || this.submitting) return
    if (this.inputTarget.value.trim() === this.before.trim()) return this.#close()
    this.submitting = true
    this.formTarget.requestSubmit()
  }

  #close() {
    this.formTarget.hidden = true
    this.viewTarget.hidden = false
    this.viewTarget.focus()
  }
}
