import { Controller } from "@hotwired/stimulus"

const KEY = "save-point:sidebar-open"

// The sidebar's folding cards: keeps whichever you last opened open when the page comes back (after adding to the
// queue, say), unless the server opened one that needs you. They open and close with an animation (the card grows or
// shrinks and its body fades, the same easing as faq_controller.js). The cards stay real <details>: `open` is set
// before an opening animation starts and removed after a closing one ends, so the keyboard and screen readers work
// as usual. One open at a time is the browser's job without JS (the `name` attribute); here it's done by hand,
// since the browser would close the other card at once. Reduced motion toggles at once.
export default class extends Controller {
  static values = { urgent: Boolean }

  connect() {
    this.remember = (event) => {
      if (event.target.open) write(KEY, event.target.dataset.section)
    }
    this.element.addEventListener("toggle", this.remember, true)

    const saved = read(KEY)
    const section = !this.urgentValue && saved && this.element.querySelector(`[data-section="${saved}"]`)
    if (section) section.open = true

    this.names = new Map()
    this.cards.forEach((card) => { this.names.set(card, card.getAttribute("name")); card.removeAttribute("name") })
  }

  disconnect() {
    this.element.removeEventListener("toggle", this.remember, true)
    this.cards.forEach((card) => {
      this.cancel(card)
      if (this.names?.get(card)) card.setAttribute("name", this.names.get(card))
    })
  }

  get cards() { return [ ...this.element.querySelectorAll(":scope > details.side-section") ] }

  toggle(event) {
    const summary = event.target.closest?.("summary.side-section__row")
    const card = summary?.parentElement
    if (!card || !this.cards.includes(card) || event.defaultPrevented) return
    event.preventDefault()
    const opening = !this.isOpen(card)
    if (opening) this.cards.filter((other) => other !== card && this.isOpen(other)).forEach((other) => this.run(other, false))
    this.run(card, opening)
  }

  isOpen(card) { return card.animation ? card.targetOpen : card.open }

  run(card, opening) {
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches || !card.animate
    const start = card.offsetHeight
    this.cancel(card)
    card.targetOpen = opening
    if (reduced) { card.open = opening; return }

    if (opening) card.open = true
    else card.dataset.closing = ""
    card.style.overflow = "hidden"
    const summary = card.querySelector("summary")
    const borders = card.offsetHeight - card.clientHeight
    const end = opening ? card.offsetHeight : summary.offsetHeight + borders
    const bodies = [ ...card.children ].filter((child) => child !== summary)

    card.animation = card.animate(
      { height: [ `${start}px`, `${end}px` ] },
      { duration: opening ? 300 : 230, easing: opening ? "cubic-bezier(.25, 1.12, .4, 1)" : "cubic-bezier(.4, 0, .2, 1)" }
    )
    card.fades = bodies.map((body) => body.animate(
      opening
        ? { opacity: [ 0, 1 ], transform: [ "translateY(-6px)", "translateY(0)" ] }
        : { opacity: [ 1, 0 ], transform: [ "translateY(0)", "translateY(-4px)" ] },
      { duration: opening ? 240 : 160, delay: opening ? 50 : 0, easing: "cubic-bezier(.22, 1, .36, 1)", fill: opening ? "backwards" : "forwards" }
    ))
    const animation = card.animation
    animation.onfinish = () => {
      if (card.animation !== animation) return
      if (!opening) card.open = false
      this.cancel(card)
    }
  }

  cancel(card) {
    const animation = card.animation
    card.animation = null
    animation?.cancel()
    card.fades?.forEach((fade) => fade.cancel())
    card.fades = null
    card.style.overflow = ""
    delete card.dataset.closing
  }
}

// localStorage can be off (private windows, blocked storage); then it just doesn't remember.
function read(key) {
  try { return localStorage.getItem(key) } catch { return null }
}

function write(key, value) {
  try { localStorage.setItem(key, value) } catch {}
}
