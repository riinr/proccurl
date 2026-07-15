import std/[unittest, json, strutils, streams, sequtils]
import proccurl
import curly


# ---------------------------------------------------------------------------
# buildError — pure function tests
# ---------------------------------------------------------------------------

suite "buildError":

  test "returns jsonrpc 2.0":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let resp = buildError(msg, -32000, "error msg")
    check resp["jsonrpc"].getStr == "2.0"

  test "id matches input msg id (integer)":
    let msg = %*{"jsonrpc": "2.0", "id": 42, "method": "test"}
    let resp = buildError(msg, -32000, "error msg")
    check resp["id"].getInt == 42

  test "id matches input msg id (string)":
    let msg = %*{"jsonrpc": "2.0", "id": "req-001", "method": "test"}
    let resp = buildError(msg, -32000, "error msg")
    check resp["id"].getStr == "req-001"

  test "id matches input msg id (null)":
    let msg = %*{"jsonrpc": "2.0", "id": nil, "method": "test"}
    let resp = buildError(msg, -32000, "error msg")
    check resp["id"].kind == JNull

  test "error.code matches code parameter":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let resp = buildError(msg, -32601, "some error")
    check resp["error"]["code"].getInt == -32601

  test "error.code handles zero":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let resp = buildError(msg, 0, "ok")
    check resp["error"]["code"].getInt == 0

  test "error.message matches message parameter":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let resp = buildError(msg, -32000, "Invalid method parameters, no params found")
    check resp["error"]["message"].getStr == "Invalid method parameters, no params found"

  test "error.message handles empty string":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let resp = buildError(msg, -32000, "")
    check resp["error"]["message"].getStr == ""

  test "error.data contains the original msg":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test", "params": {"url": "http://example.com"}}
    let resp = buildError(msg, -32000, "error")
    check resp["error"]["data"]["method"].getStr == "test"
    check resp["error"]["data"]["params"]["url"].getStr == "http://example.com"

  test "error.data preserves input id":
    let msg = %*{"jsonrpc": "2.0", "id": 99, "method": "test"}
    let resp = buildError(msg, -32000, "error")
    check resp["error"]["data"]["id"].getInt == 99

  test "msg is nil uses default id JNull":
    check buildError(nil, -1, "err")["id"].kind == JNull

  test "msg is array uses default id JNull":
    check buildError(%*[1,2], -1, "err")["id"].kind == JNull

  test "msg object without id uses default id JNull":
    check buildError(%*{"x":1}, -1, "err")["id"].kind == JNull

  test "explicit id used when msg is nil":
    check buildError(nil, -1, "err", %*{"my": "id"})["id"]["my"].getStr == "id"

  test "explicit id used when msg is array":
    check buildError(%*[1], -1, "err", %*42)["id"].getInt == 42


# ---------------------------------------------------------------------------
# buildSuccess — pure function tests
# ---------------------------------------------------------------------------

