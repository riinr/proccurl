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
    check "wd_visible_text" in names
    check "wd_active_element" in names
    check "wd_attribute" in names

  test "Create a webdriver and a session":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    let r1 = srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    check getText(r1, "text").contains("webdriver created")
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
    check src.contains("Example Domain")

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
    check eid == "mock-element-4567"
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
    check getText(r, "text").contains("session closed")

  test "Accept a JavaScript alert":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_accept_alert", %*{"session_id": sid})
    check getText(r, "text").contains("alert accepted")

  test "Dismiss a JavaScript alert":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_dismiss_alert", %*{"session_id": sid})
    check getText(r, "text").contains("alert dismissed")

  test "Get alert text":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_alert_text", %*{"session_id": sid})
    check getText(r, "text").contains("You are in a dialogs! I've seen... not much.")

  test "Get all cookies":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_all_cookies", %*{"session_id": sid})
    check getText(r, "text").contains("test=test_value")

  test "Delete all cookies":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_delete_all_cookies", %*{"session_id": sid})
    check getText(r, "text").contains("all cookies deleted")

  test "Delete a cookie by name":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_delete_cookie", %*{"session_id": sid, "name": "test"})
    check getText(r, "text").contains("cookie 'test' deleted")

  test "Get a cookie by name":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_get_cookie", %*{"session_id": sid, "name": "test"})
    check getText(r, "text").contains("test=test_value")

  test "Navigate forward":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_forward", %*{"session_id": sid})
    check getText(r, "text").contains("navigated forward")

  test "Navigate back":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_back", %*{"session_id": sid})
    check getText(r, "text").contains("navigated back")

  test "Refresh the page":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_refresh", %*{"session_id": sid})
    check getText(r, "text").contains("page refreshed")

  test "Get current URL":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_current_url", %*{"session_id": sid})
    check getText(r, "text").contains("https://example.com")

  test "Check if the browser is running":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_running", %*{"session_id": sid})
    check getText(r, "text").contains("true")

  test "Get WebDriver status":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_status", %*{"session_id": sid})
    check getText(r, "text").contains("ready=true")
    check getText(r, "text").contains("message=mock ready")

  test "Get the page title":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_title", %*{"session_id": sid})
    check getText(r, "text").contains("Example Domain")

  test "Get the window width":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_width", %*{"session_id": sid})
    check getText(r, "text").contains("1024")

  test "Get the window y-coordinate":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_y", %*{"session_id": sid})
    check getText(r, "text").contains("0")

  test "Get the window rect":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_rect", %*{"session_id": sid})
    check getText(r, "text").contains("x=0.0, y=0.0, width=1024.0, height=768.0")

  test "Get visible text of an element":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_visible_text", %*{"session_id": sid, "css_selector": "h1"})
    check getText(r, "text").contains("Example Domain")

  test "Get the active element text":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_active_element", %*{"session_id": sid})
    check getText(r, "text").contains("Example Domain")

  test "Get an element attribute":
    let srv = startServer()
    defer: srv.close()
    let url = "http://127.0.0.1:" & $gMockPort
    discard srv.mcpCall(1, "wd_new_web_driver", %*{"url": url})
    let sid = getText(srv.mcpCall(2, "wd_create_session", %*{}), "text")
    let r = srv.mcpCall(3, "wd_attribute", %*{"session_id": sid, "css_selector": "a", "attr_name": "href"})
    check getText(r, "text").contains("mock-attribute-value")
