## nif2lsif -- Convert Nim NIF (Nim Intermediate Format) AST files to LSIF.
##
## NIF is a text-based, language-agnostic AST format (see the nifspec repo,
## version 2027). LSIF is a static graph format for language-server-style code
## intelligence (symbols, definitions, references, hover). This module parses a
## `.nif` file into an AST and emits a valid LSIF JSON graph: one `document`
## vertex per input file, `range` vertices for every symbol-introducing node,
## a `resultSet` per range, a `moniker` carrying the NIF global symbol, and the
## `contains` / `next` / `moniker` edges that tie them together.
##
## Usage:
##   nif2lsif input.nif                    # pretty-prints the LSIF graph to stdout
##   nif2lsif input.nif -o graph.lsif      # writes the graph as newline-delimited JSON
##   nif2lsif input.nif --check            # parse + convert, exit 0 on success
##   nif2lsif -o all.lsif a.nif b.nif      # merge multiple NIF files into one LSIF graph
##
## The converter is intentionally conservative: nodes it does not recognise are
## skipped, but every `:SymbolDef` it sees becomes an LSIF range + moniker, so
## the output is useful for "go to definition" style tooling regardless of the
## exact NIF tag vocabulary.

import std/[strutils, tables, json, os]

# ===========================================================================
# NIF parser (v2027)
# ===========================================================================
#
# Grammar (subset needed to walk the tree robustly):
#   Atom   ::= '.' | Identifier | Symbol | SymbolDef | Number | Char | String
#   Node   ::= Atom | '(' TagHead Node* ')'
#   Suffix ::= LineInfo? Comment?   (attached with no whitespace)
#
# Line info: @<colDiff>[,<lineDiff>[,<filename>]]  or  ~<negColDiff>...
# Comment : #<escapedData>#

type
  NifNodeKind = enum
    nkEmpty          ## the '.' atom
    nkIdent          ## plain identifier atom
    nkSymbol         ## symbol atom (foo.2.m)
    nkSymbolDef      ## symbol definition atom (:foo.2.m)
    nkNumber         ## numeric literal
    nkString         ## string literal
    nkChar           ## char literal
    nkCompound       ## (tag child*)

  NifNode = ref object
    case kind: NifNodeKind
    of nkEmpty: discard
    of nkIdent, nkSymbol, nkSymbolDef, nkNumber, nkString, nkChar:
      text: string
    of nkCompound:
      tag: string
      children: seq[NifNode]
    line, col: int        ## absolute 1-based position (from suffix diffs)
    filename: string      ## source filename (from suffix, if any)
    comment: string       ## attached comment (from suffix, if any)

  NifError = object of CatchableError

proc nifError(msg: string): ref NifError =
  result = newException(NifError, msg)

# --- tokenizer -------------------------------------------------------------
#
# We drive a single recursive-descent parser over the raw bytes. Whitespace
# separates tokens; `( )` delimit compounds; `"` and `'` delimit literals;
# `.` is the empty atom; `:` starts a symbol def; `@` / `~` / `#` start
# suffixes; digits start numbers; anything else starts an identifier.

type Parser = object
  s: string
  i: int
  line: int
  col: int

proc base62Val(c: char): int
proc hexVal(c: char): int
proc unescape(s: string, i: var int): string
proc nifNodeText(n: NifNode): string

proc newParser(s: string): Parser =
  Parser(s: s, i: 0, line: 1, col: 1)

template at(p: Parser): char = p.s[p.i]
template eof(p: Parser): bool = p.i >= p.s.len

proc skipWs(p: var Parser) =
  while not p.eof:
    case p.s[p.i]
    of ' ', '\t', '\r':
      p.i.inc; p.col.inc
    of '\n':
      p.i.inc; p.line.inc; p.col = 1
    else:
      break

