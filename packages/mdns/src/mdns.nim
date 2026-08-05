## mdns — pure-Nim Multicast DNS (RFC 6762) service discovery.
##
## Given a network interface (identified by an IP address on that network),
## this module joins the mDNS multicast group, sends a DNS-SD browse query
## (RFC 6763), and collects the service announcements heard back. It has no
## C dependencies: DNS wire messages are parsed here, and the multicast group
## join is done with a raw `setsockopt`.

import std/[net, os, strutils, parseopt, tables, oserrors]
from std/times import epochTime
from std/posix import setsockopt, inet_pton, select, Timeval, TFdSet, FD_ZERO,
  FD_SET, FD_ISSET, Tipv6_mreq, InAddr, In6Addr, SockLen, AF_INET, AF_INET6,
  SOCK_DGRAM, IPPROTO_IP, IPPROTO_IPV6, IPV6_JOIN_GROUP, Time, Suseconds

const
  MdnsPort*        = Port(5353)
  MdnsV4Group*     = "224.0.0.251" ## IPv4 link-local multicast group
  MdnsV6Group*     = "ff02::fb"    ## IPv6 link-local multicast group
  MdnsDefaultType* = "_services._dns-sd._udp"

let
  IP_ADD_MEMBERSHIP {.importc, header: "<netinet/in.h>".}: cint
  IP_MULTICAST_IF   {.importc, header: "<netinet/in.h>".}: cint

type
  MdnsError* = object of CatchableError

  RecordType* = enum
    rtA    = 1
    rtPtr  = 12
    rtTxt  = 16
    rtAaaa = 28
    rtSrv  = 33

  Question* = object
    name*:   string
    qtype*:  uint16
    qclass*: uint16   ## raw class field; bit 15 is the QU bit in queries

  Record* = object
    name*:       string
    rtype*:      uint16
    rclass*:     uint16   ## raw class field, cache-flush bit masked off
    cacheFlush*: bool     ## RFC 6762 §10.2 cache-flush bit (rclass bit 15)
    ttl*:        uint32
    rdata*:      string   ## raw RDATA bytes
    rdataAbs*:   int      ## absolute offset of RDATA within the message

  Message* = object
    id*:          uint16
    qr*:          bool
    questions*:   seq[Question]
    answers*:     seq[Record]
    authorities*: seq[Record]
    additionals*: seq[Record]
    raw*:         seq[byte] ## full wire message, needed for name decompression

  Service* = object
    instance*:    string   ## e.g. "My Printer._ipp._tcp.local."
    serviceType*: string   ## e.g. "_ipp._tcp.local."
    host*:        string   ## SRV target, e.g. "mypc.local."
    port*:        int
    txt*:         seq[string]
    addresses*:   seq[string]

# ---------------------------------------------------------------------------
# Wire-format decoding
# ---------------------------------------------------------------------------

proc readU16(buf: seq[byte]; pos: var int): uint16 =
  if pos + 2 > buf.len:
    raise newException(MdnsError, "truncated message")
  result = (uint16(buf[pos]) shl 8) or uint16(buf[pos + 1])
  pos += 2

proc readU32(buf: seq[byte]; pos: var int): uint32 =
  result = (uint32(readU16(buf, pos)) shl 16) or uint32(readU16(buf, pos))

