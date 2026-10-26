// A small spreadsheet formula language: numbers, strings, TRUE/FALSE, cell references
// (A1, $B$2) and ranges (A1:C3), the operators + - * / ^ & % = <> < > <= >=, and the
// functions below. evaluate() takes the text after the "=" and a lookup(column, row)
// that returns a referenced cell's value. Errors are values too, like "#DIV/0!".

export const COLUMNS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

export class SheetError {
  constructor(code) {
    this.code = code
  }

  toString() {
    return this.code
  }
}

export function evaluate(source, lookup) {
  try {
    const parser = new Parser(tokenize(source))
    const tree = parser.expression()
    if (parser.peek()) throw new SheetError("#ERROR!")

    const value = run(tree, lookup)
    return Array.isArray(value) ? value[0][0] : value // a bare range shows its first cell
  } catch (error) {
    if (error instanceof SheetError) return error
    throw error
  }
}

// What a typed value means: a number, TRUE/FALSE, or text.
export function literal(input) {
  const text = input.trim()
  if (text !== "" && !isNaN(text)) return Number(text)
  if (/^(true|false)$/i.test(text)) return text.toUpperCase() === "TRUE"
  return input
}

// How a value reads in its cell.
export function display(value) {
  if (value instanceof SheetError) return value.code
  if (typeof value === "boolean") return value ? "TRUE" : "FALSE"
  if (typeof value === "number") return String(parseFloat(value.toPrecision(10)))
  return value ?? ""
}

// Tokens

const TOKEN = /\s*(?:(\d+\.?\d*(?:e[+-]?\d+)?|\.\d+(?:e[+-]?\d+)?)|"((?:[^"]|"")*)"|(\$?[a-z_][\w.$]*)|(<=|>=|<>|[-+*/^&=<>(),:%]))/iy
const REFERENCE = /^\$?([a-z]+)\$?(\d+)$/i

function tokenize(source) {
  const tokens = []
  TOKEN.lastIndex = 0

  while (TOKEN.lastIndex < source.length) {
    if (/^\s*$/.test(source.slice(TOKEN.lastIndex))) break

    const match = TOKEN.exec(source)
    if (!match) throw new SheetError("#ERROR!")

    const [ , number, string, word, operator ] = match
    if (number !== undefined) tokens.push({ type: "number", value: Number(number) })
    else if (string !== undefined) tokens.push({ type: "string", value: string.replaceAll('""', '"') })
    else if (word !== undefined) tokens.push({ type: "word", value: word.toUpperCase() })
    else tokens.push({ type: operator })
  }
  return tokens
}

// Parsing, loosest-binding first. As in Sheets, -2^2 is 4.

const COMPARISONS = [ "=", "<>", "<", ">", "<=", ">=" ]

class Parser {
  constructor(tokens) {
    this.tokens = tokens
    this.position = 0
  }

  peek() {
    return this.tokens[this.position]
  }

  next() {
    return this.tokens[this.position++]
  }

  accept(...types) {
    if (types.includes(this.peek()?.type)) return this.next()
  }

  expect(type) {
    if (!this.accept(type)) throw new SheetError("#ERROR!")
  }

  expression() {
    return this.#binary(COMPARISONS, () => this.#concatenation())
  }

