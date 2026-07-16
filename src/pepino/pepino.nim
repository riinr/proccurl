## Pepino — a small Gherkin (Cucumber) parser.
##
## Parses `.feature` files into a structured representation:
## Feature -> [Background], [Scenario | ScenarioOutline], each
## holding Steps and (for outlines) Examples tables.
##
## Supported Gherkin constructs:
##   - Feature / Rule
##   - Background
##   - Scenario
##   - Scenario Outline + Examples
##   - Steps: Given / When / Then / And / But / *
##   - Tags: @tag (single-line and stacked)
##   - Comments: lines starting with `#`
##   - Doc strings: """ ... """
##   - Data tables (pipe-delimited)

import std/[strutils, sequtils, tables, options]

export strutils, sequtils, tables, options


# ---------------------------------------------------------------------------
# Model
# ---------------------------------------------------------------------------

type
  StepKeyword* = enum
    skGiven, skWhen, skThen, skAnd, skBut, skStar

  KeywordMatch* = tuple[k: StepKeyword, rest: string]

  Step* = object
    keyword*: StepKeyword
    text*: string
    docString*: Option[string]
    table*: seq[seq[string]]

  Examples* = object
    tags*: seq[string]
    name*: string
    description*: string
    header*: seq[string]
    rows*: seq[seq[string]]

  Scenario* = object
    tags*: seq[string]
    name*: string
    description*: string
    steps*: seq[Step]
    isOutline*: bool
    examples*: seq[Examples]

  Rule* = object
    tags*: seq[string]
    name*: string
    description*: string
    scenarios*: seq[Scenario]

  Feature* = object
    tags*: seq[string]
    name*: string
    description*: string
    language*: string
    background*: Option[Scenario]
    rules*: seq[Rule]
    scenarios*: seq[Scenario]

  GherkinError* = ref object of CatchableError
    line*: int


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

const KeywordNames*: array[StepKeyword, string] = [
  "Given", "When", "Then", "And", "But", "*"
]

proc toKeyword*(s: string): Option[StepKeyword] =
  let t = s.strip.toLowerAscii
  for k in StepKeyword:
    if t == KeywordNames[k].toLowerAscii:
      return some(k)
  if t == "*":
    return some(skStar)
  return none(StepKeyword)

proc keywordFromText*(line: string): Option[KeywordMatch] =
  # Split "Given the user logs in" into keyword + remainder.
  # Leading indentation is ignored.
  let stripped = line.strip
  let idx = stripped.find(' ')
  if idx < 0:
    return none(KeywordMatch)
  let kw = stripped[0 ..< idx]
  let rest = stripped[idx + 1 .. ^1].strip
  let k = kw.toKeyword
  if k.isSome:
    return some((k.get, rest))
  return none(KeywordMatch)

proc gherkinError*(msg: string; line: int): GherkinError =
  result = GherkinError(msg: msg, line: line)

proc isTagLine*(line: string): bool =
  line.strip.startsWith("@")

proc splitTags*(line: string): seq[string] =
  # "@a @b @c" -> @["a", "b", "c"]
  for tok in line.strip.splitWhitespace:
    if tok.startsWith("@"):
      result.add(tok[1 .. ^1])

proc parseTableRow*(line: string): seq[string] =
  # "| a | b | c |" -> @["a", "b", "c"] (trimmed)
  var s = line.strip
  if s.startsWith("|"):
    s = s[1 .. ^1]
  if s.endsWith("|"):
    s = s[0 .. ^2]
  for cell in s.split("|"):
    result.add(cell.strip)

proc isTableRow*(line: string): bool =
  let s = line.strip
  s.startsWith("|") and s.count('|') >= 2

proc isDocStringStart*(line: string): bool =
  let s = line.strip
  s.startsWith("\"\"\"") or s.startsWith("```")

proc docStringDelim*(line: string): char =
  let s = line.strip
  if s.startsWith("\"\"\""):
    '"'
  elif s.startsWith("```"):
    '`'
  else:
    '\0'


# ---------------------------------------------------------------------------
# Parser
# ---------------------------------------------------------------------------

type Parser = object
  lines: seq[string]
  i: int
  tags: seq[string]          # pending tags for the next block
  featureTags: seq[string]   # tags seen before the Feature line

proc cur(p: Parser): string =
  if p.i < p.lines.len: p.lines[p.i] else: ""

proc atEnd(p: Parser): bool = p.i >= p.lines.len

proc next(p: var Parser) =
  p.i.inc

proc isBlank(p: Parser): bool = p.cur.strip.len == 0

proc isComment(p: Parser): bool = p.cur.strip.startsWith("#")

proc headingLevel(line: string): tuple[level: int, keyword: string, rest: string] =
  # "Feature: name" -> (1, "Feature", "name")
  # "  Scenario: name" -> (2, "Scenario", "name")
  let s = line.strip
  for kw in ["Feature", "Rule", "Background", "Scenario Outline",
             "Scenario", "Examples"]:
    if s.startsWith(kw & ":") or s.startsWith(kw & " "):
      let rest = s[kw.len .. ^1]
      # strip leading ':' or space
      var r = rest
      if r.startsWith(":"): r = r[1 .. ^1]
      return (1, kw, r.strip)
  # rule / scenario are level 2, feature level 1
  return (0, "", "")

proc startBlock(p: var Parser): bool =
  # Skip blanks and comments; capture any tag lines into p.tags.
  while not p.atEnd:
    if p.isBlank or p.isComment:
      p.next
    elif isTagLine(p.cur):
      p.tags.add(p.cur.splitTags)
      p.next
    else:
      return true
  return false

