# Package

version       = "0.1.0"
author        = "hugosenari"
description   = "MCP server exposing the halonium WebDriver library as tools"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
bin           = @["webdrivermcp"]

# Dependencies

requires "nim >= 2.2.0"
requires "halonium >= 0.2.7"

# NOTE: the package's tests/ import `pepino` for Cucumber-style coverage.
# `pepino` is a local workspace sibling (../pepino). It is NOT declared here
# as a nimble `requires` because nimble 0.20 cannot resolve local path deps;
# instead `tests/config.nims` adds `../../pepino/src` to the module search
# path, so `nim c tests/test_webdrivermcp.nim` resolves it directly.
