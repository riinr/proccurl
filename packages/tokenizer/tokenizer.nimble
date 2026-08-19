# Package

version       = "0.1.0"
author        = "hugosenari"
description   = "cl100k_base BPE tokenizer (byte-level BPE), tiktoken-compatible"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
bin           = @["tokenizer"]

# Dependencies

requires "nim >= 2.0.0"

task test, "Run the unit tests":
  exec "nim c -r tests/test_tokenizer.nim"