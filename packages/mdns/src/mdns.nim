## mdns — pure-Nim Multicast DNS (RFC 6762) service discovery.
##
## Given a network interface (identified by an IP address on that network),
## this module joins the mDNS multicast group, sends a DNS-SD browse query
## (RFC 6763), and collects the service announcements heard back. It has no
## C dependencies: DNS wire messages are parsed here, and the multicast group
## join is done with a raw `setsockopt`.
##
## This module is both a library and a command-line tool. Import it to browse
## for or advertise DNS-SD services on the local link:
##
##   * `browse` — send a PTR query and collect service announcements.
##   * `AnnouncedService` + `announce` — probe for a unique name and send
##     unsolicited announcements (RFC 6762 §8).
##   * `MdnsResponder` — a stateful responder that announces a service and
##     answers queries for it (RFC 6762 §6).
##
## It has no C dependencies: DNS wire messages are encoded and parsed here,
## and the multicast group join is done with a raw `setsockopt`.

import std/[net, os, strutils, tables, oserrors]
from std/times import epochTime
from std/posix import setsockopt, inet_pton, select, Timeval, TFdSet, FD_ZERO,
  FD_SET, FD_ISSET, Tipv6_mreq, InAddr, In6Addr, SockLen, AF_INET, AF_INET6,
  SOCK_DGRAM, IPPROTO_IP, IPPROTO_IPV6, IPV6_JOIN_GROUP, Time, Suseconds,
  SockAddr, Sockaddr_in, inet_ntop, INET_ADDRSTRLEN, gethostname

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

proc writeU32(buf: var seq[byte]; v: uint32) =
  buf.add byte((v shr 24) and 0xff)
  buf.add byte((v shr 16) and 0xff)
  buf.add byte((v shr 8) and 0xff)
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

proc localIPv4Addrs*(): seq[string] =
  ## Enumerate the non-loopback IPv4 addresses of all interfaces via getifaddrs.
  type
    Ifaddrs {.importc: "struct ifaddrs", header: "<ifaddrs.h>".} = object
      ifa_next: ptr Ifaddrs
      ifa_name: cstring
      ifa_flags: cuint
      ifa_addr: ptr SockAddr
      ifa_netmask: ptr SockAddr
  proc getifaddrs(ifap: ptr ptr Ifaddrs): cint {.importc, header: "<ifaddrs.h>".}
  proc freeifaddrs(ifap: ptr Ifaddrs) {.importc, header: "<ifaddrs.h>".}
  var ifap: ptr Ifaddrs
  if getifaddrs(addr ifap) != 0:
    raiseOSError(osLastError(), "getifaddrs")
  defer: freeifaddrs(ifap)
  var it = ifap
  while it != nil:
    if it.ifa_addr != nil and int(it.ifa_addr.sa_family) == int(AF_INET):
      let sa = cast[ptr Sockaddr_in](it.ifa_addr)
      var buf = newString(INET_ADDRSTRLEN)
      let r = inet_ntop(AF_INET, addr sa.sin_addr, buf.cstring, INET_ADDRSTRLEN)
      if r != nil:
        let ip = $r
        if ip notin result and not ip.startsWith("127."):
          result.add ip
    it = it.ifa_next

proc hostName*(): string =
  ## The system's host name, first label only, lowercased (RFC 6762 §14).
  var buf = newString(256)
  if gethostname(buf.cstring, 256) != 0:
    return "localhost"
  var idx = buf.find('\0')
  if idx < 0: idx = buf.len
  result = buf[0 ..< idx].split('.')[0].toLowerAscii

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
# Announcing (RFC 6762 §8) and responding (RFC 6762 §6)
# ---------------------------------------------------------------------------

const
  TtlPtr  = 4500.uint32  ## RFC 6762 §10: 75 min for records without a hostname
  TtlHost = 120.uint32   ## RFC 6762 §10: 2 min for records with a hostname

