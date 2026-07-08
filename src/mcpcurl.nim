import std/[json, streams, strutils, options, os]
import libcurl except Option

const MCP_PROTOCOL_VERSION* = "2025-06-18"

type Tool = object
  name: string
  description: string
  inputSchema: JsonNode

var gBodyBuf, gHeaderBuf: string

proc bodyCallback(buffer: cstring; size, nitems: int; outstream: pointer): int {.cdecl.} =
  let total = size * nitems
  gBodyBuf.setLen(gBodyBuf.len + total)
  copyMem(gBodyBuf[gBodyBuf.len - total].addr, buffer, total)
  result = total

proc headerCallback(buffer: cstring; size, nitems: int; outstream: pointer): int {.cdecl.} =
  let total = size * nitems
  gHeaderBuf.setLen(gHeaderBuf.len + total)
  copyMem(gHeaderBuf[gHeaderBuf.len - total].addr, buffer, total)
  result = total

const optResolve* = cast[libcurl.Option](10000 + 168)
const optDnsServers* = cast[libcurl.Option](10000 + 218)
const optConnectTimeout* = cast[libcurl.Option](0 + 78)

const commonArgs = [
  ("headers", "object", "HTTP headers to include as key-value pairs"),
  ("timeout", "number", "Request timeout in seconds (default: 60)"),
  ("connect_timeout", "number", "Connection timeout in seconds"),
  ("cainfo", "string", "CA certificate file path"),
  ("capath", "string", "CA certificate directory"),
  ("cert", "string", "Client certificate file path"),
  ("certtype", "string", "Client certificate type (PEM/DER)"),
  ("key", "string", "Private key file path"),
  ("keytype", "string", "Private key type (PEM/DER)"),
  ("keypasswd", "string", "Private key password"),
  ("insecure", "boolean", "Skip SSL peer and host verification"),
  ("dns_servers", "string", "Custom DNS servers (comma-separated IPs)"),
  ("resolve", "string", "Custom DNS resolution (host:port:address) or array of them"),
  ("proxy", "string", "Proxy URL"),
  ("proxy_userpwd", "string", "Proxy credentials (user:password)"),
  ("userpwd", "string", "Basic auth credentials (user:password)"),
  ("useragent", "string", "User-Agent header value"),
]

proc toolSchema(required: openArray[string]): JsonNode =
  let schema = %*{"type": "object", "properties": {}, "required": []}
  for (name, typ, desc) in commonArgs:
    schema["properties"][name] = %*{"type": typ, "description": desc}
  for name in required:
    schema["required"].add %name
  result = schema

proc defineTools(): seq[Tool] =
  result = @[
    Tool(name: "curl_get", description: "Make an HTTP GET request",
      inputSchema: toolSchema(["url"])),
    Tool(name: "curl_post", description: "Make an HTTP POST request",
      inputSchema: toolSchema(["url"])),
    Tool(name: "curl_put", description: "Make an HTTP PUT request",
      inputSchema: toolSchema(["url"])),
    Tool(name: "curl_patch", description: "Make an HTTP PATCH request",
      inputSchema: toolSchema(["url"])),
    Tool(name: "curl_delete", description: "Make an HTTP DELETE request",
      inputSchema: toolSchema(["url"])),
    Tool(name: "curl_head", description: "Make an HTTP HEAD request",
      inputSchema: toolSchema(["url"])),
    Tool(name: "curl_request", description: "Make an HTTP request with any method",
      inputSchema: toolSchema(["method", "url"])),
  ]

proc jsonRpcError(id: JsonNode; code: int; message: string): JsonNode =
  result = %*{
    "jsonrpc": "2.0",
    "id": id,
    "error": {"code": code, "message": message}
  }

proc jsonRpcResult(id: JsonNode; resultNode: JsonNode): JsonNode =
  result = %*{
    "jsonrpc": "2.0",
    "id": id,
    "result": resultNode
  }

proc formatResponse(code: int; url: string; headers, body: string): JsonNode =
  let parsedBody =
    try: body.parseJson
    except: %body
  var hdrs = %*{}
  for line in headers.split("\r\n"):
    if line.len == 0: continue
    let idx = line.find(':')
    if idx > 0:
      hdrs{line[0 ..< idx].strip()} = %line[idx + 1 ..^ 1].strip()
  %*{
    "status": code,
    "url": url,
    "headers": hdrs,
    "body": parsedBody
  }

