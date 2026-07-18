## webdrivermcp -- Model Context Protocol server exposing the `halonium`
## library (github.com/halonium/halonium) as tools.
##
## Each public method of the halonium WebDriver API is exposed as an MCP tool:
##   - wd_new_web_driver  : create a WebDriver pointing at a remote URL
##   - wd_create_session  : start a browsing session
##   - wd_close_session   : close a browsing session
##   - wd_navigate        : navigate the session to a URL
##   - wd_get_page_source : fetch the current page source
##   - wd_find_element    : locate an element by selector + strategy
##   - wd_get_text        : read an element's visible text
##
## Sessions are tracked per `sessionId` so a single server process can serve
## multiple tool/call requests that share state (navigate then find then read).
##
## The transport is line-delimited JSON-RPC over stdio, exactly like
## `mcpcurl.nim`. Run it with `./bin/webdrivermcp`.

import std/[json, streams, strutils, tables, os, options, sequtils]
import halonium

const MCP_PROTOCOL_VERSION* = "2025-06-18"

type Tool = object
  name: string
  description: string
  inputSchema: JsonNode

# State shared across tool calls in a single server process.
var gWebDriver: WebDriver
var gSessions: Table[string, Session]
var gElements: Table[string, Element]

proc toolSchema(properties: openArray[(string, string, string)];
                required: openArray[string]): JsonNode =
  result = %*{"type": "object", "properties": {}, "required": []}
  for (name, typ, desc) in properties:
    result["properties"][name] = %*{"type": typ, "description": desc}
  for name in required:
    result["required"].add %name

