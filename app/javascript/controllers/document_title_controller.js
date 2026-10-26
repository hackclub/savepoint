import { Controller } from "@hotwired/stimulus"

const TITLE_KEY = "save-point:title"
const STAR_KEY = "save-point:starred"

// The document's name in the app bar, renamable in place like Sheets: click it, type,
// then Enter (or click away) to keep it or Escape to put it back. The browser tab takes
// the new name too. The star next to it toggles. Both are remembered in localStorage.
export default class extends Controller {
  static targets = [ "input", "star" ]

  connect() {
    this.originalTitle = document.title
    this.#show(read(TITLE_KEY) || this.inputTarget.dataset.default)
    this.#starred(read(STAR_KEY) === "true")
  }

  // File > Rename
  rename() {
    this.inputTarget.focus()
    this.inputTarget.select()
  }

  begin() {
    this.before = this.inputTarget.value
  }

  key(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.#leave()
    } else if (event.key === "Escape") {
      event.preventDefault()
      this.inputTarget.value = this.before
      this.#leave()
    }
  }

  // An empty name isn't one, so it goes back to what it was.
  commit() {
    const name = this.inputTarget.value.trim() || this.before || this.inputTarget.dataset.default
    this.#show(name)
    write(TITLE_KEY, name === this.inputTarget.dataset.default ? null : name)
  }

  star() {
    const starred = this.starTarget.getAttribute("aria-pressed") !== "true"
    this.#starred(starred)
    write(STAR_KEY, starred ? "true" : null)
  }

  // Back to the grid, as Sheets does once a name's been entered.
  #leave() {
    this.inputTarget.blur()
    document.querySelector(".sheet__cells")?.focus({ preventScroll: true })
  }

  #show(name) {
    this.inputTarget.value = name
    this.inputTarget.size = Math.max(1, name.length)
    document.title = name === this.inputTarget.dataset.default ? this.originalTitle : name
  }

  #starred(starred) {
    this.starTarget.setAttribute("aria-pressed", starred)
    this.starTarget.setAttribute("aria-label", starred ? "Starred" : "Star")
  }
}

function read(key) {
  try { return localStorage.getItem(key) } catch { return null }
}

function write(key, value) {
  try {
    if (value === null) localStorage.removeItem(key)
    else localStorage.setItem(key, value)
  } catch {}
}