  #concatenation() {
    return this.#binary([ "&" ], () => this.#sum())
  }

  #sum() {
    return this.#binary([ "+", "-" ], () => this.#product())
  }

  #product() {
    return this.#binary([ "*", "/" ], () => this.#power())
  }

  #power() {
    return this.#binary([ "^" ], () => this.#unary())
  }

  #binary(operators, operand) {
    let left = operand()
    let token
    while ((token = this.accept(...operators))) {
      left = { type: "binary", operator: token.type, left, right: operand() }
    }
    return left
  }

  #unary() {
    const sign = this.accept("-", "+")
    if (sign) return { type: "unary", operator: sign.type, operand: this.#unary() }

    let node = this.#primary()
    while (this.accept("%")) node = { type: "percent", operand: node }
    return node
  }

  #primary() {
    const token = this.next()

    switch (token?.type) {
      case "number":
      case "string":
        return { type: "literal", value: token.value }
      case "(": {
        const node = this.expression()
        this.expect(")")
        return node
      }
      case "word":
        return this.#word(token.value)
      default:
        throw new SheetError("#ERROR!")
    }
  }

  #word(word) {
    if (this.accept("(")) {
      const args = []
      if (!this.accept(")")) {
        do args.push(this.expression())
        while (this.accept(","))
        this.expect(")")
      }
      return { type: "call", name: word, args }
    }

    if (word === "TRUE" || word === "FALSE") return { type: "literal", value: word === "TRUE" }

    const start = reference(word)
    if (!start) return { type: "literal", value: new SheetError("#NAME?") }
    if (!this.accept(":")) return { type: "reference", ...start }

    const end = this.accept("word")
    const finish = end && reference(end.value)
    if (!finish) throw new SheetError("#ERROR!")
    return { type: "range", start, end: finish }
  }
}

function reference(word) {
  const match = word.match(REFERENCE)
  if (!match) return

  const column = COLUMNS.indexOf(match[1])
  if (match[1].length > 1 || column < 0) return { column: Infinity, row: 0 } // past Z: #REF!
  return { column, row: Number(match[2]) - 1 }
}

// Evaluation

function run(node, lookup) {
  switch (node.type) {
    case "literal":
      if (node.value instanceof SheetError) throw node.value
      return node.value
    case "reference":
      return cell(node, lookup)
    case "range":
      return range(node, lookup)
    case "unary": {
      const value = number(run(node.operand, lookup))
      return node.operator === "-" ? -value : value
    }
    case "percent":
      return number(run(node.operand, lookup)) / 100
    case "binary":
      return binary(node.operator, run(node.left, lookup), run(node.right, lookup))
    case "call":
      return call(node, lookup)
  }
}

function cell({ column, row }, lookup) {
  if (!Number.isFinite(column) || row < 0) throw new SheetError("#REF!")

  const value = lookup(column, row)
  if (value instanceof SheetError) throw value
  return value
}

function range({ start, end }, lookup) {
  const rows = []
  for (let row = Math.min(start.row, end.row); row <= Math.max(start.row, end.row); row++) {
    const values = []
    for (let column = Math.min(start.column, end.column); column <= Math.max(start.column, end.column); column++) {
      values.push(cell({ column, row }, lookup))
    }
    rows.push(values)
  }
  return rows
}

function binary(operator, left, right) {
  if (operator === "&") return text(left) + text(right)
  if (COMPARISONS.includes(operator)) return compare(operator, scalar(left), scalar(right))

  const [ a, b ] = [ number(left), number(right) ]
  switch (operator) {
    case "+": return a + b
    case "-": return a - b
    case "*": return a * b
    case "/":
      if (b === 0) throw new SheetError("#DIV/0!")
      return a / b
    case "^": return finite(a ** b)
  }
}

// Text compares without case, and numbers sort before text, as in Sheets.
function compare(operator, a, b) {
  const rank = value => typeof value === "string" && value !== "" ? 1 : 0
  const key = value => typeof value === "string" ? (value === "" ? 0 : value.toLowerCase()) : Number(value)

  const order = rank(a) - rank(b) || (key(a) < key(b) ? -1 : key(a) > key(b) ? 1 : 0)
  switch (operator) {
    case "=": return order === 0
    case "<>": return order !== 0
    case "<": return order < 0
    case ">": return order > 0
    case "<=": return order <= 0
    case ">=": return order >= 0
  }
}

// Coercion

function scalar(value) {
  if (!Array.isArray(value)) return value
  if (value.length === 1 && value[0].length === 1) return value[0][0]
  throw new SheetError("#VALUE!")
}

function number(value) {
  value = scalar(value)
  if (typeof value === "number") return value
  if (typeof value === "boolean") return Number(value)
  if (value === "" || value == null) return 0

  const trimmed = value.trim()
  if (trimmed !== "" && !isNaN(trimmed)) return Number(trimmed)
  throw new SheetError("#VALUE!")
}