type
  AnnouncedService* = object
    instance*:   string          ## e.g. "My Web Server"
    serviceType*: string         ## e.g. "_http._tcp" or "_http._tcp.local."
    host*:       string          ## e.g. "myhost" or "myhost.local."
    port*:       Port
    txt*:        seq[string]     ## DNS-SD TXT key=value entries
    addresses*:  seq[string]     ## IPv4 addresses to advertise for `host`

  BuildRecord* = object          ## an RR we are about to put on the wire
    name*:  string
    rtype*: uint16
    flush*: bool                 ## RFC 6762 §10.2 cache-flush bit (rclass bit 15)
    ttl*:   uint32
    rdata*: seq[byte]

func ensureDot(s: string): string =
  result = s
  if result.len == 0 or result[^1] != '.': result.add '.'

func normServiceType*(st: string): string =
  ## Normalize a service type to e.g. "_http._tcp.local.".
  result = st.ensureDot
  if not result.endsWith(".local."): result.add "local."

func normHost(h: string): string =
  ## Normalize a host to e.g. "myhost.local.".
  result = h.ensureDot
  if not result.endsWith(".local."): result.add "local."

proc instanceName(a: AnnouncedService): string =
  let inst = a.instance.ensureDot
  result = inst & a.serviceType.normServiceType

proc nameRdata(n: string): seq[byte] =
  ## RDATA holding a full domain name (PTR target, SRV target).
  writeName(result, n)

proc srvRdata(port: Port; target: string): seq[byte] =
  ## SRV RDATA: priority(2) weight(2) port(2) target(name).
  let p = uint16(port)
  result = @[byte 0, 0, 0, 0, byte(p shr 8), byte(p and 0xff)]
  result.add nameRdata(target)

proc txtRdata(txt: seq[string]): seq[byte] =
  for s in txt:
    if s.len > 255:
      raise newException(MdnsError, "TXT entry longer than 255 bytes: '" & s & "'")
    result.add byte(s.len)
    for c in s: result.add byte(c)

proc aRdata(ip: string): seq[byte] =
  let parts = ip.split('.')
  if parts.len != 4:
    raise newException(MdnsError, "invalid IPv4 address: " & ip)
  for p in parts:
    let n = parseInt(p)
    if n < 0 or n > 255:
      raise newException(MdnsError, "invalid IPv4 address: " & ip)
    result.add byte(n)

proc serviceRecords*(a: AnnouncedService): seq[BuildRecord] =
  ## Build the DNS-SD record set advertising `a` (RFC 6763): one shared PTR
  ## record plus unique SRV, TXT and A records. The PTR is shared (no
  ## cache-flush bit); SRV/TXT/A are unique (cache-flush bit set, RFC 6762 §8.3).
  let st   = a.serviceType.normServiceType
  let inst = a.instanceName
  let host = a.host.normHost
  if a.port == Port(0):
    raise newException(MdnsError, "announced port cannot be 0")
  if a.addresses.len == 0:
    raise newException(MdnsError, "announced service needs at least one IPv4 address")
  result.add BuildRecord(name: st, rtype: uint16(rtPtr), flush: false,
                         ttl: TtlPtr, rdata: nameRdata(inst))
  result.add BuildRecord(name: inst, rtype: uint16(rtSrv), flush: true,
                         ttl: TtlHost, rdata: srvRdata(a.port, host))
  result.add BuildRecord(name: inst, rtype: uint16(rtTxt), flush: true,
                         ttl: TtlPtr, rdata: txtRdata(a.txt))
  for ip in a.addresses:
    result.add BuildRecord(name: host, rtype: uint16(rtA), flush: true,
                           ttl: TtlHost, rdata: aRdata(ip))

proc writeBuildRecord(buf: var seq[byte]; r: BuildRecord) =
  writeName(buf, r.name)
  buf.writeU16 r.rtype
  buf.writeU16 (if r.flush: 0x8001'u16 else: 1'u16)  # cache-flush | class IN
  buf.writeU32 r.ttl
  buf.writeU16 uint16(r.rdata.len)
  buf.add r.rdata

proc encodeHeader(buf: var seq[byte]; qr: bool; qd, an, ns, ar: int) =
  buf.writeU16 0                        # transaction id: mDNS uses 0
  buf.writeU16 (if qr: 0x8400'u16 else: 0'u16)  # flags: QR, opcode=QUERY
  buf.writeU16 uint16(qd)
  buf.writeU16 uint16(an)
  buf.writeU16 uint16(ns)
  buf.writeU16 uint16(ar)

