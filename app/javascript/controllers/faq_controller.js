import { Controller } from "@hotwired/stimulus"

// Animates a <details> FAQ card open and closed. The element stays a real
// <details>: `open` is set before an opening animation starts and removed
// after a closing animation ends. Reduced motion falls back to native toggling.
//
// One question is open at a time (D-094): opening one tells the others, with a window event, to close. A read is the
// time a question stays open. It ends when the question closes, another opens, the page is hidden or the page goes
// away, and is sent to the server then: the question's key and the whole seconds, nothing about the person.
// A hash in the URL opens the question it names (its key, or the old #faq-N). A group's anchor just scrolls there.
const MIN_READ_MS = 1000
const MAX_READ_SECONDS = 600

export default class extends Controller {
  static targets = [ "summary", "content" ]
  static values = { key: String, url: String, number: Number }

  connect() {
    this.animation = null
    this.contentAnimation = null
    this.targetOpen = this.element.open
    this.reading = false
    this.openedAt = null
    this.syncState()
    this.onToggle = () => { if (!this.animation) this.syncState() }
    this.onVisibility = () => this.visibilityChanged()
    this.onHash = () => this.openFromHash()
    this.element.addEventListener("toggle", this.onToggle)
    document.addEventListener("visibilitychange", this.onVisibility)
    window.addEventListener("pagehide", this.sendRead)
    window.addEventListener("hashchange", this.onHash)
    this.openFromHash()
  }

  disconnect() {
    this.stopReading()
    this.element.removeEventListener("toggle", this.onToggle)
    document.removeEventListener("visibilitychange", this.onVisibility)
    window.removeEventListener("pagehide", this.sendRead)
    window.removeEventListener("hashchange", this.onHash)
    this.cancelRunning()
  }

  // Another question opened: close this one.
  closeOthers(event) {
    if (event.detail.element !== this.element && this.targetOpen) this.setOpen(false)
  }

  setOpen(opening) {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches || !this.element.animate) {
      this.element.open = opening
      this.syncState()
    } else {
      this.run(opening)
    }
  }

  // Opens the question the URL's hash names, without animating, and scrolls to it.
  openFromHash() {
    const hash = decodeURIComponent(window.location.hash.slice(1))
    if (!hash || (hash !== this.keyValue && hash !== `faq-${this.numberValue}`)) return
    this.element.open = true
    this.syncState()
    this.element.scrollIntoView({ block: "center" })
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
    this.trackRead(opening)
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
    this.trackRead(this.element.open)
  }

  // A read starts when the question opens (and tells the others to close) and ends when it closes.
  trackRead(open) {
    if (open === this.reading) return
    this.reading = open
    if (open) {
      this.startClock()
      window.dispatchEvent(new CustomEvent("faq:opened", { detail: { element: this.element } }))
    } else {
      this.stopReading()
    }
  }

  startClock() {
    this.openedAt = document.hidden ? null : performance.now()
  }

  // Hidden pages end the read so far. A tab that comes back to a question still open starts a new one.
  visibilityChanged() {
    if (document.hidden) this.sendRead()
    else if (this.reading && this.openedAt === null) this.startClock()
  }

  stopReading() {
    this.reading = false
    this.sendRead()
  }

  // Sends the read so far if it lasted a second or more, capped at ten minutes. A beacon survives the page unloading.
  sendRead = () => {
    if (this.openedAt === null) return
    const elapsed = performance.now() - this.openedAt
    this.openedAt = null
    if (elapsed < MIN_READ_MS || !this.urlValue || !navigator.sendBeacon) return
    const body = new FormData()
    body.append("key", this.keyValue)
    body.append("seconds", Math.min(Math.round(elapsed / 1000), MAX_READ_SECONDS))
    navigator.sendBeacon(this.urlValue, body)
  }
}