proc parseLineInfo(p: var Parser): (int, int, string) =
  ## Parse a suffix of the form @col[,line[,file]] or ~negcol[,line[,file]].
  ## Returns (col, line, filename); -1 means "unspecified".
  result = (-1, -1, "")
  if p.eof: return
  var neg = false
  if p.s[p.i] == '~':
    neg = true; p.i.inc
  elif p.s[p.i] == '@':
    p.i.inc
  else:
    return
  # first diff: base62 integer
  var first = 0
  var have = false
  while not p.eof and p.s[p.i] in Digits + {'A'..'Z', 'a'..'z'}:
    first = first * 62 + base62Val(p.s[p.i])
    p.i.inc; have = true
  if neg: first = -first
  if have: result[0] = first
  if p.eof or p.s[p.i] != ',': return
  p.i.inc # consume ','
  # second diff (line)
  var second = 0
  have = false
  if not p.eof and p.s[p.i] in {'~'} + Digits + {'A'..'Z', 'a'..'z'}:
    neg = p.s[p.i] == '~'
    if neg: p.i.inc
    while not p.eof and p.s[p.i] in Digits + {'A'..'Z', 'a'..'z'}:
      second = second * 62 + base62Val(p.s[p.i])
      p.i.inc; have = true
    if neg: second = -second
  if have: result[1] = second
  if p.eof or p.s[p.i] != ',': return
  p.i.inc # consume ','
  # filename: arbitrary escaped data up to EOF or a control char
  var fn = ""
  while not p.eof and p.s[p.i] notin {' ', '\t', '\n', '\r', '(', ')', '[', ']',
                                      '{', '}', '~', '#', '\'', '"', '\\', ':', '@'}:
    if p.s[p.i] == '\\':
      p.i.inc
      if not p.eof:
        fn.add(unescape(p.s, p.i))
    else:
      fn.add(p.s[p.i]); p.i.inc
  result[2] = fn

proc parseComment(p: var Parser): string =
  if p.eof or p.s[p.i] != '#': return ""
  p.i.inc # consume '#'
  result = ""
  while not p.eof and p.s[p.i] != '#':
    if p.s[p.i] == '\\':
      p.i.inc
      if not p.eof:
        result.add(unescape(p.s, p.i))
    else:
      result.add(p.s[p.i]); p.i.inc
  if not p.eof and p.s[p.i] == '#':
    p.i.inc # consume closing '#'

proc unescape(s: string, i: var int): string =
  ## Decode one escape sequence starting at s[i] (which is '\').
  i.inc # consume '\'
  if i >= s.len: return ""
  let c = s[i]
  i.inc
  case c
  of 'n': return "\n"
  of 't': return "\t"
  of 'r': return "\r"
  of '|': return "\\"
  of '^': return "\""
  of '0'..'9', 'A'..'F':
    # two uppercase hex digits
    var hi = hexVal(c)
    if i < s.len and s[i] in {'0'..'9', 'A'..'F'}:
      hi = hi * 16 + hexVal(s[i]); i.inc
    return $char(hi)
  else:
    return $c

proc base62Val(c: char): int =
  case c
  of '0'..'9': result = ord(c) - ord('0')
  of 'A'..'Z': result = ord(c) - ord('A') + 10
  of 'a'..'z': result = ord(c) - ord('a') + 36
  else: result = 0

proc hexVal(c: char): int =
  case c
  of '0'..'9': result = ord(c) - ord('0')
  of 'A'..'F': result = ord(c) - ord('A') + 10
  else: result = 0

proc readIdent(p: var Parser): string =
  result = ""
  while not p.eof:
    let c = p.s[p.i]
    if c in {'_', '0'..'9', 'A'..'Z', 'a'..'z'} or ord(c) >= 128:
      result.add(c); p.i.inc
    elif c == '\\':
      p.i.inc
      if not p.eof: result.add(unescape(p.s, p.i))
    elif c notin {' ', '\t', '\n', '\r', '(', ')', '.', ':', '"', '\'', '@', '~', '#'}:
      result.add(c); p.i.inc
    else:
      break

proc readNumber(p: var Parser): string =
  result = ""
  if not p.eof and p.s[p.i] == '-':
    result.add('-'); p.i.inc
  while not p.eof and p.s[p.i] in {'0'..'9', '.', 'E', 'u', '+'}:
    result.add(p.s[p.i]); p.i.inc

