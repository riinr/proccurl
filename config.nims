# Workspace-wide Nim config.
# Adds every package's src dir to the module search path so `nim c` works
# from the repo root without going through nimble. Package-local config.nims
# files handle per-package test paths.

switch("path", "$projectDir/packages/proccurl/src")
switch("path", "$projectDir/packages/mcpcurl/src")
switch("path", "$projectDir/packages/webdrivermcp/src")
switch("path", "$projectDir/packages/pepino/src")