suite "buildSuccess":

  test "returns jsonrpc 2.0":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let resp = buildSuccess(msg["id"], 200, "http://example.com", "ok")
    check resp["jsonrpc"].getStr == "2.0"

  test "id matches input msg id (integer)":
    let msg = %*{"jsonrpc": "2.0", "id": 42, "method": "test"}
    let resp = buildSuccess(msg["id"], 200, "url", "body")
    check resp["id"].getInt == 42

  test "id matches input msg id (string)":
    let msg = %*{"jsonrpc": "2.0", "id": "req-002", "method": "test"}
    let resp = buildSuccess(msg["id"], 200, "url", "body")
    check resp["id"].getStr == "req-002"

  test "id matches input msg id (null)":
    let msg = %*{"jsonrpc": "2.0", "id": nil, "method": "test"}
    let resp = buildSuccess(msg["id"], 200, "url", "body")
    check resp["id"].kind == JNull

  test "result.code matches code parameter":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let resp = buildSuccess(msg["id"], 200, "url", "body")
    check resp["result"]["code"].getInt == 200

  test "result.code handles zero":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let resp = buildSuccess(msg["id"], 0, "url", "body")
    check resp["result"]["code"].getInt == 0

  test "result.url matches url parameter":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let resp = buildSuccess(msg["id"], 200, "http://example.com/foo", "body")
    check resp["result"]["url"].getStr == "http://example.com/foo"

  test "result.url handles empty string":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let resp = buildSuccess(msg["id"], 200, "", "body")
    check resp["result"]["url"].getStr == ""

  test "result.body matches body parameter":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let resp = buildSuccess(msg["id"], 200, "url", "response body")
    check resp["result"]["body"].getStr == "response body"

  test "result.body handles empty string":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let resp = buildSuccess(msg["id"], 200, "url", "")
    check resp["result"]["body"].getStr == ""

  test "result.body handles multi-line content":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let multiLine = "line1\nline2\nline3"
    let resp = buildSuccess(msg["id"], 200, "url", multiLine)
    check resp["result"]["body"].getStr == "line1\nline2\nline3"

  test "result.headers is empty object when no headers provided":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let resp = buildSuccess(msg["id"], 200, "http://example.com", "ok")
    check resp["result"]["headers"].kind == JObject
    check resp["result"]["headers"].len == 0

  test "result.headers present when headers parameter provided":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let hdrs = @[("Content-Type", "application/json")].toWebby
    let resp = buildSuccess(msg["id"], 200, "http://example.com", "ok", hdrs)
    check resp["result"]["headers"]["Content-Type"].getStr == "application/json"

  test "result.headers handles multiple key-value pairs":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let hdrs = @[("Content-Type", "application/json"), ("Accept", "text/html")].toWebby
    let resp = buildSuccess(msg["id"], 200, "http://example.com", "ok", hdrs)
    check resp["result"]["headers"]["Content-Type"].getStr == "application/json"
    check resp["result"]["headers"]["Accept"].getStr == "text/html"

  test "body that is valid JSON is parsed into result.body":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let resp = buildSuccess(msg["id"], 200, "url", """{"key":"val"}""")
    check resp["result"]["body"]["key"].getStr == "val"


# ---------------------------------------------------------------------------
# getHeaders — pure function tests
# ---------------------------------------------------------------------------

suite "getHeaders":

  test "no headers key returns empty headers":
    let req  = %*{"params": {"url": "http://example.com"}}
    let hdrs = getHeaders(req)
    check hdrs.toBase.len == 0

  test "headers is not a JObject returns empty headers":
    let req  = %*{"params": {"url": "http://example.com", "headers": "string"}}
    let hdrs = getHeaders(req)
    check hdrs.toBase.len == 0

  test "empty headers object returns empty headers":
    let req  = %*{"params": {"url": "http://example.com", "headers": {}}}
    let hdrs = getHeaders(req)
    check hdrs.toBase.len == 0

  test "single header key-value pair":
    let req  = %*{"params": {"url": "http://example.com", "headers": {"Content-Type": "application/json"}}}
    let hdrs = getHeaders(req)
    check hdrs["Content-Type"] == "application/json"

  test "multiple header key-value pairs":
    let req  = %*{"params": {"url": "http://example.com", "headers": {"Content-Type": "application/json", "Accept": "text/html"}}}
    let hdrs = getHeaders(req)
    check hdrs["Content-Type"] == "application/json"
    check hdrs["Accept"] == "text/html"

  test "headers with special characters in values":
    let req  = %*{"params": {"url": "http://example.com", "headers": {"Authorization": "Bearer token-123!@#", "X-Custom": "a=b&c=d"}}}
    let hdrs = getHeaders(req)
    check hdrs["Authorization"] == "Bearer token-123!@#"
    check hdrs["X-Custom"] == "a=b&c=d"


# ---------------------------------------------------------------------------
# Constants validation
# ---------------------------------------------------------------------------

