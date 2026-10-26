module MenuBarHelper
  SEPARATOR = :separator

  # The menus along the top, laid out like Sheets'. An item either dispatches a sheet
  # command (command:, value:), does something the menu bar handles itself (action:),
  # links somewhere (href:) or opens a submenu (items:). Anything this sheet can't do,
  # like making new sheets, is there but greyed out, the way Sheets shows unavailable items.
  def menu_bar_menus
    {
      "File" => file_menu,
      "Edit" => edit_menu,
      "View" => view_menu,
      "Insert" => insert_menu,
      "Format" => format_menu,
      "Data" => data_menu,
      "Tools" => tools_menu,
      "Ship" => ship_menu,
      "Help" => help_menu
    }
  end

  # The Help menu's keyboard shortcuts dialog, grouped like Sheets'. "Ctrl" reads "⌘" on a Mac.
  def keyboard_shortcut_groups
    {
      "Common actions" => [
        [ "Select all", "Ctrl+A" ], [ "Undo", "Ctrl+Z" ], [ "Redo", "Ctrl+Y" ], [ "Redo", "Ctrl+Shift+Z" ],
        [ "Cut", "Ctrl+X" ], [ "Copy", "Ctrl+C" ], [ "Paste", "Ctrl+V" ], [ "Print", "Ctrl+P" ],
        [ "Show keyboard shortcuts", "Ctrl+/" ]
      ],
      "Cell formatting" => [
        [ "Bold", "Ctrl+B" ], [ "Italic", "Ctrl+I" ], [ "Underline", "Ctrl+U" ], [ "Strikethrough", "Alt+Shift+5" ],
        [ "Clear formatting", "Ctrl+\\" ]
      ],
      "Navigate spreadsheet" => [
        [ "Move to the next cell", "Arrow keys" ], [ "Extend the selection", "Shift+Arrow keys" ],
        [ "Move to the edge of the data", "Ctrl+Arrow keys" ], [ "Extend to the edge of the data", "Ctrl+Shift+Arrow keys" ],
        [ "Move to the beginning of the row", "Home" ], [ "Move to the beginning of the sheet", "Ctrl+Home" ]
      ],
      "Edit cells" => [
        [ "Edit the active cell", "Enter" ], [ "Edit the active cell", "F2" ], [ "Save and move down", "Enter" ],
        [ "Save and move right", "Tab" ], [ "Cancel editing", "Esc" ], [ "Clear the selection", "Delete" ]
      ]
    }
  end

  private
    def file_menu
      [
        { label: "New", disabled: true, items: [ { label: "Spreadsheet", disabled: true } ] },
        { label: "Open", shortcut: "Ctrl+O", disabled: true },
        { label: "Import", disabled: true },
        { label: "Make a copy", disabled: true },
        SEPARATOR,
        { label: "Share", disabled: true, items: [ { label: "Share with others", disabled: true } ] },
        { label: "Email", disabled: true, items: [ { label: "Email this file", disabled: true } ] },
        { label: "Download", items: [
          { label: "Microsoft Excel (.xlsx)", disabled: true },
          { label: "OpenDocument (.ods)", disabled: true },
          { label: "PDF (.pdf)", disabled: true },
          { label: "Web page (.html)", disabled: true },
          { label: "Comma separated values (.csv)", action: "download", value: "csv" },
          { label: "Tab separated values (.tsv)", action: "download", value: "tsv" }
        ] },
        SEPARATOR,
        { label: "Rename", action: "rename" },
        { label: "Move", disabled: true },
        { label: "Add shortcut to Drive", disabled: true },
        { label: "Move to trash", disabled: true },
        SEPARATOR,
        { label: "Version history", disabled: true, items: [ { label: "See version history", disabled: true } ] },
        { label: "Make available offline", disabled: true },
        SEPARATOR,
        { label: "Reset this sheet", command: "clearSheet" },
        { label: "Details", disabled: true },
        { label: "Settings", disabled: true },
        SEPARATOR,
        { label: "Print", shortcut: "Ctrl+P", action: "print" }
      ]
    end

    def edit_menu
      [
        { label: "Undo", shortcut: "Ctrl+Z", command: "undo", disabled: true },
        { label: "Redo", shortcut: "Ctrl+Y", command: "redo", disabled: true },
        SEPARATOR,
        { label: "Cut", shortcut: "Ctrl+X", command: "cut" },
        { label: "Copy", shortcut: "Ctrl+C", command: "copy" },
        { label: "Paste", shortcut: "Ctrl+V", command: "paste" },
        { label: "Paste special", disabled: true, items: [ { label: "Values only", disabled: true } ] },
        SEPARATOR,
        { label: "Move", disabled: true, items: [ { label: "Row up", disabled: true } ] },
        { label: "Delete", items: [
          { label: "Values", command: "delete" },
          { label: "Row", disabled: true },
          { label: "Column", disabled: true }
        ] },
        SEPARATOR,
        { label: "Select all", shortcut: "Ctrl+A", command: "selectAll" },
        { label: "Find and replace", shortcut: "Ctrl+H", disabled: true }
      ]
    end

    def view_menu
      [
        { label: "Show", items: [
          { label: "Formula bar", action: "formulaBar", checked: true },
          { label: "Gridlines", action: "gridlines", checked: true },
          { label: "Formulas", shortcut: "Ctrl+`", disabled: true }
        ] },
        { label: "Freeze", disabled: true, items: [ { label: "No rows", disabled: true } ] },
        { label: "Group", disabled: true },
        SEPARATOR,
        { label: "Zoom", items: [ 50, 75, 90, 100, 125, 150, 200 ].map { |zoom| { label: "#{zoom}%", command: "zoom", value: zoom } } },
        { label: "Full screen", action: "fullScreen" }
      ]
    end

    def insert_menu
      [
        { label: "Cells", disabled: true, items: [ { label: "Insert cells and shift right", disabled: true } ] },
        { label: "Rows", disabled: true, items: [ { label: "Insert 1 row above", disabled: true } ] },
        { label: "Columns", disabled: true, items: [ { label: "Insert 1 column left", disabled: true } ] },
        { label: "Sheet", shortcut: "Shift+F11", disabled: true },
        SEPARATOR,
        { label: "Chart", disabled: true },
        { label: "Pivot table", disabled: true },
        { label: "Image", disabled: true, items: [ { label: "Insert image in cell", disabled: true } ] },
        { label: "Drawing", disabled: true },
        SEPARATOR,
        { label: "Function", items: %w[SUM AVERAGE COUNT MAX MIN].map { |name| { label: name, command: "insertFunction", value: name } } },
        SEPARATOR,
        { label: "Link", shortcut: "Ctrl+K", action: "prompt", command: "insertLink" },
        { label: "Checkbox", disabled: true },
        { label: "Dropdown", disabled: true },
        SEPARATOR,
        { label: "Comment", shortcut: "Ctrl+Alt+M", action: "prompt", command: "comment" }
      ]
    end

    def format_menu
      [
        { label: "Theme", disabled: true },
        SEPARATOR,
        { label: "Number", items: [
          { label: "Automatic", command: "numberFormat", value: "automatic" },
          { label: "Plain text", command: "numberFormat", value: "plain" },
          SEPARATOR,
          { label: "Number", hint: "1,000.12", command: "numberFormat", value: "number" },
          { label: "Percent", hint: "10.12%", command: "numberFormat", value: "percent" },
          { label: "Scientific", hint: "1.01E+03", command: "numberFormat", value: "scientific" },
          SEPARATOR,
          { label: "Currency", hint: "$1,000.12", command: "numberFormat", value: "currency" },
          SEPARATOR,
          { label: "Date", hint: "9/26/2008", command: "numberFormat", value: "date" },
          { label: "Time", hint: "3:59:00 PM", command: "numberFormat", value: "time" },
          SEPARATOR,
          { label: "Increase decimal places", command: "decimals", value: 1 },
          { label: "Decrease decimal places", command: "decimals", value: -1 }
        ] },
        { label: "Text", items: [
          { label: "Bold", shortcut: "Ctrl+B", command: "bold" },
          { label: "Italic", shortcut: "Ctrl+I", command: "italic" },
          { label: "Underline", shortcut: "Ctrl+U", command: "underline" },
          { label: "Strikethrough", shortcut: "Alt+Shift+5", command: "strikethrough" }
        ] },
        { label: "Alignment", items: [
          { label: "Left", shortcut: "Ctrl+Shift+L", command: "alignH", value: "left" },
          { label: "Center", shortcut: "Ctrl+Shift+E", command: "alignH", value: "center" },
          { label: "Right", shortcut: "Ctrl+Shift+R", command: "alignH", value: "right" },
          SEPARATOR,
          { label: "Top", command: "alignV", value: "top" },
          { label: "Middle", command: "alignV", value: "middle" },
          { label: "Bottom", command: "alignV", value: "bottom" }
        ] },
        { label: "Wrapping", items: [
          { label: "Overflow", command: "wrap", value: "overflow" },
          { label: "Wrap", command: "wrap", value: "wrap" },
          { label: "Clip", command: "wrap", value: "clip" }
        ] },
        { label: "Rotation", items: [
          { label: "None", command: "rotate", value: 0 },
          { label: "Tilt up", command: "rotate", value: 45 },
          { label: "Tilt down", command: "rotate", value: -45 },
          { label: "Stack vertically", command: "rotate", value: "vertical" },
          { label: "Rotate up", command: "rotate", value: 90 },
          { label: "Rotate down", command: "rotate", value: -90 }
        ] },
        SEPARATOR,
        { label: "Font size", items: [ 6, 7, 8, 9, 10, 11, 12, 14, 18, 24, 36 ].map { |size| { label: size.to_s, command: "fontSize", value: size } } },
        { label: "Merge cells", items: [
          { label: "Merge all", command: "merge", value: "all" },
          { label: "Merge horizontally", command: "merge", value: "horizontal" },
          { label: "Merge vertically", command: "merge", value: "vertical" },
          { label: "Unmerge", command: "merge", value: "unmerge" }
        ] },
        SEPARATOR,
        { label: "Conditional formatting", disabled: true },
        { label: "Alternating colors", disabled: true },
        SEPARATOR,
        { label: "Clear formatting", shortcut: "Ctrl+\\", command: "clearFormat" }
      ]
    end

    def data_menu
      [
        { label: "Sort sheet", disabled: true, items: [ { label: "Sort sheet (A to Z)", disabled: true } ] },
        { label: "Sort range", disabled: true, items: [ { label: "Sort range (A to Z)", disabled: true } ] },
        SEPARATOR,
        { label: "Create a filter", disabled: true },
        { label: "Filter views", disabled: true, items: [ { label: "Create new filter view", disabled: true } ] },
        { label: "Add a slicer", disabled: true },
        SEPARATOR,
        { label: "Protect sheets and ranges", disabled: true },
        { label: "Named ranges", disabled: true },
        { label: "Named functions", disabled: true },
        { label: "Randomize range", disabled: true },
        SEPARATOR,
        { label: "Column stats", disabled: true },
        { label: "Data validation", disabled: true },
        { label: "Data cleanup", disabled: true, items: [ { label: "Remove duplicates", disabled: true } ] },
        { label: "Split text to columns", disabled: true }
      ]
    end

    def tools_menu
      [
        { label: "Create a new form", disabled: true },
        SEPARATOR,
        { label: "Spelling", disabled: true, items: [ { label: "Spell check", disabled: true } ] },
        { label: "Suggestion controls", disabled: true, items: [ { label: "Enable autocomplete", disabled: true } ] },
        SEPARATOR,
        { label: "Notification settings", disabled: true, items: [ { label: "Edit notifications", disabled: true } ] },
        { label: "Accessibility", disabled: true }
      ]
    end

    # The program, step by step: its own sheets, then the Hackatime link to track your hours with.
    def ship_menu
      [
        { label: "How it works", href: "#how-it-works" },
        { label: "Get an idea", href: "#ideas" },
        { label: "See examples", href: "#examples" },
        { label: "FAQ", href: "#faq" },
        SEPARATOR,
        { label: "Track hours with Hackatime", hint: "writing code", href: hackatime_url },
        SEPARATOR,
        { label: "Ask in the Hack Club Slack", href: footer_links["slack"] },
        { label: "Fulfillment", href: footer_links["fulfillment"] }
      ]
    end

    def help_menu
      [
        { label: "Help", disabled: true },
        { label: "Training", disabled: true },
        { label: "Updates", disabled: true },
        SEPARATOR,
        { label: "Help Sheets improve", disabled: true },
        { label: "Privacy Policy", href: footer_links["privacy"] },
        { label: "Terms of Service", href: footer_links["privacy"] },
        SEPARATOR,
        { label: "Function list", disabled: true },
        { label: "Keyboard shortcuts", shortcut: "Ctrl+/", action: "shortcuts" }
      ]
    end
end