proc handleInitialize(id: JsonNode; params: JsonNode): JsonNode =
  jsonRpcResult(id, %*{
    "protocolVersion": MCP_PROTOCOL_VERSION,
    "capabilities": {"tools": {}},
    "serverInfo": {"name": "mcpcurl", "version": "0.1.0"}
  })

proc handlePing(id: JsonNode): JsonNode =
  jsonRpcResult(id, %*{})

proc handleToolsList(id: JsonNode): JsonNode =
  let tools = defineTools()
  var toolList = newJArray()
  for t in tools:
    var schema = t.inputSchema
    schema["properties"]["url"] = %*{"type": "string", "description": "URL to send the request to"}
    schema["properties"]["body"] = %*{"type": "string", "description": "Request body content"}
    schema["properties"]["method"] = %*{"type": "string", "description": "HTTP method (GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS, etc.)"}
    toolList.add(%*{
      "name": t.name,
      "description": t.description,
      "inputSchema": schema
    })
  jsonRpcResult(id, %*{"tools": toolList})

proc buildSlist(headers: JsonNode): Pslist =
  if headers != nil and headers.kind == JObject:
    for k, n in headers.pairs:
      result = slist_append(result, (k & ": " & n.getStr()).cstring)

proc doRequest(httpMethod, url: string; args: JsonNode): JsonNode =
  gBodyBuf = ""
  gHeaderBuf = ""

  let curl = easy_init()
  if curl == nil:
    return jsonRpcError(newJNull(), -32000, "Failed to create curl handle")

  var
    httpCode: int32 = 0
    effUrl: cstring = nil
    slist: Pslist = nil
    resolveList: Pslist = nil

  try:
    discard curl.easy_setopt(OPT_URL, url.cstring)
    discard curl.easy_setopt(OPT_CUSTOMREQUEST, httpMethod.cstring)
    discard curl.easy_setopt(OPT_FOLLOWLOCATION, 1)
    discard curl.easy_setopt(OPT_MAXREDIRS, 10)
    discard curl.easy_setopt(OPT_NOSIGNAL, 1)

    let timeout = args{"timeout"}.getFloat(60).int
    discard curl.easy_setopt(OPT_TIMEOUT, timeout)

    let connectTimeout = args{"connect_timeout"}.getFloat(0).int
    if connectTimeout > 0:
      discard curl.easy_setopt(optConnectTimeout, connectTimeout)

    if httpMethod == "HEAD":
      discard curl.easy_setopt(OPT_NOBODY, 1)

    let body = args{"body"}.getStr("")
    if body.len > 0:
      discard curl.easy_setopt(OPT_POSTFIELDSIZE, body.len)
      discard curl.easy_setopt(OPT_POSTFIELDS, body.cstring)

    let headers = args{"headers"}
    slist = buildSlist(headers)
    if slist != nil:
      discard curl.easy_setopt(OPT_HTTPHEADER, slist)

    let cainfo = args{"cainfo"}.getStr("")
    if cainfo.len > 0:
      discard curl.easy_setopt(OPT_CAINFO, cainfo.cstring)

    let capath = args{"capath"}.getStr("")
    if capath.len > 0:
      discard curl.easy_setopt(OPT_CAPATH, capath.cstring)

    let cert = args{"cert"}.getStr("")
    if cert.len > 0:
      discard curl.easy_setopt(OPT_SSLCERT, cert.cstring)

    let certtype = args{"certtype"}.getStr("")
    if certtype.len > 0:
      discard curl.easy_setopt(OPT_SSLCERTTYPE, certtype.cstring)

    let key = args{"key"}.getStr("")
    if key.len > 0:
      discard curl.easy_setopt(OPT_SSLKEY, key.cstring)

    let keytype = args{"keytype"}.getStr("")
    if keytype.len > 0:
      discard curl.easy_setopt(OPT_SSLKEYTYPE, keytype.cstring)

    let keypasswd = args{"keypasswd"}.getStr("")
    if keypasswd.len > 0:
      discard curl.easy_setopt(OPT_SSLKEYPASSWD, keypasswd.cstring)

    if args{"insecure"}.getBool(false):
      discard curl.easy_setopt(OPT_SSL_VERIFYPEER, 0)
      discard curl.easy_setopt(OPT_SSL_VERIFYHOST, 0)

    let dnsServers = args{"dns_servers"}.getStr("")
    if dnsServers.len > 0:
      discard curl.easy_setopt(optDnsServers, dnsServers.cstring)

    let resolve = args{"resolve"}
    if resolve != nil:
      case resolve.kind
      of JArray:
        for item in resolve.items:
          let entry = item.getStr("")
          if entry.len > 0:
            resolveList = slist_append(resolveList, entry.cstring)
      of JString:
        let entry = resolve.getStr("")
        if entry.len > 0:
          resolveList = slist_append(resolveList, entry.cstring)
      else: discard
    if resolveList != nil:
      discard curl.easy_setopt(optResolve, resolveList)

    let proxy = args{"proxy"}.getStr("")
    if proxy.len > 0:
      discard curl.easy_setopt(OPT_PROXY, proxy.cstring)

    let proxyUserpwd = args{"proxy_userpwd"}.getStr("")
    if proxyUserpwd.len > 0:
      discard curl.easy_setopt(OPT_PROXYUSERPWD, proxyUserpwd.cstring)

    let userpwd = args{"userpwd"}.getStr("")
    if userpwd.len > 0:
      discard curl.easy_setopt(OPT_USERPWD, userpwd.cstring)

    let useragent = args{"useragent"}.getStr("")
    if useragent.len > 0:
      discard curl.easy_setopt(OPT_USERAGENT, useragent.cstring)

    discard curl.easy_setopt(OPT_WRITEFUNCTION, bodyCallback)
    discard curl.easy_setopt(OPT_HEADERFUNCTION, headerCallback)

    let ret = easy_perform(curl)
    if ret != E_OK:
      return jsonRpcResult(newJNull(), %*{
        "content": [{"type": "text", "text": $easy_strerror(ret)}],
        "isError": true
      })

    discard curl.easy_getinfo(INFO_RESPONSE_CODE, addr httpCode)
    discard curl.easy_getinfo(INFO_EFFECTIVE_URL, addr effUrl)

    let finalUrl =
      if effUrl != nil: $effUrl
      else: url

    result = jsonRpcResult(newJNull(), %*{
      "content": [{"type": "text", "text": gBodyBuf}],
      "structuredContent": formatResponse(httpCode.int, finalUrl, gHeaderBuf, gBodyBuf),
      "isError": false
    })
  finally:
    if slist != nil: slist_free_all(slist)
    if resolveList != nil: slist_free_all(resolveList)
    easy_cleanup(curl)

