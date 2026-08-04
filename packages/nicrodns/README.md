# nicrodns

Nim DNS tooling: a pure-Nim message parser/resolver and a wrapper around the
vendored [libmicrodns](https://github.com/videolabs/libmicrodns) C library.

## Pure-Nim resolver

`src/nicrodns.nim` — DNS header, question, record types, wire-format
encode/decode with name compression support, and a small UDP `resolve` helper
built on `std/net`.

```nim
import nicrodns

let answers = resolve("example.com", RecordType.A)
for a in answers:
  echo a
```

## libmicrodns wrapper

`src/nicrodns/microdns.nim` — header-driven bindings for the mDNS C library in
`clib/` (`mdns_init` / `mdns_destroy` / `mdns_listen` / `mdns_announce` /
`mdns_serve`, plus the `rr_entry`/`rr_data` structs and callbacks). Struct
layouts are read straight from the C headers, so bitfields and unions stay
ABI-correct.

The `scan` binary (`nimble build`) wraps this into a CLI: it announces a
service, requests an initial announce, and concurrently runs `mdnsListen` to
discover responders, printing every announce it sends and every response it
discovers until a timeout (default 10s) or Ctrl-C.

```nim
import nicrodns/microdns

var ctx: ptr MdnsCtx
discard mdnsInit(addr ctx, nil, MDNS_PORT.cushort)
# ... mdnsListen or mdnsAnnounce + mdnsServe ...
discard mdnsDestroy(ctx)
```

### Building the C library

The wrapper links against a static `libmicrodns.a` built from the sources in
`clib/`. From the package root:

```sh
mkdir -p clib/build
cat > clib/build/config.h <<'EOF'
#define HAVE_CONFIG_H 1
#define HAVE_INET_NTOP 1
#define HAVE_POLL 1
#define HAVE_STRUCT_POLLFD 1
#define HAVE_GETIFADDRS 1
#define HAVE_IFADDRS_H 1
#define HAVE_UNISTD_H 1
EOF
cd clib/build
gcc -c -DHAVE_CONFIG_H -I. -I../include -I../compat -fPIC \
  ../src/mdns.c ../src/rr.c ../compat/compat.c ../compat/inet.c ../compat/poll.c
ar rcs libmicrodns.a mdns.o rr.o compat.o inet.o poll.o
```

`config.nims` adds `clib/include` to the C include path and links
`clib/build/libmicrodns.a` when present.

## Tests

```sh
nimble test
```
