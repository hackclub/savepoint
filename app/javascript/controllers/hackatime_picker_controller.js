import { Controller } from "@hotwired/stimulus"

// The Hackatime project list: a tick or an untick saves on its own (no button), a moment after the last one. What is saved is
// the list of ticked projects, so an unticked one really is unlinked. With none ticked nothing is sent, since hours need a
// project: it says so and keeps what was saved.
// mode "swap" stays where it is and swaps the page parts named in `swap` (the project page's chips and schedule).
// mode "page" goes back to the project page once saved (the steps move on). mode "json" stays where it is and says what it saved
// ("hackatime-picker:saved", with the projects and the hours), so the ship page can update itself without losing what was typed.
export default class extends Controller {
  static targets = [ "box", "status" ]
  static values = { url: String, mode: { type: String, default: "page" }, swap: { type: Array, default: [] } }

  disconnect() { clearTimeout(this.timer) }

  change(event) {
    if (!this.boxTargets.includes(event.target)) return
    clearTimeout(this.timer)
    const names = this.names()
    if (!names.length) return this.say("Pick at least one project: your hours come from it.", "error")
    this.say("Saving…")
    this.timer = setTimeout(() => this.save(names), 350)
  }

  names() { return this.boxTargets.filter((box) => box.checked).map((box) => box.value) }

  async save(names) {
    const body = new FormData()
    body.append("_method", "patch")
    names.forEach((name) => body.append("project[hackatime_project_names][]", name))
    const version = this.version = (this.version || 0) + 1
    try {
      const response = await fetch(this.urlValue, {
        method: "POST", body, credentials: "same-origin",
        headers: { "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || "", Accept: this.modeValue === "json" ? "application/json" : "text/html" }
      })
      if (version !== this.version) return // a newer save is on its way
      if (!response.ok) throw new Error(response.status)
      this.say("Saved", "saved")
      if (this.modeValue === "json") this.dispatch("saved", { detail: await response.json() })
      else if (this.modeValue === "swap") await this.swapParts(response)
      else window.Turbo ? window.Turbo.visit(this.urlValue.replace(/\/ship\/hackatime$/, ""), { action: "replace" }) : window.location.assign(this.urlValue)
    } catch {
      this.say("Couldn't save that. Try again.", "error")
    }
  }

  // The page parts that depend on the linked projects (the chips, the schedule and its hours) are swapped for the saved page's,
  // so the list itself, its open state and the scroll position stay as they are.
  async swapParts(response) {
    const doc = new DOMParser().parseFromString(await response.text(), "text/html")
    this.swapValue.forEach((selector) => {
      const fresh = doc.querySelector(selector)
      const current = document.querySelector(selector)
      if (fresh && current) current.replaceWith(document.importNode(fresh, true))
    })
    this.dispatch("saved", { detail: {} })
  }

  say(text, state = "") {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = text
    if (state) this.statusTarget.dataset.state = state
    else delete this.statusTarget.dataset.state
  }
}
