# mcpcurl

An MCP (Model Context Protocol) server that wraps libcurl to provide HTTP request tools over stdio JSON-RPC 2.0.

## Usage

Built from `src/mcpcurl.nim`, the `mcpcurl` binary is a stdio-based MCP server. Register it as an MCP client tool:

```json
{
  "mcp": {
    "mcpcurl": {
      "command": ["/path/to/mcpcurl"],
      "enabled": true,
      "type": "local"
    }
  }
}
```

### CLI invocation

Pipe JSON-RPC messages into the binary. Each message is a single JSON line; responses come one per line on stdout.

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"0.1.0"}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"curl_get","arguments":{"url":"https://yesno.wtf/api"}}}' \
| ./mcpcurl
```

Each request line must be self-contained JSON — no pretty-printing. For readability with `printf`, use `%s` with single-quoted strings joined by `\n`.

## Tools

| Tool | Description |
|------|-------------|
| `curl_get` | HTTP GET request |
| `curl_post` | HTTP POST request |
| `curl_put` | HTTP PUT request |
| `curl_patch` | HTTP PATCH request |
| `curl_delete` | HTTP DELETE request |
| `curl_head` | HTTP HEAD request |
| `curl_request` | HTTP request with arbitrary method |

### Common arguments

All tools accept these optional arguments:

| Argument | Type | Description |
|----------|------|-------------|
| `headers` | object | HTTP headers as key-value pairs |
| `timeout` | number | Request timeout in seconds (default: 60) |
| `connect_timeout` | number | Connection timeout in seconds |
| `body` | string | Request body content |
| `cainfo` | string | CA certificate file path |
| `capath` | string | CA certificate directory |
| `cert` | string | Client certificate file path |
| `certtype` | string | Client certificate type (PEM/DER) |
| `key` | string | Private key file path |
| `keytype` | string | Private key type (PEM/DER) |
| `keypasswd` | string | Private key password |
| `insecure` | boolean | Skip SSL peer and host verification |
| `dns_servers` | string | Custom DNS servers (comma-separated IPs) |
| `resolve` | string or array | Custom DNS resolution (host:port:address) |
| `proxy` | string | Proxy URL |
| `proxy_userpwd` | string | Proxy credentials (user:password) |
| `userpwd` | string | Basic auth credentials (user:password) |
| `useragent` | string | User-Agent header value |

`curl_request` additionally requires a `method` argument.

## Response format

Each tool returns a JSON-RPC result with:

```json
{
  "status": 200,
  "url": "https://example.com",
  "headers": { "Content-Type": "application/json", ... },
  "body": { ... }
}
```

The `body` field attempts JSON parsing; if it fails, the raw string is returned.

## Nim client library

`src/mcpcurl/mcpcurlclient.nim` provides a native Nim client that spawns the `mcpcurl` binary and communicates over stdio.

### Usage

```nim
import mcpcurl/mcpcurlclient

let client = newMcpcurlClient("./mcpcurl")
let resp = client.get("https://yesno.wtf/api")
echo resp.status
echo resp.body["answer"]

client.close()
```

### API

| Proc | Description |
|------|-------------|
| `newMcpcurlClient*(binaryPath)` | Spawn mcpcurl and perform initialize handshake |
| `close*()` | Kill the subprocess |
| `get*(url, opt?)` | HTTP GET |
| `post*(url, opt?)` | HTTP POST |
| `put*(url, opt?)` | HTTP PUT |
| `patch*(url, opt?)` | HTTP PATCH |
| `delete*(url, opt?)` | HTTP DELETE |
| `head*(url, opt?)` | HTTP HEAD |
| `request*(httpMethod, url, opt?)` | Arbitrary HTTP method |

**`HttpResponse`** fields:

| Field | Type | Description |
|-------|------|-------------|
| `status` | `int` | HTTP status code (0 if unavailable) |
| `url` | `string` | Effective URL after redirects |
| `headers` | `HttpHeaders` (Table[string,string]) | Response headers |
| `body` | `JsonNode` | Parsed JSON body (falls back to raw string) |

### Options

The `Option` object mirrors the server's common arguments:

```nim
var opt = initOption()
opt.timeout = 30
opt.headers = {"Authorization": "Bearer token"}.toTable
opt.insecure = true
opt.proxy = "http://proxy:8080"

let resp = client.get("https://example.com", opt)
```

All fields are optional and map directly to the arguments in the [Common arguments](#common-arguments) table.

### Errors

`McpcurlError` (a `CatchableError`) is raised on protocol errors, JSON-RPC errors, and connection failures.

## Protocol

Implements the MCP protocol (version `2025-06-18`) over stdio using JSON-RPC 2.0:

- `initialize` — server info and capabilities
- `ping` — keepalive
- `tools/list` — list available tools
- `tools/call` — execute a tool

## Building

```bash
nimble build
```

Requires `nim >= 2.2.0`, `curly >= 1.1.1`, and `libcurl >= 1.0.0`.
