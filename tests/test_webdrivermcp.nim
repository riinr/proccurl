## Tests for the `webdrivermcp` Model Context Protocol server.
##
## These tests drive the compiled `./bin/webdrivermcp` binary over stdio using
## the line-delimited JSON-RPC transport it speaks, exactly like a real MCP
## client would. A standalone mock W3C-WebDriver server (`tests/mock_webdriver.nim`,
## spawned here as its own process) stands in for a real Selenium/Geckodriver,
## so the suite is fully self-contained and runs without a browser.
##
## The scenarios under test mirror `features/webdrivermcp.feature`:
##   1. List the webdriver tools
##   2. Create a webdriver and a session
##   3. Navigate and read page source
##   4. Find an element and read its text
##   5. Close the session

import std/[unittest, json, strutils, os, osproc, streams, sequtils]
import pepino

# ---------------------------------------------------------------------------
# Mock WebDriver server (separate process)
# ---------------------------------------------------------------------------

var gMockProc: Process
var gMockPort: int

proc mockPortFile(): string =
  # tests/test_webdrivermcp.nim -> ../../ from project root
  let here = currentSourcePath().splitFile.dir  # .../tests
  result = here / ".." / "tests" / "mock_webdriver.nim"
  result.normalizePath

proc startMockServer() =
  # Spawn the mock server via `nim c -r` so the suite needs no prebuilt helper.
  gMockProc = startProcess("nim",
    args = ["c", "-r", "--threads:on",
            "--hints:off", "--verbosity:0", mockPortFile()],
    options = {poStdErrToStdOut, poUsePath})
  # The server prints "MOCKPORT=<port>" as its first line.
  var line: string
  while gMockProc.outputStream.readLine(line):
    let s = line.strip
    if s.startsWith("MOCKPORT="):
      gMockPort = s.split('=')[1].parseInt
      break

# ---------------------------------------------------------------------------
# Subprocess MCP driver
# ---------------------------------------------------------------------------

proc binPath(): string =
  # tests/test_webdrivermcp.nim -> ../../bin/webdrivermcp from project root.
  let here = currentSourcePath().splitFile.dir  # .../tests
  result = here / ".." / "bin" / "webdrivermcp"
  result.normalizePath

proc startServer(): Process =
  startProcess(binPath(), args = [], options = {poStdErrToStdOut, poUsePath})

proc sendLine(p: Process; line: string) =
  p.inputStream.write(line & "\n")
  p.inputStream.flush()

proc readMsg(p: Process): JsonNode =
  # Read until a parseable JSON object line appears.
  while true:
    let line = p.outputStream.readLine().strip()
    if line.len == 0:
      continue
    try:
      let j = parseJson(line)
      if j.kind == JObject:
        return j
    except:
      continue

proc mcpCall(p: Process; id: int; name: string; args: JsonNode): JsonNode =
  let params = %*{"name": name, "arguments": args}
  p.sendLine($(%*{"jsonrpc": "2.0", "id": id, "method": "tools/call", "params": params}))
  result = p.readMsg()

proc mcpToolsList(p: Process; id: int): JsonNode =
  p.sendLine($(%*{"jsonrpc": "2.0", "id": id, "method": "tools/list"}))
  result = p.readMsg()

proc getText(node: JsonNode; key: string): string =
  # Dig `text` out of an MCP content/structuredContent response.
  if node.hasKey("result"):
    let r = node["result"]
    if r.hasKey("content") and r["content"].len > 0 and
       r["content"][0].hasKey("text"):
      return r["content"][0]["text"].getStr
    if r.hasKey("structuredContent") and r["structuredContent"].hasKey(key):
      return r["structuredContent"][key].getStr
  return ""

# ---------------------------------------------------------------------------
# Tests — one per feature scenario
# ---------------------------------------------------------------------------

startMockServer()
assert gMockPort > 0, "mock webdriver server did not report a port"

