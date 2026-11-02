import { Controller } from "@hotwired/stimulus"

// D-135: saves the review form as a draft while the reviewer types. A change waits 800 ms for the next one, then goes to the server
// as a fetch. When the page hides it goes at once as a beacon, which survives the page unloading. Only the fields that changed are
// sent, and the server merges them, so a draft another admin wrote is kept. A verdict submit drops what is waiting: the verdict
// uses the draft up. The lapse and AI forms sit outside this form, so the listener is on the document.
const DELAY_MS = 800
const FIELDS = {
  coding_hours: "#verdict [name=coding_hours]",
  art_hours: "#verdict [name=art_hours]",
  technical_features: "#verdict [name=technical_features]",
  deflation_reason: "#verdict [name=deflation_reason]",
  evidence: "#verdict [name=evidence]",
  judgement: "#verdict [name=review_judgement]",
  feedback: "#verdict [name=review_feedback]",
  lapse_coding_hours: "#lapse-split [name=lapse_coding_hours]",
  ai_coding_hours: "#reviewer-ai [name=reviewer_ai_coding_hours]",
  ai_reason: "#reviewer-ai [name=reviewer_ai_reason]"
}

export default class extends Controller {
  static targets = [ "status" ]
  static values = { url: String }

  connect() {
    this.dirty = new Set()
    this.timer = null
    this.submitted = false
    this.onInput = (event) => this.#touch(event.target)
    this.onClick = (event) => { if (event.target.closest("[data-verdict]")) this.#mark("decision") }
    this.onHide = () => { if (document.visibilityState === "hidden") this.#beacon() }
    this.onPageHide = () => this.#beacon()
    this.onSubmit = (event) => { if (event.target === this.element) this.#stop() }
    document.addEventListener("input", this.onInput)
    this.element.addEventListener("click", this.onClick)
    this.element.addEventListener("submit", this.onSubmit)
    document.addEventListener("visibilitychange", this.onHide)
    window.addEventListener("pagehide", this.onPageHide)
  }

  disconnect() {
    document.removeEventListener("input", this.onInput)
    this.element.removeEventListener("click", this.onClick)
    this.element.removeEventListener("submit", this.onSubmit)
    document.removeEventListener("visibilitychange", this.onHide)
    window.removeEventListener("pagehide", this.onPageHide)
    clearTimeout(this.timer)
  }

  #touch(target) {
    const key = Object.keys(FIELDS).find((name) => target.matches?.(FIELDS[name]))
    if (!key) return
    this.#mark(key)
    // Coding moves the art limit, which can lower the art field with no event of its own.
    if (key === "coding_hours") this.#mark("art_hours")
  }

  #mark(key) {
    if (this.submitted) return
    this.dirty.add(key)
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.#save(), DELAY_MS)
  }

  #stop() {
    this.submitted = true
    this.dirty.clear()
    clearTimeout(this.timer)
  }

  #body() {
    const body = new FormData()
    this.dirty.forEach((key) => {
      const value = key === "decision" ? document.querySelector("#verdict-submit")?.value : document.querySelector(FIELDS[key])?.value
      if (value !== undefined) body.append(`draft[${key}]`, value)
    })
    return body
  }

  #save() {
    if (!this.dirty.size || this.submitted) return
    const body = this.#body()
    this.dirty.clear()
    const token = document.querySelector("meta[name=csrf-token]")?.content
    fetch(this.urlValue, { method: "POST", body, headers: { "X-CSRF-Token": token, Accept: "application/json" }, keepalive: true })
      .then((response) => (response.ok ? response.json() : null))
      .then((saved) => { if (saved && this.hasStatusTarget) this.statusTarget.textContent = `Draft saved just now by ${saved.by}.` })
      .catch(() => {})
  }

  #beacon() {
    if (!this.dirty.size || this.submitted || !navigator.sendBeacon) return
    const body = this.#body()
    body.append("authenticity_token", document.querySelector("meta[name=csrf-token]")?.content || "")
    this.dirty.clear()
    clearTimeout(this.timer)
    navigator.sendBeacon(this.urlValue, body)
  }
}