function text(value) {
  return display(scalar(value))
}

function truthy(value) {
  value = scalar(value)
  if (typeof value === "string" && value !== "") throw new SheetError("#VALUE!")
  return Boolean(number(value))
}

function finite(value) {
  if (!Number.isFinite(value)) throw new SheetError("#NUM!")
  return value
}

// Every value in the arguments, ranges flattened.
function values(args) {
  return args.flatMap(arg => Array.isArray(arg) ? arg.flat() : [ arg ])
}

// The numbers among the arguments: numbers typed as arguments count, text in ranges doesn't.
function numbers(args) {
  return args.flatMap(arg => Array.isArray(arg) ? arg.flat().filter(value => typeof value === "number") : [ number(arg) ])
}

// Functions

function call({ name, args }, lookup) {
  // IF and IFERROR only evaluate the branch they need.
  if (name === "IF") {
    arity(args, 2, 3)
    const branch = truthy(run(args[0], lookup)) ? args[1] : args[2]
    return branch ? run(branch, lookup) : false
  }
  if (name === "ISERROR" || name === "ISERR" || name === "ISNA") {
    arity(args, 1, 1)
    try {
      scalar(run(args[0], lookup))
      return false
    } catch (error) {
      if (!(error instanceof SheetError)) throw error
      return name === "ISNA" ? error.code === "#N/A" : name === "ISERROR" || error.code !== "#N/A"
    }
  }
  if (name === "IFS") {
    if (!args.length || args.length % 2) throw new SheetError("#N/A")
    for (let index = 0; index < args.length; index += 2) {
      if (truthy(run(args[index], lookup))) return run(args[index + 1], lookup)
    }
    throw new SheetError("#N/A")
  }
  if (name === "IFERROR") {
    arity(args, 1, 2)
    try {
      return scalar(run(args[0], lookup))
    } catch (error) {
      if (!(error instanceof SheetError)) throw error
      return args[1] ? run(args[1], lookup) : ""
    }
  }

  const fn = FUNCTIONS[name]
  if (!fn) throw new SheetError("#NAME?")

  arity(args, fn.min ?? fn.length, fn.max ?? fn.length)
  return fn(...args.map(arg => run(arg, lookup)))
}

function arity(args, min, max) {
  if (args.length < min || args.length > max) throw new SheetError("#N/A")
}

// Functions taking any number of arguments (at least one) get them as a list.
const variadic = fn => Object.assign((...args) => fn(args), { min: 1, max: Infinity })
const extremum = pick => variadic(args => {
  const list = numbers(args)
  return list.length ? pick(...list) : 0
})

