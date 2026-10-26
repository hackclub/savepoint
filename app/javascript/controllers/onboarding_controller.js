import { Controller } from "@hotwired/stimulus"

// The onboarding sheet: your game (A1), the Hackatime project its hours come from (A2), your prize (A3), then when you'll build (A4).
// Answered rows fold into bars that reopen them. Answers live in this tab (sessionStorage keeps them across the
// trip to Hack Club and Hackatime), and "Start building" saves them as your project.
const PICK_DELAY = 360
const ANSWERS_KEY = "save-point:onboarding"
const ANSWERS = [ "step", "name", "repo", "jame", "hackatime", "hackatimeSkipped", "prize", "buildTime" ]

export default class extends Controller {
  static targets = [
    "row", "summary", "value",
    "name", "repo", "jame", "repoHint", "gameNext",
    "hackatime", "hackatimeList",
    "prize", "prizeNext", "buildTime", "start", "startLabel", "saveError", "saveErrorText",
    "projectTab"
  ]
  static values = { prizes: Array, defaultPrize: String, signedIn: Boolean, projectUrl: String, progressUrl: String, hackatimeUrl: String, hasProject: Boolean }

  connect() {
    this.listedRepo = "" // the code link the picker rows were drawn for (the page draws them with none)
    this.state = {
      step: 1, name: "", repo: "", jame: false, hackatime: "", hackatimeSkipped: false, prize: null, buildTime: null, saving: false,
      ...this.#restoreAnswers()
    }
    // Picking a Hackatime project needs you signed in, so without that you can't be past step 2.
    if (!this.signedInValue) this.state.step = Math.min(this.state.step, 2)
    // The prize you claimed on the landing page, until you pick another.
    if (!this.#validPrize(this.state.prize)) this.state.prize = this.#startingPrize()
    // A time that isn't one of the tiles (an old or edited answer) is no answer.
    if (!this.buildTimeTargets.some((input) => input.value === this.state.buildTime)) this.state.buildTime = null
    // Without a prize there's nothing to go on from, so you can't be past step 3.
    if (!this.state.prize) this.state.step = Math.min(this.state.step, 3)
    this.nameTarget.value = this.state.name
    this.repoTarget.value = this.state.repo
    this.jameTarget.checked = this.state.jame
    this.#render()
    this.#refreshHackatime()
  }

  disconnect() {
    clearTimeout(this.pickTimer)
  }

  // An answered row, reopened. The row right after the open one is a way to go on: it does what the open step's Next does.
  open({ params: { step } }) {
    if (step === this.state.step + 1) return this.#next()
    this.#goTo(step)
  }

  // A1

  typeGame() {
    this.#set({ name: this.nameTarget.value, repo: this.repoTarget.value.trim(), jame: this.jameTarget.checked })
  }

  saveGame(event) {
    event.preventDefault()
    if (!this.#gameReady()) return
    this.#goTo(2)
  }

  // A2

  pickHackatime({ target }) {
    this.#set({ hackatime: target.value, hackatimeSkipped: false })
    this.#after(PICK_DELAY, () => this.#goTo(3))
  }

  skipHackatime() {
    this.#set({ hackatime: "", hackatimeSkipped: true })
    this.#goTo(3)
  }

  // Off to sign in with Hack Club or to link Hackatime, and back here. The answers wait in this tab.
  leave() {
    this.#saveAnswers()
  }

  // A3

  pickPrize({ params: { prize } }) {
    this.#set({ prize })
  }

  savePrize() {
    if (!this.state.prize) return
    this.#goTo(4)
  }

  // A4

  pickBuildTime({ target }) {
    this.#set({ buildTime: target.value })
  }

  async saveProject() {
    const s = this.state
    if (!s.prize || !s.buildTime || s.saving || !this.#gameReady()) return
    this.#set({ saving: true })
    this.#reportStep(5)
    this.saveErrorTarget.hidden = true
    const project = { name: s.name.trim(), repo_url: s.repo, jame_gam: s.jame, prize_key: s.prize, build_time: s.buildTime }
    if (s.hackatime) project.hackatime_project_names = [ s.hackatime ]
    try {
      const response = await fetch(this.projectUrlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json",
                   "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content },
        body: JSON.stringify({ project })
      })
      const body = await response.json().catch(() => ({}))
      if (!response.ok) throw new Error(body.errors?.join(". ") || `Saving the project: ${response.status}`)
      try { sessionStorage.removeItem(ANSWERS_KEY) } catch {}
      // Anything Turbo kept of the project from before it existed was the redirect back here.
      window.Turbo?.cache.clear()
      window.Turbo ? window.Turbo.visit(body.location) : window.location.assign(body.location)
    } catch (error) {
      this.saveErrorTextTarget.textContent = String(error.message ?? error)
      this.saveErrorTarget.hidden = false
      this.#set({ saving: false })
    }
  }

  // Flow

  // The open step's Next, by the same path as clicking it: submit the game's form, which validates and runs saveGame, or press
  // the prize's Next. Only those two steps have a Next (Hackatime goes on when you pick a project or skip, and the last step
  // is Start building), so only the row after one of them is a way forward.
  #next() {
    if (this.state.step === 3) return this.prizeNextTarget.click()
    if (this.state.step !== 1) return
    if (this.gameNextTarget.disabled) return (this.nameTarget.value.trim() ? this.repoTarget : this.nameTarget).focus()
    this.gameNextTarget.form.requestSubmit(this.gameNextTarget)
  }

  #goTo(step) {
    clearTimeout(this.pickTimer)
    this.#set({ step })
    this.#reportStep(step)
    this.rowTargets[step - 1].querySelector("h2").focus({ preventScroll: true })
    this.#refreshHackatime()
  }

