import { Controller } from "@hotwired/stimulus"
import { boxOf, cellSize } from "sheet/grid"

const MAC = /Mac|iPhone|iPad/.test(navigator.userAgentData?.platform ?? navigator.platform)
const MODIFIERS = { Ctrl: "⌘", Alt: "⌥", Shift: "⇧" }

// The menu bar, working like Sheets': a click opens a menu, then hovering moves between
// menus and into submenus; arrows, Enter and Escape work from the keyboard, and a click
// outside closes it. Items send "command" events to the sheet (the toolbar's commands:
// undo, bold, numberFormat, zoom…) or do menu-bar things: download the tab as CSV/TSV,
// print, rename, show or hide the gridlines and formula bar, full screen, and the
// keyboard shortcuts, link and comment dialogs. Links go to the program's pages and sheets.
export default class extends Controller {
  static targets = [ "menu", "shortcuts", "shortcutSearch", "shortcutGroup", "prompt", "promptTitle", "promptInput" ]

  connect() {
    if (MAC) this.element.querySelectorAll("[data-shortcut]").forEach(key => key.textContent = mac(key.dataset.shortcut))
  }

  // Clicking a menu's name opens it, and clicking it again closes it.
  toggle(event) {
    const menu = event.currentTarget.closest(".menu-bar__menu")
    const justHovered = this.hovered === menu
    this.hovered = null
    if (justHovered) return // the click that follows the hover which opened it

    if (menu === this.openMenu) {
      this.close()
      this.#refocus()
    } else {
      this.#open(menu)
    }
  }

  // Once a menu's open, the others open just by hovering over them.
  hover(event) {
    const menu = event.currentTarget.closest(".menu-bar__menu")
    if (this.openMenu && menu !== this.openMenu) {
      this.#open(menu)
      this.hovered = menu
    }
  }

  unhover() {
    this.hovered = null
  }

  // Pressing in the menus keeps focus where the menus put it, so the grid gets it back afterwards.
  hold(event) {
    event.preventDefault()
  }

  // Hovering an item highlights it and opens its submenu, closing any other.
  enter(event) {
    const entry = event.currentTarget
    entry.focus({ preventScroll: true })
    this.#closeSubmenus(entry.closest(".menu-bar__dropdown"), entry)
    if (this.#submenuOf(entry) && !disabled(entry)) this.#openSubmenu(entry)
  }

  choose(event) {
    const entry = event.currentTarget
    if (disabled(entry)) return event.preventDefault()

    if (this.#submenuOf(entry)) {
      if (!this.openMenu) this.#open(entry.closest(".menu-bar__menu"))
      this.#openSubmenu(entry)
      return this.#first(this.#submenuOf(entry))?.focus()
    }

    const href = entry.getAttribute("href")
    if (href?.startsWith("#")) {
      event.preventDefault()
      document.querySelector(`.sheet-tab[href="${href}"]`)?.click()
    }
    this.close()
    if (!href || href.startsWith("#")) this.#refocus() // before running, so a dialog or the title can take focus
    if (!href) this.#run(entry)
  }

  // Arrows, Enter, Space and Escape, as in Sheets' menus.
  navigate(event) {
    const menus = this.menuTargets
    const button = event.target.closest(".menu-bar__item")
    const handled = this.openMenu ? this.#navigateMenu(event.key) : button && this.#navigateBar(event.key, menus.indexOf(button.closest(".menu-bar__menu")))
    if (handled) {
      event.preventDefault()
      event.stopPropagation()
    }
  }

  // A press anywhere else closes the menus, as it does in Sheets.
  dismiss(event) {
    if (this.openMenu && !this.element.querySelector(".menu-bar").contains(event.target)) this.close()
  }

  // Ctrl/Cmd+/ opens the keyboard shortcuts, from anywhere.
  shortcut(event) {
    if ((event.ctrlKey || event.metaKey) && event.key === "/") {
      event.preventDefault()
      this.close()
      this.#showShortcuts()
    }
  }

  // Undo and redo are only there when there's something to undo or redo.
  reflect({ detail: { canUndo = false, canRedo = false } = {} }) {
    this.element.querySelectorAll("[data-command=undo]").forEach(entry => setDisabled(entry, !canUndo))
    this.element.querySelectorAll("[data-command=redo]").forEach(entry => setDisabled(entry, !canRedo))
  }

  close() {
    this.hovered = null
    if (!this.openMenu) return

    this.#closeSubmenus(this.openMenu.querySelector(".menu-bar__dropdown"))
    this.openMenu.querySelector(".menu-bar__dropdown").hidden = true
    this.openMenu.querySelector(".menu-bar__item").setAttribute("aria-expanded", "false")
    this.openMenu = null
  }

  filterShortcuts() {
    const query = this.shortcutSearchTarget.value.trim().toLowerCase()
    this.shortcutGroupTargets.forEach(group => {
      let shown = 0
      group.querySelectorAll(".menu-dialog__shortcut").forEach(row => {
        row.hidden = query !== "" && !row.textContent.toLowerCase().includes(query)
        if (!row.hidden) shown++
      })
      group.hidden = shown === 0
    })
  }

  // A click on the dimmed backdrop (the dialog element itself, outside its box) closes it.
  backdrop(event) {
    if (event.target === event.currentTarget) this.closeDialog(event)
  }

  closeDialog(event) {
    event.target.closest("dialog").close()
  }

  // However a dialog closes (a button, Escape, the backdrop), the grid gets the keys back.
  closed() {
    this.#refocus()
  }

  // Insert > Link and Insert > Comment send what was typed with their command.
  submitPrompt() {
    const value = this.promptInputTarget.value.trim()
    if (value && this.pendingCommand) this.#send(this.pendingCommand, value)
    this.pendingCommand = null
  }

  #open(menu) {
    this.close()
    this.openMenu = menu
    const dropdown = menu.querySelector(".menu-bar__dropdown")
    dropdown.hidden = false
    dropdown.style.maxBlockSize = `${window.innerHeight - dropdown.getBoundingClientRect().top - 8}px`
    menu.querySelector(".menu-bar__item").setAttribute("aria-expanded", "true")
    dropdown.focus({ preventScroll: true })
  }