const FUNCTIONS = {
  SUM: variadic(args => numbers(args).reduce((sum, value) => sum + value, 0)),
  AVERAGE: variadic(args => {
    const list = numbers(args)
    if (!list.length) throw new SheetError("#DIV/0!")
    return list.reduce((sum, value) => sum + value, 0) / list.length
  }),
  MIN: extremum(Math.min),
  MAX: extremum(Math.max),
  COUNT: variadic(args => values(args).filter(value => typeof value === "number").length),
  COUNTA: variadic(args => values(args).filter(value => value !== "").length),
  PRODUCT: variadic(args => numbers(args).reduce((product, value) => product * value, 1)),

  ROUND: Object.assign((value, places = 0) => {
    const factor = 10 ** number(places)
    return Math.round(number(value) * factor) / factor
  }, { max: 2 }),
  ABS: value => Math.abs(number(value)),
  SQRT: value => {
    if (number(value) < 0) throw new SheetError("#NUM!")
    return Math.sqrt(number(value))
  },
  MOD: (value, divisor) => {
    const [ a, b ] = [ number(value), number(divisor) ]
    if (b === 0) throw new SheetError("#DIV/0!")
    return a - b * Math.floor(a / b)
  },
  POWER: (base, exponent) => finite(number(base) ** number(exponent)),
  INT: value => Math.floor(number(value)),
  PI: () => Math.PI,
  RAND: () => Math.random(),
  RANDBETWEEN: (low, high) => {
    const [ a, b ] = [ Math.ceil(number(low)), Math.floor(number(high)) ]
    if (a > b) throw new SheetError("#NUM!")
    return a + Math.floor(Math.random() * (b - a + 1))
  },

  AND: variadic(args => values(args).every(truthy)),
  OR: variadic(args => values(args).some(truthy)),
  NOT: value => !truthy(value),

  CONCAT: variadic(args => values(args).map(text).join("")),
  CONCATENATE: variadic(args => values(args).map(text).join("")),
  LEN: value => text(value).length,
  UPPER: value => text(value).toUpperCase(),
  LOWER: value => text(value).toLowerCase(),
  TRIM: value => text(value).trim().replace(/\s+/g, " "),
  REPT: (value, times) => text(value).repeat(Math.max(0, Math.floor(number(times)))),
  LEFT: Object.assign((value, length = 1) => text(value).slice(0, count(length)), { min: 1, max: 2 }),
  RIGHT: Object.assign((value, length = 1) => {
    const size = count(length)
    return size ? text(value).slice(-size) : ""
  }, { min: 1, max: 2 }),
  MID: (value, start, length) => {
    const from = Math.floor(number(start))
    if (from < 1) throw new SheetError("#VALUE!")
    return text(value).substr(from - 1, count(length))
  },
  FIND: Object.assign((needle, haystack, start = 1) => position(text(haystack).indexOf(text(needle), number(start) - 1)), { min: 2, max: 3 }),
  SEARCH: Object.assign((needle, haystack, start = 1) => {
    return position(text(haystack).toLowerCase().indexOf(text(needle).toLowerCase(), number(start) - 1))
  }, { min: 2, max: 3 }),
  SUBSTITUTE: Object.assign((value, search, replacement, occurrence) => {
    const [ source, find, replace ] = [ text(value), text(search), text(replacement) ]
    if (find === "") return source
    if (occurrence === undefined) return source.replaceAll(find, replace)

    let index = -1
    for (let seen = 0; seen < number(occurrence); seen++) {
      index = source.indexOf(find, index + 1)
      if (index < 0) return source
    }
    return source.slice(0, index) + replace + source.slice(index + find.length)
  }, { min: 3, max: 4 }),
  PROPER: value => text(value).toLowerCase().replace(/(^|[^a-z])([a-z])/g, (_, before, letter) => before + letter.toUpperCase()),
  EXACT: (a, b) => text(a) === text(b),
  VALUE: value => number(value),
  TEXTJOIN: Object.assign((delimiter, skipEmpty, ...args) => {
    const list = values(args).map(text)
    return (truthy(skipEmpty) ? list.filter(item => item !== "") : list).join(text(delimiter))
  }, { min: 3, max: Infinity }),
  JOIN: Object.assign((delimiter, ...args) => values(args).map(text).join(text(delimiter)), { min: 2, max: Infinity }),
  HYPERLINK: Object.assign((url, label) => text(label ?? url), { min: 1, max: 2 }),

  ROUNDUP: Object.assign((value, places = 0) => rounded(Math.ceil, value, places), { max: 2 }),
  ROUNDDOWN: Object.assign((value, places = 0) => rounded(Math.trunc, value, places), { max: 2 }),
  CEILING: Object.assign((value, step = 1) => multiple(Math.ceil, value, step), { max: 2 }),
  FLOOR: Object.assign((value, step = 1) => multiple(Math.floor, value, step), { max: 2 }),
  TRUNC: Object.assign((value, places = 0) => rounded(Math.trunc, value, places), { max: 2 }),
  SIGN: value => Math.sign(number(value)),
  EXP: value => finite(Math.exp(number(value))),
  LN: value => logarithm(Math.log, value),
  LOG10: value => logarithm(Math.log10, value),
  LOG: Object.assign((value, base = 10) => logarithm(Math.log, value) / logarithm(Math.log, base), { max: 2 }),
  MEDIAN: variadic(args => {
    const list = numbers(args).sort((a, b) => a - b)
    if (!list.length) throw new SheetError("#NUM!")
    const middle = Math.floor(list.length / 2)
    return list.length % 2 ? list[middle] : (list[middle - 1] + list[middle]) / 2
  }),
  COUNTBLANK: variadic(args => values(args).filter(value => value === "").length),

  SUMIF: Object.assign((cells, criterion, sums = cells) => {
    const test = matcher(criterion)
    const targets = values([ sums ])
    return values([ cells ]).reduce((sum, value, index) => {
      return test(value) && typeof targets[index] === "number" ? sum + targets[index] : sum
    }, 0)
  }, { min: 2, max: 3 }),
  COUNTIF: (cells, criterion) => values([ cells ]).filter(matcher(criterion)).length,
  AVERAGEIF: Object.assign((cells, criterion, averages = cells) => {
    const test = matcher(criterion)
    const targets = values([ averages ])
    const list = values([ cells ]).flatMap((value, index) => test(value) && typeof targets[index] === "number" ? [ targets[index] ] : [])
    if (!list.length) throw new SheetError("#DIV/0!")
    return list.reduce((sum, value) => sum + value, 0) / list.length
  }, { min: 2, max: 3 }),

  VLOOKUP: Object.assign((search, table, column, sorted = true) => {
    const rows = grid(table)
    const index = lookup(scalar(search), rows.map(row => row[0]), truthy(sorted))
    return pick(rows[index], number(column) - 1)
  }, { min: 3, max: 4 }),
  HLOOKUP: Object.assign((search, table, row, sorted = true) => {
    const rows = grid(table)
    const index = lookup(scalar(search), rows[0], truthy(sorted))
    return pick(rows.map(cells => cells[index]), number(row) - 1)
  }, { min: 3, max: 4 }),
  INDEX: Object.assign((table, row = 0, column = 0) => {
    const rows = grid(table)
    let [ r, c ] = [ Math.floor(number(row)), Math.floor(number(column)) ]
    if (rows.length === 1 && c === 0) [ r, c ] = [ 1, r ] // INDEX(A1:E1, 3) reads along the row
    if (r < 0 || c < 0 || r > rows.length || c > rows[0].length) throw new SheetError("#REF!")
    return rows[Math.max(r, 1) - 1][Math.max(c, 1) - 1]
  }, { min: 1, max: 3 }),
  MATCH: Object.assign((search, cells, type = 1) => {
    const list = values([ cells ])
    const kind = number(type)
    if (kind === 0) return lookup(scalar(search), list, false) + 1
    if (kind > 0) return lookup(scalar(search), list, true) + 1

    const index = list.findLastIndex(value => compare(">=", value, scalar(search)))
    if (index < 0) throw new SheetError("#N/A")
    return index + 1
  }, { min: 2, max: 3 }),

  ISBLANK: value => scalar(value) === "",
  ISNUMBER: value => typeof scalar(value) === "number",
  ISTEXT: value => typeof scalar(value) === "string" && scalar(value) !== "",
  ISLOGICAL: value => typeof scalar(value) === "boolean",
  NA: () => { throw new SheetError("#N/A") },
  TRUE: () => true,
  FALSE: () => false,

  // Dates are serial numbers, days since 30 December 1899, as in Sheets.
  TODAY: () => serial(new Date(), false),
  NOW: () => serial(new Date(), true),
  DATE: (year, month, day) => (Date.UTC(number(year), number(month) - 1, number(day)) - EPOCH) / DAY,
  TIME: (hours, minutes, seconds) => (number(hours) * 3600 + number(minutes) * 60 + number(seconds)) / 86400 % 1,
  YEAR: value => date(value).getUTCFullYear(),
  MONTH: value => date(value).getUTCMonth() + 1,
  DAY: value => date(value).getUTCDate(),
  WEEKDAY: Object.assign(value => date(value).getUTCDay() + 1, { max: 1 }),
  HOUR: value => Math.floor(fraction(value) * 24),
  MINUTE: value => Math.floor(fraction(value) * 1440) % 60,
  SECOND: value => Math.round(fraction(value) * 86400) % 60
}

