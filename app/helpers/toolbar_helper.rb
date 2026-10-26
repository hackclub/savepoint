# What the toolbar's menus offer, in the order Google Sheets lists them.
module ToolbarHelper
  ZOOM_LEVELS = [ 50, 75, 90, 100, 125, 150, 200 ].freeze

  # Fonts every browser has (plus the ones the page loads), each shown in itself.
  FONT_FAMILIES = [
    "Arial", "Comic Sans MS", "Courier New", "Georgia", "IBM Plex Mono", "Impact",
    "Roboto", "Times New Roman", "Trebuchet MS", "Verdana"
  ].freeze

  FONT_SIZES = [ 6, 7, 8, 9, 10, 11, 12, 14, 18, 24, 36 ].freeze

  # [ label, value, sample ], with nil for a divider.
  NUMBER_FORMATS = [
    [ "Automatic", "automatic" ], [ "Plain text", "plain" ], nil,
    [ "Number", "number", "1,000.12" ], [ "Percent", "percent", "10.12%" ], [ "Scientific", "scientific", "1.01E+03" ], nil,
    [ "Currency", "currency", "$1,000.12" ], nil,
    [ "Date", "date", "9/26/2008" ], [ "Time", "time", "3:59:00 PM" ]
  ].freeze

  FUNCTIONS = %w[SUM AVERAGE COUNT MAX MIN].freeze

  # Sheets' palette: a row of greys, a row of bright hues, then three tints and three shades of each hue.
  PALETTE_HUES = [ "red berry", "red", "orange", "yellow", "green", "cyan", "cornflower blue", "blue", "purple", "magenta" ].freeze
  PALETTE = [
    [ "black", "#000000" ], [ "dark gray 4", "#434343" ], [ "dark gray 3", "#666666" ], [ "dark gray 2", "#999999" ],
    [ "dark gray 1", "#b7b7b7" ], [ "gray", "#cccccc" ], [ "light gray 1", "#d9d9d9" ], [ "light gray 2", "#efefef" ],
    [ "light gray 3", "#f3f3f3" ], [ "white", "#ffffff" ],
    *PALETTE_HUES.zip(%w[#980000 #ff0000 #ff9900 #ffff00 #00ff00 #00ffff #4a86e8 #0000ff #9900ff #ff00ff]),
    *{
      "light %s 3" => %w[#e6b8af #f4cccc #fce5cd #fff2cc #d9ead3 #d0e0e3 #c9daf8 #cfe2f3 #d9d2e9 #ead1dc],
      "light %s 2" => %w[#dd7e6b #ea9999 #f9cb9c #ffe599 #b6d7a8 #a2c4c9 #a4c2f4 #9fc5e8 #b4a7d6 #d5a6bd],
      "light %s 1" => %w[#cc4125 #e06666 #f6b26b #ffd966 #93c47d #76a5af #6d9eeb #6fa8dc #8e7cc3 #c27ba0],
      "dark %s 1" => %w[#a61c00 #cc0000 #e69138 #f1c232 #6aa84f #45818e #3c78d8 #3d85c6 #674ea7 #a64d79],
      "dark %s 2" => %w[#85200c #990000 #b45f06 #bf9000 #38761d #134f5c #1155cc #0b5394 #351c75 #741b47],
      "dark %s 3" => %w[#5b0f00 #660000 #783f04 #7f6000 #274e13 #0c343d #1c4587 #073763 #20124d #4c1130]
    }.flat_map { |name, colors| PALETTE_HUES.map { |hue| format(name, hue) }.zip(colors) }
  ].freeze

  # [ value, label, icon ] for the menus that pick one of a few icons.
  ALIGNMENTS = {
    "alignH" => [ [ "left", "Left", "format-align-left" ], [ "center", "Center", "format-align-center" ], [ "right", "Right", "format-align-right" ] ],
    "alignV" => [ [ "top", "Top", "vertical-align-top" ], [ "middle", "Middle", "vertical-align-center" ], [ "bottom", "Bottom", "vertical-align-bottom" ] ],
    "wrap" => [ [ "overflow", "Overflow", "format-text-overflow" ], [ "wrap", "Wrap", "format-text-wrap" ], [ "clip", "Clip", "format-text-clip" ] ],
    "rotate" => [
      [ 0, "None", "text-rotation-none" ], [ 45, "Tilt up", "text-rotation-angleup" ], [ -45, "Tilt down", "text-rotation-angledown" ],
      [ "vertical", "Stack vertically", "text-rotate-vertical" ], [ 90, "Rotate up", "text-rotate-up" ], [ -90, "Rotate down", "text-rotation-down" ]
    ]
  }.freeze

  # The borders grid, two rows of five like Sheets. Horizontal and vertical aren't in the command set.
  BORDERS = [
    [ "all", "All borders", "border-all" ], [ "inner", "Inner borders", "border-inner" ],
    [ nil, "Horizontal borders", "border-horizontal" ], [ nil, "Vertical borders", "border-vertical" ],
    [ "outer", "Outer borders", "border-outer" ],
    [ "left", "Left border", "border-left" ], [ "top", "Top border", "border-top" ],
    [ "right", "Right border", "border-right" ], [ "bottom", "Bottom border", "border-bottom" ],
    [ "none", "Clear borders", "border-clear" ]
  ].freeze

  MERGES = [ [ "all", "Merge all" ], [ "vertical", "Merge vertically" ], [ "horizontal", "Merge horizontally" ], [ "unmerge", "Unmerge" ] ].freeze
end
