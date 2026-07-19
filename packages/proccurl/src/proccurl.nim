import std/[json,syncio,strutils,options,streams]
import curly


const STDIO_JSONL_JSONRPC*         = "stdio-v1+jsonl-v1+json-rpc-v2"
const STDIO_JSONL_JSONRPC_HELP*    = staticRead "../PROTOCOLS/STDIO-v1_JSONL-v1_JSON-RPC-v2_OPEN-RPC-v1.md"
const STDIO_JSONL_JSONRPC_OPENRPC* = staticRead "../PROTOCOLS/STDIO-v1_JSONL-v1_JSON-RPC-v2_OPEN-RPC-v1.json"
const STDIO_JSONL_JSONRPC_ERR      = """
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": 0,
    "message": "",
    "data": {}
  }
}
"""
const STDIO_JSONL_JSONRPC_OK       = """
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "code": 0,
    "url":  "",
    "body": ""
  }
}
"""
const UNKNOWN_COMMAND_OR_PROTOCOL*  = """
Unknown command or protocol!!
List of protocols: `proccurl protocols`
Protocol details:  `proccurl protocols --protocol {protocol}`
Connect protocol:  `proccurl connect   --protocol {protocol}`
"""


proc buildError*(msg: JsonNode; code: int; message: string; id: JsonNode = newJNull()): JsonNode =
  result = parseJson STDIO_JSONL_JSONRPC_ERR
  result["id"] =
    if msg != nil and msg.kind == JObject and msg.contains("id"):
      msg["id"]
    else:
      id
  result["error"]["code"]    = %code
  result["error"]["message"] = %message
  result["error"]["data"]    = msg


proc buildSuccess*(id: JsonNode; code: int; url, body: string; headers: HttpHeaders = emptyHttpHeaders()): JsonNode =
  result = parseJson STDIO_JSONL_JSONRPC_OK
  result["id"] = id
  result["result"]["code"]    = %code
  result["result"]["url"]     = %url
  result["result"]["headers"] = block:
    var hdrs = %* {}
    for kv in headers.items:
      hdrs{kv[0]} = % kv[1]
    hdrs
  result["result"]["body"]    = block:
    try:
      body.parseJson
    except:
      %body

proc getHeaders*(msg: JsonNode): HttpHeaders =
  result = emptyHttpHeaders()
  if msg.contains("params") and
     msg["params"].contains("headers") and
     msg["params"]["headers"].kind == JObject:
    var hdrs = newSeq[(string, string)]()
    for k, n in msg["params"]["headers"].pairs:
      hdrs.add((k, n.getStr))
    if hdrs.len > 0:
      result = hdrs.toWebby


proc getMethod*(msg: JsonNode): string =
  if msg == nil or
   msg.kind != JObject or
   not(msg.contains("method")) or
   not(msg["method"].kind == JString) or
   not(msg["method"].getStr in [
     "/_API/v1", "/curl/v0/get", "/curl/v0/post", "/curl/v0/batch"
   ]):
     ""
  else:
    msg["method"].getStr

proc getUrl* (msg: JsonNode): string =
  if msg.contains("params") and msg["params"].contains("url"):
    msg["params"]["url"].getStr
  else:
    ""
proc getBody*(msg: JsonNode): string =
  if msg.contains("params") and msg["params"].contains("body"):
    msg["params"]["body"].getStr
  else:
    ""

