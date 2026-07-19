# pepino

A small Gherkin (Cucumber) parser plus a `unittest` drop-in (`test`) that
reports Cucumber-style scenario coverage for Nim test files.

Import `pepino` from a `tests/test_<name>.nim` file: it resolves
`../features/<name>.feature` and, when the test binary exits, prints which
scenarios are covered / undefined.

## Build

```bash
nimble build            # -> ../../bin/pepino
# or
nim c -o:../../bin/pepino src/pepino.nim
```

## Test

```bash
nim c -r tests/test_pepino.nim
```