proc readString(p: var Parser): string =
  # assumes current char is '"'
  p.i.inc # consume opening quote
  result = ""
  while not p.eof and p.s[p.i] != '"':
    if p.s[p.i] == '\\':
      p.i.inc
      if not p.eof: result.add(unescape(p.s, p.i))
    else:
      result.add(p.s[p.i]); p.i.inc
  if not p.eof and p.s[p.i] == '"':
    p.i.inc # consume closing quote

proc readChar(p: var Parser): string =
  # assumes current char is '\''
  p.i.inc
  result = ""
  while not p.eof and p.s[p.i] != '\'':
    if p.s[p.i] == '\\':
      p.i.inc
      if not p.eof: result.add(unescape(p.s, p.i))
    else:
      result.add(p.s[p.i]); p.i.inc
  if not p.eof and p.s[p.i] == '\'':
    p.i.inc

proc applySuffix(p: var Parser, n: NifNode) =
  let (cd, ld, fn) = p.parseLineInfo()
  if cd >= 0: n.col = cd
  if ld >= 0: n.line = ld
  if fn.len > 0: n.filename = fn
  n.comment = p.parseComment()

proc parseAtom(p: var Parser): NifNode =
  if p.eof: raise nifError("unexpected EOF while parsing atom")
  let c = p.s[p.i]
  case c
  of '.':
    p.i.inc
    # disambiguate empty atom '.' from a dot-symbol start later; an isolated
    # '.' (followed by whitespace or ')') is the empty node.
    if p.eof or p.s[p.i] in {' ', '\t', '\n', '\r', ')'}:
      result = NifNode(kind: nkEmpty)
      return
    # otherwise it is the start of a symbol (e.g. ".foo" or ".2.m")
    result = NifNode(kind: nkSymbol, text: "." & p.readIdent())
    return
  of ':':
    p.i.inc
    result = NifNode(kind: nkSymbolDef, text: ":" & p.readIdent())
    return
  of '"':
    result = NifNode(kind: nkString, text: p.readString())
    return
  of '\'':
    result = NifNode(kind: nkChar, text: p.readChar())
    return
  of '0'..'9', '-':
    result = NifNode(kind: nkNumber, text: p.readNumber())
    return
  else:
    # identifier or symbol (symbol starts with an ident then a '.')
    let start = p.readIdent()
    if not p.eof and p.s[p.i] == '.' and p.i + 1 < p.s.len and p.s[p.i + 1] in {'0'..'9', '.', 'A'..'Z', 'a'..'z'}:
      # looks like a symbol: ident '.' disamb...
      p.i.inc # consume '.'
      let rest = p.readIdent()
      result = NifNode(kind: nkSymbol, text: start & "." & rest)
    else:
      result = NifNode(kind: nkIdent, text: start)
    return

proc parseNode(p: var Parser): NifNode =
  p.skipWs()
  if p.eof: raise nifError("unexpected EOF")
  if p.s[p.i] == '(':
    p.i.inc # consume '('
    p.skipWs()
    if p.eof: raise nifError("unexpected EOF after '('")
    # tag is an identifier (possibly with suffix)
    let tag = p.readIdent()
    if tag.len == 0: raise nifError("expected tag name after '('")
    let node = NifNode(kind: nkCompound, tag: tag, children: @[])
    p.applySuffix(node)
    while true:
      p.skipWs()
      if p.eof: raise nifError("unexpected EOF, missing ')'")
      if p.s[p.i] == ')':
        p.i.inc
        break
      let child = p.parseNode()
      node.children.add(child)
    return node
  else:
    result = p.parseAtom()
    p.applySuffix(result)

proc parseDirectives(p: var Parser): seq[(string, seq[string])] =
  ## Read leading (.directive ...) forms until the first non-directive node.
  result = @[]
  while true:
    p.skipWs()
    if p.eof: break
    if p.s[p.i] == '(':
      # peek: is the next token a '.' ?
      var j = p.i + 1
      while j < p.s.len and p.s[j] in {' ', '\t', '\n', '\r'}: j.inc
      if j < p.s.len and p.s[j] == '.':
        # directive
        p.i.inc # '('
        p.skipWs()
        p.i.inc # '.'
        let name = p.readIdent()
        var args: seq[string] = @[]
        while true:
          p.skipWs()
          if p.eof: break
          if p.s[p.i] == ')':
            p.i.inc; break
          let a = p.parseNode()
          args.add(nifNodeText(a))
        result.add((name, args))
      else:
        break
    else:
      break

