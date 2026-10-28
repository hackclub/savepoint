import { Controller } from "@hotwired/stimulus"

// Saves each reviewer checklist tick as it happens (D-049), and keeps the "N of 7" in the section's summary current (D-106).
export default class extends Controller {
  static values = { url: String }
  static targets = [ "count" ]

  save(event) {
    // D-050: the saved tick owns the value now, so its "auto" tag goes.
    event.target.closest("label")?.querySelector("[data-checklist-target=auto]")?.remove()
    this.#count()
    const token = document.querySelector("meta[name=csrf-token]")?.content
    const body = new URLSearchParams({ key: event.target.name, value: event.target.checked ? "1" : "0" })
    fetch(this.urlValue, { method: "PATCH", body, headers: { "X-CSRF-Token": token } })
  }

  #count() {
    if (this.hasCountTarget) this.countTarget.textContent = this.element.querySelectorAll("input[type=checkbox]:checked").length
  }
}
