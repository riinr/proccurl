## pepino -- Cucumber-style scenario coverage for Nim test files.
##
## Import this module from a file named `tests/test_<name>.nim`. It resolves
## `../features/<name>.feature` (relative to the test file) using the parser in
## `pepino/pepino`, and when the test binary exits it reports a Cucumber-style
## summary showing which scenarios have a matching test.
##
## Inside a `suite`, declare that a feature scenario is covered by writing a
## `test` whose name matches the scenario. `test` here is pepino's drop-in
## replacement for `std/unittest`'s `test`; it both runs the test body and
## records the scenario. Any scenario present in the `.feature` file but with no
## matching `test` is reported as `undefined` -- the same way Cucumber reports a
## scenario with no step definitions.
##
## Example `tests/test_calc.nim`:
##
##   import pepino
##   suite "calc":
##     test "Add two numbers":
##       check 1 + 1 == 2
##
## For a scenario with `Examples`, write the `test` once (no "[k]") and pepino
## expands it into one `unittest.test` per example row, each named
## `"<scenario> [<k>]"`, injecting the row's cells as string variables:
##
##   test "Multiply two numbers":
##     check parseInt(left_op) * parseInt(right_op) == parseInt(expected)
##
## `test` here is pepino's drop-in replacement for `std/unittest`'s `test`; it
## runs the test body and records the scenario named by the test.
##
## Output (Cucumber-style):
##
##   Feature: Calculator
##
##     Scenario: Add two numbers        # features/calc.feature
##       passed
##
##   1 Scenarios (1 passed)
##
## (The library adds no timing line; the run exits non-zero when any scenario is
## `failed` or `failing`.)

import std/[hashes, os, tables, strutils, macros]
# Pull in `std/unittest` and re-export the *whole module* (not just selected
# symbols). Re-exporting individual templates (`suite`/`test`) is not enough:
# those templates call methods on unittest's internal `Formatter` type, and a
# partial re-export does not bring that type's method table into the caller's
# module -- so `suite`/`test` would fail to compile for anyone importing only
# `pepino`. Re-exporting the module transitively makes `import pepino` behave
# exactly like `import pepino, std/unittest`, so a test file only needs pepino.
import std/unittest
export unittest
import pepino/pepino

# We keep ONLY the compile-time call-site file name in a global, assigned
# directly from the `instantiationInfo` const. A minimal repro showed a plain
# global string assigned this way survives unchanged until program exit (while
# derived/parsed strings stored in globals got their buffers clobbered by Nim's
# sink/move reuse). Everything else is re-derived fresh in `printSummary`.
#
# Scenario outcomes are tracked in `gStatus`, keyed by scenario name. The status
# is recorded at the *end* of the `test` block (via a `defer` installed by the
# `test` template), so it sees the final result of any `check` calls.
# `testStatusIMPL` is injected into the test body by stdlib `unittest` and reflects
# OK/FAILED once the body has run, so it is readable inside that `defer`.
type PepinoStatus = enum
  psUndefined
  psPassed
  psFailed

var gCallFile: string
var gResolved: bool
var gStatus: Table[string, PepinoStatus]

# A minimal OutputFormatter that captures the checkpoint messages emitted by a
# failed `check` (unittest calls `failureOccurred(checkpoints, ...)` for each
# failed assertion, then `testEnded` with the owning test name). We stash them
# in the captor's `reasons` table keyed by the test name -- which is exactly the
# scenario name pepino uses as its status key -- so the summary can print them.
type ReasonCaptor = ref object of OutputFormatter
  cur: seq[string]
  reasons: Table[string, seq[string]]

method failureOccurred(f: ReasonCaptor, checkpoints: seq[string],
    stackTrace: string) {.gcsafe.} =
  for c in checkpoints:
    f.cur.add(c)

method testEnded(f: ReasonCaptor, testResult: TestResult) {.gcsafe.} =
  if f.cur.len > 0:
    f.reasons[testResult.testName] = f.cur
  f.cur.setLen(0)

