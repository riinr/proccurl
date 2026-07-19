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
const MOCK_ELEMENT_H1 = "mock-element-4567"
const MOCK_ELEMENT_BODY = "mock-element-body"
const MOCK_ELEMENT_HTML = "mock-element-html"
const MOCK_PAGE_SOURCE = "<html><body><h1>Example Domain</h1></body></html>"
const MOCK_PAGE_TITLE = "Example Domain"
const MOCK_ELEMENT_TEXT = "Example Domain"

proc handle(meth, path: string): tuple[status, body: string] =
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
      if "/element/" in path:
        # element rect -> GET /session/<id>/element/<eid>/rect
        """{"value":{"x":0,"y":0,"width":200,"height":100}}"""
      else:
        """{"value":{"x":0,"y":0,"width":1024,"height":768}}"""
    elif path.endsWith("/element/active"):
      """{"value":{"element-6066-11e4-a52e-4f735466cecf":"""" & MOCK_ELEMENT_ID & """"}}"""
    elif path.endsWith("/element") and "/element/" in path:
      # parent-element search (findElement(el, "..", XPathSelector))
      # path: /session/<id>/element/<eid>/element
      let cur = path.split("/element/")[1].split("/")[0]
      if cur == MOCK_ELEMENT_HTML:
        # html is the root: no parent -> 404 "no such element" so the
        # toString walk terminates (findElement returns None)
        return ("HTTP/1.1 404 Not Found",
          """{"value":{"error":"no such element","message":"no such element"}}""")
      else:
        let parentId = case cur
          of MOCK_ELEMENT_BODY: MOCK_ELEMENT_HTML
          of MOCK_ELEMENT_H1:   MOCK_ELEMENT_BODY
          else:                    MOCK_ELEMENT_H1
        """{"value":{"element-6066-11e4-a52e-4f735466cecf":"""" & parentId & """"}}"""
    elif path.endsWith("/elements") and "/element/" in path:
      # preceding-sibling search (findElement(el, "preceding-sibling::*[1]", XPathSelector))
      # path: /session/<id>/element/<eid>/elements
      """{"value":[]}"""
    elif path.endsWith("/element"):
      """{"value":{"element-6066-11e4-a52e-4f735466cecf":"""" & MOCK_ELEMENT_ID & """"}}"""
    elif path.endsWith("/alert/text") or path.endsWith("/alert_text"):
      """{"value":"You are in a dialogs! I've seen... not much."}"""
    elif path.endsWith("/name"):
      # tagName() -> GET /session/<id>/element/<eid>/name
      let eid = path.split("/element/")[1].split("/")[0]
      let tag = case eid
        of MOCK_ELEMENT_H1:   "h1"
        of MOCK_ELEMENT_BODY: "body"
        of MOCK_ELEMENT_HTML: "html"
        else:                    "div"
      """{"value":"""" & tag & """"}"""
    elif path.endsWith("/text"):
      """{"value":"""" & MOCK_ELEMENT_TEXT & """"}"""
    elif "/element/" in path and path.endsWith("/screenshot"):
      # element screenshot -> POST /session/<id>/element/<eid>/screenshot
      """{"value":"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M8AAAMCAQDJ/3pUAAAAAElFTkSuQmCC"}"""
    elif "/element/" in path and path.endsWith("/selected"):
      # element selected -> GET /session/<id>/element/<eid>/selected
      """{"value":true}"""
    elif "/attribute/" in path:
      """{"value":"mock-attribute-value"}"""
    elif "/property/" in path:
      """{"value":"mock-property-value"}"""
    elif "/css/" in path:
      """{"value":"mock-css-value"}"""
    elif path.endsWith("/enabled"):
      """{"value":true}"""
    elif path.endsWith("/displayed"):
      """{"value":true}"""
    elif path.endsWith("/alert/accept") or path.endsWith("/accept_alert"):
      """{"value":null}"""
    elif path.endsWith("/cookie"):
      """{"value":[{"name":"test","value":"test_value","path":"/","domain":"example.com","secure":false,"httpOnly":true}]}"""
    elif "/cookie/" in path:
      """{"value":{"name":"test","value":"test_value","path":"/","domain":"example.com","secure":false,"httpOnly":true}}"""
    else:
      """{"value":null}"""
  result = ("HTTP/1.1 200 OK", body)

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
      let full = resp.status & "\r\nContent-Length: " & $resp.body.len &
        "\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n" & resp.body
      discard conn.send(full.cstring, full.len)
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