proc handleMethod*(batch: var RequestBatch; msg: JsonNode): JsonNode =
  result = newJNull()
  let meth = msg.getMethod
  if meth == "":
    return buildError(msg, -32601, "Method not found")
  elif meth in ["/curl/v0/get", "/curl/v0/post", "/curl/v0/batch"] and not(msg.contains "params"):
    return buildError(msg, -32601, "Invalid method parameters, no params found")
  elif meth in ["/curl/v0/get", "/curl/v0/post"] and not msg["params"].contains "url":
    return buildError(msg, -32601, "Invalid method parameters, no param url found")
  elif meth in ["/curl/v0/post"] and not(msg["params"].contains "body"):
    return buildError(msg, -32601, "Invalid method parameters, no param body found")
  elif meth in ["/curl/v0/post"] and msg["params"]["body"].kind != JString:
    return buildError(msg, -32601, "Invalid method parameters, body should be a string")
  elif meth in ["/curl/v0/batch"] and (not(msg["params"].contains "requests") or msg["params"]["requests"].kind != JArray):
    return buildError(msg, -32601, "Invalid method parameters, requests should be an array")
  elif meth == "/_API/v1":
    result = parseJson STDIO_JSONL_JSONRPC_OPENRPC
    if msg.contains("id"):
      result["id"] = msg["id"]
    return result
  elif meth == "/curl/v0/get":
    batch.get(
        msg.getUrl,
        headers= msg.getHeaders,
        tag=     $msg["id"])
  elif meth == "/curl/v0/post":
    batch.post(
        msg.getUrl,
        body=    msg.getBody,
        headers= msg.getHeaders,
        tag=     $msg["id"])
  elif meth == "/curl/v0/batch":
    for req in msg["params"]["requests"].items:
      let id =
        if req.contains "id":
          req["id"]
        else:
          newJNull()
      if "/curl/v0/get" == req.getMethod:
        batch.get(
          req.getUrl,
          headers= req.getHeaders,
          tag=     $id)
      elif "/curl/v0/post" == req.getMethod:
        batch.post(
          req.getUrl,
          body=    req.getBody,
          headers= req.getHeaders,
          tag=     $id)


proc poolResponse*(sout: Stream; curl: Curly): int =
  result = 0
  let answer = curl.pollForResponse
  if answer.isSome:
    let curled = answer.get.response
    let error  = answer.get.error
    let id = parseJson curled.request.tag
    if error == "":
      write sout, $buildSuccess(id, curled.code, curled.url, curled.body, curled.headers) & "\n"
    else:
      write sout, $buildError(%*{"id": id}, -32000, error) & "\n"
    return 1


iterator getLine*(sin: Stream): string =
  while true:
    yield ""
    try:
      yield sin.readLine.strip
    except:
      break


proc connect*(sin, sout: Stream): void =
  let curl = newCurly()
  var i    = 0
  for line in sin.getLine:
    if line.len == 0:
      i -= sout.poolResponse curl
    else:
      var batch: RequestBatch
      let err = batch.handleMethod line.parseJson
      i += batch.len
      if err.kind != JNull:
        write sout, $err & "\n"
      if batch.len > 0:
        curl.startRequests batch
  while i > 0:
    i -= sout.poolResponse curl


type CliActionKind* = enum
  cakShowProtocols     ## Show Protocols list
  cakShowProtocolHelp  ## Show Protocols details
  cakConnect           ## Connect using protocol
  cakUnknown           ## Unknow args


proc parseCliArgs*(args: openArray[string]): CliActionKind =
  ## Pure function: parse CLI args into an action. No I/O, no quit.
  if args.len == 1 and args[0] == "protocols":
    return cakShowProtocols
  elif args.len == 3 and
     args[0] == "protocols" and
     args[1] == "--protocol" and
     args[2] == STDIO_JSONL_JSONRPC:
    return cakShowProtocolHelp
  if args.len == 3 and
     args[0] == "connect" and
     args[1] == "--protocol" and
     args[2] == STDIO_JSONL_JSONRPC:
    return cakConnect
  return cakUnknown


proc main*(params: seq[string], sin, sout, serr: Stream): void =
  case params.parseCliArgs
  of cakConnect:           connect(sin, sout)
  of cakShowProtocols:     sout.write STDIO_JSONL_JSONRPC
  of cakShowProtocolHelp:  sout.write STDIO_JSONL_JSONRPC_HELP
  of cakUnknown:
    serr.write UNKNOWN_COMMAND_OR_PROTOCOL
    quit 1


when isMainModule:
  import std/os
  var params = newSeq[string]()
  for i in 1..paramCount():
    params.add i.paramStr

  params.main stdin.newFileStream, stdout.newFileStream, stderr.newFileStream