suite "webdrivermcp scenarios":

  test "List the webdriver tools":
    let srv = startServer()
    defer: srv.close()
    let resp = srv.mcpToolsList(1)
    let tools = resp["result"]["tools"]
    check tools.kind == JArray
    let names = tools.mapIt(it["name"].getStr)
    check "wd_new_web_driver" in names
    check "wd_create_session" in names
    check "wd_close_session" in names
    check "wd_navigate" in names
    check "wd_get_page_source" in names
    check "wd_find_element" in names
    check "wd_get_text" in names
    check "wd_accept_alert" in names
    check "wd_dismiss_alert" in names
    check "wd_alert_text" in names
    check "wd_all_cookies" in names
    check "wd_get_cookie" in names
    check "wd_delete_all_cookies" in names
    check "wd_delete_cookie" in names
    check "wd_forward" in names
    check "wd_back" in names
    check "wd_refresh" in names
    check "wd_current_url" in names
    check "wd_running" in names
    check "wd_status" in names
    check "wd_title" in names
    check "wd_width" in names
    check "wd_y" in names
    check "wd_rect" in names
    check "wd_element_rect" in names
    check "wd_save_screen_shot_to" in names
    check "wd_visible_text" in names
    check "wd_active_element" in names
    check "wd_attribute" in names
    check "wd_clear" in names
    check "wd_click" in names
    check "wd_double_click" in names
    check "wd_drag_and_drop" in names
    check "wd_send_keys" in names
    check "wd_css_property_value" in names
    check "wd_property" in names
    check "wd_enabled" in names
    check "wd_displayed" in names
    check "wd_selected" in names
    check "wd_submit" in names
    check "wd_tag_name" in names
    check "wd_height" in names
    check "wd_location" in names

  test "Create a webdriver and a session":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    let r1 = srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    check "webdriver created" in getText(r1, "text")
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    check sid.len > 0
    check sid == "mock-session-0123"

  test "Navigate and read page source":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    discard srv.mcpCall(3, "wd_navigate", %*{"session_id": sid, "url": "https://example.com"})
    let src = getText(srv.mcpCall(4, "wd_get_page_source", %*{"session_id": sid}), "text")
    check "Example Domain" in src

  test "Find an element and read its text":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let eid = getText(
      srv.mcpCall(3, "wd_find_element",
        %*{"session_id": sid, "selector": "h1", "strategy": "css"}),
      "text")
    check eid.len > 0
    check "mock-element-4567" in eid
    let txt = getText(
      srv.mcpCall(4, "wd_get_text", %*{"session_id": sid, "element_id": eid}),
      "text")
    check txt == "Example Domain"

  test "Close the session":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_close_session", %*{"session_id": sid})
    check "session closed" in getText(r, "text")

  test "Accept a JavaScript alert":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_accept_alert", %*{"session_id": sid})
    check "alert accepted" in getText(r, "text")

  test "Dismiss a JavaScript alert":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_dismiss_alert", %*{"session_id": sid})
    check "alert dismissed" in getText(r, "text")

  test "Get alert text":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_alert_text", %*{"session_id": sid})
    check "You are in a dialogs! I've seen... not much." in getText(r, "text")

  test "Get all cookies":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_all_cookies", %*{"session_id": sid})
    check "test=test_value" in getText(r, "text")

  test "Delete all cookies":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_delete_all_cookies", %*{"session_id": sid})
    check "all cookies deleted" in getText(r, "text")

  test "Delete a cookie by name":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_delete_cookie", %*{"session_id": sid, "name": "test"})
    check "cookie 'test' deleted" in getText(r, "text")

  test "Get a cookie by name":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_get_cookie", %*{"session_id": sid, "name": "test"})
    check "test=test_value" in getText(r, "text")

  test "Navigate forward":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_forward", %*{"session_id": sid})
    check "navigated forward" in getText(r, "text")

  test "Navigate back":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_back", %*{"session_id": sid})
    check "navigated back" in getText(r, "text")

  test "Refresh the page":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_refresh", %*{"session_id": sid})
    check "page refreshed" in getText(r, "text")

  test "Get current URL":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_current_url", %*{"session_id": sid})
    check "https://example.com" in getText(r, "text")

  test "Check if the browser is running":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_running", %*{"session_id": sid})
    check "true" in getText(r, "text")

  test "Get WebDriver status":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_status", %*{"session_id": sid})
    check "ready=true" in getText(r, "text")
    check "message=mock ready" in getText(r, "text")

  test "Get the page title":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_title", %*{"session_id": sid})
    check "Example Domain" in getText(r, "text")

  test "Get the window width":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_width", %*{"session_id": sid})
    check "1024" in getText(r, "text")

  test "Get the window y-coordinate":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_y", %*{"session_id": sid})
    check "0" in getText(r, "text")

  test "Get the window rect":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_rect", %*{"session_id": sid})
    check "x=0.0, y=0.0, width=1024.0, height=768.0" in getText(r, "text")

  test "Get the rect of an element":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_element_rect", %*{"session_id": sid, "css_selector": "button"})
    check "x=0.0, y=0.0, width=200.0, height=100.0" in getText(r, "text")

  test "Save a screenshot of an element to a file":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let fn = getTempDir() / "wd_element_shot.png"
    let r = srv.mcpCall(3, "wd_save_screen_shot_to",
      %*{"session_id": sid, "css_selector": "button", "filename": fn})
    check "screenshot saved to " & fn in getText(r, "text")
    check fn.fileExists
    removeFile(fn)

  test "Get visible text of an element":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_visible_text", %*{"session_id": sid, "css_selector": "h1"})
    check "Example Domain" in getText(r, "text")

  test "Get the active element selector":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_active_element", %*{"session_id": sid})
    check "mock-element-4567" in getText(r, "text")

  test "Get an element attribute":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_attribute", %*{"session_id": sid, "css_selector": "a", "attr_name": "href"})
    check "mock-attribute-value" in getText(r, "text")

  test "Clear an element":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_clear", %*{"session_id": sid, "css_selector": "input"})
    check "element cleared" in getText(r, "text")

  test "Click on an element":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_click", %*{"session_id": sid, "css_selector": "button"})
    check "element clicked" in getText(r, "text")

  test "Right-click on an element":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_click", %*{"session_id": sid, "css_selector": "button", "button": "mbRight"})
    check "element clicked" in getText(r, "text")

  test "Double-click on an element":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_double_click", %*{"session_id": sid, "css_selector": "button"})
    check "element double-clicked" in getText(r, "text")

  test "Right double-click on an element":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_double_click", %*{"session_id": sid, "css_selector": "button", "button": "mbRight"})
    check "element double-clicked" in getText(r, "text")

  test "Drag an element by offset":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_drag_and_drop", %*{"session_id": sid, "css_selector": "div", "delta_x": 100, "delta_y": 50})
    check "element dragged" in getText(r, "text")

  test "Send keys to an element":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_send_keys", %*{"session_id": sid, "css_selector": "input", "text": "hello world"})
    check "keys sent" in getText(r, "text")

  test "Get a CSS property value":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_css_property_value", %*{"session_id": sid, "css_selector": "h1", "name": "color"})
    check "mock-css-value" in getText(r, "text")

  test "Get an element property value":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_property", %*{"session_id": sid, "css_selector": "input", "name": "value"})
    check "mock-property-value" in getText(r, "text")

  test "Check whether an element is enabled":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_enabled", %*{"session_id": sid, "css_selector": "button"})
    check "true" in getText(r, "text")

  test "Check whether an element is displayed":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_displayed", %*{"session_id": sid, "css_selector": "button"})
    check "true" in getText(r, "text")

  test "Check whether an element is selected":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_selected", %*{"session_id": sid, "css_selector": "input"})
    check "true" in getText(r, "text")

  test "Submit a form containing an element":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_submit", %*{"session_id": sid, "css_selector": "input"})
    check "element submitted" in getText(r, "text")

  test "Get the tag name of an element":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_tag_name", %*{"session_id": sid, "css_selector": "input"})
    check "h1" in getText(r, "text")

  test "Get the height of an element":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_height", %*{"session_id": sid, "css_selector": "button"})
    check "100.0" in getText(r, "text")

  test "Get the location of an element":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_location", %*{"session_id": sid, "css_selector": "button"})
    check "x=0.0, y=0.0" in getText(r, "text")
