import { Controller } from "@hotwired/stimulus"

// The ship form and its checker (D-002). Two kinds of check tick themselves off as you fill the form in:
//   - the ones the form can answer alone (title, description, what you changed, screenshot), instantly; and
//   - the ones that need the internet (the repository is public and has a README, the playable link loads, commits since
//     Save Point began), which the server answers as JSON once you stop typing in the two link fields.
// Each check that isn't done yet has a Fix link that jumps to its field. The checker also previews the ship: its title
// and screenshot follow the form. Every ship needs a new screenshot (D-016), so an earlier one never counts. After a failed submit the screenshot just sent is carried, and counts.
// A check that is met shows its green check for a moment and then leaves the list (D-019). The ones already met when the page opens
// never show. A check that goes unmet again comes back.
// Ship it stays greyed out until every blocking check passes. A check the server couldn't run never blocks, and if the
// server can't be reached at all the form falls back to the local checks (the server still checks the form on submit).
export default class extends Controller {
  static targets = [ "title", "description", "changes", "count", "repo", "demo", "file", "preview", "placeholder", "confirm",
                     "submit", "check", "progress", "thumb", "thumbEmpty", "previewTitle", "allset", "hours" ]
  static values = { descriptionMin: Number, checksUrl: String, carried: Boolean }

  connect() {
    this.network = { status: "idle", items: {} }
    this.check()
    if (this.repoTarget.value.trim() || this.demoTarget.value.trim()) this.askServer()
  }

  disconnect() {
    clearTimeout(this.timer)
    this.abort?.abort()
  }

  check() {
    const length = this.descriptionTarget.value.trim().length
    const short = length < this.descriptionMinValue
    this.countTarget.textContent = short ? `${length} / ${this.descriptionMinValue} min` : `${length} characters`
    this.countTarget.toggleAttribute("data-enough", !short)

    const done = {
      title: Boolean(this.titleTarget.value.trim()),
      description: length > 0,
      descmin: !short,
      changes: Boolean(this.changesTarget.value.trim()),
      screenshot: this.fileTarget.files.length > 0 || this.carriedValue,
      confirm: this.confirmTarget.checked,
      repolink: this.looksLikeLink(this.repoTarget.value),
      demolink: this.looksLikeLink(this.demoTarget.value),
      // Linked, as the ticked rows say (no rows, because Hackatime couldn't be reached, leaves it as the server had it).
      hackatime: !this.element.querySelector("[data-hackatime-picker-target=box]") || this.element.querySelector("[data-hackatime-picker-target=box]:checked") !== null
    }

    const needs = [
      !done.title, !done.description, !done.descmin, !done.changes, !done.hackatime, !done.screenshot, !done.confirm,
      !done.repolink, !done.demolink, ...this.networkBlocking()
    ].filter(Boolean)
    // A check still being asked about holds the button off too, hidden or not.
    this.submitTarget.disabled = needs.length > 0 || this.network.status === "checking"
    this.previewTitleTarget.textContent = this.titleTarget.value.trim() || "Your game"

    this.checkTargets.filter(step => !step.dataset.network).forEach(step => this.settle(step, Boolean(done[step.dataset.check])))
    this.paintNetwork()
    this.gate()
    this.sort()
    this.progress()
    this.allSet()
  }

  // A web address, as far as the browser can tell. The server decides for real when it's sent.
  looksLikeLink(value) {
    return /^(https?:\/\/)?[^\s/.]+\.[^\s]{2,}$/i.test(value.trim())
  }

