import { SheetError, display, literal } from "sheet/formula"

// Number formats, as Sheets' "123" menu has them. A cell's value stays a plain number;
// its format decides how it reads: 1234.5 shows as $1,234.50, 12.35%, 1.23E+03 or,
// read as days since 30 December 1899, 5/18/1903.

const DAY = 86400000
const EPOCH = Date.UTC(1899, 11, 30)
const FIXED = { number: 2, percent: 2, scientific: 2, currency: 2 }

// How a value reads in a cell with this format. Text, TRUE/FALSE and errors read as they are.
export function formatValue(value, { numberFormat = "automatic", decimals } = {}) {
  if (typeof value !== "number" || !Number.isFinite(value)) return display(value)

  const places = decimals ?? FIXED[numberFormat]
  switch (numberFormat) {
    case "number":
      return grouped(value, places)
    case "percent":
      return `${grouped(value * 100, places)}%`
    case "scientific":
      return scientific(value, places)
    case "currency":
      return `${value < 0 ? "-" : ""}$${grouped(Math.abs(value), places)}`
    case "date":
      return dateOf(value)
    case "time":
      return timeOf(value)
    case "datetime":
      return `${dateOf(value)} ${timeOf(value, { clock: 24 })}`
    default:
      return places === undefined ? display(value) : value.toFixed(places)
  }
}

// What a value typed into a cell means, and the format it implies, as Sheets reads it:
// "12%" is 0.12 as a percent, "$5" is 5 in dollars, "1,234" a number, "9/29/2026" a date,
// "3:30 PM" a time. A cell formatted as plain text keeps what's typed as text.
export function interpret(input, numberFormat) {
  if (numberFormat === "plain") return { value: input }

  const text = input.trim()
  let match
  if ((match = text.match(/^([-+]?)\$\s*([\d,]*\.?\d+)$/)) && commas(match[2])) {
    return { value: Number(match[1] + match[2].replaceAll(",", "")), implied: { numberFormat: "currency" } }
  }
  if ((match = text.match(/^([-+]?[\d,]*\.?\d+)\s*%$/)) && commas(match[1])) {
    return { value: Number(match[1].replaceAll(",", "")) / 100, implied: { numberFormat: "percent", decimals: match[1].includes(".") ? 2 : 0 } }
  }
  if ((match = text.match(/^[-+]?\d{1,3}(,\d{3})+(\.\d+)?$/))) {
    return { value: Number(text.replaceAll(",", "")), implied: { numberFormat: "number", decimals: decimalsIn(text) } }
  }

  const date = dateIn(text)
  if (date !== undefined) return date

  return { value: literal(input) }
}

// A formula's result reads as a date when the formula is a date function, as in Sheets.
export function impliedByFormula(formula) {
  const [ , name ] = formula.match(/^=\s*([A-Z]+)\s*\(/i) ?? []
  switch (name?.toUpperCase()) {
    case "TODAY": case "DATE": return { numberFormat: "date" }
    case "NOW": return { numberFormat: "datetime" }
    case "TIME": return { numberFormat: "time" }
  }
}

// The decimal places a value shows with, so "increase decimals" can start from there.
export function decimalsShown(value, format = {}) {
  if (format.decimals !== undefined) return format.decimals
  if (FIXED[format.numberFormat] !== undefined) return FIXED[format.numberFormat]
  if (typeof value !== "number") return 0
  return (display(value).split(".")[1] ?? "").replace(/e.*/i, "").length
}

// Errors and numbers aside, what kind of value a cell holds, for its default alignment.
export function kind(value) {
  if (value instanceof SheetError) return "error"
  if (typeof value === "number") return "number"
  if (typeof value === "boolean") return "boolean"
  return "text"
}

function grouped(value, places = 0) {
  return value.toLocaleString("en-US", { minimumFractionDigits: places, maximumFractionDigits: places })
}

function scientific(value, places = 2) {
  const [ mantissa, exponent ] = value.toExponential(places).split("e")
  const power = Number(exponent)
  return `${mantissa}E${power < 0 ? "-" : "+"}${String(Math.abs(power)).padStart(2, "0")}`
}

function dateOf(value) {
  const date = new Date(EPOCH + Math.floor(value) * DAY)
  return `${date.getUTCMonth() + 1}/${date.getUTCDate()}/${date.getUTCFullYear()}`
}

function timeOf(value, { clock = 12 } = {}) {
  const seconds = Math.round((value - Math.floor(value)) * 86400) % 86400
  const [ hours, minutes, rest ] = [ Math.floor(seconds / 3600), Math.floor(seconds / 60) % 60, seconds % 60 ]
  const pad = number => String(number).padStart(2, "0")
  if (clock === 24) return `${hours}:${pad(minutes)}:${pad(rest)}`
  return `${(hours + 11) % 12 + 1}:${pad(minutes)}:${pad(rest)} ${hours < 12 ? "AM" : "PM"}`
}

// Dates (9/29/2026, 2026-09-29), times (15:30, 3:30 PM) or both, typed in.
function dateIn(text) {
  const day = text.match(/^(\d{1,2})\/(\d{1,2})\/(\d{2}|\d{4})(?=\s|$)|^(\d{4})-(\d{1,2})-(\d{1,2})(?=\s|$)/)
  const rest = day ? text.slice(day[0].length).trim() : text
  const clock = rest.match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(am|pm)?$/i)
  if (!day && !clock) return
  if (rest && !clock) return

  let serial = 0
  if (day) {
    const [ month, date, year ] = day[4] ? [ day[5], day[6], day[4] ] : [ day[1], day[2], day[3] ]
    const fullYear = year.length === 2 ? 2000 + Number(year) : Number(year)
    if (month < 1 || month > 12 || date < 1 || date > 31) return
    serial = (Date.UTC(fullYear, month - 1, date) - EPOCH) / DAY
  }
  if (clock) {
    let hours = Number(clock[1])
    if (clock[4]) hours = hours % 12 + (clock[4].toLowerCase() === "pm" ? 12 : 0)
    if (hours > 23 || Number(clock[2]) > 59) return
    serial += (hours * 3600 + Number(clock[2]) * 60 + Number(clock[3] ?? 0)) / 86400
  }

  const numberFormat = day && clock ? "datetime" : day ? "date" : "time"
  return { value: serial, implied: { numberFormat } }
}

function commas(digits) {
  return !digits.includes(",") || /^\d{1,3}(,\d{3})*(\.\d+)?$/.test(digits)
}

function decimalsIn(digits) {
  return digits.split(".")[1]?.length ?? 0
}