proc defineTools(): seq[Tool] =
  result = @[
    Tool(
      name: "wd_new_web_driver",
      description: "Create a WebDriver client pointing at a remote driver URL",
      inputSchema: toolSchema(
        [("url", "string", "Remote WebDriver URL (default: http://localhost:4444)"),
         ("browser", "string", "Browser kind: firefox, chrome, edge (default: firefox)")],
        [])),
    Tool(
      name: "wd_create_session",
      description: "Create a new browsing session on the WebDriver",
      inputSchema: toolSchema([], [])),
    Tool(
      name: "wd_close_session",
      description: "Close a browsing session by its id",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id returned by wd_create_session")],
        ["session_id"])),
    Tool(
      name: "wd_navigate",
      description: "Navigate a session to a URL",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id"),
         ("url", "string", "URL to navigate to")],
        ["session_id", "url"])),
    Tool(
      name: "wd_get_page_source",
      description: "Get the current page source of a session",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id")],
        ["session_id"])),
    Tool(
      name: "wd_find_element",
      description: "Find an element in a session using a location strategy",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id"),
         ("selector", "string", "Selector value (e.g. CSS or XPath)"),
         ("strategy", "string", "Location strategy: css, xpath, link_text, partial_link_text, name, tag_name, class_name (default: css)")],
        ["session_id", "selector"])),
    Tool(
      name: "wd_get_text",
      description: "Get the visible text of a previously found element",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id"),
         ("element_id", "string", "Element id returned by wd_find_element")],
        ["session_id", "element_id"])),
    Tool(
      name: "wd_accept_alert",
      description: "Accept a JavaScript alert dialog in the current session",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id")],
        ["session_id"])),
    Tool(
      name: "wd_dismiss_alert",
      description: "Dismiss a JavaScript alert dialog in the current session",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id")],
        ["session_id"])),
    Tool(
      name: "wd_alert_text",
      description: "Get the text of a JavaScript alert dialog in the current session",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id")],
        ["session_id"])),
    Tool(
      name: "wd_all_cookies",
      description: "Get all cookies for the current session",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id")],
        ["session_id"])),
    Tool(
      name: "wd_get_cookie",
      description: "Get a specific cookie by name in the current session",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id"),
         ("name", "string", "Cookie name to get")],
        ["session_id", "name"])),
    Tool(
      name: "wd_delete_all_cookies",
      description: "Delete all cookies in the current session",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id")],
        ["session_id"])),
    Tool(
      name: "wd_delete_cookie",
      description: "Delete a specific cookie by name in the current session",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id"),
         ("name", "string", "Cookie name to delete")],
        ["session_id", "name"])),
    Tool(
      name: "wd_forward",
      description: "Navigate forward in the browser history",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id")],
        ["session_id"])),
    Tool(
      name: "wd_back",
      description: "Navigate back in the browser history",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id")],
        ["session_id"])),
    Tool(
      name: "wd_refresh",
      description: "Refresh the current page",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id")],
        ["session_id"])),
    Tool(
      name: "wd_current_url",
      description: "Get the current URL of the session",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id")],
        ["session_id"])),
    Tool(
      name: "wd_running",
      description: "Check whether the browser is running",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id")],
        ["session_id"])),
    Tool(
      name: "wd_status",
      description: "Get the WebDriver status (message and ready state)",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id")],
        ["session_id"])),
    Tool(
      name: "wd_title",
      description: "Get the current page title",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id")],
        ["session_id"])),
    Tool(
      name: "wd_width",
      description: "Get the current window width in pixels",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id")],
        ["session_id"])),
    Tool(
      name: "wd_y",
      description: "Get the current window y-coordinate in pixels",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id")],
        ["session_id"])),
    Tool(
      name: "wd_rect",
      description: "Get the current window rect (x, y, width, height)",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id")],
        ["session_id"])),
    Tool(
      name: "wd_visible_text",
      description: "Get the visible text of the first element matching the CSS selector",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id"),
         ("css_selector", "string", "CSS selector to find the element")],
        ["session_id", "css_selector"])),
    Tool(
      name: "wd_active_element",
      description: "Get the visible text of the currently focused element",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id")],
        ["session_id"])),
    Tool(
      name: "wd_attribute",
      description: "Get the value of an attribute on the first element matching the CSS selector",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id"),
         ("css_selector", "string", "CSS selector to find the element"),
         ("attr_name", "string", "Name of the attribute to retrieve")],
        ["session_id", "css_selector", "attr_name"])),
    Tool(
      name: "wd_clear",
      description: "Clear the content of the first element matching the CSS selector",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id"),
         ("css_selector", "string", "CSS selector to find the element")],
        ["session_id", "css_selector"])),
    Tool(
      name: "wd_click",
      description: "Click on the first element matching the CSS selector using the specified mouse button",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id"),
         ("css_selector", "string", "CSS selector to find the element"),
         ("button", "string", "Mouse button: mbLeft, mbMiddle, or mbRight (default: mbLeft)")],
        ["session_id", "css_selector"])),
    Tool(
      name: "wd_double_click",
      description: "Double-click on the first element matching the CSS selector using the specified mouse button",
      inputSchema: toolSchema(
        [("session_id", "string", "Session id"),
         ("css_selector", "string", "CSS selector to find the element"),
         ("button", "string", "Mouse button: mbLeft, mbMiddle, or mbRight (default: mbLeft)")],
        ["session_id", "css_selector"])),
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

proc contentResult(id: JsonNode; text: string): JsonNode =
  jsonRpcResult(id, %*{
    "content": [{"type": "text", "text": text}],
    "structuredContent": {"text": text},
    "isError": false
  })

proc handleInitialize(id: JsonNode; params: JsonNode): JsonNode =
  jsonRpcResult(id, %*{
    "protocolVersion": MCP_PROTOCOL_VERSION,
    "capabilities": {"tools": {}},
    "serverInfo": {"name": "webdrivermcp", "version": "0.1.0"}
  })

proc handlePing(id: JsonNode): JsonNode =
  jsonRpcResult(id, %*{})

proc handleToolsList(id: JsonNode): JsonNode =
  let tools = defineTools()
  var toolList = newJArray()
  for t in tools:
    toolList.add(%*{
      "name": t.name,
      "description": t.description,
      "inputSchema": t.inputSchema
    })
  jsonRpcResult(id, %*{"tools": toolList})

proc getSession(id: JsonNode; args: JsonNode): Session =
  let sid = args{"session_id"}.getStr("")
  if sid == "":
    raise newException(WebDriverException, "Missing required argument: session_id")
  if not gSessions.hasKey(sid):
    raise newException(WebDriverException, "Unknown session_id: " & sid)
  result = gSessions[sid]