suite "Constants":

  test "STDIO_JSONL_JSONRPC equals expected protocol string":
    check STDIO_JSONL_JSONRPC == "stdio-v1+jsonl-v1+json-rpc-v2"

  test "STDIO_JSONL_JSONRPC_HELP is non-empty":
    check STDIO_JSONL_JSONRPC_HELP.len > 0

  test "STDIO_JSONL_JSONRPC_HELP contains protocol keyword":
    check STDIO_JSONL_JSONRPC in STDIO_JSONL_JSONRPC_HELP

  test "STDIO_JSONL_JSONRPC_OPENRPC is non-empty":
    check STDIO_JSONL_JSONRPC_OPENRPC.len > 0

  test "STDIO_JSONL_JSONRPC_OPENRPC parses as valid JSON":
    let parsed = parseJson(STDIO_JSONL_JSONRPC_OPENRPC)
    check parsed.kind == JObject

  test "STDIO_JSONL_JSONRPC_OPENRPC contains openrpc field in result":
    let parsed = parseJson(STDIO_JSONL_JSONRPC_OPENRPC)
    check parsed["result"]["openrpc"].getStr == "1.2.1"


# ---------------------------------------------------------------------------
# handleMethod — validation paths (no HTTP calls made)
# ---------------------------------------------------------------------------

suite "handleMethod":

  var batch: RequestBatch

  test "GET with missing params returns error":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "/curl/v0/get"}
    var resp: JsonNode
    resp = batch.handleMethod(msg)
    check resp["error"]["code"].getInt == -32601
    check resp["error"]["message"].getStr == "Invalid method parameters, no params found"
    check resp["error"]["data"]["method"].getStr == "/curl/v0/get"

  test "GET with params but no url returns error":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "/curl/v0/get", "params": {}}
    var resp: JsonNode
    resp = batch.handleMethod(msg)
    check resp["error"]["code"].getInt == -32601
    check resp["error"]["message"].getStr == "Invalid method parameters, no param url found"
    check resp["error"]["data"]["method"].getStr == "/curl/v0/get"

  test "POST with missing params returns error":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "/curl/v0/post"}
    var resp: JsonNode
    resp = batch.handleMethod(msg)
    check resp["error"]["code"].getInt == -32601
    check resp["error"]["message"].getStr == "Invalid method parameters, no params found"
    check resp["error"]["data"]["method"].getStr == "/curl/v0/post"

  test "POST with params but no url returns error":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "/curl/v0/post", "params": {}}
    var resp: JsonNode
    resp = batch.handleMethod(msg)
    check resp["error"]["code"].getInt == -32601
    check resp["error"]["message"].getStr == "Invalid method parameters, no param url found"
    check resp["error"]["data"]["method"].getStr == "/curl/v0/post"

  test "POST with url but no body returns error":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "/curl/v0/post",
                 "params": {"url": "http://example.com"}}
    var resp: JsonNode
    resp = batch.handleMethod(msg)
    check resp["error"]["code"].getInt == -32601
    check resp["error"]["message"].getStr == "Invalid method parameters, no param body found"
    check resp["error"]["data"]["method"].getStr == "/curl/v0/post"

  test "POST with non-string body returns error":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "/curl/v0/post",
                 "params": {"url": "http://example.com", "body": 123}}
    var resp: JsonNode
    resp = batch.handleMethod(msg)
    check resp["error"]["code"].getInt == -32601
    check resp["error"]["message"].getStr == "Invalid method parameters, body should be a string"
    check resp["error"]["data"]["method"].getStr == "/curl/v0/post"

  test "Unknown method returns Method not found error":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "/unknown/method"}
    var resp: JsonNode
    resp = batch.handleMethod(msg)
    check resp["error"]["code"].getInt == -32601
    check resp["error"]["message"].getStr == "Method not found"
    check resp["error"]["data"]["method"].getStr == "/unknown/method"

  test "Unknown method preserves input id":
    let msg = %*{"jsonrpc": "2.0", "id": 99, "method": "/does/not/exist"}
    var resp: JsonNode
    resp = batch.handleMethod(msg)
    check resp["id"].getInt == 99

  test "Error responses always return jsonrpc 2.0":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "/curl/v0/get"}
    var resp: JsonNode
    resp = batch.handleMethod(msg)
    check resp["jsonrpc"].getStr == "2.0"

  test "_API/v1 with id preserves the id":
    let msg = %*{"jsonrpc": "2.0", "id": 42, "method": "/_API/v1"}
    var resp: JsonNode
    resp = batch.handleMethod(msg)
    check resp["id"].getInt == 42
    check resp["result"]["openrpc"].getStr == "1.2.1"

  test "_API/v1 without id uses default template id":
    let msg = %*{"jsonrpc": "2.0", "method": "/_API/v1"}
    var resp: JsonNode
    resp = batch.handleMethod(msg)
    check resp["id"].getInt == 1
    check resp["result"]["openrpc"].getStr == "1.2.1"