# Single captor instance that records, per scenario (test) name, the
# "Check failed: ..." messages emitted by stdlib `unittest`. Populated via a
# custom OutputFormatter so pepino can show *why* a scenario failed next to its
# own `fail` line.
var gCaptor: ReasonCaptor

proc resolveFeaturePath(testFile: string): string =
  ## Derive `../features/<name>.feature` from the importing test file's path.
  let dir = testFile.splitFile.dir
  let base = testFile.splitFile.name           # e.g. "test_calc"
  # strip a leading "test_" if present; keep the rest as the feature name
  let feat = if base.startsWith("test_") and base.len > 5:
               base[5 .. ^1]
             else:
               base
  result = dir / ".." / "features" / (feat & ".feature")
  result.normalizePath

proc initCoverage*(testFile: string) =
  if gResolved:
    return
  gStatus = initTable[string, PepinoStatus]()
  # Register a formatter that records failure reasons for later display.
  gCaptor = ReasonCaptor(reasons: initTable[string, seq[string]]())
  addOutputFormatter(gCaptor)
  gCallFile = testFile
  gResolved = true

template pepinoTestImpl*(name: string, body: untyped) =
  ## Per-unit runner used internally by `expandTests`. Registers `name` as a
  ## covered scenario, runs the (possibly example-injected) `body` inside
  ## unittest's `test`, and records the final `testStatusIMPL` via a `defer` so a
  ## failed `check` flips the status to `fail`. Kept as a template so the
  ## `gStatus`/`psPassed` bookkeeping stays in pepino's scope.
  ##
  ## The body is run inside a `block:` so example columns (which pepino injects
  ## as `let` bindings) get their own scope -- this avoids a clash when a column
  ## is named `result` (which would otherwise collide with the test proc's magic
  ## `result` variable).
  gStatus[name] = psPassed
  unittest.test name:
    defer:
      when declared(testStatusIMPL):
        if testStatusIMPL == TestStatus.FAILED:
          gStatus[name] = psFailed
    body

template test*(name: string, body: untyped) =
  ## User-facing entry point. Defined as a template so it shadows the
  ## re-exported `unittest.test`; it delegates the actual (possibly expanded)
  ## work to the `expandTests` macro. See `expandTests` for the behavior.
  expandTests(name, body)

