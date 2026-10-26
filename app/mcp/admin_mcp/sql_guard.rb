# The text checks of the `query_sql` tool (AdminMcp::Tools::Analytics::QuerySql), ported from ShaderGator's MCP guard.
# The query runs with Save Point's own database login, which can read every table, so these checks and the read-only
# transaction around the query are what keep it to the `insights` views (D-041, D-046).
#
# | Layer | What it stops |
# |---|---|
# | The text starts with SELECT, WITH, VALUES or TABLE | SET, SHOW, COPY, DO, CALL, EXPLAIN, DDL and writes |
# | No `;` outside a string or comment | A second statement |
# | A schema name before a dot, other than `insights` | `public.users`, `information_schema.columns`, `pg_catalog.pg_roles` |
# | Any name that starts with `pg_`, except `pg_typeof` | The system catalogs and views, and every file, lock, signal and settings function |
# | A list of other functions | `current_setting`, `set_config`, `dblink`, `lo_*`, `query_to_xml` and the like, which read or run SQL from a string |
# | A lexer for these checks (`tokens`) | Comments (a `--` comment ends at `\n` or `\r`) and string literals that hide text, and `U&` escapes |
#
# The tool wraps the query in `select * from (...) limit N`, which stops `WITH ... DELETE`, `SELECT INTO` and more than N
# rows, and runs it in a transaction that is read only, with `search_path = insights`, so a bare name is an insights view.
# These checks read SQL text, so they are a denylist. A database role with a grant on `insights` alone would be stronger.
module AdminMcp::SqlGuard
  MAX_SQL_CHARS = 20_000
  SCHEMA = "insights"
  STARTS = %w[select with values table].freeze
  # Names that start with pg_ and are harmless.
  PG_ALLOWED = %w[pg_typeof].freeze
  # Functions beyond pg_*: they act outside the read, run SQL from a string, or answer from the server's settings.
  DENIED_FUNCTIONS = %w[
    current_setting set_config nextval currval setval lastval txid_current ts_stat ts_rewrite crosstab connectby
    query_to_xml table_to_xml cursor_to_xml schema_to_xml database_to_xml
    query_to_xml_and_xmlschema table_to_xml_and_xmlschema schema_to_xml_and_xmlschema database_to_xml_and_xmlschema
    query_to_json xmlschema_to_xml
  ].freeze
  DENIED_PREFIXES = %w[dblink lo_ txid_].freeze

  class Refused < AdminMcp::Refused; end

  Token = Data.define(:kind, :value)

  module_function

  # The text trimmed of trailing semicolons, or a Refused for what the checks before the database can see. `schemas` are
  # the names of the database's schemas.
  def check(raw, schemas:)
    raise Refused, "Send one SELECT statement." unless raw.is_a?(String) && raw.strip.present?
    raise Refused, "Keep the query under #{MAX_SQL_CHARS} characters." if raw.length > MAX_SQL_CHARS

    text = raw.strip.sub(/;\s*\z/, "").strip
    tokens = tokens(text)
    first = tokens.find { !mark?(it, "(") }
    unless first&.kind == :word && STARTS.include?(first.value)
      raise Refused, "Only one SELECT, WITH, VALUES or TABLE statement runs here. Make changes with the write tools."
    end

    outside = schemas - [ SCHEMA ]
    tokens.each_with_index do |token, at|
      raise Refused, "Only one statement runs here: take out the semicolon." if mark?(token, ";")
      next unless name?(token)

      check_name(token, tokens[at + 1], outside)
    end
    text
  end

  def check_name(token, following, outside)
    value = token.value
    folded = value.downcase
    raise Refused, "#{value} is not allowed here. Query the views in the #{SCHEMA} schema (describe_schema lists them)." if folded.start_with?("pg_") && PG_ALLOWED.exclude?(folded)
    raise Refused, "information_schema is not allowed here. Use describe_schema." if folded == "information_schema"
    raise Refused, "#{value}() is not allowed here." if mark?(following, "(") && denied_function?(folded)
    # A schema before a dot: only `insights` is readable. (A table alias with a schema's name is refused too.)
    raise Refused, "Only the #{SCHEMA} schema is readable here, not #{value}." if mark?(following, ".") && outside.include?(token.kind == :word ? folded : value)
  end

  def denied_function?(name) = DENIED_FUNCTIONS.include?(name) || DENIED_PREFIXES.any? { name.start_with?(it) }

  def name?(token) = token.kind == :word || token.kind == :name

  def mark?(token, mark) = token&.kind == :mark && token.value == mark

  WORD_START = /[A-Za-z_\u0080-\u{10FFFF}]/
  WORD_REST = /[\w$\u0080-\u{10FFFF}]/
  # PostgreSQL ends a `--` comment at a line feed or a carriage return, whichever comes first (scan.l: non_newline).
  LINE_END = /[\n\r]/
  DOLLAR_TAG = /\A\$(?:[A-Za-z_\u0080-\u{10FFFF}][\w\u0080-\u{10FFFF}]*)?\$/

  # Splits the text as PostgreSQL's lexer does, for the checks only. Comments (`--` ends at \n or \r, `/* */` nested, as PostgreSQL nests them) and string
  # literals of every kind are skipped, so neither can hide text from the checks. Refuses `U&'...'` and `U&"..."`, which
  # can spell any name in a form no check reads.
  def tokens(text)
    tokens = []
    n = text.length
    i = 0
    while i < n
      c = text[i]
      if c.match?(/\s/)
        i += 1
      elsif c == "-" && text[i + 1] == "-"
        i = text.index(LINE_END, i) ? text.index(LINE_END, i) + 1 : n
      elsif c == "/" && text[i + 1] == "*"
        i = skip_comment(text, i)
      elsif c.match?(/u/i) && text[i + 1] == "&" && [ "'", '"' ].include?(text[i + 2])
        raise Refused, "Unicode escapes (U&) are not allowed here. Write the text or the name plainly."
      elsif c.match?(/e/i) && text[i + 1] == "'"
        i = close_quote(text, "'", i + 2, backslash: true)
        tokens << Token.new(:literal, "")
      elsif c.match?(/[bxn]/i) && text[i + 1] == "'"
        i = close_quote(text, "'", i + 2)
        tokens << Token.new(:literal, "")
      elsif c == "'"
        i = close_quote(text, "'", i + 1)
        tokens << Token.new(:literal, "")
      elsif c == '"'
        stop = close_quote(text, '"', i + 1)
        tokens << Token.new(:name, text[(i + 1)...(stop - 1)].gsub('""', '"'))
        i = stop
      elsif c == "$" && (tag = text[i, 64][DOLLAR_TAG])
        stop = text.index(tag, i + tag.length) or raise Refused, "The query has an unclosed dollar-quoted string."
        i = stop + tag.length
        tokens << Token.new(:literal, "")
      elsif c.match?(WORD_START)
        stop = i + 1
        stop += 1 while stop < n && text[stop].match?(WORD_REST)
        tokens << Token.new(:word, text[i...stop].downcase)
        i = stop
      elsif c.match?(/[0-9]/)
        stop = i + 1
        stop += 1 while stop < n && text[stop].match?(/[\w.]/)
        tokens << Token.new(:literal, "")
        i = stop
      else
        tokens << Token.new(:mark, c)
        i += 1
      end
    end
    tokens
  end

  # The index after the nested comment that starts at `from`.
  def skip_comment(text, from)
    depth = 1
    i = from + 2
    while i < text.length && depth.positive?
      if text[i, 2] == "/*"
        depth += 1
        i += 2
      elsif text[i, 2] == "*/"
        depth -= 1
        i += 2
      else
        i += 1
      end
    end
    raise Refused, "The query has an unclosed comment." if depth.positive?

    i
  end

  # The index after the quote that closes the string or name starting at `from`.
  def close_quote(text, quote, from, backslash: false)
    i = from
    while i < text.length
      if backslash && text[i] == "\\"
        i += 2
      elsif text[i] == quote && text[i + 1] == quote
        i += 2
      elsif text[i] == quote
        return i + 1
      else
        i += 1
      end
    end
    raise Refused, "The query has an unclosed #{quote == '"' ? "quoted name" : "string"}."
  end
end
