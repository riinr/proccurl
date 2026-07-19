import std/[osproc, json, tables, streams]

type
  McpcurlClient* = ref object
    procHandle: Process
    idCounter: int

  HttpHeaders* = Table[string, string]

  HttpResponse* = object
    status*: int
    url*: string
    headers*: HttpHeaders
    body*: JsonNode

  McpcurlError* = object of CatchableError
    code*: int

  Option* = object
    headers*: HttpHeaders
    timeout*: int
    connectTimeout*: int
    body*: string
    cainfo*: string
    capath*: string
    cert*: string
    certtype*: string
    key*: string
    keytype*: string
    keypasswd*: string
    insecure*: bool
    dnsServers*: string
    resolve*: string
    proxy*: string
    proxyUserpwd*: string
    userpwd*: string
    useragent*: string

proc toJson(opt: Option): JsonNode =
  result = %*{}
  if opt.headers.len > 0:
    var h = %*{}
    for k, v in opt.headers:
      h[k] = %v
    result["headers"] = h
  if opt.timeout > 0: result["timeout"] = %opt.timeout
  if opt.connectTimeout > 0: result["connect_timeout"] = %opt.connectTimeout
  if opt.body.len > 0: result["body"] = %opt.body
  if opt.cainfo.len > 0: result["cainfo"] = %opt.cainfo
  if opt.capath.len > 0: result["capath"] = %opt.capath
  if opt.cert.len > 0: result["cert"] = %opt.cert
  if opt.certtype.len > 0: result["certtype"] = %opt.certtype
  if opt.key.len > 0: result["key"] = %opt.key
  if opt.keytype.len > 0: result["keytype"] = %opt.keytype
  if opt.keypasswd.len > 0: result["keypasswd"] = %opt.keypasswd
  if opt.insecure: result["insecure"] = %true
  if opt.dnsServers.len > 0: result["dns_servers"] = %opt.dnsServers
  if opt.resolve.len > 0: result["resolve"] = %opt.resolve
  if opt.proxy.len > 0: result["proxy"] = %opt.proxy
  if opt.proxyUserpwd.len > 0: result["proxy_userpwd"] = %opt.proxyUserpwd
  if opt.userpwd.len > 0: result["userpwd"] = %opt.userpwd
  if opt.useragent.len > 0: result["useragent"] = %opt.useragent

proc initOption*(): Option =
  result = Option(timeout: 60)

proc call(client: McpcurlClient; mcpMethod: string; params: JsonNode = newJNull()): JsonNode =
  let id = client.idCounter
  inc client.idCounter
  let req = %*{
    "jsonrpc": "2.0",
    "id": id,
    "method": mcpMethod
  }
  if params != nil and params.kind != JNull:
    req["params"] = params
  client.procHandle.inputStream.writeLine($req)
  client.procHandle.inputStream.flush
  let line = client.procHandle.outputStream.readLine
  if line.len == 0:
    raise newException(McpcurlError, "Empty response from mcpcurl")
  let resp = parseJson(line)
  if resp{"id"}.getInt != id:
    raise newException(McpcurlError, "Response ID mismatch")
  resp

proc newMcpcurlClient*(binaryPath: string): McpcurlClient =
  let procHandle = startProcess(
    binaryPath,
    options = {poUsePath, poStdErrToStdOut}
  )
  result = McpcurlClient(procHandle: procHandle, idCounter: 1)
  let resp = result.call("initialize", %*{
    "protocolVersion": "2025-06-18",
    "capabilities": {},
    "clientInfo": {"name": "mcpcurlclient", "version": "0.1.0"}
  })
  if resp.contains("error"):
    raise newException(McpcurlError, "Initialize failed: " & resp["error"]["message"].getStr())

proc close*(client: McpcurlClient) =
  if client.procHandle != nil:
    client.procHandle.close

proc toolCall(client: McpcurlClient; toolName, url: string; opt: Option = initOption(); extra: JsonNode = nil): HttpResponse =
  var params = %*{"name": toolName, "arguments": {"url": %url}}
  let optJson = opt.toJson
  for k, v in optJson.pairs:
    params["arguments"][k] = v
  if extra != nil:
    for k, v in extra.pairs:
      params["arguments"][k] = v
  let resp = client.call("tools/call", params)
  if resp.contains("error"):
    var e = newException(McpcurlError, resp["error"]["message"].getStr())
    e.code = resp["error"]["code"].getInt
    raise e
  let content = resp{"result", "content"}
  if content.len > 0 and content[0]{"type"}.getStr == "text":
    let rawText = content[0]{"text"}.getStr
    let structured = resp{"result", "structuredContent"}
    if structured != nil and structured.kind == JObject:
      var hdrs: HttpHeaders
      if structured{"headers"} != nil:
        for k, v in structured{"headers"}.pairs:
          hdrs[k] = v.getStr
      result = HttpResponse(
        status: structured{"status"}.getInt,
        url: structured{"url"}.getStr,
        headers: hdrs,
        body: structured{"body"}
      )
    else:
      let parsed =
        try: parseJson(rawText)
        except: %rawText
      result = HttpResponse(status: 0, body: parsed)
  else:
    result = HttpResponse(status: 0, body: %*{})

proc get*(client: McpcurlClient; url: string; opt: Option = initOption()): HttpResponse =
  client.toolCall("curl_get", url, opt)

proc post*(client: McpcurlClient; url: string; opt: Option = initOption()): HttpResponse =
  client.toolCall("curl_post", url, opt)

proc put*(client: McpcurlClient; url: string; opt: Option = initOption()): HttpResponse =
  client.toolCall("curl_put", url, opt)

proc patch*(client: McpcurlClient; url: string; opt: Option = initOption()): HttpResponse =
  client.toolCall("curl_patch", url, opt)

proc delete*(client: McpcurlClient; url: string; opt: Option = initOption()): HttpResponse =
  client.toolCall("curl_delete", url, opt)

proc head*(client: McpcurlClient; url: string; opt: Option = initOption()): HttpResponse =
  client.toolCall("curl_head", url, opt)

proc request*(client: McpcurlClient; httpMethod, url: string; opt: Option = initOption()): HttpResponse =
  client.toolCall("curl_request", url, opt, %*{"method": %httpMethod})