macro expandTests*(nameLit: untyped, body: untyped): untyped =
  ## Expand a `test` into one or more `unittest.test` blocks.
  ##
  ## If `nameLit` names a scenario that has `Examples` rows, the `test` is
  ## *expanded* into one `unittest.test` per example row, named `"<name> [<k>]"`
  ## (1-based across all of the scenario's `Examples` tables). The row's cells
  ## are injected into `body` as `let` bindings (one per column), so writing the
  ## `test` once exercises every example:
  ##
  ##   test "Multiply two numbers":
  ##     check parseInt(left_op) * parseInt(right_op) == parseInt(expected)
  ##
  ## produces four scenarios: "Multiply two numbers [1]" .. "[4]".
  ##
  ## You may also target a single row explicitly with `"<name> [<k>]"`; that runs
  ## only row `k` with its cells injected.
  ##
  ## The feature is resolved from the call-site file and parsed at compile time,
  ## so expansion and injection happen before the binary is built.
  # 1. Locate + read the feature from the `test` call site.
  let callFile = nameLit.lineInfoObj.filename
  var featPath = resolveFeaturePath(callFile)
  if featPath.len > 0 and featPath[0] != '/':
    featPath = "/" & featPath

  # 2. Collect the scenario's example rows (header + flat row list), if any.
  var header: seq[string] = @[]
  var rows: seq[seq[string]] = @[]
  var baseName = nameLit.strVal
  var explicitK = 0
  if featPath.fileExists:
    let nm = nameLit.strVal
    let openBracket = nm.rfind(" [")
    if openBracket >= 0 and nm.endsWith("]"):
      baseName = nm[0 .. openBracket - 1]
      let idxStr = nm[openBracket + 2 .. ^2]
      if idxStr.allCharsInSet(Digits):
        explicitK = parseInt(idxStr)
    let feature = parseFeature(staticRead(featPath))
    for sc in feature.scenarios:
      if sc.name == baseName:
        for ex in sc.examples:
          if header.len == 0: header = ex.header
          for r in ex.rows: rows.add(r)
    for rule in feature.rules:
      for sc in rule.scenarios:
        if sc.name == baseName:
          for ex in sc.examples:
            if header.len == 0: header = ex.header
            for r in ex.rows: rows.add(r)

  # 3. Build the (possibly expanded) test blocks.
  result = newStmtList()
  result.add(quote do:
    initCoverage(`callFile`))

  if explicitK > 0:
    # Explicit single row: "Name [k]".
    if explicitK <= rows.len:
      var b = copyNimTree(body)
      for i in 0 ..< header.len:
        let col = ident(header[i])
        let v = newLit(rows[explicitK - 1][i])
        b.insert(0, quote do:
          let `col`: string = `v`)
      result.add(quote do:
        pepinoTestImpl `nameLit.strVal`:
          `b`)
    else:
      # Unknown row index: still run it (will show as covered by its name).
      result.add(quote do:
        pepinoTestImpl `nameLit.strVal`:
          `body`)
  elif rows.len > 0:
    # Scenario with examples: expand into one block per row.
    for k in 1 .. rows.len:
      var b = copyNimTree(body)
      for i in 0 ..< header.len:
        let col = ident(header[i])
        let v = newLit(rows[k - 1][i])
        b.insert(0, quote do:
          let `col`: string = `v`)
      # Evaluate the unit name to a string literal NOW (not an expression over the
      # loop variable `k`, which would be out of range by the time the test runs).
      let unitName = newLit(baseName & " [" & $k & "]")
      result.add(quote do:
        pepinoTestImpl `unitName`:
          `b`)
  else:
    # Plain scenario (no examples, or no matching feature): single block.
    result.add(quote do:
      pepinoTestImpl `nameLit.strVal`:
        `body`)