const DAY = 86400000
const EPOCH = Date.UTC(1899, 11, 30)

// A local time as a serial number, with or without the time of day.
function serial(now, withTime) {
  const days = (Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()) - EPOCH) / DAY
  if (!withTime) return days
  return days + (now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds()) / 86400
}

function date(value) {
  return new Date(EPOCH + Math.floor(number(value)) * DAY)
}

function fraction(value) {
  const time = number(value)
  return time - Math.floor(time) + 1e-9
}

function count(value) {
  const length = Math.floor(number(value))
  if (length < 0) throw new SheetError("#VALUE!")
  return length
}

function position(index) {
  if (index < 0) throw new SheetError("#VALUE!")
  return index + 1
}

function rounded(round, value, places) {
  const factor = 10 ** number(places)
  return round(parseFloat((number(value) * factor).toPrecision(12))) / factor
}

function multiple(round, value, step) {
  const size = number(step)
  if (size === 0) return 0
  return round(parseFloat((number(value) / size).toPrecision(12))) * size
}

function logarithm(log, value) {
  if (number(value) <= 0) throw new SheetError("#NUM!")
  return log(number(value))
}

// A range as rows, or a single value as a one-cell table.
function grid(value) {
  return Array.isArray(value) ? value : [ [ value ] ]
}