  // D-064: the picker rows come from the server, which knows how to compare repo links. The page renders them with no repo
  // (nothing typed yet), so on reaching step 2 ask for them again with the code link from step 1. A project Hackatime links to
  // a different repo then goes last, with a warning. Your pick stays (#render ticks it again). If the server can't answer,
  // the rows stay as they were.
  async #refreshHackatime() {
    if (this.state.step !== 2 || !this.hasHackatimeListTarget || this.listedRepo === this.state.repo) return
    const repo = this.state.repo
    const request = this.hackatimeRequest = (this.hackatimeRequest ?? 0) + 1
    try {
      const response = await fetch(`${this.hackatimeUrlValue}?${new URLSearchParams({ repo })}`, { headers: { Accept: "text/html" } })
      if (response.status !== 200 || request !== this.hackatimeRequest || !this.hasHackatimeListTarget) return
      this.hackatimeListTarget.innerHTML = await response.text()
      this.listedRepo = repo
      this.#render()
    } catch {}
  }

  // Tell the server how far you got (step 5 is Start building), so we can see where people stop. Fire and forget: the server
  // keeps only the furthest step, and a failure here must never get in the way of the sheet.
  #reportStep(step) {
    if (!this.signedInValue) return
    try {
      fetch(this.progressUrlValue, {
        method: "POST",
        keepalive: true,
        headers: { "Content-Type": "application/json", Accept: "application/json",
                   "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content },
        body: JSON.stringify({ step })
      }).catch(() => {})
    } catch {}
  }

  #after(delay, callback) {
    clearTimeout(this.pickTimer)
    this.pickTimer = setTimeout(callback, delay)
  }

  #set(changes) {
    Object.assign(this.state, changes)
    this.#render()
  }

  #gameReady() {
    return !!this.state.name.trim() && this.#repoOk()
  }

  // The code URL is optional, but a link when there is one.
  #repoOk() {
    if (!this.state.repo) return true
    // A link may come without https:// (the server adds it); it needs a host with a dot.
    return /^(https?:\/\/)?[a-z0-9][a-z0-9-]*(\.[a-z0-9-]+)+(:\d{1,5})?([/?#]\S*)?$/i.test(this.state.repo)
  }

  #validPrize(id) {
    return !!id && this.prizesValue.some((prize) => prize.id === id)
  }

  // What you claimed on the landing page (sp-claim), or the goal it showed (sp-goal), or its default.
  #startingPrize() {
    for (const key of [ "sp-claim", "sp-goal" ]) {
      let id = null
      try { id = localStorage.getItem(key) } catch {}
      if (this.#validPrize(id)) return id
    }
    return this.#validPrize(this.defaultPrizeValue) ? this.defaultPrizeValue : null
  }

  #saveAnswers() {
    const answers = Object.fromEntries(ANSWERS.map((key) => [ key, this.state[key] ]))
    try { sessionStorage.setItem(ANSWERS_KEY, JSON.stringify(answers)) } catch {}
  }

  #restoreAnswers() {
    try {
      const answers = JSON.parse(sessionStorage.getItem(ANSWERS_KEY)) ?? {}
      return Object.fromEntries(ANSWERS.filter((key) => key in answers).map((key) => [ key, answers[key] ]))
    } catch {
      return {}
    }
  }

  // Drawing

  #render() {
    const s = this.state
    const prize = this.prizesValue.find((prize) => prize.id === s.prize)
    const gameDone = this.#gameReady() && s.step > 1
    const done = { 1: gameDone, 2: s.step > 2 && (!!s.hackatime || s.hackatimeSkipped), 3: s.step > 3 && !!prize, 4: false }
    const values = { 1: s.name.trim(), 2: s.hackatime || (s.hackatimeSkipped ? "Later" : ""), 3: prize?.name ?? "", 4: s.buildTime ?? "" }

    this.rowTargets.forEach((row, index) => {
      const step = index + 1
      const active = step === s.step
      row.dataset.state = active ? "active" : done[step] ? "done" : "locked"
      // The row after the game or prize step is a button too: it goes on like Next.
      const next = (s.step === 1 || s.step === 3) && step === s.step + 1
      const summary = this.summaryTargets[index]
      summary.disabled = active || !(done[step] || next)
      row.toggleAttribute("data-next", next)
      if (next) summary.setAttribute("aria-label", `Continue to ${summary.querySelector(".onboarding-row__name").textContent.trim()}`)
      else summary.removeAttribute("aria-label")
      this.valueTargets[index].textContent = values[step]
    })

    this.repoHintTarget.hidden = this.#repoOk()
    this.gameNextTarget.disabled = !this.#gameReady()
    this.hackatimeTargets.forEach((input) => { input.checked = input.value === s.hackatime })
    this.prizeTargets.forEach((card) => {
      const picked = card.dataset.prize === s.prize
      card.toggleAttribute("data-picked", picked)
      card.setAttribute("aria-pressed", picked)
    })
    this.prizeNextTarget.disabled = !s.prize
    this.buildTimeTargets.forEach((input) => { input.checked = input.value === s.buildTime })
    this.startTarget.disabled = !s.prize || !s.buildTime || s.saving || !this.signedInValue
    this.startLabelTarget.textContent = s.saving ? "Starting…" : "Start building"

    this.projectTabTarget.setAttribute("aria-disabled", !this.hasProjectValue)
  }
}