  // A check that looks at a link, or at an earlier check, isn't listed until it has something to say (D-020): nothing without its link,
  // nothing while it is waiting on another check or being asked, and nothing for a check that passes. Failed or doubtful, it is
  // listed. One that was listed stays until it has shown its green check and left.
  gate() {
    const repo = Boolean(this.repoTarget.value.trim()), demo = Boolean(this.demoTarget.value.trim())
    const needs = { repo: repo, readme: repo, readme_demo: repo && demo, demo: demo, commits: repo }
    this.checkTargets.filter(step => step.dataset.network).forEach(step => {
      const state = step.dataset.state
      // wait: nothing to look at yet. unchecked: GitHub or the host couldn't answer, which the participant is told nothing about (D-022).
      if (!needs[step.dataset.check] || state === "wait" || state === "unchecked") step.setAttribute("data-hidden", "")
      else if (state === "fail" || state === "warn") step.removeAttribute("data-hidden")
    })
    const description = this.descriptionTarget.value.trim().length
    const descmin = this.checkTargets.find(step => step.dataset.check === "descmin")
    descmin?.toggleAttribute("data-hidden", description === 0)
  }

  // Organised by severity: failed checks, then blockers not met, then warnings; the form's order within each. Re-sorted as states
  // change, with the rows sliding to their new places.
  sort() {
    const rank = step => {
      if (step.hasAttribute("data-done")) return Number(step.dataset.rank || 1) // keeps its place while it shows its green check
      const failed = step.dataset.state === "fail" || step.hasAttribute("data-error")
      const value = failed ? 0 : (step.dataset.blocker === "true" && step.dataset.state !== "warn" ? 1 : 2)
      step.dataset.rank = value
      return value
    }
    const ordered = [ ...this.checkTargets ].sort((a, b) => rank(a) - rank(b) || a.dataset.index - b.dataset.index)
    if (ordered.every((step, index) => step === this.checkTargets[index])) return
    const parent = ordered[0].parentElement
    const visible = ordered.filter(step => step.offsetParent)
    const before = new Map(visible.map(step => [ step, step.getBoundingClientRect().top ]))
    ordered.forEach(step => parent.appendChild(step))
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) return
    visible.forEach(step => {
      const shift = before.get(step) - step.getBoundingClientRect().top
      if (shift) step.animate([ { transform: `translateY(${shift}px)` }, { transform: "none" } ], { duration: 250, easing: "ease" })
    })
  }

  // A link changed: ask the server once typing stops.
  links() {
    clearTimeout(this.timer)
    this.abort?.abort()
    if (this.linkPair() === this.answered && this.answers) { // back to links already answered: nothing to ask
      this.network = this.answers
      return this.check()
    }
    this.network = { status: "checking", items: {} }
    this.check()
    this.timer = setTimeout(() => this.askServer(), 700)
  }

  linkPair() { return `${this.repoTarget.value.trim()}\n${this.demoTarget.value.trim()}` }

  // force: asked again though the links are as they were (back from fixing a README, say). Otherwise the answer we have stands.
  async askServer(force = false) {
    const asked = this.linkPair()
    if (!force && this.answered === asked && this.answers) { this.network = this.answers; return this.check() }
    this.abort?.abort()
    this.abort = new AbortController()
    this.network = { status: "checking", items: {} }
    this.check()
    const url = new URL(this.checksUrlValue, location.href)
    url.searchParams.set("repo_url", this.repoTarget.value.trim())
    url.searchParams.set("demo_url", this.demoTarget.value.trim())
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" }, signal: this.abort.signal })
      if (!response.ok) throw new Error(response.status)
      const body = await response.json()
      this.network = { status: "done", items: Object.fromEntries(body.items.map(item => [ item.key, item ])) }
      this.answered = asked
      this.answers = this.network
    } catch (error) {
      if (error.name === "AbortError") return
      this.network = { status: "error", items: {} }
    }
    this.check()
  }

  // The blocking network checks that failed.
  networkBlocking() {
    if (this.network.status !== "done") return []
    return Object.values(this.network.items).filter(item => item.blocker && item.state === "fail")
  }

  // A Fix link: jump to the field that fixes the check.
  fix(event) {
    const field = document.getElementById(event.currentTarget.getAttribute("href").slice(1))
    if (!field) return
    event.preventDefault()
    field.scrollIntoView({ block: "center", behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" })
    field.focus({ preventScroll: true })
  }

  paintNetwork() {
    this.checkTargets.filter(step => step.dataset.network).forEach(step => {
      const item = this.network.items[step.dataset.check]
      const state = this.network.status === "checking" ? "checking" : (item?.state || "wait")
      step.dataset.state = state
      // While the server is asked again, a check keeps its place: it only changes with the answer.
      if (this.network.status === "done") this.settle(step, state === "ok")
      step.toggleAttribute("data-error", state === "fail")
      step.toggleAttribute("data-warn", state === "warn")
      const detail = step.querySelector("[data-detail]")
      if (detail) {
        const text = this.network.status === "done" && state !== "ok" ? (item?.detail || "") : ""
        detail.textContent = text
        detail.hidden = !text
      }
    })
  }

  // Met or not. The first answer for a check is how the page opened: met means it never shows. After that, met shows the green
  // check for a moment, then the row leaves.
  settle(step, met) {
    const wasMet = step.hasAttribute("data-done")
    step.toggleAttribute("data-done", met)
    if (!step.dataset.settled) {
      step.dataset.settled = "1"
      met ? this.leave(step, false) : this.restore(step)
    } else if (met && !wasMet) {
      clearTimeout(step.timer)
      step.timer = setTimeout(() => this.leave(step, true), 1500)
    } else if (!met) {
      clearTimeout(step.timer)
      this.restore(step)
    }
    this.allSet()
  }

  leave(step, animate) {
    if (!animate || matchMedia("(prefers-reduced-motion: reduce)").matches) {
      step.setAttribute("data-gone", "")
      return this.allSet()
    }
    step.style.height = `${step.offsetHeight}px`
    step.getBoundingClientRect()
    step.setAttribute("data-leaving", "")
    step.timer = setTimeout(() => {
      step.removeAttribute("data-leaving")
      step.style.height = ""
      step.setAttribute("data-gone", "")
      this.allSet()
    }, 320)
  }

  restore(step) {
    step.removeAttribute("data-leaving")
    step.removeAttribute("data-gone")
    step.style.height = ""
  }

  // Nothing left in the list: say so.
  allSet() {
    if (!this.hasAllsetTarget) return
    const listed = this.checkTargets.some(step => !step.hasAttribute("data-gone") && !step.hasAttribute("data-hidden"))
    this.allsetTarget.hidden = listed || this.submitTarget.disabled
  }

  // The Hackatime list saved a tick or an untick: show the hours it brought. The ticked rows themselves are what the
  // "Link a Hackatime project" check looks at, so it follows them as they change.
  hackatimeSaved({ detail }) {
    if (this.hasHoursTarget) this.hoursTarget.textContent = detail.hours
    this.check()
  }

  // Back from fixing the README on GitHub: ask again.
  recheck() {
    if (this.network?.status === "done" && Object.values(this.network.items).some(item => item.state === "fail")) this.askServer(true)
  }

  progress() {
    if (!this.hasProgressTarget) return
    const steps = this.checkTargets.filter(step => step.dataset.blocker === "true")
    // A check that couldn't be asked counts as passed: it never holds a ship back (D-022).
    const ticked = steps.filter(step => step.hasAttribute("data-done") || step.dataset.state === "unchecked").length
    this.progressTarget.textContent = `${ticked} of ${steps.length}`
  }

  preview() {
    const [ file ] = this.fileTarget.files
    if (!file) return
    URL.revokeObjectURL(this.previewTarget.src)
    this.previewTarget.src = URL.createObjectURL(file)
    this.previewTarget.hidden = false
    this.placeholderTarget.hidden = true
    this.thumbTarget.src = this.previewTarget.src
    this.thumbTarget.hidden = false
    this.thumbEmptyTarget.hidden = true
    this.check()
  }
}
