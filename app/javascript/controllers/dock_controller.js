import { Controller } from "@hotwired/stimulus"

// The landing page's dock: the call to action and the time left, floating at the bottom, hidden while any of the
// big calls to action (its watch targets) is on screen.
export default class extends Controller {
  static targets = [ "dock", "watch" ]

  connect() {
    const showing = new Set()
    this.observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => entry.isIntersecting ? showing.add(entry.target) : showing.delete(entry.target))
      this.dockTarget.classList.toggle("is-away", showing.size > 0)
    })
    this.watchTargets.forEach((watch) => this.observer.observe(watch))
  }

  disconnect() {
    this.observer.disconnect()
  }
}