proc nifNodeText(n: NifNode): string =
  case n.kind
  of nkEmpty: result = "."
  of nkIdent, nkSymbol, nkSymbolDef, nkNumber, nkString, nkChar:
    result = n.text
  of nkCompound: result = n.tag

proc parseNif(text: string): (seq[(string, seq[string])], seq[NifNode]) =
  ## Parse a whole NIF module. Returns the leading directives and the top-level
  ## nodes (the module body).
  var p = newParser(text)
  let dirs = p.parseDirectives()
  var nodes: seq[NifNode] = @[]
  while true:
    p.skipWs()
    if p.eof: break
    nodes.add(p.parseNode())
  result = (dirs, nodes)

# ===========================================================================
# LSIF emitter
# ===========================================================================
#
# LSIF is a graph of `vertex` and `edge` elements, each a JSON object with a
# numeric `id`, a `type` ("vertex"/"edge"), and a `label`. We emit
# newline-delimited JSON (one element per line), which is the on-the-wire LSIF
# form and is also easy to pretty-print for inspection.

type LsifWriter = object
  elements: seq[JsonNode]
  nextId: int
  projectId: int  ## ID of the project vertex (set by setupWriter)

proc newWriter(): LsifWriter =
  result = LsifWriter(elements: @[], nextId: 1)

proc alloc(w: var LsifWriter): int =
  result = w.nextId
  w.nextId.inc

proc addVertex(w: var LsifWriter, label: string, body: JsonNode): int =
  let id = w.alloc()
  var o = newJObject()
  o["id"] = newJInt(id)
  o["type"] = newJString("vertex")
  o["label"] = newJString(label)
  for k, v in body: o[k] = v
  w.elements.add(o)
  result = id

proc addEdge(w: var LsifWriter, label: string, body: JsonNode): int =
  let id = w.alloc()
  var o = newJObject()
  o["id"] = newJInt(id)
  o["type"] = newJString("edge")
  o["label"] = newJString(label)
  for k, v in body: o[k] = v
  w.elements.add(o)
  result = id

proc toNdjson*(w: LsifWriter): string =
  result = ""
  for e in w.elements:
    result.add($e & "\n")

proc toPretty(w: LsifWriter): string =
  result = ""
  for e in w.elements:
    result.add(pretty(e) & "\n")

# --- symbol extraction -----------------------------------------------------
#
# NIF nodes that introduce a symbol carry it as their *second* child, written
# as a `:SymbolDef` atom. The known shapes (from the spec) are:
#   (proc  :foo.1.m  pragmas?  params?  rettype?  body?)
#   (type  :foo.1.m  pragmas?  body?)
#   (var   :foo.1.m  typ?  value?)
#   (let   :foo.1.m  typ?  value?)
#   (const :foo.1.m  typ?  value?)
#   (fld   :foo.1.m  typ?  value?)
#   (param :foo.1.m  typ?  value?)
#   (imp   :foo.1.m)                  import of an external symbol
# The symbol def is the first child that is a nkSymbolDef (skipping the tag).
#
# We also read the node's own line/col (from the suffix) for the range, and map
# the NIF tag to an LSIF symbol kind.

type SymInfo = object
  symbol: string       ## the symbol text (e.g. ":foo.1.m" or "foo")
  ident: string        ## the bare identifier (e.g. "foo")
  kind: string         ## NIF tag (proc/type/var/...)
  line, col: int       ## 1-based location
  node: NifNode

const KindToLsif = {
  "proc": 12, "func": 12, "iterator": 12, "method": 12, "converter": 12,
  "macro": 12, "template": 12,
  "type": 5, "object": 5, "enum": 5, "distinct": 5, "alias": 5,
  "var": 13, "let": 13, "const": 13, "global": 13, "field": 13,
  "fld": 7, "param": 14, "imp": 13,
}.toTable

