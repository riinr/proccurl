import std/[unittest, tables, strutils, os, base64]
import tokenizer

# Build a small synthetic tiktoken-format vocab in a temp dir.
# Tokens (raw bytes -> rank):
#   "a" -> 0, "b" -> 1, "c" -> 2, "ab" -> 3, "bc" -> 4, "abc" -> 5
proc writeVocab(dir: string): string =
  let tokens = @["a", "b", "c", "ab", "bc", "abc"]
  var lines: seq[string]
  for i, t in tokens:
    lines.add(encode(t) & " " & $i)
  result = dir / "vocab.tiktoken"
  writeFile(result, lines.join("\n") & "\n")

suite "vocab loading":
  test "loadRanks parses base64 token + rank lines":
    let dir = getTempDir()
    let path = writeVocab(dir)
    let enc = newBpeEncoder(path)
    check enc.ranks["a"] == 0
    check enc.ranks["abc"] == 5
    check enc.ranks.len == 6
    removeFile(path)

suite "bpeMerge":
  test "single char piece returns itself":
    let ranks = initTable[string, int]()
    check bpeMerge(ranks, "a") == @["a"]

  test "merges lowest-rank adjacent pair repeatedly":
    let ranks = {"ab": 3, "bc": 4, "abc": 5}.toTable
    # "abc": pairs "ab"(3) and "bc"(4); merge "ab" -> ["ab","c"],
    # then "bc"(4) -> ["ab","bc"]; "abbc" not in ranks -> stop.
    check bpeMerge(ranks, "abc") == @["ab", "bc"]

  test "no merge when no pair is in ranks":
    let ranks = {"xy": 0}.toTable
    check bpeMerge(ranks, "abc") == @["a", "b", "c"]

suite "encode":
  test "single token in ranks is emitted directly":
    let dir = getTempDir()
    let path = writeVocab(dir)
    let enc = newBpeEncoder(path)
    check enc.encode("abc") == @[5]
    removeFile(path)

  test "multi-token text encodes to merged ids":
    let dir = getTempDir()
    let path = writeVocab(dir)
    let enc = newBpeEncoder(path)
    # "ab" -> 3, "c" -> 2
    check enc.encode("abc") == @[5]
    check enc.encode("ab") == @[3]
    check enc.encode("c") == @[2]
    removeFile(path)

  test "empty text encodes to empty seq":
    let dir = getTempDir()
    let path = writeVocab(dir)
    let enc = newBpeEncoder(path)
    check enc.encode("") == @[]
    removeFile(path)

suite "countTokens":
  test "counts encoded ids":
    let dir = getTempDir()
    let path = writeVocab(dir)
    let enc = newBpeEncoder(path)
    check countTokens(enc, "abc") == 1
    check countTokens(enc, "ab") == 1
    check countTokens(enc, "") == 0
    removeFile(path)