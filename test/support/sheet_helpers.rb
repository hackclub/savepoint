# Helpers for the sheet editor's tests: typing into cells, sending the toolbar's
# commands, selecting ranges and reading back what's drawn.
module SheetHelpers
  private
    def type_into(column, row, *keys)
      click_cell(column:, row:)
      page.send_keys(*keys)
    end

    def assert_entry(address, text)
      assert_selector "#{entry_selector(address)}", exact_text: text
    end

    def entry_selector(address)
      column, row = coordinates(address)
      ".sheet-entry[style*='grid-area: #{row + 1} / #{column + 1}']"
    end

    def entry(address)
      find(".sheet__entries [data-sheet-key='#{address}']")
    end

    def coordinates(address)
      [ address[0].ord - "A".ord, address[1..].to_i - 1 ]
    end

    # Sends a command the way the toolbar and the menus do.
    def command(name, value = nil)
      execute_script(<<~JS, name, value)
        document.querySelector(".sheet-viewport").dispatchEvent(new CustomEvent("toolbar:command", {
          bubbles: true, detail: { command: arguments[0], value: arguments[1] }
        }))
      JS
    end

    # Selects a range like "A25:B26": clicks its first cell, then tells the editor about
    # the whole range the way cell-selection's select event does.
    def select_range(range)
      first, last = range.split(":").map { |address| coordinates(address) }
      click_cell(column: first[0], row: first[1])
      execute_script(<<~JS, *first, last[0] - first[0] + 1, last[1] - first[1] + 1)
        const [ column, row, width, height ] = arguments
        const box = { column, row, width: 1, height: 1 }
        const address = String.fromCharCode(65 + column) + (row + 1)
        const cell = document.querySelector(`.sheet__entries [data-sheet-key="${address}"]`) ?? undefined
        document.querySelector(".spreadsheet").dispatchEvent(new CustomEvent("cell-selection:select", {
          detail: { box, cell, range: { column, row, width, height } }
        }))
      JS
    end

    # The last format (and undo state) the editor reported to the toolbar.
    def reported
      evaluate_script("window.lastSheetFormat")
    end

    def reported_format
      reported["format"]
    end

    def record_formats
      execute_script(<<~JS)
        window.addEventListener("sheet-editor:format", event => { window.lastSheetFormat = event.detail })
      JS
    end

    def inline_style(element, property)
      evaluate_script("arguments[0].style.getPropertyValue(arguments[1])", element, property)
    end
end