proc getBrowserKind(s: string): BrowserKind =
  case s.normalize
  of "firefox", "ff": Firefox
  of "chrome", "chromium": Chrome
  of "edge": Edge
  else: Firefox

proc getStrategy(s: string): LocationStrategy =
  case s.normalize
  of "css", "css selector": CssSelector
  of "xpath": XPathSelector
  of "link_text", "link text": LinkTextSelector
  of "partial_link_text", "partial link text": PartialLinkTextSelector
  of "name": NameSelector
  of "tag_name", "tag name": TagNameSelector
  of "class_name", "class name": ClassNameSelector
  else: CssSelector

proc handleToolsCall(id: JsonNode; params: JsonNode): JsonNode =
  let toolName = params{"name"}.getStr("")
  let args = params{"arguments"}
  if args == nil or args.kind != JObject:
    return jsonRpcError(id, -32602, "Invalid arguments")

  try:
    case toolName
    of "wd_new_web_driver":
      let url = args{"url"}.getStr("http://localhost:4444")
      let browser = getBrowserKind(args{"browser"}.getStr("firefox"))
      gWebDriver = newRemoteWebDriver(browser, url)
      result = contentResult(id, "webdriver created for " & url & " (" & $browser & ")")

    of "wd_create_session":
      if gWebDriver == nil:
        gWebDriver = newRemoteWebDriver(Firefox)
      let session = gWebDriver.createRemoteSession()
      gSessions[session.id] = session
      result = contentResult(id, session.id)

    of "wd_close_session":
      let session = getSession(id, args)
      session.close()
      gSessions.del(session.id)
      result = contentResult(id, "session closed: " & session.id)

    of "wd_navigate":
      let session = getSession(id, args)
      let url = args{"url"}.getStr("")
      if url == "":
        return jsonRpcError(id, -32602, "Missing required argument: url")
      session.navigate(url)
      result = contentResult(id, "navigated to " & url)

    of "wd_get_page_source":
      let session = getSession(id, args)
      let src = session.pageSource()
      result = contentResult(id, src)

    of "wd_find_element":
      let session = getSession(id, args)
      let selector = args{"selector"}.getStr("")
      if selector == "":
        return jsonRpcError(id, -32602, "Missing required argument: selector")
      let strategy = getStrategy(args{"strategy"}.getStr("css"))
      let elOpt = session.findElement(selector, strategy)
      if elOpt.isNone:
        return jsonRpcError(id, -32602, "No element found for: " & selector)
      let el = elOpt.get
      gElements[el.id] = el
      result = contentResult(id, el.id)

    of "wd_get_text":
      let session = getSession(id, args)
      let eid = args{"element_id"}.getStr("")
      if eid == "":
        return jsonRpcError(id, -32602, "Missing required argument: element_id")
      if not gElements.hasKey(eid):
        return jsonRpcError(id, -32602, "Unknown element_id: " & eid)
      let text = gElements[eid].visibleText()
      result = contentResult(id, text)

    of "wd_accept_alert":
      let session = getSession(id, args)
      session.acceptAlert()
      result = contentResult(id, "alert accepted")

    of "wd_dismiss_alert":
      let session = getSession(id, args)
      session.dismissAlert()
      result = contentResult(id, "alert dismissed")

    of "wd_alert_text":
      let session = getSession(id, args)
      let text = session.alertText()
      result = contentResult(id, text)

    of "wd_all_cookies":
      let session = getSession(id, args)
      let cookies = session.allCookies()
      let lines = cookies.mapIt(it.name & "=" & it.value)
      result = contentResult(id, lines.join("\n"))

    of "wd_delete_all_cookies":
      let session = getSession(id, args)
      session.deleteAllCookies()
      result = contentResult(id, "all cookies deleted")

    of "wd_delete_cookie":
      let session = getSession(id, args)
      let name = args["name"].getStr()
      session.deleteCookie(name)
      result = contentResult(id, "cookie '" & name & "' deleted")

    of "wd_get_cookie":
      let session = getSession(id, args)
      let name = args["name"].getStr()
      let opt = session.getCookie(name)
      if opt.isSome:
        let c = opt.get
        result = contentResult(id, c.name & "=" & c.value)
      else:
        result = contentResult(id, "cookie not found")

    of "wd_forward":
      let session = getSession(id, args)
      session.forward()
      result = contentResult(id, "navigated forward")

    of "wd_back":
      let session = getSession(id, args)
      session.back()
      result = contentResult(id, "navigated back")

    of "wd_refresh":
      let session = getSession(id, args)
      session.refresh()
      result = contentResult(id, "page refreshed")

    of "wd_current_url":
      let session = getSession(id, args)
      let url = session.currentUrl()
      result = contentResult(id, url)

    of "wd_running":
      let session = getSession(id, args)
      let s = session.status()
      result = contentResult(id, $s.ready)

    of "wd_status":
      let session = getSession(id, args)
      let s = session.status()
      result = contentResult(id, "ready=" & $s.ready & ", message=" & s.message)

    of "wd_title":
      let session = getSession(id, args)
      let t = session.title()
      result = contentResult(id, t)

    of "wd_width":
      let session = getSession(id, args)
      let w = session.currentWindow().rect().width
      result = contentResult(id, $w)

    of "wd_y":
      let session = getSession(id, args)
      let y = session.currentWindow().rect().y
      result = contentResult(id, $y)

    of "wd_rect":
      let session = getSession(id, args)
      let r = session.currentWindow().rect()
      result = contentResult(id, "x=" & $r.x & ", y=" & $r.y & ", width=" & $r.width & ", height=" & $r.height)

    of "wd_visible_text":
      let session = getSession(id, args)
      let css = args["css_selector"].getStr()
      let opt = session.findElement(css)
      if opt.isSome:
        result = contentResult(id, opt.get.visibleText())
      else:
        result = contentResult(id, "element not found")

    of "wd_active_element":
      let session = getSession(id, args)
      let elem = session.activeElement()
      result = contentResult(id, elem.visibleText())

    of "wd_attribute":
      let session = getSession(id, args)
      let css = args["css_selector"].getStr()
      let attr = args["attr_name"].getStr()
      let opt = session.findElement(css)
      if opt.isSome:
        result = contentResult(id, opt.get.attribute(attr))
      else:
        result = contentResult(id, "element not found")

    of "wd_clear":
      let session = getSession(id, args)
      let css = args["css_selector"].getStr()
      let opt = session.findElement(css)
      if opt.isSome:
        opt.get.clear()
        result = contentResult(id, "element cleared")
      else:
        result = contentResult(id, "element not found")

    of "wd_click":
      let session = getSession(id, args)
      let css = args["css_selector"].getStr()
      let opt = session.findElement(css)
      if opt.isSome:
        let btn = if args.hasKey("button"): args["button"].getStr() else: "mbLeft"
        let button = case btn
          of "mbRight": mbRight
          of "mbMiddle": mbMiddle
          else: mbLeft
        discard session.actionChain().click(opt.get, button).perform()
        result = contentResult(id, "element clicked")
      else:
        result = contentResult(id, "element not found")

    of "wd_double_click":
      let session = getSession(id, args)
      let css = args["css_selector"].getStr()
      let opt = session.findElement(css)
      if opt.isSome:
        let btn = if args.hasKey("button"): args["button"].getStr() else: "mbLeft"
        let button = case btn
          of "mbRight": mbRight
          of "mbMiddle": mbMiddle
          else: mbLeft
        discard session.actionChain().doubleClick(opt.get, button).perform()
        result = contentResult(id, "element double-clicked")
      else:
        result = contentResult(id, "element not found")

    else:
      result = jsonRpcResult(id, %*{
        "content": [{"type": "text", "text": "Unknown tool: " & toolName}],
        "isError": true
      })
  except WebDriverException as e:
    result = jsonRpcResult(id, %*{
      "content": [{"type": "text", "text": e.msg}],
      "isError": true
    })
  except CatchableError as e:
    result = jsonRpcError(id, -32000, e.msg)

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
  connect(sin, sout)

when isMainModule:
  var params = newSeq[string]()
  for i in 1..paramCount():
    params.add i.paramStr
  params.main stdin.newFileStream, stdout.newFileStream, stderr.newFileStream
