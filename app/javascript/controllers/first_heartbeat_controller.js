import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Hackatime's asked this often (the server answers from its last look in between, so it never asks more than once
// every 30 seconds), and for this long, then "Check again" takes over.
const CHECK_EVERY = 30 * 1000
const GIVE_UP_AFTER = 15 * 60 * 1000
// How long the success panel shows before the page carries on without a reload from you.
const CARRY_ON_AFTER = 2500

// D-078: the project page while no time has ever arrived from you. Checks for your first heartbeat on its own while the
// tab is in view, turns the panel to a success one when it comes, then reloads the page into your project.
export default class extends Controller {
  static targets = [ "panel", "title", "note", "status", "again", "waitingIcon", "doneIcon" ]
  static values = { url: String }

  connect() {
    this.#start()
  }

  disconnect() {
    this.#stop()
  }

  again() {
    this.againTarget.hidden = true
    this.#start()
    this.check()
  }

  // Also on coming back to the tab: the server decides whether it's time to ask Hackatime again.
  async check() {
    if (document.hidden || this.checking || this.done) return

    this.checking = true
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
      if (response.ok && (await response.json()).arrived) this.#arrived()
    } catch {
      // Hackatime (or we) couldn't answer: try again next time.
    } finally {
      this.checking = false
    }
  }

  #start() {
    this.#stop()
    this.statusTarget.hidden = true
    this.panelTarget.dataset.state = "waiting"
    this.timer = setInterval(() => this.check(), CHECK_EVERY)
    this.giveUp = setTimeout(() => this.#giveUp(), GIVE_UP_AFTER)
  }

  #stop() {
    clearInterval(this.timer)
    clearTimeout(this.giveUp)
  }

  #giveUp() {
    this.#stop()
    this.panelTarget.dataset.state = "stopped"
    this.statusTarget.hidden = false
    this.againTarget.hidden = false
  }

  #arrived() {
    this.done = true
    this.#stop()
    this.panelTarget.dataset.state = "success"
    this.waitingIconTarget.hidden = true
    this.doneIconTarget.hidden = false
    this.titleTarget.textContent = "Got your first heartbeat!"
    this.noteTarget.textContent = "Hackatime just saw you coding. Your hours count from here."
    this.statusTarget.hidden = true
    setTimeout(() => Turbo.visit(window.location.href, { action: "replace" }), CARRY_ON_AFTER)
  }
}
