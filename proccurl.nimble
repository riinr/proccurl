# Package

version       = "0.1.0"
author        = "hugosenari"
description   = "Curl IPC"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
bin           = @["proccurl", "mcpcurl", "pepino", "webdrivermcp"]

# Dependencies

requires "nim >= 2.2.0"
requires "curly >=1.1.1"
requires "libcurl >=1.0.0"
requires "halonium >= 0.2.7"