proc readName(buf: seq[byte]; pos: var int; jumpBudget: var int): string =
  ## Decode a (possibly compressed) domain name. `pos` is updated to the first
  ## byte after the name, which for a compression pointer is the byte after
  ## the pointer itself (RFC 1035 §4.1.4). Pointers may only point backwards;
  ## `jumpBudget` bounds the pointer chain.
  let start = pos
  var readPos = pos
  var cursor = pos
  var jumped = false
  while true:
    if cursor >= buf.len:
      raise newException(MdnsError, "truncated name")
    let len = int(buf[cursor])
    if len == 0:
      if not jumped: readPos = cursor + 1
      break
    if (len and 0xc0) == 0xc0:
      if cursor + 1 >= buf.len:
        raise newException(MdnsError, "truncated pointer")
      let target = ((len and 0x3f) shl 8) or int(buf[cursor + 1])
      if not jumped:
        readPos = cursor + 2
        jumped = true
      if target >= start or target >= buf.len:
        raise newException(MdnsError, "invalid compression pointer")
      dec jumpBudget
      if jumpBudget < 0:
        raise newException(MdnsError, "too many compression jumps")
      cursor = target
    else:
      if cursor + 1 + len > buf.len:
        raise newException(MdnsError, "truncated label")
      if result.len > 0: result.add '.'
      for i in 0 ..< len:
        result.add char(buf[cursor + 1 + i])
      cursor += 1 + len
  pos = readPos

