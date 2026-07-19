# proccurl (monorepo)

A monorepo of small Nim command/lib projects around using `libcurl` without
linking it directly, plus the tooling that grew around it.

This is a [nimble workspace](https://nim-lang.org/docs/nimble.html): the root
`proccurl.nimble` references each package by local path, so `nimble` resolves
cross-package dependencies and `nim c` works from anywhere thanks to the root
`config.nims`.

## Packages

| Package | What it is | Binary |
|---------|------------|--------|
| [`packages/proccurl`](packages/proccurl) | Curl IPC — talk to a `libcurl`-backed process over a JSON-RPC protocol | `proccurl` |
| [`packages/mcpcurl`](packages/mcpcurl) | MCP server wrapping libcurl as HTTP tools over stdio | `mcpcurl` |
| [`packages/webdrivermcp`](packages/webdrivermcp) | MCP server exposing the `halonium` WebDriver lib as tools | `webdrivermcp` |
| [`packages/pepino`](packages/pepino) | Cucumber-style scenario coverage for Nim test files | `pepino` |

## Layout

```
proccurl.nimble        # workspace root (requires path:packages/*)
config.nims            # exposes every package src/ to `nim c`
packages/<name>/
  src/                 # package sources (srcDir)
  tests/               # package tests + config.nims
  features/            # gherkin specs (where relevant)
  <name>.nimble        # per-package manifest + local deps
bin/                   # build output (git-ignored)
bench/                 # cross-package benchmarks
.nix/                  # devshell / tooling (flake)
```

## Build

```bash
nix develop            # or: direnv allow
nimble build          # builds all package binaries into bin/
```

Or build a single package:

```bash
cd packages/proccurl && nim c -o:../../bin/proccurl src/proccurl.nim
```
