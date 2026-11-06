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
    const box = event.target
    fetch(this.urlValue, { method: "PATCH", body, headers: { "X-CSRF-Token": token, Accept: "application/json" } }).then(async (response) => {
      if (response.ok) return
      // D-152: a refused tick (Real name with a missing or initial name) goes back, with the reason.
      const answer = await response.json().catch(() => ({}))
      box.checked = !box.checked
      this.#count()
      if (answer.error) window.alert(answer.error)
    })
  }

  #count() {
    if (this.hasCountTarget) this.countTarget.textContent = this.element.querySelectorAll("input[type=checkbox]:checked").length
  }
}
