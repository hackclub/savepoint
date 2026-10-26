import { COLUMNS } from "sheet/formula"

// Where cells sit in the grid. Positions are read from the layout, so the CSS stays
// the single source; the cell size comes from the grid's --cell-width and --cell-height.

export function cellSize(grid) {
  const style = getComputedStyle(grid)
  return {
    width: parseFloat(style.getPropertyValue("--cell-width")),
    height: parseFloat(style.getPropertyValue("--cell-height"))
  }
}

// The toolbar's zoom (CSS zoom on the sheet). Layout reads like offsetLeft and the cell
// size stay unzoomed, but pointer and bounding-rect maths is in screen pixels, so divide by it.
export function zoomOf(grid) {
  return grid.currentCSSZoom ?? 1
}

// The columns and rows a cell covers. Cells stop 1px short of their gridlines, hence the rounding.
export function boxOf(cell, { width, height }) {
  return {
    column: Math.round(cell.offsetLeft / width),
    row: Math.round(cell.offsetTop / height),
    width: Math.round(cell.offsetWidth / width),
    height: Math.round(cell.offsetHeight / height)
  }
}

// { column: 1, row: 10 } ⇄ "B11"
export function address({ column, row }) {
  return `${COLUMNS[column]}${row + 1}`
}

export function position(address) {
  const [ , letter, number ] = address.match(/^([A-Z])(\d+)$/)
  return { column: COLUMNS.indexOf(letter), row: Number(number) - 1 }
}