proc encodeResponse*(answers, additionals: openArray[BuildRecord]): seq[byte] =
  ## Build a Multicast DNS response (QR=1) with the given Answer and Additional
  ## record sections. RFC 6762 §6: responses contain no questions.
  result.encodeHeader(true, 0, answers.len, 0, additionals.len)
  for r in answers:   result.writeBuildRecord r
  for r in additionals: result.writeBuildRecord r

proc encodeProbe*(names: openArray[string]; proposed: seq[BuildRecord]): seq[byte] =
  ## Build a probe query (RFC 6762 §8.1): one ANY question per name we want to
  ## claim uniquely, with our proposed records in the Authority Section so
  ## simultaneous probes can be tie-broken (RFC 6762 §8.2).
  result.encodeHeader(false, names.len, 0, proposed.len, 0)
  for n in names:
    result.writeName n
    result.writeU16 255      # QTYPE = ANY
    result.writeU16 0x8001   # QCLASS = QU bit | IN
  for r in proposed: result.writeBuildRecord r

proc buildSocket(interfaceIp: string; ipv6: bool): Socket =
  let group = if ipv6: MdnsV6Group else: MdnsV4Group
  result = openMdnsSocket(interfaceIp, ipv6)
  try:
    if ipv6:
      joinV6(result, group)
    else:
      joinV4(result, group, interfaceIp)
      setV4MulticastIf(result, interfaceIp)
  except CatchableError:
    result.close()
    raise

proc sendMsg(sock: Socket; msg: seq[byte]; group: string) =
  var qs = newStringOfCap(msg.len)
  for b in msg: qs.add char(b)
  sock.sendTo(group, MdnsPort, qs)

proc probeConflict(m: Message; names: seq[string]): string =
  ## RFC 6762 §8.1: an answer naming a name we are probing for is a conflict
  ## unless its rdata exactly matches our own proposed record for that name.
  for rr in m.answers & m.additionals & m.authorities:
    let nm = rr.name.normName
    if nm in names:
      return nm
  ""

proc probeUnique(sock: Socket; recs: seq[BuildRecord]; group: string) =
  ## RFC 6762 §8.1: send three ANY probe queries 250 ms apart and consider the
  ## names claimed only if no conflicting response is heard in between. A
  ## conflict raises MdnsError so the caller can pick a new name.
  var names: seq[string]
  for r in recs:
    if r.flush and r.name notin names: names.add r.name
  if names.len == 0: return
  let msg = encodeProbe(names, recs)
  for i in 0 ..< 3:
    sendMsg(sock, msg, group)
    let deadline = epochTime() + 0.25
    while epochTime() < deadline:
      var m: Message
      try:
        m = recvMessage(sock, int((deadline - epochTime()) * 1000))
      except TimeoutError:
        break
      if m.qr:
        let conflict = probeConflict(m, names)
        if conflict.len > 0:
          raise newException(MdnsError, "name conflict on " & conflict &
                                        "; choose a different instance/host name")

proc announce*(service: AnnouncedService; interfaceIp = ""; ipv6 = false;
               probe = true; repetitions = 2) =
  ## Probe for name uniqueness then send `repetitions` unsolicited multicast
  ## announcements one second apart (RFC 6762 §8.1, §8.3). `repetitions` must
  ## be at least 2 (RFC 6762 §8.3: "MUST send at least two").
  let reps = max(repetitions, 2)
  let group = if ipv6: MdnsV6Group else: MdnsV4Group
  let recs = serviceRecords(service)
  let sock = buildSocket(interfaceIp, ipv6)
  try:
    if probe: probeUnique(sock, recs, group)
    let msg = encodeResponse(recs, [])
    for i in 0 ..< reps:
      sendMsg(sock, msg, group)
      if i < reps - 1: sleep(1000)
  finally:
    sock.close()

