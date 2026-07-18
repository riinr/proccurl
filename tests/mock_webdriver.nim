## Standalone mock W3C WebDriver HTTP server, used by
## `tests/test_webdrivermcp.nim` so the suite is self-contained (no real
## Selenium/Geckodriver needed). It listens on an ephemeral localhost port,
## prints `MOCKPORT=<port>` to stdout on the first line, then answers the small
## subset of the WebDriver protocol that `src/webdrivermcp.nim` exercises:
##   GET  /status                       -> {"value":{"ready":true}}
##   POST /session                      -> {"value":{"sessionId": <id>}}
##   DELETE /session/<id>               -> {"value": null}
##   GET  /session/<id>/url              -> {"value": "<current url>"}
##   POST /session/<id>/url             -> {"value": null}
##   POST /session/<id>/back            -> {"value": null}
##   GET  /session/<id>/source          -> {"value": "<html>..."}
##   GET  /session/<id>/title           -> {"value": "<title>"}
##   GET  /session/<id>/element/active  -> {"value":{"element-...-cf":<eid>}}
##   GET  /session/<id>/window/rect     -> {"value": {x,y,width,height}}
##   POST /session/<id>/element         -> {"value":{"element-...-cf": <eid>}}
##   POST /session/<id>/alert/accept    -> {"value":null}
##   POST /session/<id>/accept_alert    -> {"value":null}
##   GET  /session/<id>/alert/text          -> {"value": "<alert text>"}
##   GET  /session/<id>/alert_text          -> {"value": "<alert text>"}
##   GET  /session/<id>/element/<eid>/text        -> {"value": "<text>"}
##   GET  /session/<id>/element/<eid>/attribute/<n> -> {"value": "<attr-val>"}
##   GET  /session/<id>/cookie                    -> {"value": [{"name":"...","value":"..."}]}

import std/[net, os, strutils, typedthreads]

const MOCK_SESSION_ID = "mock-session-0123"
const MOCK_ELEMENT_ID = "mock-element-4567"
const MOCK_PAGE_SOURCE = "<html><body><h1>Example Domain</h1></body></html>"
const MOCK_PAGE_TITLE = "Example Domain"
const MOCK_ELEMENT_TEXT = "Example Domain"

proc handle(meth, path: string): string =
  let body = case path
  of "/status":
    """{"value":{"ready":true,"message":"mock ready"}}"""
  of "/session":
    """{"value":{"sessionId":"""" & MOCK_SESSION_ID & """"}}"""
  else:
    if path.endsWith("/back"):
      """{"value":null}"""
    elif path.endsWith("/url"):
      if meth == "GET":
        """{"value":"https://example.com"}"""
      else:
        """{"value":null}"""
    elif path.endsWith("/source"):
      """{"value":"""" & MOCK_PAGE_SOURCE & """"}"""
    elif path.endsWith("/title"):
      """{"value":"""" & MOCK_PAGE_TITLE & """"}"""
    elif path.endsWith("/rect"):
      """{"value":{"x":0,"y":0,"width":1024,"height":768}}"""
    elif path.endsWith("/element/active"):
      """{"value":{"element-6066-11e4-a52e-4f735466cecf":"""" & MOCK_ELEMENT_ID & """"}}"""
    elif path.endsWith("/element"):
      """{"value":{"element-6066-11e4-a52e-4f735466cecf":"""" & MOCK_ELEMENT_ID & """"}}"""
    elif path.endsWith("/alert/text") or path.endsWith("/alert_text"):
      """{"value":"You are in a dialogs! I've seen... not much."}"""
    elif path.endsWith("/text"):
      """{"value":"""" & MOCK_ELEMENT_TEXT & """"}"""
    elif "/attribute/" in path:
      """{"value":"mock-attribute-value"}"""
    elif path.endsWith("/alert/accept") or path.endsWith("/accept_alert"):
      """{"value":null}"""
    elif path.endsWith("/cookie"):
      """{"value":[{"name":"test","value":"test_value","path":"/","domain":"example.com","secure":false,"httpOnly":true}]}"""
    elif "/cookie/" in path:
      """{"value":{"name":"test","value":"test_value","path":"/","domain":"example.com","secure":false,"httpOnly":true}}"""
    else:
      """{"value":null}"""
  "HTTP/1.1 200 OK\r\nContent-Length: " & $body.len &
    "\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n" & body

proc readHttpRequest(conn: Socket): tuple[meth, path: string] =
  var line: string
  conn.readLine(line)
  if line.strip.len == 0:
    return ("", "")
  let parts = line.splitWhitespace()
  if parts.len < 2:
    return ("", "")
  result.meth = parts[0]
  result.path = parts[1]
  var h: string
  while true:
    conn.readLine(h)
    if h.strip.len == 0:
      break

proc loop(server: Socket) {.thread.} =
  while true:
    var conn: owned(Socket)
    try:
      server.accept(conn)
    except:
      break
    if conn == nil:
      continue
    let req = conn.readHttpRequest
    if req.meth.len > 0:
      let resp = handle(req.meth, req.path)
      var rb = resp
      discard conn.send(rb.cstring, rb.len)
    conn.close()

var server = newSocket()
server.bindAddr(Port(0), "127.0.0.1")
server.listen()
let port = server.getLocalAddr()[1]
echo "MOCKPORT=" & $port.int
var t: Thread[Socket]
createThread(t, loop, server)
while true:
  sleep(1_000_000)