proc takeTags(p: var Parser): seq[string] =
  result = p.tags
  p.tags = @[]

proc parseStep(p: var Parser): Step =
  let (k, rest) = p.cur.keywordFromText.get
  result = Step(keyword: k, text: rest)
  p.next
  # doc string
  if isDocStringStart(p.cur):
    let delim = docStringDelim(p.cur)
    p.next
    var buf: seq[string]
    while not p.atEnd and docStringDelim(p.cur) != delim:
      buf.add(p.cur)
      p.next
    if not p.atEnd:
      p.next  # consume closing delimiter
    result.docString = some(buf.join("\n"))
  # table
  var tbl: seq[seq[string]]
  while not p.atEnd and isTableRow(p.cur):
    tbl.add(p.cur.parseTableRow)
    p.next
  if tbl.len > 0:
    result.table = tbl

proc parseSteps(p: var Parser): seq[Step] =
  while not p.atEnd:
    let s = p.cur.strip
    if s.len == 0 or p.isComment or isTagLine(p.cur):
      # a blank/comment may separate but we stop on new blocks below
      if isTagLine(p.cur): break
      p.next
      continue
    if p.cur.keywordFromText.isSome:
      result.add(p.parseStep)
    else:
      break

proc parseScenario(p: var Parser; isOutline: bool): Scenario =
  result.isOutline = isOutline
  result.tags = p.takeTags
  # name + description: "Scenario: name" then prose until first step
  let s = p.cur.strip
  let idx = s.find(':')
  if idx >= 0:
    result.name = "" & s[idx + 1 .. ^1].strip
  p.next
  # description lines until first step or blank-then-step
  var descLines: seq[string]
  while not p.atEnd:
    if p.isBlank or p.isComment:
      # peek: description continues if next non-blank is not a step
      var j = p.i
      while j < p.lines.len and (p.lines[j].strip.len == 0 or p.lines[j].strip.startsWith("#")):
        j.inc
      if j < p.lines.len and p.lines[j].keywordFromText.isSome:
        break
      descLines.add(p.cur)
      p.next
    elif p.cur.keywordFromText.isSome:
      break
    else:
      descLines.add(p.cur)
      p.next
  result.description = descLines.mapIt(it.strip).filterIt(it.len > 0).join("\n")
  result.steps = p.parseSteps
  # examples (for outlines)
  while true:
    if not p.startBlock: break
    let (_, kw, rest) = p.cur.headingLevel
    if kw == "Examples":
      var ex: Examples
      ex.tags = p.takeTags
      ex.name = rest
      p.next
      # header is the next table row
      if not p.atEnd and isTableRow(p.cur):
        ex.header = p.cur.parseTableRow
        p.next
      while not p.atEnd and isTableRow(p.cur):
        ex.rows.add(p.cur.parseTableRow)
        p.next
      result.examples.add(ex)
    else:
      break

proc parseFeature*(text: string): Feature =
  ## Parse a Gherkin feature document into a `Feature`.
  var p: Parser
  p.lines = text.splitLines
  # Normalize trailing newline artifacts
  while p.lines.len > 0 and p.lines[^1].len == 0:
    p.lines.delete(p.lines.len - 1)

  # capture tags before Feature
  while p.startBlock:
    let (_, kw, rest) = p.cur.headingLevel
    if kw == "Feature":
      result.tags = p.takeTags
      result.name = rest
      result.language = "en"
      p.next
      break
    else:
      # unexpected
      raise gherkinError("Expected 'Feature:' but found: " & p.cur.strip, p.i + 1)

  # description until first block
  var desc: seq[string]
  while not p.atEnd:
    if p.isBlank or p.isComment:
      p.next
      continue
    if isTagLine(p.cur):
      # tags belong to the upcoming block; let the main loop handle them
      break
    let (_, kw, _) = p.cur.headingLevel
    if kw == "" or kw == "Feature":
      if kw == "Feature":
        # already consumed; safety
        p.next
        continue
      # prose description line
      desc.add(p.cur.strip)
      p.next
    else:
      break
  result.description = desc.join("\n")

  # main body
  while p.startBlock:
    let (_, kw, rest) = p.cur.headingLevel
    case kw
    of "Background":
      var sc = p.parseScenario(false)
      sc.name = rest
      result.background = some(sc)
    of "Scenario":
      result.scenarios.add(p.parseScenario(false))
    of "Scenario Outline":
      result.scenarios.add(p.parseScenario(true))
    of "Rule":
      var rule: Rule
      rule.tags = p.takeTags
      rule.name = rest
      p.next
      # rule description + nested scenarios
      while p.startBlock:
        let (_, kw2, rest2) = p.cur.headingLevel
        case kw2
        of "Scenario":
          rule.scenarios.add(p.parseScenario(false))
        of "Scenario Outline":
          rule.scenarios.add(p.parseScenario(true))
        of "Background":
          # background inside rule is uncommon; treat as scenario steps holder
          var sc = p.parseScenario(false)
          sc.name = rest2
          rule.scenarios.add(sc)
        else:
          # description-ish; bail out of rule
          break
      result.rules.add(rule)
    of "Examples":
      # stray examples outside outline — ignore name, skip
      discard p.takeTags
      p.next
      while not p.atEnd and isTableRow(p.cur):
        p.next
    else:
      # unknown heading; skip line
      p.next

  if result.name.len == 0:
    raise gherkinError("No Feature found in document", 0)
