## scan.nim — mDNS responder/announcer CLI.
##
## Announces a service via libmicrodns, explicitly requests an initial announce,
## then serves for a bounded time answering mDNS questions. Every announce the
## program sends (initial, response to a query, goodbye) is printed to stdout.
##
## Usage:
##   scan [options] [instance]
##     instance   the host/instance name to announce (default "mdnshost.local")
##     -t, --type       service type to announce (default "_nicrodns._tcp.local")
##     -p, --port       service port in the SRV record  (default 9001)
##     -d, --duration   how long to serve, in seconds    (default 10)
##     -h, --help       show this help

import std/[os, monotimes, strutils, times]
import std/typedthreads
import microdns

const
  AF_INET  = 2
  AF_INET6 = 10

type
  Options = object
    instance:    string
    serviceType: string
    port:        uint16
    duration:    float

  RawSockAddr = object
    saFamily: cushort
    saData:   array[14, uint8]

  ListenArgs = object
    ctx:         ptr MdnsCtx
    serviceType: cstring

var
  gOpts = Options(instance: "mdnshost.local",
                  serviceType: "_nicrodns._tcp.local",
                  port: 9001, duration: 10.0)
  gDuration: float
  gStarted: MonoTime
  gStopping = false

proc printUsage() =
  echo """scan — announce an mDNS service and answer queries for a while

Usage: scan [options] [instance]
  instance          host/instance name to announce (default "mdnshost.local")
  -t, --type TYPE   service type to announce      (default "_nicrodns._tcp.local")
  -p, --port PORT   service port in the SRV record (default 9001)
  -d, --duration S  how long to serve, in seconds  (default 10)
  -h, --help        show this help"""

proc parseOptions() =
  let args = commandLineParams()
  var i = 0
  while i < args.len:
    case args[i]
    of "-h", "--help":
      printUsage(); quit(0)
    of "-t", "--type":
      inc i; gOpts.serviceType = args[i]
    of "-p", "--port":
      inc i; gOpts.port = parseInt(args[i]).uint16
    of "-d", "--duration":
      inc i; gOpts.duration = parseInt(args[i]).float
    else:
      if args[i].startsWith("-"):
        echo "unknown option: ", args[i]
        printUsage(); quit(1)
      gOpts.instance = args[i]
    inc i

proc errString(rc: cint): string =
  ## Format a libmicrodns error code into a message.
  if rc >= 0: return "ok"
  var buf = newString(128)
  discard mdnsStrerror(rc, buf.cstring, buf.len.csize_t)
  result = buf.strip

proc stop(cookie: pointer): bool {.cdecl.} =
  ## `mdns_stop_func`: stop once the duration elapses (or on Ctrl-C).
  result = gStopping or
    float(inSeconds(getMonoTime() - gStarted)) >= gDuration

proc sendAnnounce(ctx: ptr MdnsCtx; sockAddr: ptr SockAddr;
                  service: cstring; typ: MdnsAnnounceType) =
  ## Build PTR/TXT/SRV/A-AAAA records for the announced service and send them.
  let serviceName = gOpts.serviceType.cstring
  let linkStr = gOpts.instance & " " & gOpts.serviceType
  let instanceLink = linkStr.cstring

  var
    hdr = MdnsHdr()
    answers: array[4, RrEntry]

  hdr.flags = FLAG_QR or FLAG_AA
  hdr.numAnsRr = 4
  for i in 0 ..< answers.len:
    answers[i].rrClass = uint16(RR_IN)
    answers[i].ttl = if typ == MDNS_ANNOUNCE_GOODBYE: 0'u32 else: 120'u32
    answers[i].msbit = 1
    if i + 1 < answers.len:
      answers[i].next = addr answers[i + 1]

  # PTR: point the service type at our instance
  answers[0].rType = uint16(RR_PTR)
  answers[0].name  = serviceName
  answers[0].data.PTR.domain = instanceLink

  # TXT: optional metadata (empty here)
  answers[1].rType = uint16(RR_TXT)
  answers[1].name  = instanceLink

  # SRV: instance -> port/target
  answers[2].rType = uint16(RR_SRV)
  answers[2].name  = instanceLink
  answers[2].data.SRV.priority = 0
  answers[2].data.SRV.weight   = 0
  answers[2].data.SRV.port     = gOpts.port
  answers[2].data.SRV.target   = gOpts.instance.cstring

  # A/AAAA: instance -> interface address
  answers[3].name = gOpts.instance.cstring
  let sa = cast[ptr RawSockAddr](sockAddr)
  if sa.saFamily == AF_INET:
    answers[3].rType = uint16(RR_A)
    let src = cast[ptr UncheckedArray[uint8]](sockAddr)
    let dst = cast[ptr UncheckedArray[uint8]](
      addr answers[3].data.A.address.s_addr)
    for i in 0 ..< 4:
      dst[i] = src[4 + i]
  elif sa.saFamily == AF_INET6:
    answers[3].rType = uint16(RR_AAAA)
    let src = cast[ptr UncheckedArray[uint8]](sockAddr)
    for i in 0 ..< 16:
      answers[3].data.AAAA.address.s6_addr[i] = src[8 + i]

  echo "-> announce[", $typ, "]",
       (if service != nil: " for " & $service else: ""), ":"
  mdnsEntriesPrint(addr answers[0])

  let rc = mdnsEntriesSend(ctx, addr hdr, addr answers[0])
  if rc < 0:
    echo "!! send failed: ", errString(rc)