proc decodeMessage*(data: seq[byte]): Message =
  ## Parse a DNS/mDNS wire message. Throws `MdnsError` on malformed input.
  result.raw = data
  var pos = 0
  result.id = readU16(data, pos)
  let flags = readU16(data, pos)
  result.qr = ((flags shr 15) and 1) == 1
  let nq  = int(readU16(data, pos))
  let na  = int(readU16(data, pos))
  let nns = int(readU16(data, pos))
  let nar = int(readU16(data, pos))
  for _ in 0 ..< nq:
    var q: Question
    var budget = 16
    q.name = readName(data, pos, budget)
    q.qtype = readU16(data, pos)
    q.qclass = readU16(data, pos)
    result.questions.add q
  let counts = [na, nns, nar]
  for section in 0 ..< 3:
    for _ in 0 ..< counts[section]:
      var rr: Record
      var budget = 16
      rr.name = readName(data, pos, budget)
      rr.rtype = readU16(data, pos)
      let rclass = readU16(data, pos)
      rr.cacheFlush = (rclass and 0x8000'u16) != 0
      rr.rclass = rclass and 0x7fff'u16
      rr.ttl = readU32(data, pos)
      let rdlen = int(readU16(data, pos))
      if pos + rdlen > data.len:
        raise newException(MdnsError, "truncated rdata")
      rr.rdataAbs = pos
      rr.rdata = newString(rdlen)
      for i in 0 ..< rdlen:
        rr.rdata[i] = char(data[pos + i])
      pos += rdlen
      case section
      of 0: result.answers.add rr
      of 1: result.authorities.add rr
      else: result.additionals.add rr

# ---------------------------------------------------------------------------
# Wire-format encoding (browse query)
# ---------------------------------------------------------------------------

proc writeU16(buf: var seq[byte]; v: uint16) =
  buf.add byte(v shr 8)
  buf.add byte(v and 0xff)

proc writeName(buf: var seq[byte]; name: string) =
  if name.len == 0:
    buf.add 0
    return
  for label in name.split('.'):
    if label.len == 0: continue
    if label.len > 63:
      raise newException(MdnsError, "invalid label in name: '" & name & "'")
    buf.add byte(label.len)
    for c in label:
      buf.add byte(c)
  buf.add 0

proc encodeBrowseQuery*(serviceType: string): seq[byte] =
  ## Build an mDNS PTR query for `serviceType` (e.g. `_http._tcp` or
  ## `_services._dns-sd._udp`). The `.local.` suffix is appended if missing.
  ## RFC 6762 §5.4: the QU (unicast-response) bit is set in the class field.
  var name = serviceType
  if not name.endsWith(".local"):
    if name.len > 0 and not name.endsWith("."): name.add '.'
    name.add "local"
  if not name.endsWith("."): name.add '.'
  result.writeU16 0      # transaction id: mDNS uses 0
  result.writeU16 0      # flags: QR=0, opcode=QUERY
  result.writeU16 1      # QDCOUNT
  result.writeU16 0      # ANCOUNT
  result.writeU16 0      # NSCOUNT
  result.writeU16 0      # ARCOUNT
  result.writeName name
  result.writeU16 12     # QTYPE = PTR
  result.writeU16 0x8001 # QCLASS = QU bit | IN

# ---------------------------------------------------------------------------
# RDATA helpers
# ---------------------------------------------------------------------------

proc rdataName*(m: Message; rr: Record): string =
  ## Decode the (possibly compressed) target name stored in a PTR or SRV
  ## record's RDATA, using the original message for compression pointers.
  ## SRV RDATA is priority(2) weight(2) port(2) target(name).
  var pos = rr.rdataAbs
  if rr.rtype == uint16(rtSrv): pos += 6
  var budget = 16
  result = readName(m.raw, pos, budget)

proc rdataIP*(rr: Record): string =
  ## Format RDATA as a dotted IPv4 or colon-hex IPv6 address (A/AAAA).
  if rr.rtype == uint16(rtA) and rr.rdata.len >= 4:
    result = $uint8(rr.rdata[0]) & "." & $uint8(rr.rdata[1]) & "." &
             $uint8(rr.rdata[2]) & "." & $uint8(rr.rdata[3])
  elif rr.rtype == uint16(rtAaaa) and rr.rdata.len >= 16:
    var parts: seq[string]
    for i in countup(0, 14, 2):
      parts.add toHex((uint8(rr.rdata[i]).uint16 shl 8) or
                      uint8(rr.rdata[i + 1]).uint16, 4)
    result = parts.join(":")

proc rdataSrvPort*(rr: Record): int =
  ## Extract the port from an SRV record's RDATA (bytes 4-5; SRV RDATA is
  ## priority(2) weight(2) port(2) target(name)).
  if rr.rtype == uint16(rtSrv) and rr.rdata.len >= 6:
    result = (uint8(rr.rdata[4]).int shl 8) or uint8(rr.rdata[5]).int

proc rdataTxt*(rr: Record): seq[string] =
  ## Split a TXT record's RDATA into its individual strings.
  if rr.rtype != uint16(rtTxt): return
  var i = 0
  while i < rr.rdata.len:
    let len = uint8(rr.rdata[i]).int
    inc i
    if len > 0 and i + len <= rr.rdata.len:
      result.add rr.rdata[i ..< i + len]
    i += len

# ---------------------------------------------------------------------------
# Discovery collection
# ---------------------------------------------------------------------------

func normName(s: string): string =
  result = s
  if not result.endsWith("."): result.add '.'

proc collectMessage*(services: var Table[string, Service]; m: Message) =
  ## Fold one received mDNS message into `services`, keyed by instance name.
  for rr in m.answers & m.additionals & m.authorities:
    case rr.rtype
    of uint16(rtPtr):
      let instance = rdataName(m, rr).normName
      if instance.len > 0:
        var svc = services.getOrDefault(instance)
        svc.instance = instance
        svc.serviceType = rr.name.normName
        services[instance] = svc
    of uint16(rtSrv):
      let instance = rr.name.normName
      var svc = services.getOrDefault(instance)
      svc.instance = instance
      svc.host = rdataName(m, rr).normName
      svc.port = rdataSrvPort(rr)
      services[instance] = svc
    of uint16(rtTxt):
      let instance = rr.name.normName
      var svc = services.getOrDefault(instance)
      svc.instance = instance
      svc.txt = rdataTxt(rr)
      services[instance] = svc
    of uint16(rtA), uint16(rtAaaa):
      let host = rr.name.normName
      let ip = rdataIP(rr)
      if ip.len == 0: continue
      for instance, svc in services.mpairs:
        if svc.host == host and ip notin svc.addresses:
          svc.addresses.add ip
    else:
      discard

# ---------------------------------------------------------------------------
# Multicast socket
# ---------------------------------------------------------------------------

type
  IpMreq {.importc: "struct ip_mreq", header: "<netinet/in.h>".} = object
    imr_multiaddr: InAddr
    imr_interface: InAddr

proc strToInAddr(s: string; ia: var InAddr): bool =
  inet_pton(AF_INET, s.cstring, addr ia) == 1

proc joinV4(sock: Socket; group, interfaceIp: string) =
  var mreq: IpMreq
  if not strToInAddr(group, mreq.imr_multiaddr):
    raise newException(MdnsError, "invalid IPv4 multicast group: " & group)
  if interfaceIp.len == 0:
    mreq.imr_interface.s_addr = 0 # INADDR_ANY -> default interface
  elif not strToInAddr(interfaceIp, mreq.imr_interface):
    raise newException(MdnsError, "invalid interface IPv4 address: " & interfaceIp)
  if setsockopt(getFd(sock), IPPROTO_IP, IP_ADD_MEMBERSHIP,
                addr mreq, sizeof(mreq).SockLen) != 0:
    raiseOSError(osLastError(), "cannot join " & group)

proc joinV6(sock: Socket; group: string) =
  var mreq: Tipv6_mreq
  if inet_pton(AF_INET6, group.cstring, addr mreq.ipv6mr_multiaddr) != 1:
    raise newException(MdnsError, "invalid IPv6 multicast group: " & group)
  mreq.ipv6mr_interface = 0 # default interface
  if setsockopt(getFd(sock), IPPROTO_IPV6, IPV6_JOIN_GROUP,
                addr mreq, sizeof(mreq).SockLen) != 0:
    raiseOSError(osLastError(), "cannot join " & group)

proc setV4MulticastIf(sock: Socket; interfaceIp: string) =
  ## Route outgoing multicast on the interface `interfaceIp`.
  if interfaceIp.len == 0: return
  var ia: InAddr
  if not strToInAddr(interfaceIp, ia): return
  discard setsockopt(getFd(sock), IPPROTO_IP, IP_MULTICAST_IF,
                     addr ia, sizeof(ia).SockLen)

proc openMdnsSocket(interfaceIp: string; ipv6: bool): Socket =
  let domain = if ipv6: AF_INET6 else: AF_INET
  result = newSocket(domain, SOCK_DGRAM, IPPROTO_UDP)
  result.setSockOpt(OptReuseAddr, true)
  result.setSockOpt(OptReusePort, true)
  # Bind to the wildcard address so multicast traffic reaches us regardless of
  # destination; SO_REUSEPORT lets other mDNS responders coexist on :5353.
  result.bindAddr(MdnsPort, "")

proc recvMessage(sock: Socket; timeoutMs: int): Message =
  ## Wait up to `timeoutMs` ms for one datagram and decode it as mDNS.
  var fdset: TFdSet
  FD_ZERO(fdset)
  FD_SET(getFd(sock), fdset)
  var tv = Timeval(tv_sec: Time(timeoutMs div 1000),
                   tv_usec: Suseconds((timeoutMs mod 1000) * 1000))
  let rc = select(cint(getFd(sock)) + 1, addr fdset, nil, nil, addr tv)
  if rc < 0:
    raiseOSError(osLastError())
  if rc == 0:
    raise newException(TimeoutError, "no datagram within timeout")
  var data = newString(2048)
  var src: string
  var srcPort: Port
  let n = sock.recvFrom(data, data.len, src, srcPort)
  data.setLen(n)
  var buf = newSeq[byte](data.len)
  for i in 0 ..< data.len:
    buf[i] = byte(data[i])
  result = decodeMessage(buf)

# ---------------------------------------------------------------------------
# High-level browse
# ---------------------------------------------------------------------------

proc browse*(services: var Table[string, Service]; serviceType = MdnsDefaultType;
             interfaceIp = ""; timeoutMs = 5000; ipv6 = false) =
  ## Join the mDNS group on the interface `interfaceIp` (empty = default),
  ## send a PTR browse query for `serviceType`, and fold every announcement
  ## heard during `timeoutMs` into `services`.
  let group = if ipv6: MdnsV6Group else: MdnsV4Group
  let sock = openMdnsSocket(interfaceIp, ipv6)
  try:
    if ipv6:
      joinV6(sock, group)
    else:
      joinV4(sock, group, interfaceIp)
      setV4MulticastIf(sock, interfaceIp)
    let query = encodeBrowseQuery(serviceType)
    var qs = newStringOfCap(query.len)
    for b in query: qs.add char(b)
    sock.sendTo(group, MdnsPort, qs)
    let deadline = epochTime() + timeoutMs.float / 1000.0
    while epochTime() < deadline:
      let remaining = int((deadline - epochTime()) * 1000.0)
      if remaining <= 0: break
      var m: Message
      try:
        m = recvMessage(sock, remaining)
      except TimeoutError:
        break
      if m.qr: collectMessage(services, m)
  finally:
    sock.close()

# ---------------------------------------------------------------------------
# Command-line interface
# ---------------------------------------------------------------------------

const Usage = """mdns — Multicast DNS service discovery (RFC 6762)

Usage:
  mdns [options] [interface-ip]

Searches for mDNS announcements on the network reached through `interface-ip`
(a local IP that belongs to the interface you want to listen on). If omitted,
the default interface is used.

Options:
  -q, --query <type>   Service type to browse (default: _services._dns-sd._udp)
  -t, --timeout <sec>  Seconds to listen for announcements (default: 5)
  -6, --ipv6           Use the IPv6 multicast group ff02::fb instead of IPv4
  -h, --help           Show this help
"""

type
  Options = object
    interfaceIp: string
    serviceType: string
    timeoutMs: int
    ipv6: bool

proc parseOptions(): Options =
  result.serviceType = MdnsDefaultType
  result.timeoutMs = 5000
  var positional: seq[string]
  var p = initOptParser()
  proc takeValue(key: string): string =
    ## Option value may be attached (`-t3`, `--timeout=3`) or the next token
    ## (`-t 3`, `--timeout 3`).
    if p.val.len > 0: return p.val
    p.next()
    if p.kind == cmdArgument: return p.key
    raise newException(ValueError, "missing value for option --" & key)
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdLongOption, cmdShortOption:
      case p.key
      of "query", "q": result.serviceType = takeValue(p.key)
      of "timeout", "t": result.timeoutMs = parseInt(takeValue(p.key)) * 1000
      of "ipv6", "6": result.ipv6 = true
      of "help", "h": echo Usage; quit 0
      else: echo "unknown option: ", p.key; echo Usage; quit 1
    of cmdArgument:
      positional.add p.key
  if positional.len > 0:
    result.interfaceIp = positional[0]

proc printService(name: string; svc: Service) =
  echo "\n" & name
  if svc.serviceType.len > 0: echo "  type:     ", svc.serviceType
  if svc.host.len > 0:        echo "  host:     ", svc.host
  if svc.port > 0:            echo "  port:     ", svc.port
  for ip in svc.addresses:    echo "  address:  ", ip
  for t in svc.txt:           echo "  txt:      ", t

proc main() =
  let opts = parseOptions()
  let group = if opts.ipv6: MdnsV6Group else: MdnsV4Group
  let iface = if opts.interfaceIp.len > 0: " on " & opts.interfaceIp else: ""
  echo "mdns: browsing ", opts.serviceType, ".local on ", group, ":",
       MdnsPort, iface, " for ", opts.timeoutMs div 1000, "s (Ctrl-C to stop)"
  var services = initTable[string, Service]()
  browse(services, opts.serviceType, opts.interfaceIp, opts.timeoutMs, opts.ipv6)
  if services.len == 0:
    echo "no services found"
    return
  echo "\nfound ", services.len, " service",
       (if services.len == 1: "" else: "s"), ":"
  for name, svc in services:
    printService(name, svc)
  echo ""

when isMainModule:
  main()