## NIF tags whose second child carries the symbol name when no explicit
## `:SymbolDef` atom is present. The `nim-parsed` dialect (nifspec v2027) writes
## declaration names as plain idents in this position, e.g.
##   (proc toolSchema . . . (params ...))
##   (var gWebDriver . . WebDriver)
##   (type Tool . . . (object ...))
##   (fld name . . string)
proc isDeclTag(tag: string): bool =
  case tag
  of "proc", "func", "iterator", "method", "converter", "macro", "template",
     "type", "object", "enum", "distinct", "alias",
     "var", "let", "const", "global", "field", "fld", "param", "imp":
    result = true
  else:
    result = false

proc lsifKind(nifTag: string): int =
  if KindToLsif.hasKey(nifTag): result = KindToLsif[nifTag]
  else: result = 13  # variable/other fallback

proc declNameOf(n: NifNode): NifNode =
  ## Return the node that names the symbol introduced by compound node `n`.
  ## Prefers an explicit `:SymbolDef` atom; otherwise, for declaration tags, the
  ## second child (index 1) is the name when it is an identifier or symbol.
  if n.kind != nkCompound: return nil
  for c in n.children:
    if c.kind == nkSymbolDef:
      return c
  if isDeclTag(n.tag) and n.children.len >= 2:
    let c = n.children[1]
    if c.kind in {nkIdent, nkSymbol}:
      return c
  return nil

proc bareIdent(symText: string): string =
  ## ":foo.1.m" -> "foo"; "foo" -> "foo"
  var s = symText
  if s.startsWith(":"): s = s[1 .. ^1]
  let dot = s.find('.')
  if dot >= 0: s = s[0 .. dot - 1]
  result = s

proc collectSymbols(n: NifNode, outp: var seq[SymInfo]) =
  if n.kind == nkCompound:
    let nm = n.declNameOf()
    if nm != nil:
      let raw = nm.text
      outp.add(SymInfo(symbol: raw, ident: bareIdent(raw),
                       kind: n.tag, line: n.line, col: n.col, node: n))
    for c in n.children:
      collectSymbols(c, outp)

proc collectAll(nodes: seq[NifNode], outp: var seq[SymInfo]) =
  for n in nodes: collectSymbols(n, outp)

# --- the conversion --------------------------------------------------------

proc setupWriter*(w: var LsifWriter, projectRoot = "") =
  ## Initialise a writer with metaData and project vertices.
  var meta = newJObject()
  meta["version"] = newJString("0.5.0")
  meta["projectRoot"] = newJString(if projectRoot.len > 0: projectRoot else: "file:///")
  meta["positionEncoding"] = newJString("utf-16")
  var tool = newJObject()
  tool["name"] = newJString("nif2lsif")
  tool["version"] = newJString("0.1.0")
  meta["toolInfo"] = tool
  discard w.addVertex("metaData", meta)

  var proj = newJObject()
  proj["kind"] = newJString("nim")
  w.projectId = w.addVertex("project", proj)

