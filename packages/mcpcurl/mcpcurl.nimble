# Package

version       = "0.1.0"
author        = "hugosenari"
description   = "MCP server exposing a curl client as tools"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
bin           = @["mcpcurl"]

# Dependencies

requires "nim >= 2.2.0"
requires "libcurl >=1.0.0"