when not isMainModule:
  import std/exitprocs
  proc printSummary() =
    # When pepino is used only as a driver (e.g. via `pepinoMain`) there is no
    # `suite`/`test` and `gCallFile` is never set; skip the scenario report so the
    # driver output stays clean.
    if gCallFile.len == 0:
      return
    # Drain gStatus into a local seq once. Under --mm:arc and --mm:orc, the
    # Table[string, ...] pairs iterator may yield by sink / lent and iterating
    # twice causes a SIGSEGV, and getOrDefault also misses entries. We snapshot
    # the data (with proper copies) into a local seq and use that for everything.
    var gStatusSeq: seq[(string, PepinoStatus)] = @[]
    for k, v in gStatus:
      gStatusSeq.add((k, v))
    var passed, failed, undefined: int
  
    # Derive the feature path fresh, at exit, from the surviving call-site file.
    var pathStr = resolveFeaturePath(gCallFile)
    # `instantiationInfo().filename` can report a path whose leading separator is
    # missing; test files are always absolute, so restore it before normalizing.
    if pathStr.len > 0 and pathStr[0] != '/':
      pathStr = "/" & pathStr
    # Report the path relative to the current working directory (typically the
    # project root), e.g. `features/calc.feature` rather than an absolute path.
    pathStr = relativePath(pathStr, getCurrentDir())
    let hasPath = pathStr.len > 0 and pathStr.fileExists
  
    # Re-parse the feature here, at exit, where string buffers are stable. The
    # parser keeps some strings as views into the source text, so we use the
    # resulting `Feature` only within this proc (never stored in a global, where
    # its views would dangle by the time we print).
    var feature = Feature()
    if hasPath:
      try:
        feature = parseFeature(readFile(pathStr))
      except GherkinError as e:
        echo "pepino: failed to parse " & pathStr & ": " & e.msg
  
    let featTitle = if feature.name.len > 0: feature.name
                    else: "(no feature file)"
  
    # Accumulate everything into ONE growing buffer via `add`. Using a single
    # local buffer (rather than many `echo`/`&` calls on the globals) avoids the
    # per-iteration string aliasing that corrupted the path earlier.
    var outp = ""
    outp.add("\n")
    outp.add("Feature: ")
    outp.add(featTitle)
    outp.add("\n")
    if hasPath:
      outp.add("\n")
  
    # Enumerate every checkable unit from the feature:
    #   * a scenario with no `Examples` is one unit keyed by its name;
    #   * a scenario that carries one or more `Examples` tables expands into one
    #     unit per example row, keyed by "<name> [<k>]" (1-based across all of the
    #     scenario's `Examples` tables). This covers both explicit `Scenario
    #     Outline:` blocks and plain `Scenario:` blocks that happen to have rows.
    # A `test "Multiply two numbers [1]":` then covers example row 1, and so on.
    proc addUnits(scs: seq[Scenario]; units: var seq[(string, string)]) =
      for s in scs:
        if s.examples.len == 0:
          # Plain scenario (or outline with no example rows): one unit by name.
          units.add((s.name, s.name))
        else:
          # Scenario (Outline) with Examples: one unit per example row, keyed by
          # "<name> [<k>]" (1-based across all of its `Examples` tables).
          var k = 0
          for ex in s.examples:
            for row in ex.rows:
              k.inc
              let key = s.name & " [" & $k & "]"
              units.add((key, key))
  
    var units: seq[(string, string)] = @[]
    addUnits(feature.scenarios, units)
    for r in feature.rules:
      addUnits(r.scenarios, units)
  
    # Emit one scenario line per unit and tally its outcome. The three outcomes
    # mirror Cucumber: a referenced unit whose test body passed, one whose test
    # body failed, or one never referenced at all (failing).
    #
    # Lookup uses gStatusSeq (the local snapshot) to avoid Table[string, ...]
    # iteration and getOrDefault issues under --mm:arc and --mm:orc.
    for u in units:
      var st = psUndefined
      for i in 0..<gStatusSeq.len:
        if gStatusSeq[i][0] == u[0]:
          st = gStatusSeq[i][1]
          break
      case st
      of psPassed:
        inc passed
        outp.add("  Scenario: "); outp.add(u[1])
        if hasPath: outp.add(" # "); outp.add(pathStr)
        outp.add("\n    passed\n\n")
      of psFailed:
        inc failed
        outp.add("  Scenario: "); outp.add(u[1])
        if hasPath: outp.add(" # "); outp.add(pathStr)
        outp.add("\n    fail\n")
        # Show *why* the scenario failed: the captured "Check failed: ..." lines
        # for this scenario (keyed by its name), if any were recorded.
        if gCaptor != nil and gCaptor.reasons.hasKey(u[0]):
          for r in gCaptor.reasons[u[0]]:
            outp.add("      ")
            outp.add(r.replace("\n", "\n      "))
            outp.add("\n")
        outp.add("\n")
      of psUndefined:
        inc undefined
        outp.add("  Scenario: "); outp.add(u[1])
        if hasPath: outp.add(" # "); outp.add(pathStr)
        outp.add("\n    failing\n\n")
  
    # Summary footer -- Cucumber style.
    var scenParts: seq[string] = @[]
    if passed > 0: scenParts.add $passed & " passed"
    if failed > 0: scenParts.add $failed & " failed"
    if undefined > 0: scenParts.add $undefined & " failing"
    let scenSummary = if scenParts.len == 0: "0"
                      else: scenParts.join(", ")
    let n = units.len
    outp.add($n & " Scenarios (" & scenSummary & ")")
    outp.add("\n")
  
    echo outp
  
    # A Cucumber run fails when any scenario is not green: a failed test body or a
    # scenario with no matching test (undefined). `quit(1)` inside the exit proc
    # overrides the process exit code accordingly. We also write the reason to
    # stderr so the failure is visible even if a wrapper (e.g. `nim c -r` in some
    # setups, or a CI step) swallows the numeric exit code.
    if failed > 0 or undefined > 0:
      var why: seq[string] = @[]
      if failed > 0: why.add $failed & " failed"
      if undefined > 0: why.add $undefined & " failing"
      stderr.writeLine "pepino: " & why.join(", ") & " -- exiting with failure"
      quit(1)



  addExitProc printSummary