proc isLocalAddress(entry: ptr RrEntry): bool =
  ## True when an A/AAAA record points at a loopback, link-local, multicast
  ## or unspecified address — i.e. not a real device on the network.
  if entry == nil: return false
  case entry.rType
  of uint16(RR_A):
    let b = entry.data.A.address.s_addr  # network byte order
    let b0 = (b shr 24) and 0xFF'u32
    let b1 = (b shr 16) and 0xFF'u32
    if b0 == 127: return true                  # 127/8 loopback
    if b0 == 0: return true                    # 0/8 unspecified
    if b0 == 169 and b1 == 254: return true    # 169.254/16 link-local
    if b0 >= 224: return true                  # 224/4 multicast/reserved
  of uint16(RR_AAAA):
    let a = entry.data.AAAA.address.s6_addr
    if a[0] == 0: return true                  # ::, ::1, ::ffff:...
    if a[0] == 0xfe and (a[1] and 0xC0) == 0x80: return true  # fe80::/10
    if a[0] == 0xff: return true               # ff00::/8 multicast
  else: discard
  result = false

proc printDiscovered(entry: ptr RrEntry) =
  ## Print `entry`'s record list, dropping A/AAAA records whose address is
  ## local so the scan only reports real devices.
  var buf: seq[RrEntry]
  for e in entries(entry):
    if e.rType in [uint16(RR_A), uint16(RR_AAAA)] and isLocalAddress(e):
      continue
    buf.add e[]
  if buf.len == 0:
    echo "  (filtered: only local addresses)"
    return
  for i in 0 ..< buf.len - 1:
    buf[i].next = addr buf[i + 1]
  buf[^1].next = nil
  mdnsEntriesPrint(addr buf[0])

proc listenCallback(cookie: pointer; status: cint;
                     entry: ptr RrEntry) {.cdecl.} =
  ## Fired by `mdnsListen` for each discovered response.
  if status < 0:
    echo "!! listen error: ", errString(status)
    return
  echo "-> discovered:"
  printDiscovered(entry)

proc listenLoop(args: ListenArgs) {.thread.} =
  ## Background discovery: probe for `args.serviceType` until stopped.
  let names = cast[cstringArray](alloc0(sizeof(cstring) * 2))
  defer: dealloc(names)
  names[0] = args.serviceType
  names[1] = nil
  let rc = mdnsListen(args.ctx, names, 1, RR_PTR, 2, stop,
                      cast[MdnsListenCallback](listenCallback), nil)
  if rc < 0:
    echo "!! listen ended: ", errString(rc)

proc announceCallback(cookie: pointer; sockAddr: ptr SockAddr;
                      service: cstring; typ: MdnsAnnounceType) {.cdecl.} =
  let ctx = cast[ptr MdnsCtx](cookie)
  sendAnnounce(ctx, sockAddr, service, typ)

proc main() =
  parseOptions()
  gStarted = getMonoTime()

  setControlCHook(proc() {.noconv.} =
    gStopping = true
    echo "\nSIGINT received, stopping ...")

  var ctx: ptr MdnsCtx
  if mdnsInit(addr ctx, nil, MDNS_PORT.cushort) < 0:
    echo "fatal: mdns_init failed"
    quit 1

  if mdnsAnnounce(ctx, RR_PTR, cast[MdnsAnnounceCallback](announceCallback),
                   cast[pointer](ctx)) < 0:
    echo "fatal: mdns_announce failed"
    discard mdnsDestroy(ctx)
    quit 1

  # Second context for discovery: runs `mdnsListen` in a background thread
  # while `mdnsServe` answers queries on the main thread.
  gDuration = gOpts.duration
  var listenCtx: ptr MdnsCtx
  if mdnsInit(addr listenCtx, nil, MDNS_PORT.cushort) < 0:
    echo "fatal: mdns_init (listen) failed"
    discard mdnsDestroy(ctx)
    quit 1
  let serviceTypeArr = allocCStringArray([gOpts.serviceType])
  var listenArgs = ListenArgs(ctx: listenCtx,
                              serviceType: serviceTypeArr[0])
  var listenThread: Thread[ListenArgs]
  createThread(listenThread, listenLoop, listenArgs)

  echo "Announcing ", gOpts.instance, " as ", gOpts.serviceType,
       " (port ", gOpts.port, ") for ", gOpts.duration, "s"
  echo "Ctrl-C to stop early"

  # Explicit initial announce (RFC 6762 §8.3), then serve and answer queries.
  mdnsRequestInitialAnnounce(ctx, gOpts.serviceType.cstring)
  let rc = mdnsServe(ctx, stop, nil)
  if rc < 0:
    echo "fatal: mdns_serve: ", errString(rc)

  joinThread(listenThread)
  deallocCStringArray(serviceTypeArr)
  discard mdnsDestroy(listenCtx)
  discard mdnsDestroy(ctx)
  echo "done."

main()
