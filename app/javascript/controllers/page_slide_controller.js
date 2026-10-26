import { Controller } from "@hotwired/stimulus"

// Picks the direction of the slide between pages (top-bar.css). It sits on <html>, which Turbo keeps between visits.
// Before a visit it compares the current page's place in the nav with the target's: further right slides the old page
// out to the left, further left the other way. A page that is not a tab, or no known direction, leaves it unset and
// the page crossfades. The order is the nav's, left to right, from the layout.
export default class extends Controller {
  static values = { order: Array }

  connect() {
    this.before = (event) => this.pick(event.detail.url)
    this.after = () => this.clearWhenDone()
    this.locked = (event) => { this.markSegment(event); this.stopLocked(event) }
    // Capture phase on the document: before Turbo's own click handling, which skips a click that is already cancelled.
    document.addEventListener("click", this.locked, true)
    document.addEventListener("turbo:before-visit", this.before)
    document.addEventListener("turbo:load", this.after)
  }

  disconnect() {
    document.removeEventListener("click", this.locked, true)
    document.removeEventListener("turbo:before-visit", this.before)
    document.removeEventListener("turbo:load", this.after)
  }

  // A click on a segmented bar that loads pages (the Today/Total switch, the stats toggle, the admin nav: data-seg-nav) sets
  // data-seg-nav on <html> until the visit is over. Only then do the bar's gold pill and labels get their transition names
  // (transitions.css), so they glide when you pick another segment and are plain page content on any other visit. A modified
  // click opens a tab and visits nothing here.
  markSegment(event) {
    delete this.element.dataset.segNav
    const modified = event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button > 0
    if (!modified && event.target.closest?.("[data-seg-nav] a")) this.element.dataset.segNav = ""
  }

  // A tab for the page you are already on (aria-current), and the active Today/Total segment, cancel their click too.
  // A locked tab (aria-disabled, like "My project" before there is a project) goes nowhere: no visit and no slide. It shakes
  // and shows its tip instead. A click also covers Enter on the focused link. Onboarding's controller flips aria-disabled
  // when the project exists, and this reads the attribute at click time, so the unlocked tab navigates normally.
  stopLocked(event) {
    const link = event.target.closest?.('.top-bar__nav a[aria-disabled="true"], .top-bar__nav a[aria-current="page"], .leaderboard__sorts a[aria-current="page"], [data-seg-nav] a[aria-current]')
    if (!link) return
    event.preventDefault()
    event.stopPropagation()
    // The page you are on does nothing: no visit, no slide, no reload. Only a locked tab shakes.
    if (link.getAttribute("aria-disabled") !== "true") return
    link.classList.remove("is-nudged")
    void link.offsetWidth
    link.classList.add("is-nudged")
    link.addEventListener("animationend", () => link.classList.remove("is-nudged"), { once: true })
  }

  pick(url) {
    const from = this.indexOf(location.pathname)
    const to = this.indexOf(new URL(url, location.href).pathname)
    // A segmented bar that changes only the page's own query (the stats toggle): the pill glides and nothing else moves.
    if ("segNav" in this.element.dataset && new URL(url, location.href).pathname === location.pathname) { this.element.dataset.navDir = "same"; return }
    // Same page (a step opening on the project page): nothing slides or fades. The page changes at once.
    if (from >= 0 && from === to) { this.element.dataset.navDir = "same"; return }
    if (from < 0 || to < 0) return this.clear()
    this.element.dataset.navDir = to > from ? "forward" : "back"
  }

  indexOf(path) { return this.orderValue.indexOf(path.replace(/\/+$/, "") || "/") }

  // The direction has to stay until the slide ends, or the keyframes switch mid-way. Wait for the transition's animations.
  clearWhenDone() {
    const token = (this.token = {})
    requestAnimationFrame(() => requestAnimationFrame(() => {
      const running = this.element.getAnimations({ subtree: true }).map((animation) => animation.finished.catch(() => {}))
      Promise.all(running).then(() => { if (this.token === token) { this.clear(); delete this.element.dataset.segNav } })
    }))
  }

  clear() { delete this.element.dataset.navDir }
}