proc pepinoMain*(featuresDir = "features", testsDir = "tests",
                 noPrompt = false) =
  ## Scan `featuresDir` for `*.feature` files and check that each has a matching
  ## test file `testsDir/test_<name>.nim`. For every feature without one, prompt
  ## the user (default answer `Y`) whether to create a stub test file; on `Y` the
  ## stub is written (listing each scenario as a TODO `test`), otherwise the
  ## process exits non-zero.
  ##
  ## Pass `noPrompt = true` (or run the driver with a `-N` command-line flag) to
  ## skip the prompt entirely: missing test files then cause an immediate
  ## non-zero exit with no stub creation. This is handy for CI / pre-test gates.
  ##
  ## Call this from a small driver, e.g. `tests/pepino_driver.nim`:
  ##
  ##   import pepino
  ##   pepinoMain()
  ##
  ## and run it with `nim c -r tests/pepino_driver.nim` (or wire it into your CI
  ## as a pre-test gate, e.g. `nim c -r tests/pepino_driver.nim -N`).
  # Honor an explicit `-N` flag from the command line, unless the caller already
  # forced `noPrompt` explicitly (the parameter default false lets the CLI win).
  let np = noPrompt or "-N" in commandLineParams()
  if not featuresDir.dirExists:
    stderr.writeLine "pepino: features directory not found: " & featuresDir
    quit(1)
  if not testsDir.dirExists:
    stderr.writeLine "pepino: tests directory not found: " & testsDir
    quit(1)

  var missing: seq[string] = @[]   # feature base names without a test file
  for f in walkDir(featuresDir):
    if f.kind != pcFile or not f.path.endsWith(".feature"):
      continue
    let base = f.path.splitFile.name          # e.g. "calc_examples"
    let testPath = testsDir / ("test_" & base & ".nim")
    if not testPath.fileExists:
      missing.add(base)

  if missing.len == 0:
    echo "pepino: all feature files have a matching test_<name>.nim"
    return

  echo "pepino: missing test files for " & $missing.len & " feature file(s):"
  for m in missing:
    echo "  - test_" & m & ".nim  (from " & featuresDir / (m & ".feature") & ")"

  if np:
    # No-prompt mode (e.g. CI): do not ask, do not create stubs, just fail.
    stderr.writeLine "pepino: missing test files; exiting with failure (-N)"
    quit(1)

  stdout.write("Create stub test files for the above? [Y/n] ")
  stdout.flushFile()
  let answer = stdin.readLine().strip.toLowerAscii
  let create = answer.len == 0 or answer == "y" or answer == "yes"

  if not create:
    stderr.writeLine "pepino: missing test files; exiting with failure"
    quit(1)

  for m in missing:
    let featPath = featuresDir / (m & ".feature")
    let testPath = testsDir / ("test_" & m & ".nim")
    var stub = ""
    stub.add("import pepino\n\n")
    stub.add("suite \"" & m.replace('_', ' ') & "\":\n")
    try:
      let feature = parseFeature(readFile(featPath))
      var names: seq[string] = @[]
      for sc in feature.scenarios: names.add(sc.name)
      for r in feature.rules:
        for sc in r.scenarios: names.add(sc.name)
      if names.len == 0:
        stub.add("  # TODO: add tests for the scenarios in " & featPath & "\n")
      else:
        for nm in names:
          stub.add("\n  test \"" & nm & "\":\n")
          stub.add("    # TODO: implement\n")
          stub.add("    check false\n")
    except GherkinError as e:
      stub.add("  # TODO: failed to parse " & featPath & ": " & e.msg & "\n")
    writeFile(testPath, stub)
    echo "pepino: created stub " & testPath

  echo "pepino: created " & $missing.len & " stub test file(s)."

when isMainModule:
  pepinoMain()
