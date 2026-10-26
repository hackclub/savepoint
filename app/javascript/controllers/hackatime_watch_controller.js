import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Hackatime's checked this often while you're on the page.
const CHECK_EVERY = 2 * 60 * 1000

// Before a Hackatime project's linked: asks Hackatime every so often while you're looking (and as soon as you're
// back from your editor), and once your first new project has linked itself, reloads to say so. Not in the middle of
// a pomodoro, though: that waits until you're out.
export default class extends Controller {
  static values = { url: String }

  connect() {
    this.timer = setInterval(() => this.check(), CHECK_EVERY)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  async check() {
    if (this.linked) return this.#reloadIfFree()
    if (document.hidden || this.checking) return

    this.checking = true
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
      if (response.ok && (await response.json()).tracking) {
        this.linked = true
        this.#reloadIfFree()
      }
    } catch {
      // Hackatime (or we) couldn't answer: try again next time.
    } finally {
      this.checking = false
    }
  }

  #reloadIfFree() {
    const pomodoro = this.element.querySelector("[data-focus-target=overlay]")
    if (pomodoro && !pomodoro.hidden) return

    clearInterval(this.timer)
    Turbo.visit(window.location.href, { action: "replace" })
  }
}