proc handleToolsCall(id: JsonNode; params: JsonNode): JsonNode =
  let toolName = params{"name"}.getStr("")
  let args = params{"arguments"}
  if args == nil or args.kind != JObject:
    return jsonRpcError(id, -32602, "Invalid arguments")

  let url = args{"url"}.getStr("")
  if url == "":
    return jsonRpcError(id, -32602, "Missing required argument: url")

  let httpMethod = case toolName
    of "curl_get":     "GET"
    of "curl_post":    "POST"
    of "curl_put":     "PUT"
    of "curl_patch":   "PATCH"
    of "curl_delete":  "DELETE"
    of "curl_head":    "HEAD"
    of "curl_request": args{"method"}.getStr("GET").toUpperAscii
    else: return jsonRpcResult(id, %*{
      "content": [{"type": "text", "text": "Unknown tool: " & toolName}],
      "isError": true
    })

  result = doRequest(httpMethod, url, args)
  result["id"] = id

proc handleRequest(msg: JsonNode): JsonNode =
  let mcpMethod = msg{"method"}.getStr("")
  let id = msg{"id"}

  case mcpMethod
  of "initialize": handleInitialize(id, msg{"params"})
  of "ping":       handlePing(id)
  of "tools/list": handleToolsList(id)
  of "tools/call": handleToolsCall(id, msg{"params"})
  else: jsonRpcError(id, -32601, "Method not found: " & mcpMethod)

iterator lines(sin: Stream): string =
  while true:
    try:
      let line = sin.readLine.strip
      if line.len > 0:
        yield line
    except:
      break

proc connect(sin, sout: Stream): void =
  for line in sin.lines:
    let msg = try: parseJson(line) except: newJNull()
    if msg.kind != JObject:
      continue

    let mcpMethod = msg{"method"}.getStr("")

    if mcpMethod in ["notifications/initialized", "notifications/cancelled"]:
      continue

    if msg.contains("id"):
      let resp = handleRequest(msg)
      write sout, $resp & "\n"
      sout.flush

proc main*(params: seq[string]; sin, sout, serr: Stream): void =
  discard global_init(GLOBAL_DEFAULT)
  connect(sin, sout)
  global_cleanup()

when isMainModule:
  var params = newSeq[string]()
  for i in 1..paramCount():
    params.add i.paramStr
  params.main stdin.newFileStream, stdout.newFileStream, stderr.newFileStream
