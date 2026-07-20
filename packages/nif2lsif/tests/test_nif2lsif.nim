import pepino
import std/[json, strutils]
import nif2lsif

const webdrivermcpNifContent = staticRead("../../webdrivermcp/src/webdrivermcp.nif")
const webdrivermcpDepsNifContent = staticRead("../../webdrivermcp/src/webdrivermcp.deps.nif")

proc parseLines(text: string): seq[JsonNode] =
  result = @[]
  for line in text.splitLines:
    let trimmed = line.strip
    if trimmed.len == 0: continue
    try:
      result.add(parseJson(trimmed))
    except JsonParsingError:
      discard

proc hasType(elements: seq[JsonNode], tp: string, label: string): bool =
  for e in elements:
    if e.hasKey("type") and e["type"].getStr() == tp and
       e.hasKey("label") and e["label"].getStr() == label:
      return true
  return false

suite "nif2lsif conversion":

  test "Convert a NIF file to LSIF graph":
    let w = convert(webdrivermcpNifContent, "file:///webdrivermcp.nif")
    let elements = parseLines(w.toNdjson())
    check elements.len > 0
    for e in elements:
      check e.kind == JObject
      check e.hasKey("id")
      check e.hasKey("type")
      check e.hasKey("label")
    check hasType(elements, "vertex", "metaData")
    check hasType(elements, "vertex", "project")
    check hasType(elements, "vertex", "document")

  test "Convert a NIF deps file to LSIF graph":
    let w = convert(webdrivermcpDepsNifContent, "file:///webdrivermcp.deps.nif")
    let elements = parseLines(w.toNdjson())
    check elements.len > 0
    for e in elements:
      check e.kind == JObject
      check e.hasKey("id")
      check e.hasKey("type")
      check e.hasKey("label")
    check hasType(elements, "vertex", "metaData")
    check hasType(elements, "vertex", "project")
    check hasType(elements, "vertex", "document")

  test "LSIF output has correct document URI":
    let w = convert(webdrivermcpNifContent, "file:///webdrivermcp.nif")
    let elements = parseLines(w.toNdjson())
    var found = false
    for e in elements:
      if e.hasKey("type") and e["type"].getStr() == "vertex" and
         e.hasKey("label") and e["label"].getStr() == "document":
        let uri = e["uri"].getStr()
        check "webdrivermcp.nif" in uri
        found = true
    check found

  test "LSIF output contains project-document containment":
    let w = convert(webdrivermcpNifContent, "file:///webdrivermcp.nif")
    let elements = parseLines(w.toNdjson())
    check hasType(elements, "edge", "contains")
