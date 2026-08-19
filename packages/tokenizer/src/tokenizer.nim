## cl100k_base BPE tokenizer (byte-level BPE), compatible with the encoding
## used by gpt-4, gpt-3.5-turbo, and the text-embedding-3-* models.
##
## Vocab file format: one entry per line, `<base64-encoded-token> <rank>`
## (this is OpenAI's standard tiktoken plaintext vocab format).
##
## Usage:
##   nim c -r tokenizer.nim cl100k_base.tiktoken "your text here"
##   nim c -r tokenizer.nim cl100k_base.tiktoken --file path/to/file.txt

import std/[tables, strutils, os, re, base64]

type
  BpeEncoder = object
    ranks: Table[string, int]   ## merged token bytes (raw) -> rank
    pattern: Regex

# cl100k_base's Unicode-aware pre-tokenization pattern.
# Splits text into chunks before BPE merging is applied within each chunk.
const Cl100kPattern =
  r"'(?:[sdmt]|ll|ve|re)|[^\r\n\pL\pN]?\pL+|\pN{1,3}| ?[^\s\pL\pN]+[\r\n]*|\s*[\r\n]+|\s+(?!\S)|\s+"

proc loadRanks(path: string): Table[string, int] =
  ## Parses the tiktoken plaintext vocab file into a bytes->rank table.
  result = initTable[string, int]()
  for line in lines(path):
    if line.len == 0:
      continue
    let parts = line.split(' ')
    doAssert parts.len == 2, "malformed vocab line: " & line
    let tokenBytes = decode(parts[0])  # base64 -> raw bytes, as a Nim string
    let rank = parseInt(parts[1])
    result[tokenBytes] = rank

proc newBpeEncoder(vocabPath: string): BpeEncoder =
  result.ranks = loadRanks(vocabPath)
  result.pattern = re(Cl100kPattern)

proc bpeMerge(ranks: Table[string, int], piece: string): seq[string] =
  ## Naive O(n^2) BPE merge: repeatedly merges the adjacent byte-pair with
  ## the lowest rank until no mergeable pair remains. Mirrors the reference
  ## algorithm from tiktoken's own educational module.
  result = @[]
  for ch in piece:
    result.add($ch)

  if result.len <= 1:
    return result

  while true:
    var minRank = high(int)
    var minIdx = -1
    for i in 0 ..< result.len - 1:
      let pair = result[i] & result[i + 1]
      let r = ranks.getOrDefault(pair, high(int))
      if r < minRank:
        minRank = r
        minIdx = i
    if minIdx == -1:
      break
    result[minIdx] = result[minIdx] & result[minIdx + 1]
    result.delete(minIdx + 1)

proc encode*(enc: BpeEncoder, text: string): seq[int] =
  ## Encodes `text` into a sequence of cl100k_base token IDs.
  result = @[]
  var start = 0
  while start < text.len:
    let bounds = findBounds(text, enc.pattern, start)
    if bounds.first < 0:
      break
    let piece = text[bounds.first .. bounds.last]
    if enc.ranks.hasKey(piece):
      result.add(enc.ranks[piece])
    else:
      for sub in bpeMerge(enc.ranks, piece):
        result.add(enc.ranks[sub])
    start = bounds.last + 1

proc countTokens*(enc: BpeEncoder, text: string): int =
  enc.encode(text).len

when isMainModule:
  if paramCount() < 2:
    echo "usage: tokenizer <vocab_path> <text>"
    echo "       tokenizer <vocab_path> --file <path>"
    quit(1)

  let vocabPath = paramStr(1)
  var input: string

  if paramStr(2) == "--file":
    if paramCount() < 3:
      echo "error: --file requires a path"
      quit(1)
    input = readFile(paramStr(3))
  else:
    input = paramStr(2)

  let enc = newBpeEncoder(vocabPath)
  let tokens = enc.encode(input)

  echo "tokens: ", tokens.len
  echo "ids: ", tokens
