import std/os

# Wire the vendored libmicrodns (clib/) into the C build: add its include dir
# for the `header` pragmas and link the static library built from clib sources.
let
  clibRoot = currentSourcePath().parentDir / "clib"
  includeDir = clibRoot / "include"
  staticLib = clibRoot / "build" / "libmicrodns.a"

switch("passC", "-I" & includeDir)
# Nim's callback/pointer types can't carry C `const`/`enum` qualifiers; those
# differences are ABI-identical, so silence the const-qualifier pointer checks.
switch("passC", "-Wno-incompatible-pointer-types")
if fileExists(staticLib):
  switch("passL", staticLib)