proc addDocument*(w: var LsifWriter, text: string, uri: string) =
  ## Add one NIF module (as `text`) to the LSIF graph as a document.
  let (dirs, nodes) = parseNif(text)
  var doc = newJObject()
  doc["uri"] = newJString(uri)
  doc["languageId"] = newJString("nim")
  let docId = w.addVertex("document", doc)

  # project contains document
  var pc = newJObject()
  pc["outV"] = newJInt(w.projectId)
  var projDocArr = newJArray()
  projDocArr.add(newJInt(docId))
  pc["inVs"] = projDocArr
  discard w.addEdge("contains", pc)

  # collect symbols
  var syms: seq[SymInfo] = @[]
  collectAll(nodes, syms)

  # one range + resultSet + moniker per symbol
  var rangeIds: seq[JsonNode] = @[]
  for s in syms:
    let line = if s.line > 0: s.line else: 1
    let col = if s.col > 0: s.col else: 1
    var rng = newJObject()
    var start = newJObject()
    start["line"] = newJInt(line - 1)
    start["character"] = newJInt(col - 1)
    var ende = newJObject()
    ende["line"] = newJInt(line - 1)
    ende["character"] = newJInt(col - 1 + max(s.ident.len, 1))
    rng["start"] = start
    rng["end"] = ende
    let rangeId = w.addVertex("range", rng)
    rangeIds.add(newJInt(rangeId))

    # resultSet
    let rsId = w.addVertex("resultSet", newJObject())

    # range -> resultSet (next)
    var nx = newJObject()
    nx["outV"] = newJInt(rangeId)
    nx["inV"] = newJInt(rsId)
    discard w.addEdge("next", nx)

    # moniker (global symbol)
    var mon = newJObject()
    mon["scheme"] = newJString("nim")
    mon["identifier"] = newJString(s.ident)   # bare symbol name, e.g. "foo"
    mon["kind"] = newJString("export")
    let monId = w.addVertex("moniker", mon)
    var me = newJObject()
    me["outV"] = newJInt(rsId)
    me["inV"] = newJInt(monId)
    discard w.addEdge("moniker", me)

    # hover result attached to the resultSet (NIF tag + identifier)
    var hover = newJObject()
    var contents = newJObject()
    contents["kind"] = newJString("markdown")
    contents["value"] = newJString("```nim\n" & s.kind & " " & s.ident & "\n```")
    hover["contents"] = contents
    let hoverId = w.addVertex("hoverResult", hover)
    var he = newJObject()
    he["outV"] = newJInt(rsId)
    he["inV"] = newJInt(hoverId)
    discard w.addEdge("textDocument/hover", he)

  # document contains ranges
  if rangeIds.len > 0:
    var dc = newJObject()
    dc["outV"] = newJInt(docId)
    var rangeArr = newJArray()
    for rid in rangeIds: rangeArr.add(rid)
    dc["inVs"] = rangeArr
    discard w.addEdge("contains", dc)

  # documentSymbolResult: a tree of ranges for outline view
  if rangeIds.len > 0:
    var dsr = newJObject()
    var resArr = newJArray()
    for rid in rangeIds: resArr.add(rid)
    dsr["result"] = resArr
    let dsrId = w.addVertex("documentSymbolResult", dsr)
    var dse = newJObject()
    dse["outV"] = newJInt(docId)
    dse["inV"] = newJInt(dsrId)
    discard w.addEdge("textDocument/documentSymbol", dse)

proc convert*(text: string, uri: string, projectRoot = ""): LsifWriter =
  ## Parse `text` (a NIF module) and return an LSIF writer holding the graph.
  ## Equivalent to creating a writer, calling `setupWriter`, then `addDocument`.
  var w = newWriter()
  setupWriter(w, projectRoot)
  addDocument(w, text, uri)
  return w

# ===========================================================================
# CLI
# ===========================================================================

proc main() =
  var inputs: seq[string] = @[]
  var outPath = ""
  var checkOnly = false
  var pretty = false
  var args = commandLineParams()
  var i = 0
  while i < args.len:
    case args[i]
    of "-o", "--output":
      i.inc; outPath = args[i]
    of "--check":
      checkOnly = true
    of "--pretty":
      pretty = true
    else:
      inputs.add(args[i])
    i.inc

  if inputs.len == 0:
    stderr.writeLine("usage: nif2lsif [-o OUT.lsif] [--check] [--pretty] INPUT.nif [INPUT2.nif ...]")
    quit(2)

  for input in inputs:
    if not fileExists(input):
      stderr.writeLine("nif2lsif: file not found: " & input)
      quit(2)

  var w = newWriter()
  setupWriter(w)

  for input in inputs:
    let text = readFile(input)
    let uri = "file://" & absolutePath(input)
    addDocument(w, text, uri)

  if checkOnly:
    echo "nif2lsif: parsed " & $inputs.len & " file(s) -> " & $w.elements.len & " LSIF elements"
    quit(0)

  let data = if pretty: w.toPretty() else: w.toNdjson()
  if outPath.len > 0:
    writeFile(outPath, data)
    echo "nif2lsif: wrote " & outPath & " (" & $w.elements.len & " elements)"
  else:
    stdout.write(data)

when isMainModule:
  main()