function pick(list, index) {
  if (!list || index < 0 || index >= list.length) throw new SheetError("#REF!")
  return list[index]
}

// Where a value is in a list: exactly (text without case, with * and ? wildcards), or in a
// sorted list, the last value not past it.
function lookup(search, list, sorted) {
  if (sorted) {
    let found = -1
    list.forEach((value, index) => {
      if (value !== "" && typeof value === typeof search && compare("<=", value, search)) found = index
    })
    if (found < 0) throw new SheetError("#N/A")
    return found
  }

  const test = typeof search === "string" ? wildcard(search) : value => value === search
  const index = list.findIndex(value => test(value))
  if (index < 0) throw new SheetError("#N/A")
  return index
}

function wildcard(pattern) {
  const source = pattern.replace(/[.+^${}()|[\]\\]/g, "\\$&").replaceAll("*", ".*").replaceAll("?", ".")
  const regexp = new RegExp(`^${source}$`, "i")
  return value => typeof value === "string" && regexp.test(value)
}

// SUMIF and COUNTIF criteria: 5, "5", ">5", "<>done", "a*".
function matcher(criterion) {
  criterion = scalar(criterion)
  if (typeof criterion !== "string") return value => value === criterion

  const [ , operator = "=", operand ] = criterion.match(/^(<=|>=|<>|<|>|=)?(.*)$/s)
  const target = literal(operand)
  if (typeof target === "string" && (operator === "=" || operator === "<>")) {
    const test = operand === "" ? value => value === "" : wildcard(operand)
    return operator === "=" ? test : value => !test(value)
  }
  return value => value !== "" && typeof value === typeof target && compare(operator, value, target)
}


// Moves a formula's relative references, as copying and pasting it does in Sheets:
// =A1 pasted one column over reads =B1, while $A$1 stays put. Text in quotes is left alone.
export function shift(source, columns, rows) {
  return source.replace(/"(?:[^"]|"")*"|(?<![\w.$])(\$?)([A-Z])(\$?)(\d+)(?![\w(])/gi, (match, fixColumn, letter, fixRow, digits) => {
    if (letter === undefined) return match

    const column = fixColumn ? COLUMNS.indexOf(letter.toUpperCase()) : COLUMNS.indexOf(letter.toUpperCase()) + columns
    const row = fixRow ? Number(digits) : Number(digits) + rows
    if (column < 0 || column >= COLUMNS.length || row < 1) return "#REF!"
    return `${fixColumn}${COLUMNS[column]}${fixRow}${row}`
  })
}
