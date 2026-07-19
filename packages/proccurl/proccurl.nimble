# Package

version       = "0.1.0"
author        = "hugosenari"
description   = "Curl IPC — use libcurl without linking it directly"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
bin           = @["proccurl"]

# Dependencies

requires "nim >= 2.2.0"
requires "curly >=1.1.1"