proc goodbye*(service: AnnouncedService; interfaceIp = ""; ipv6 = false) =
  ## Send goodbye announcements (RR TTL zero) for `service` so peer caches drop
  ## it promptly (RFC 6762 §10.1).
  let group = if ipv6: MdnsV6Group else: MdnsV4Group
  var recs = serviceRecords(service)
  for r in recs.mitems: r.ttl = 0
  let sock = buildSocket(interfaceIp, ipv6)
  try:
    sendMsg(sock, encodeResponse(recs, []), group)
  finally:
    sock.close()

proc answersFor*(m: Message; recs: seq[BuildRecord]): tuple[ans, add: seq[BuildRecord]] =
  ## RFC 6762 §6: pick the records that answer each question in `m` (matching
  ## name, and qtype ANY or equal rtype); the rest of the record set goes in
  ## the Additional section to flesh out the answer.
  for q in m.questions:
    let qn = q.name.normName
    for r in recs:
      if r.name.normName != qn: continue
      if q.qtype != 255 and q.qtype != r.rtype: continue
      if r notin result.ans: result.ans.add r
  for r in recs:
    if r notin result.ans: result.add.add r

proc respond*(service: AnnouncedService; interfaceIp = ""; ipv6 = false;
              runSeconds = 0.0) =
  ## Join the mDNS group and answer queries for `service` until Ctrl-C (or
  ## `runSeconds`, if positive). RFC 6762 §6. This is what makes the announced
  ## service discoverable: a peer browsing the same service type will query
  ## and receive our PTR/SRV/TXT/A records.
  let group = if ipv6: MdnsV6Group else: MdnsV4Group
  let recs = serviceRecords(service)
  let sock = buildSocket(interfaceIp, ipv6)
  let deadline = if runSeconds > 0: epochTime() + runSeconds else: -1.0
  try:
    while true:
      let remaining =
        if deadline > 0:
          int((deadline - epochTime()) * 1000)
        else:
          -1
      if deadline > 0 and remaining <= 0: break
      var m: Message
      try:
        m = recvMessage(sock, (if remaining < 0: 1000 else: remaining))
      except TimeoutError:
        continue
      if m.qr: continue
      let (ans, add) = answersFor(m, recs)
      if ans.len == 0: continue
      sendMsg(sock, encodeResponse(ans, add), group)
  finally:
    sock.close()

# ---------------------------------------------------------------------------
# High-level responder (library API)
# ---------------------------------------------------------------------------

type
  MdnsResponder* = ref object
    ## A stateful mDNS responder for one service. `announce` probes for a
    ## unique name and advertises it; `serve` answers queries for it (blocks);
    ## `goodbye` removes it from peer caches on shutdown.
    service*:     AnnouncedService
    interfaceIp*: string
    ipv6*:        bool
    registered*:  bool   ## true once `announce` has completed

proc newMdnsResponder*(service: AnnouncedService; interfaceIp = ""; ipv6 = false): MdnsResponder =
  ## Create a responder for `service`. Pass `interfaceIp` (a local IPv4 address
  ## on the interface to use) to pin the responder to one interface.
  result = MdnsResponder(service: service, interfaceIp: interfaceIp, ipv6: ipv6)

proc announce*(r: MdnsResponder; probe = true; repetitions = 2) =
  ## Probe for name uniqueness (RFC 6762 §8.1) and send `repetitions`
  ## unsolicited announcements (RFC 6762 §8.3). Raises `MdnsError` on a name
  ## conflict so the caller can pick a different instance/host name.
  announce(r.service, r.interfaceIp, r.ipv6, probe, repetitions)
  r.registered = true

proc serve*(r: MdnsResponder; runSeconds = 0.0) =
  ## Answer queries for the announced service (RFC 6762 §6) until Ctrl-C, or
  ## for `runSeconds` seconds if positive. Blocks the calling thread; run it in
  ## your own thread if you need to keep doing other work.
  respond(r.service, r.interfaceIp, r.ipv6, runSeconds)

proc goodbye*(r: MdnsResponder) =
  ## Send goodbye announcements (RR TTL zero) so peer caches drop the service
  ## promptly (RFC 6762 §10.1).
  goodbye(r.service, r.interfaceIp, r.ipv6)
  r.registered = false