  // Submenus are fixed to the viewport, so a menu that scrolls doesn't clip them. They open to
  // the right of their item, or to the left when there's no room, and stay on screen.
  #openSubmenu(entry) {
    const submenu = this.#submenuOf(entry)
    if (!submenu.hidden) return

    submenu.hidden = false
    entry.setAttribute("aria-expanded", "true")
    const item = entry.getBoundingClientRect()
    const { width, height } = submenu.getBoundingClientRect()
    const left = item.right + width > window.innerWidth ? item.left - width : item.right
    const top = Math.max(8, Math.min(item.top - 8, window.innerHeight - height - 8))
    submenu.style.left = `${left}px`
    submenu.style.top = `${top}px`
  }

  #closeSubmenus(dropdown, except) {
    dropdown.querySelectorAll(":scope > .menu-bar__group > .menu-bar__entry[aria-expanded=true]").forEach(entry => {
      if (entry === except) return
      const submenu = this.#submenuOf(entry)
      this.#closeSubmenus(submenu)
      submenu.hidden = true
      entry.setAttribute("aria-expanded", "false")
    })
  }

  #submenuOf(entry) {
    return entry.parentElement.matches(".menu-bar__group") ? entry.nextElementSibling : null
  }

  #navigateBar(key, index) {
    if (key === "ArrowDown" || key === "Enter" || key === " ") {
      this.#open(this.menuTargets[index])
      this.#first(this.openMenu.querySelector(".menu-bar__dropdown"))?.focus()
    } else if (key === "ArrowRight" || key === "ArrowLeft") {
      const next = this.menuTargets.at((index + (key === "ArrowRight" ? 1 : -1)) % this.menuTargets.length)
      next.querySelector(".menu-bar__item").focus()
    } else {
      return false
    }
    return true
  }

  #navigateMenu(key) {
    const active = document.activeElement
    const dropdown = active?.closest(".menu-bar__dropdown") ?? this.openMenu.querySelector(".menu-bar__dropdown")
    const entry = active?.matches(".menu-bar__entry") ? active : null
    const entries = [ ...dropdown.querySelectorAll(":scope > .menu-bar__entry, :scope > .menu-bar__group > .menu-bar__entry") ]
      .filter(item => !disabled(item))
    const index = entries.indexOf(entry)
    const parent = dropdown.parentElement.matches(".menu-bar__group") ? dropdown.previousElementSibling : null
    const top = this.menuTargets.indexOf(this.openMenu)

    switch (key) {
      case "ArrowDown":
        entries.at((index + 1) % entries.length)?.focus()
        break
      case "ArrowUp":
        entries.at(index < 0 ? -1 : index - 1)?.focus()
        break
      case "Home":
        entries[0]?.focus()
        break
      case "End":
        entries.at(-1)?.focus()
        break
      case "ArrowRight":
        if (entry && this.#submenuOf(entry) && !disabled(entry)) {
          this.#openSubmenu(entry)
          this.#first(this.#submenuOf(entry))?.focus()
        } else {
          this.#switchMenu(top + 1)
        }
        break
      case "ArrowLeft":
        if (parent) {
          this.#closeSubmenus(parent.closest(".menu-bar__dropdown"))
          parent.focus()
        } else {
          this.#switchMenu(top - 1)
        }
        break
      case "Enter":
      case " ":
        entry?.click()
        break
      case "Escape":
        if (parent) {
          this.#closeSubmenus(parent.closest(".menu-bar__dropdown"))
          parent.focus()
        } else {
          this.close()
          this.#refocus()
        }
        break
      case "Tab":
        this.close()
        return false
      default:
        return false
    }
    return true
  }

  #switchMenu(index) {
    const menus = this.menuTargets
    this.#open(menus.at(index % menus.length))
    this.#first(this.openMenu.querySelector(".menu-bar__dropdown"))?.focus()
  }

  #first(dropdown) {
    return [ ...dropdown.querySelectorAll(":scope > .menu-bar__entry, :scope > .menu-bar__group > .menu-bar__entry") ]
      .find(item => !disabled(item))
  }

  #run(entry) {
    const { command, menuAction, value } = entry.dataset
    const parsed = value === undefined ? undefined : JSON.parse(value)

    switch (menuAction) {
      case "download": return this.#download(parsed)
      case "print": return window.print()
      case "rename": return this.dispatch("rename")
      case "gridlines": return this.#toggle(entry, document.querySelector(".sheet__cells"), "sheet__cells--no-gridlines")
      case "formulaBar": return this.#toggleHidden(entry, document.querySelector(".formula-bar"))
      case "fullScreen": return document.fullscreenElement ? document.exitFullscreen() : document.documentElement.requestFullscreen?.()
      case "shortcuts": return this.#showShortcuts()
      case "prompt": return this.#ask(entry.dataset.title, command)
    }
    if (command) this.#send(command, parsed)
  }

  #send(command, value) {
    this.dispatch("command", { detail: { command, value } })
  }

  #toggle(entry, element, className) {
    const shown = entry.getAttribute("aria-checked") !== "true"
    entry.setAttribute("aria-checked", shown)
    element?.classList.toggle(className, !shown)
  }

  #toggleHidden(entry, element) {
    const shown = entry.getAttribute("aria-checked") !== "true"
    entry.setAttribute("aria-checked", shown)
    if (element) element.hidden = !shown
  }

  #showShortcuts() {
    if (this.shortcutsTarget.open) return

    this.shortcutSearchTarget.value = ""
    this.filterShortcuts()
    this.shortcutsTarget.showModal()
    this.shortcutSearchTarget.focus()
  }

  #ask(title, command) {
    this.pendingCommand = command
    this.promptTitleTarget.textContent = title
    this.promptInputTarget.value = ""
    this.promptInputTarget.placeholder = command === "insertLink" ? "Paste a link" : "Add a comment"
    this.promptTarget.showModal()
    this.promptInputTarget.focus()
  }

  // File > Download: the open tab as it's shown, cell by cell by address, as Sheets would export it.
  #download(format) {
    const separator = format === "tsv" ? "\t" : ","
    const text = this.#table().map(row => row.map(value => quote(value, format)).join(separator)).join("\r\n")
    const tab = document.querySelector(".sheet__section:not([hidden])")?.getAttribute("aria-label") ?? "Sheet1"
    const title = document.querySelector(".app-bar__title")?.value || "Save Point"

    const link = document.createElement("a")
    link.href = URL.createObjectURL(new Blob([ text ], { type: format === "tsv" ? "text/tab-separated-values" : "text/csv" }))
    link.download = `${title} - ${tab}.${format}`
    link.click()
    setTimeout(() => URL.revokeObjectURL(link.href), 0)
  }

  // Rows of what each cell shows, placed at the cell's top-left address (later cells, like
  // typed-in ones, cover earlier ones), trimmed to the last row and column with anything in it.
  #table() {
    const grid = document.querySelector(".sheet__cells")
    if (!grid) return []

    const size = cellSize(grid)
    const rows = []
    grid.querySelectorAll(".sheet__section:not([hidden]) .cell, .sheet__entries .cell").forEach(cell => {
      if (!cell.offsetParent) return

      const { column, row } = boxOf(cell, size)
      rows[row] ??= []
      rows[row][column] = shownText(cell)
    })

    const width = Math.max(0, ...Array.from(rows, row => row ? row.findLastIndex(value => value) + 1 : 0))
    const height = rows.findLastIndex(row => row?.some(value => value)) + 1
    return Array.from({ length: height }, (_, row) => Array.from({ length: width }, (_, column) => rows[row]?.[column] ?? ""))
  }

  #refocus() {
    document.querySelector(".sheet__cells")?.focus({ preventScroll: true })
  }
}

function disabled(entry) {
  return entry.getAttribute("aria-disabled") === "true"
}

function setDisabled(entry, value) {
  if (value) entry.setAttribute("aria-disabled", "true")
  else entry.removeAttribute("aria-disabled")
}

// What a cell reads as, leaving out copies made for looks (the marquee repeats its text).
function shownText(cell) {
  let copy = cell
  if (cell.querySelector("[aria-hidden=true]")) {
    copy = cell.cloneNode(true)
    copy.querySelectorAll("[aria-hidden=true]").forEach(element => element.remove())
  }
  return copy.textContent.replace(/\s+/g, " ").trim()
}

function quote(value, format) {
  if (format === "tsv") return value.replace(/[\t\r\n]+/g, " ")
  return /[",\r\n]/.test(value) ? `"${value.replaceAll('"', '""')}"` : value
}

// "Ctrl+Shift+Z" → "⌘⇧Z", as Sheets spells shortcuts on a Mac.
function mac(shortcut) {
  const parts = shortcut.split("+")
  const key = parts.pop()
  const modifiers = parts.map(part => MODIFIERS[part] ?? `${part}+`).join("")
  return modifiers ? `${modifiers}${key.includes(" ") ? "+" : ""}${key}` : key
}
