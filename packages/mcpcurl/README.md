# mcpcurl

An MCP (Model Context Protocol) server that wraps `libcurl` to provide HTTP
request tools over stdio JSON-RPC 2.0. See the root [`../../README_MCPCURL.md`](../../README_MCPCURL.md)
for the full tool/option reference and the native Nim client library.

## Build

```bash
nimble build            # -> ../../bin/mcpcurl
# or
nim c -o:../../bin/mcpcurl src/mcpcurl.nim
```
