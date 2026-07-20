# Package

version       = "0.1.0"
author        = "hugosenari"
description   = "Convert Nim NIF (Nim Intermediate Format) AST files to LSIF code-intelligence graphs"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
bin           = @["nif2lsif"]

# Dependencies

requires "nim >= 2.2.0"

# NOTE: tests/ import `pepino` for Cucumber-style coverage. `pepino` is a local
# workspace sibling (../pepino) that nimble 0.20 cannot resolve as a path dep,
# so `tests/config.nims` adds `../../pepino/src` to the module search path.