# ---------------------------------------------------------------------------
# handleMethod — non-JObject input
# ---------------------------------------------------------------------------

  test "non-JObject input returns error":
    let msg = %*["not", "an", "object"]
    var resp: JsonNode
    resp = batch.handleMethod(msg)
    check resp["error"]["code"].getInt == -32601
    check resp["error"]["message"].getStr == "Method not found"


suite "handleMethod batch":

  var batch: RequestBatch

  test "batch with missing params returns error":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "/curl/v0/batch"}
    var resp: JsonNode
    resp = batch.handleMethod(msg)
    check resp["error"]["code"].getInt == -32601
    check resp["error"]["message"].getStr == "Invalid method parameters, no params found"

  test "batch with missing requests returns error":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "/curl/v0/batch", "params": {}}
    var resp: JsonNode
    resp = batch.handleMethod(msg)
    check resp["error"]["code"].getInt == -32601
    check resp["error"]["message"].getStr == "Invalid method parameters, requests should be an array"

  test "batch with non-array requests returns error":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "/curl/v0/batch",
                 "params": {"requests": "not-an-array"}}
    var resp: JsonNode
    resp = batch.handleMethod(msg)
    check resp["error"]["code"].getInt == -32601
    check resp["error"]["message"].getStr == "Invalid method parameters, requests should be an array"


# ---------------------------------------------------------------------------
# parseCliArgs — pure function tests
# ---------------------------------------------------------------------------

suite "parseCliArgs":

  test "protocols returns cakShowProtocols":
    check parseCliArgs(@["protocols"]) == cakShowProtocols

  test "protocols with help flag returns cakShowProtocolHelp":
    check parseCliArgs(@["protocols", "--protocol", STDIO_JSONL_JSONRPC]) == cakShowProtocolHelp

  test "connect with protocol returns cakConnect":
    check parseCliArgs(@["connect", "--protocol", STDIO_JSONL_JSONRPC]) == cakConnect

  test "empty args returns cakUnknown":
    check parseCliArgs(newSeq[string]()) == cakUnknown

  test "unknown command returns cakUnknown":
    check parseCliArgs(@["something"]) == cakUnknown

  test "protocols with extra args returns cakUnknown":
    check parseCliArgs(@["protocols", "extra"]) == cakUnknown

  test "connect without protocol returns cakUnknown":
    check parseCliArgs(@["connect"]) == cakUnknown

  test "protocols with wrong protocol returns cakUnknown":
    check parseCliArgs(@["protocols", "--protocol", "other"]) == cakUnknown

  test "connect with wrong protocol returns cakUnknown":
    check parseCliArgs(@["connect", "--protocol", "other"]) == cakUnknown


# ---------------------------------------------------------------------------
# CliActionKind enum validation
# ---------------------------------------------------------------------------

suite "CliActionKind":

  test "cakShowProtocols is ord 0":
    check ord(cakShowProtocols) == 0

  test "cakShowProtocolHelp is ord 1":
    check ord(cakShowProtocolHelp) == 1

  test "cakConnect is ord 2":
    check ord(cakConnect) == 2

  test "cakUnknown is ord 3":
    check ord(cakUnknown) == 3



# ---------------------------------------------------------------------------
# getMethod — pure function tests
# ---------------------------------------------------------------------------

