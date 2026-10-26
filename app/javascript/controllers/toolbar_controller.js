import { Controller } from "@hotwired/stimulus"

const ZOOM_KEY = "save-point:zoom"

// How a cell looks with no format of its own, for keys sheet-editor:format leaves out.
const DEFAULTS = {
  bold: false, italic: false, underline: false, strikethrough: false, textColor: "#000000", fillColor: null,
  fontFamily: "Arial", fontSize: 14, numberFormat: "automatic", alignH: "left", alignV: "middle", wrap: "overflow", rotate: 0
}

const PRESSED = { bold: "bold", italic: "italic", strikethrough: "strikethrough" }

// The formatting toolbar, like Google Sheets'. Buttons and menu choices send a
// "command" event for the sheet to carry out, and the buttons follow the active
// cell's format. Zoom, print, filters and hiding the menus are the toolbar's own.
// The grid keeps focus throughout: buttons don't take it on mousedown, and
// anything that does (the font size box, the link box) hands it back when done.
export default class extends Controller {
  static targets = [ "menu", "results", "search", "tooltip", "zoomLabel", "fontFamily", "fontSize" ]

  connect() {
    this.format = { ...DEFAULTS }
    this.zoom = 100
    const zoom = Number(read(ZOOM_KEY))
    if (zoom) this.#applyZoom(zoom)
    this.#reflectState()
    if (!/Mac|iPhone|iPad/.test(navigator.platform)) return

    // Mac shortcuts read "⌘B" and "⌘+Shift+X" in Sheets' tooltips.
    this.element.querySelectorAll("[data-toolbar-hint]").forEach(element => {
      element.dataset.toolbarHint = element.dataset.toolbarHint
        .replace("Ctrl+Alt+", "⌘+Option+").replace(/Ctrl\+(?=\w\))/, "⌘").replace("Ctrl+", "⌘+")
    })
  }

  disconnect() {
    this.#unfilter()
  }

  // Keeps the grid focused when a button is pressed. Text boxes still take focus.
  hold(event) {
    if (!event.target.closest("input, textarea")) event.preventDefault()
  }

  run({ currentTarget, params: { command, value } }) {
    if (currentTarget.getAttribute("aria-disabled") === "true") return

    this.close()
    this.#send(command, value ?? null)
  }

  // A custom color from the palette's color input.
  pick({ target, params: { command } }) {
    this.close()
    this.#send(command, target.value)
  }

  // The link and comment popovers.
  submit(event) {
    event.preventDefault()
    const field = event.currentTarget.elements.value
    const value = field.value.trim()
    if (!value) return

    this.close()
    this.#send(event.params.command, value)
  }

  // Cmd/Ctrl+Enter posts a comment, like Sheets.
  commentKey(event) {
    if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) event.currentTarget.requestSubmit()
  }

  toggle({ currentTarget: trigger, detail }) {
    const menu = this.#menuFor(trigger)
    if (menu === this.openMenu) return this.close()

    this.#open(menu, trigger)
    // From the keyboard, move into the menu. From the mouse, only text boxes take focus.
    const field = menu.querySelector("input:not([type=color]), textarea")
    if (field) {
      field.focus()
      field.select()
    } else if (detail === 0) {
      this.#items(menu)[0]?.focus()
    }
  }

  close() {
    const menu = this.openMenu
    if (!menu) return

    menu.hidden = true
    this.openTrigger?.setAttribute("aria-expanded", "false")
    this.openMenu = this.openTrigger = null
    if (menu.contains(document.activeElement)) this.#refocus()
  }

  // Clicking anywhere outside the open menu closes it.
  dismiss({ target }) {
    if (!this.openMenu || this.openMenu.contains(target) || this.openTrigger?.contains(target)) return
    this.close()
  }

  // Arrow keys move through a menu's choices; Escape backs out.
  navigate(event) {
    const menu = this.menuTargets.find(menu => !menu.hidden && menu.contains(event.target))
    if (!menu || menu.matches("form")) return

    const items = this.#items(menu)
    const index = items.indexOf(event.target)
    const across = menu.matches(".toolbar-menu--palette") ? 1 : 0
    const steps = { ArrowDown: across ? 10 : 1, ArrowUp: across ? -10 : -1, ArrowRight: 1, ArrowLeft: -1, Home: -Infinity, End: Infinity }
    if (!(event.key in steps) || index < 0) return

    event.preventDefault()
    const next = Math.min(items.length - 1, Math.max(0, index + steps[event.key]))
    items[next].focus()
  }

  // Window-wide keys: Escape closes menus and cancels the format painter,
  // Ctrl+Shift+F hides the menus and Alt+/ searches them, like Sheets.
  shortcut(event) {
    if (event.key === "Escape") {
      if (this.openMenu) {
        const trigger = this.openTrigger
        const inMenu = this.openMenu.contains(document.activeElement)
        this.close()
        if (inMenu && trigger?.matches("button")) trigger.focus()
      } else if (this.painting) {
        this.#send("paintFormat", null)
      }
    } else if (event.key.toLowerCase() === "f" && event.shiftKey && (event.ctrlKey || event.metaKey) && !event.altKey) {
      event.preventDefault()
      this.#toggleMenus()
    } else if (event.code === "Slash" && event.altKey && !event.ctrlKey && !event.metaKey) {
      event.preventDefault()
      this.searchTarget.focus()
    }
  }

  // Follows the active cell: pressed styles, the font and size, the chosen alignments,
  // undo/redo, and whether the format painter is still waiting for somewhere to paint.
  reflect({ detail: { format = {}, canUndo = false, canRedo = false, painting = false } }) {
    this.format = { ...DEFAULTS, ...compact(format) }
    this.canUndo = canUndo
    this.canRedo = canRedo
    this.painting = painting
    this.#reflectState()
  }

  // The selected range, for the filter.
  track({ detail: { box, range } }) {
    this.range = range ?? box
  }

  // Zoom can be set from the menu bar's View menu too.
  external({ detail: { command, value } }) {
    if (command === "zoom") this.#applyZoom(value)
  }

  // Menus search: lists the toolbar's actions (and the menu bar's) matching what's typed.
  search() {
    const query = this.searchTarget.value.trim().toLowerCase()
    this.resultsTarget.replaceChildren()
    if (!query) return this.#closeSearch()

    const matches = this.#actions.filter(({ label }) => label.toLowerCase().includes(query)).slice(0, 12)
    matches.forEach(({ label, element }, index) => {
      const option = document.createElement("button")
      option.type = "button"
      option.className = "toolbar-menu__item toolbar-menu__item--plain"
      option.setAttribute("role", "option")
      option.setAttribute("aria-selected", index === 0)
      option.textContent = label
      option.addEventListener("mousedown", event => event.preventDefault())
      option.addEventListener("click", () => this.#choose(element))
      this.resultsTarget.append(option)
    })
    if (!matches.length) {
      const empty = document.createElement("p")
      empty.className = "toolbar-menu__empty"
      empty.textContent = "No results"
      this.resultsTarget.append(empty)
    }

    if (this.openMenu !== this.resultsTarget) this.#open(this.resultsTarget, this.searchTarget)
  }

  searchKey(event) {
    const options = [ ...this.resultsTarget.querySelectorAll("[role=option]") ]
    const index = options.findIndex(option => option.getAttribute("aria-selected") === "true")

    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      const next = (index + (event.key === "ArrowDown" ? 1 : -1) + options.length) % options.length
      options.forEach((option, position) => option.setAttribute("aria-selected", position === next))
    } else if (event.key === "Enter") {
      event.preventDefault()
      options[index]?.click()
    } else if (event.key === "Escape") {
      event.preventDefault()
      this.searchTarget.value = ""
      this.#closeSearch()
      this.#refocus()
    }
  }

  endSearch() {
    this.searchTarget.value = ""
    this.#closeSearch()
  }

  // The font size box: shows the size list while it's being edited, Enter applies.
  editSize() {
    this.fontSizeTarget.select()
    this.#open(this.#menuFor(this.fontSizeTarget), this.fontSizeTarget)
  }

  sizeKey(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      const size = Math.round(Number(this.fontSizeTarget.value))
      this.close()
      if (size >= 1 && size <= 400) this.#send("fontSize", size)
      this.#refocus()
    } else if (event.key === "Escape") {
      this.close()
      this.#refocus()
    } else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      this.#send("fontSizeStep", event.key === "ArrowUp" ? 1 : -1)
      this.fontSizeTarget.select()
    }
  }

  // Leaving the box without Enter puts back the cell's size.
  endSize() {
    if (this.openMenu === this.#menuFor(this.fontSizeTarget)) this.close()
    this.fontSizeTarget.value = this.format.fontSize
  }

  // Tooltips, placed by hand because the toolbar clips anything that overflows it.
  hint({ target }) {
    const element = target.closest("[data-toolbar-hint]")
    if (!element || element === this.hinted) return

    this.hinted = element
    clearTimeout(this.hintTimer)
    this.hintTimer = setTimeout(() => {
      const tooltip = this.tooltipTarget
      const rect = element.getBoundingClientRect()
      tooltip.textContent = element.dataset.toolbarHint
      tooltip.hidden = false
      const left = rect.left + rect.width / 2 - tooltip.offsetWidth / 2
      tooltip.style.left = `${Math.max(4, Math.min(left, innerWidth - tooltip.offsetWidth - 4))}px`
      tooltip.style.top = `${rect.bottom + 6}px`
    }, 400)
  }

  unhint({ relatedTarget }) {
    if (this.hinted?.contains(relatedTarget)) return

    this.hinted = null
    clearTimeout(this.hintTimer)
    this.tooltipTarget.hidden = true
  }

  // A filter belongs to its sheet, so switching tabs drops it.
  unfilter() {
    this.#unfilter()
    this.#reflectState()
  }

  #send(command, value) {
    switch (command) {
      case "print": this.#refocus(); return window.print()
      case "filter": return this.#toggleFilter()
      case "hideMenus": return this.#toggleMenus()
      case "zoom": this.#applyZoom(value); break
    }

    this.dispatch("command", { detail: { command, value } })
    this.#refocus()
  }

  #open(menu, trigger) {
    this.close()
    this.unhint({})
    menu.hidden = false
    trigger.setAttribute("aria-expanded", "true")
    this.openMenu = menu
    this.openTrigger = trigger
    this.#place(menu, this.#anchorFor(menu, trigger))
  }

  // Below the anchor, kept on screen.
  #place(menu, anchor) {
    const rect = anchor.getBoundingClientRect()
    const left = Math.min(rect.left, innerWidth - menu.offsetWidth - 8)
    const top = rect.bottom + menu.offsetHeight + 4 > innerHeight ? Math.max(8, rect.top - menu.offsetHeight - 4) : rect.bottom + 4
    menu.style.left = `${Math.max(8, left)}px`
    menu.style.top = `${top}px`
  }

  // Links and comments open beside the selected cell, like Sheets, when it's in view.
  #anchorFor(menu, trigger) {
    if (menu === this.resultsTarget) return trigger.closest("label")
    if (!menu.matches("form")) return trigger

    const selection = document.querySelector(".sheet__selection")
    const viewport = selection?.closest(".sheet-viewport")?.getBoundingClientRect()
    const rect = selection?.getBoundingClientRect()
    const visible = rect && viewport && rect.bottom > viewport.top && rect.top < viewport.bottom - 40 &&
      rect.left < viewport.right - 200 && rect.right > viewport.left
    return visible ? selection : trigger
  }

  #menuFor(trigger) {
    return this.menuTargets.find(menu => menu.id === trigger.getAttribute("aria-controls"))
  }

  #items(menu) {
    return [ ...menu.querySelectorAll("button:not([aria-disabled=true]), input") ]
  }

  #refocus() {
    const focused = document.activeElement
    if (focused && focused !== document.body && !this.element.contains(focused)) return

    document.querySelector(".sheet__cells")?.focus({ preventScroll: true })
  }

  #reflectState() {
    const format = this.format
    for (const [ name, key ] of Object.entries(PRESSED)) {
      this.#button(name)?.setAttribute("aria-pressed", Boolean(format[key]))
    }
    this.#button("undo")?.setAttribute("aria-disabled", !this.canUndo)
    this.#button("redo")?.setAttribute("aria-disabled", !this.canRedo)
    this.#button("filter")?.setAttribute("aria-pressed", Boolean(this.filter))
    this.#button("paintFormat")?.setAttribute("aria-pressed", Boolean(this.painting))

    this.fontFamilyTarget.textContent = format.fontFamily
    if (document.activeElement !== this.fontSizeTarget) this.fontSizeTarget.value = format.fontSize
    this.zoomLabelTarget.textContent = `${this.zoom}%`
    this.element.style.setProperty("--text-color", hex(format.textColor) ?? "#000000")
    this.element.style.setProperty("--fill-color", hex(format.fillColor) ?? "transparent")

    const state = { ...format, zoom: this.zoom }
    this.menuTargets.filter(menu => menu.dataset.reflect).forEach(menu => {
      const current = normalize(state[menu.dataset.reflect])
      let chosen
      menu.querySelectorAll("[aria-checked]").forEach(item => {
        const checked = normalize(parseParam(item.dataset.toolbarValueParam)) === current
        item.setAttribute("aria-checked", checked)
        if (checked) chosen = item
      })

      // The align menus' buttons show the current choice's icon.
      const slot = this.element.querySelector(`[aria-controls="${menu.id}"] .toolbar__current`)
      const icon = chosen?.querySelector(".icon")
      if (slot && icon && menu.matches(".toolbar-menu--icons")) slot.replaceChildren(icon.cloneNode(true))
    })
  }

  #button(command) {
    return this.element.querySelector(`.toolbar [data-toolbar-command-param="${command}"]`)
  }

  // Zoom scales the whole grid with CSS zoom. Layout reads (offsetLeft, the cell
  // size variables) stay unzoomed, so only pointer maths needs the zoom factor.
  #applyZoom(level) {
    const zoom = Number(level)
    if (!(zoom >= 25 && zoom <= 400)) return

    const sheet = document.querySelector(".sheet")
    const viewport = sheet?.closest(".sheet-viewport")
    const scale = zoom / this.zoom
    this.zoom = zoom
    write(ZOOM_KEY, zoom === 100 ? null : zoom)
    if (sheet) {
      sheet.style.zoom = zoom === 100 ? "" : zoom / 100
      sheet.style.setProperty("--sheet-zoom", zoom / 100)
      sheet.classList.toggle("sheet--zoomed", zoom !== 100)
    }
    this.#reflectState()
    // More or fewer rows now fit on screen. Keep the same cell at the top left, like Sheets.
    window.dispatchEvent(new Event("resize"))
    viewport?.scrollTo(viewport.scrollLeft * scale, viewport.scrollTop * scale)
  }

  // Like Sheets' "Hide the menus": the title and menu bar fold away, the toolbar stays.
  #toggleMenus() {
    const hidden = this.element.closest(".spreadsheet")?.classList.toggle("spreadsheet--menus-hidden")
    const button = this.#button("hideMenus")
    button?.setAttribute("aria-pressed", Boolean(hidden))
    button?.setAttribute("aria-label", hidden ? "Show the menus" : "Hide the menus")
    if (button) button.dataset.toolbarHint = button.dataset.toolbarHint.replace(hidden ? "Hide" : "Show", hidden ? "Show" : "Hide")
    this.#refocus()
  }

  // A filter on the selected range: its top row gets Sheets' filter buttons and the
  // columns' headers turn green. The rows aren't actually hidden.
  #toggleFilter() {
    if (this.filter) {
      this.#unfilter()
    } else if (this.range) {
      this.#drawFilter(this.range)
    }
    this.#reflectState()
    this.#refocus()
  }

  #drawFilter({ column, row, width }) {
    const grid = document.querySelector(".sheet__cells")
    if (!grid) return

    const filter = document.createElement("div")
    filter.className = "toolbar-filter"
    filter.style.setProperty("--column", column + 1)
    filter.style.setProperty("--row", row + 1)
    filter.style.setProperty("--width", width)
    filter.setAttribute("aria-hidden", "true")
    for (let index = 0; index < width; index++) filter.append(document.createElement("span"))
    grid.append(filter)

    const headers = [ ...document.querySelectorAll(".sheet__column-header") ].slice(column, column + width)
    headers.forEach(header => header.classList.add("toolbar-filter__header"))
    this.filter = { element: filter, headers }
  }

  #unfilter() {
    if (!this.filter) return

    this.filter.element.remove()
    this.filter.headers.forEach(header => header.classList.remove("toolbar-filter__header"))
    this.filter = null
  }

  #closeSearch() {
    if (this.openMenu === this.resultsTarget) this.close()
    this.resultsTarget.hidden = true
  }

  #choose(element) {
    this.searchTarget.value = ""
    this.#closeSearch()
    this.searchTarget.blur()
    this.#refocus()
    element.click()
  }

  // Everything the search can find: toolbar buttons, the toolbar menus' choices, and the menu bar's items.
  get #actions() {
    const toolbar = [ ...this.element.querySelectorAll(".toolbar [data-toolbar-hint]:not(label)") ]
      .filter(element => element.getAttribute("aria-disabled") !== "true" && element !== this.fontSizeTarget)
      .map(element => ({ label: element.getAttribute("aria-label"), element }))

    const choices = this.menuTargets.filter(menu => menu !== this.resultsTarget && !menu.matches("form"))
      .flatMap(menu => [ ...menu.querySelectorAll("button[data-action]") ].map(element => ({
        label: `${menu.getAttribute("aria-label")}: ${element.getAttribute("aria-label") ?? element.querySelector(".toolbar-menu__label")?.textContent ?? element.textContent.trim()}`,
        element
      })))

    const menuBar = [ ...document.querySelectorAll(".menu-bar [role^=menuitem]:not([aria-haspopup], [aria-disabled=true])") ]
      .map(element => ({
        label: `${element.closest("[role=menu]")?.getAttribute("aria-label")}: ${element.querySelector(".menu-bar__label")?.textContent.trim()}`,
        element
      }))

    // The View menu's zoom levels repeat the toolbar's, so the first of each label wins.
    const labels = new Set()
    return [ ...toolbar, ...choices, ...menuBar ].filter(({ label }) => label && !labels.has(label) && labels.add(label))
  }
}

function compact(object) {
  return Object.fromEntries(Object.entries(object).filter(([ , value ]) => value !== undefined && value !== null))
}

// Values are compared as the menus spell them: "#rrggbb" colors, numbers as numbers.
function normalize(value) {
  return hex(value) ?? String(value).toLowerCase()
}

function parseParam(value) {
  try { return JSON.parse(value) } catch { return value }
}

// "#RGB", "#rrggbb" or "rgb(r, g, b)" → "#rrggbb", anything else → null.
function hex(color) {
  if (typeof color !== "string") return null
  const short = color.match(/^#([0-9a-f])([0-9a-f])([0-9a-f])$/i)
  if (short) return `#${short.slice(1).map(digit => digit + digit).join("")}`.toLowerCase()
  if (/^#[0-9a-f]{6}$/i.test(color)) return color.toLowerCase()

  const rgb = color.match(/^rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)$/)
  if (!rgb || rgb[4] === "0") return null
  return `#${rgb.slice(1, 4).map(part => Number(part).toString(16).padStart(2, "0")).join("")}`
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
