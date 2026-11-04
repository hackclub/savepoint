import { Controller } from "@hotwired/stimulus"

// D-135: saves the review form as a draft while the reviewer types. A change waits 800 ms for the next one, then goes to the server
// as a fetch. When the page hides it goes at once as a beacon, which survives the page unloading. Only the fields that changed are
// sent, and the server merges them, so a draft another admin wrote is kept. A verdict submit drops what is waiting: the verdict
// uses the draft up. The lapse and AI forms sit outside this form, so the listener is on the document. Each save says which draft
// the page was filled from (loaded). When the server holds a newer one it answers 409: the page stops saving and tells the reviewer
// to reload, so text the browser restored on a reload (autocomplete="off" stops most of it) never lands over a newer save.
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
  static values = { url: String, loaded: String }

  connect() {
    this.dirty = new Set()
    this.stale = false
    this.unchecked = false
    this.loaded = this.loadedValue
    this.timer = null
    this.submitted = false
    this.onInput = (event) => this.#touch(event.target)
    this.onClick = (event) => { if (event.target.closest("[data-verdict]")) this.#mark("decision") }
    this.onHide = () => { if (document.visibilityState === "hidden") this.#beacon() }
    this.onPageHide = () => this.#beacon()
    this.onSubmit = (event) => this.#submitted(event)
    document.addEventListener("input", this.onInput)
    this.element.addEventListener("click", this.onClick)
    document.addEventListener("submit", this.onSubmit, true)
    document.addEventListener("visibilitychange", this.onHide)
    window.addEventListener("pagehide", this.onPageHide)
  }

  disconnect() {
    document.removeEventListener("input", this.onInput)
    this.element.removeEventListener("click", this.onClick)
    document.removeEventListener("submit", this.onSubmit, true)
    document.removeEventListener("visibilitychange", this.onHide)
    window.removeEventListener("pagehide", this.onPageHide)
    clearTimeout(this.timer)
  }

  // The verdict submit drops what waits: the verdict uses the draft up. Any other form (Set Lapse coding, Set AI coding, hours start)
  // reloads the page, so the draft is saved first and the form is sent once the save has landed. The page then fills from the draft.
  #submitted(event) {
    const form = event.target
    if (form === this.element) return this.#stop()
    if (this.resubmitting === form || !this.dirty.size || this.submitted) return
    event.preventDefault()
    clearTimeout(this.timer)
    const submitter = event.submitter
    this.#save().finally(() => {
      this.resubmitting = form
      form.requestSubmit(submitter)
    })
  }

  #touch(target) {
    const key = Object.keys(FIELDS).find((name) => target.matches?.(FIELDS[name]))
    if (!key) return
    this.#mark(key)
    // Coding moves the art limit, which can lower the art field with no event of its own.
    if (key === "coding_hours") this.#mark("art_hours")
  }

  #mark(key) {
    if (this.submitted || this.stale) return
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
    // After a beacon the page doesn't know the time the server stored, so the next save goes unchecked and learns it from the answer.
    if (!this.unchecked) body.append("loaded_at", this.loaded || "")
    this.dirty.forEach((key) => {
      const value = key === "decision" ? document.querySelector("#verdict-submit")?.value : document.querySelector(FIELDS[key])?.value
      if (value !== undefined) body.append(`draft[${key}]`, value)
    })
    return body
  }

  // Saves go one at a time, so each carries the time the one before it stored.
  #save() {
    this.pending = (this.pending || Promise.resolve()).then(() => this.#send())
    return this.pending
  }

  #send() {
    if (!this.dirty.size || this.submitted || this.stale) return Promise.resolve()
    const body = this.#body()
    this.dirty.clear()
    const token = document.querySelector("meta[name=csrf-token]")?.content
    return fetch(this.urlValue, { method: "POST", body, headers: { "X-CSRF-Token": token, Accept: "application/json" }, keepalive: true })
      .then((response) => (response.ok || response.status === 409 ? response.json().then((json) => ({ ok: response.ok, json })) : null))
      .then((result) => {
        if (!result) return
        if (!result.ok) {
          this.stale = true
          if (this.hasStatusTarget) this.statusTarget.textContent = result.json.error
          return
        }
        this.loaded = result.json.at || ""
        this.unchecked = false
        if (this.hasStatusTarget) this.statusTarget.textContent = `Draft saved just now by ${result.json.by}.`
      })
      .catch(() => {})
  }

  #beacon() {
    if (!this.dirty.size || this.submitted || this.stale || !navigator.sendBeacon) return
    const body = this.#body()
    body.append("authenticity_token", document.querySelector("meta[name=csrf-token]")?.content || "")
    this.dirty.clear()
    clearTimeout(this.timer)
    this.unchecked = true
    navigator.sendBeacon(this.urlValue, body)
  }
}
