# proccurl

Curl IPC — a Linux command/lib POC to use `libcurl` without linking it
directly. Splits the app in two: a small `libcurl`-backed process (`proccurl`)
and your application, which talks to it over a defined JSON-RPC protocol.

See the top-level [`../README.md`](../README.md) and
[`PROTOCOLS/`](PROTOCOLS) for the protocol spec.

## Build

```bash
nimble build            # -> ../../bin/proccurl
# or
nim c -o:../../bin/proccurl src/proccurl.nim
```

## Test

```bash
nim c -r tests/test_proccurl.nim
```
