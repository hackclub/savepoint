import { Controller } from "@hotwired/stimulus"

// The sheet tabs are the site's navigation: each tab shows one section of the
// grid. The URL hash tracks the open section so it can be linked to directly.
export default class extends Controller {
  static targets = [ "tab", "section", "viewport" ]

  connect() {
    this.restore()
  }

  select(event) {
    event.preventDefault()
    history.pushState(null, "", event.currentTarget.hash)
    this.restore()
  }

  restore() {
    const id = location.hash.slice(1)
    const current = this.sectionTargets.find(section => section.id === id) ?? this.sectionTargets[0]
    if (current === this.current) return
    this.current = current

    this.sectionTargets.forEach(section => section.hidden = section !== current)
    this.tabTargets.forEach(tab => {
      if (tab.hash === `#${current.id}`) {
        tab.setAttribute("aria-current", "page")
      } else {
        tab.removeAttribute("aria-current")
      }
    })
    this.viewportTarget.scrollTo(0, 0)
    this.dispatch("change")
  }
}
