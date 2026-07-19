# webdrivermcp

An MCP server exposing the [`halonium`](https://github.com/halonium/halonium)
WebDriver library as tools (navigate, find element, read text, ...). Transport
is line-delimited JSON-RPC over stdio, like `mcpcurl`.

The Cucumber-style coverage spec lives in [`features/webdrivermcp.feature`](features/webdrivermcp.feature)
and is exercised by [`tests/test_webdrivermcp.nim`](tests/test_webdrivermcp.nim)
(via the `pepino` package).

## Build

```bash
nimble build            # -> ../../bin/webdrivermcp
# or
nim c -o:../../bin/webdrivermcp src/webdrivermcp.nim
```
