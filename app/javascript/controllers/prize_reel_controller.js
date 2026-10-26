import { Controller } from "@hotwired/stimulus"

const SPEED = 0.04 // px per ms

// The landing page's strip of prizes: four copies of the list, drifting left forever. It keeps the view in the
// second copy, so there's a full copy of room either way for people to scroll into (trackpad, drag, keys), and it
// waits while they do, and while they hover or focus it. Holds still for reduced motion.
export default class extends Controller {
  connect() {
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) return

    this.items = this.element.querySelectorAll(".reel__item")
    this.idleUntil = 0
    this.hovered = false
    this.last = 0
    this.#set(this.#period())

    this.onScroll = () => this.#scrolled()
    this.onMove = () => this.#moved()
    this.onWheel = (event) => this.#wheel(event)
    this.onEnter = (event) => { if (event.pointerType === "mouse") this.hovered = true }
    this.onLeave = () => { this.hovered = false; this.#moved() }
    this.element.addEventListener("scroll", this.onScroll, { passive: true })
    for (const type of [ "touchstart", "touchmove", "pointerdown", "keydown" ]) {
      this.element.addEventListener(type, this.onMove, { passive: true })
    }
    this.element.addEventListener("wheel", this.onWheel, { passive: false })
    this.element.addEventListener("pointerenter", this.onEnter)
    this.element.addEventListener("pointerleave", this.onLeave)
    this.frame = requestAnimationFrame((time) => this.#step(time))
  }

  disconnect() {
    cancelAnimationFrame(this.frame)
    this.element.removeEventListener("scroll", this.onScroll)
    for (const type of [ "touchstart", "touchmove", "pointerdown", "keydown" ]) {
      this.element.removeEventListener(type, this.onMove)
    }
    this.element.removeEventListener("wheel", this.onWheel)
    this.element.removeEventListener("pointerenter", this.onEnter)
    this.element.removeEventListener("pointerleave", this.onLeave)
  }

  #step(time) {
    const elapsed = this.last ? Math.min(time - this.last, 50) : 0
    this.last = time
    if (!this.hovered && !this.element.matches(":focus-within") && time > this.idleUntil) this.#set(this.position + SPEED * elapsed)
    this.frame = requestAnimationFrame((next) => this.#step(next))
  }

  // The strip scrolls sideways, so the browser hands it any wheel gesture that has even a sliver of sideways movement
  // (a trackpad swipe is never perfectly straight) and the page never sees the rest of that gesture. A mostly
  // vertical gesture goes to the page here instead. Sideways ones stay with the strip.
  #wheel(event) {
    this.#moved()
    if (event.ctrlKey || Math.abs(event.deltaY) <= Math.abs(event.deltaX)) return

    const unit = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? window.innerHeight : 1
    event.preventDefault()
    window.scrollBy({ top: event.deltaY * unit, behavior: "instant" })
  }

  #scrolled() {
    if (Math.abs(this.element.scrollLeft - this.position) < 2) return // our own nudge

    this.#moved()
    const x = this.element.scrollLeft, wrapped = this.#wrap(x)
    if (Math.abs(wrapped - x) > 1) this.#set(wrapped)
    else this.position = x
  }

  #moved() {
    this.idleUntil = performance.now() + 1500
  }

  #set(x) {
    this.position = this.#wrap(x)
    this.element.scrollLeft = this.position
  }

  #wrap(x) {
    const period = this.#period()
    if (period <= 0) return x
    while (x >= 2 * period) x -= period
    while (x < period) x += period
    return x
  }

  // The width of one copy of the list.
  #period() {
    const copy = this.items.length / 4
    return this.items[copy].offsetLeft - this.items[0].offsetLeft
  }
}