suite "getUrl/getBody":

  test "getUrl returns url from params":
    let msg = %*{"params": {"url": "http://example.com"}}
    check getUrl(msg) == "http://example.com"

  test "getUrl returns empty string when no params":
    let msg = %*{"method": "/curl/v0/get"}
    check getUrl(msg) == ""

  test "getBody returns body from params":
    let msg = %*{"params": {"url": "http://example.com", "body": "payload"}}
    check getBody(msg) == "payload"

  test "getBody returns empty string when no body":
    let msg = %*{"params": {"url": "http://example.com"}}
    check getBody(msg) == ""


suite "getMethod":

  test "nil input returns empty string":
    check getMethod(nil) == ""

  test "array input returns empty string":
    check getMethod(%*[1,2,3]) == ""

  test "string input returns empty string":
    check getMethod(%*"hello") == ""

  test "object without method key returns empty string":
    check getMethod(%*{"id": 1}) == ""

  test "method is not a string returns empty string":
    check getMethod(%*{"method": 123}) == ""

  test "unknown method returns empty string":
    check getMethod(%*{"method": "/foo/bar"}) == ""

  test "_API/v1 method returns _API/v1":
    check getMethod(%*{"method": "/_API/v1"}) == "/_API/v1"

  test "curl/v0/get method returns curl/v0/get":
    check getMethod(%*{"method": "/curl/v0/get"}) == "/curl/v0/get"

  test "curl/v0/post method returns curl/v0/post":
    check getMethod(%*{"method": "/curl/v0/post"}) == "/curl/v0/post"

  test "curl/v0/batch method returns curl/v0/batch":
    check getMethod(%*{"method": "/curl/v0/batch"}) == "/curl/v0/batch"



# ---------------------------------------------------------------------------
# connect — stdio loop integration (no-network messages only)
# ---------------------------------------------------------------------------

suite "connect":

  test "loop echoes _API/v1 response and validation error as JSONL":
    let input  = newStringStream(
      """{"jsonrpc": "2.0", "id": 1, "method": "/_API/v1"}
{"jsonrpc": "2.0", "id": 2, "method": "/curl/v0/get"}
""")
    let output = newStringStream()
    connect(input, output)
    let lines = output.data.splitLines.filterIt(it.len > 0)
    check lines.len == 2
    let first  = parseJson lines[0]
    let second = parseJson lines[1]
    check first["id"].getInt == 1
    check first["result"]["openrpc"].getStr == "1.2.1"
    check second["id"].getInt == 2
    check second["error"]["code"].getInt == -32601
    check second["error"]["message"].getStr == "Invalid method parameters, no params found"

  test "empty input yields no output":
    let input  = newStringStream("")
    let output = newStringStream()
    connect(input, output)
    check output.data.len == 0

  test "malformed JSON line is skipped without crashing":
    let input  = newStringStream("not-json\n")
    let output = newStringStream()
    connect(input, output)
    check output.data.len == 0


# ---------------------------------------------------------------------------
# main — CLI dispatch
# ---------------------------------------------------------------------------

suite "main":

  test "protocols action writes the protocol id to stdout":
    let sin   = newStringStream("")
    let sout  = newStringStream()
    let serr  = newStringStream()
    main(@["protocols"], sin, sout, serr)
    check sout.data.strip == STDIO_JSONL_JSONRPC

  test "protocols --protocol action writes the help doc":
    let sin   = newStringStream("")
    let sout  = newStringStream()
    let serr  = newStringStream()
    main(@["protocols", "--protocol", STDIO_JSONL_JSONRPC], sin, sout, serr)
    check STDIO_JSONL_JSONRPC in sout.data

  test "unknown action help constant lists protocols and connect usage":
    # main writes UNKNOWN_COMMAND_OR_PROTOCOL to stderr then quit(1) on an
    # unknown action; assert the constant it emits contains the guidance.
    check "proccurl protocols" in UNKNOWN_COMMAND_OR_PROTOCOL
    check "proccurl connect" in UNKNOWN_COMMAND_OR_PROTOCOL
    check "proccurl protocols --protocol" in UNKNOWN_COMMAND_OR_PROTOCOL





