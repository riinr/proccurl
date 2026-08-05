# Package

version       = "0.1.0"
author        = "hugosenari"
description   = "Pure-Nim Multicast DNS service discovery (RFC 6762)"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
bin           = @["mdns_cli=mdns"]

# Dependencies

requires "nim >= 2.0.0"

task test, "Run the unit tests":
  exec "nim c -r tests/test_mdns.nim"

