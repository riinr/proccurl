# Package

version       = "0.1.0"
author        = "hugosenari"
description   = "Minimal pure-Nim DNS message parser and resolver"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
bin           = @["nicrodns/scan=scan"]

# Dependencies

requires "nim >= 2.0.0"
