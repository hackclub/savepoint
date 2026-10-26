import { Controller } from "@hotwired/stimulus"

// Animates a <details> FAQ card open and closed. The element stays a real
// <details>: `open` is set before an opening animation starts and removed
// after a closing animation ends. Reduced motion falls back to native toggling.
export default class extends Controller {
  static targets = [ "summary", "content" ]

  connect() {
    this.animation = null
    this.contentAnimation = null
    this.targetOpen = this.element.open
    this.syncState()
    this.onToggle = () => { if (!this.animation) this.syncState() }
    this.element.addEventListener("toggle", this.onToggle)
  }

  disconnect() {
    this.element.removeEventListener("toggle", this.onToggle)
    this.cancelRunning()
  }

  toggle(event) {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches || !this.element.animate) return
    event.preventDefault()
    const opening = this.animation ? !this.targetOpen : !this.element.open
    this.run(opening)
  }

  run(opening) {
    const el = this.element
    const startHeight = el.offsetHeight
    this.cancelRunning()
    this.targetOpen = opening
    el.dataset.faqState = opening ? "open" : "closed"
    el.style.overflow = "hidden"

    if (opening) el.open = true
    const borders = el.offsetHeight - el.clientHeight
    const endHeight = opening ? el.offsetHeight : this.summaryTarget.offsetHeight + borders

    const duration = opening ? 300 : 230
    const easing = opening ? "cubic-bezier(.25, 1.12, .4, 1)" : "cubic-bezier(.4, 0, .2, 1)"
    const animation = el.animate(
      { height: [ `${startHeight}px`, `${endHeight}px` ] },
      { duration, easing }
    )
    this.contentAnimation = this.contentTarget.animate(
      opening
        ? { opacity: [ 0, 1 ], transform: [ "translateY(-6px)", "translateY(0)" ] }
        : { opacity: [ 1, 0 ], transform: [ "translateY(0)", "translateY(-4px)" ] },
      { duration: opening ? 240 : 160, delay: opening ? 50 : 0, easing: "cubic-bezier(.22, 1, .36, 1)", fill: opening ? "backwards" : "forwards" }
    )
    this.animation = animation
    animation.onfinish = () => {
      if (this.animation !== animation) return
      if (!opening) el.open = false
      this.cleanup()
    }
  }

  cancelRunning() {
    const animation = this.animation
    this.animation = null
    if (animation) animation.cancel()
    if (this.contentAnimation) this.contentAnimation.cancel()
    this.contentAnimation = null
  }

  cleanup() {
    this.animation = null
    if (this.contentAnimation) this.contentAnimation.cancel()
    this.contentAnimation = null
    this.element.style.overflow = ""
    this.syncState()
  }

  syncState() {
    this.targetOpen = this.element.open
    this.element.dataset.faqState = this.element.open ? "open" : "closed"
  }
}
