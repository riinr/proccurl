## nicrodns — minimal pure-Nim DNS message parser and UDP resolver.
##
## Implements DNS header, question and resource-record types plus wire-format
## encode/decode (with name compression) and a small `resolve` helper built on
## `std/net`.

import std/net
import std/selectors
import std/strutils

type
  MessageType* = enum
    mtQuery    = 0
    mtResponse = 1

  Opcode* = enum
    opQuery    = 0
    opIQuery   = 1
    opStatus   = 2
    opNotify   = 4
    opUpdate   = 5

  RCode* = enum
    rcNoError   = 0
    rcFormatErr = 1
    rcServerErr = 2
    rcNameErr   = 3
    rcNotImpl   = 4
    rcRefused   = 5

  RecordType* = enum
    rTypeA     = 1
    rTypeNS    = 2
    rTypeCNAME = 5
    rTypeSOA   = 6
    rTypePTR   = 12
    rTypeMX    = 15
    rTypeTXT   = 16
    rTypeAAAA  = 28
    rTypeSRV   = 33

  RecordClass* = enum
    rClassIN = 1
    rClassCS = 2
    rClassCH = 3
    rClassHS = 4

  Question* = object
    name*:   string
    qType*:  RecordType
    qClass*: RecordClass

  ResourceRecord* = object
    name*:   string
    rType*:  RecordType
    rClass*: RecordClass
    ttl*:    uint32
    rdata*:  string

  Message* = object
    id*:          uint16
    qr*:          MessageType
    opcode*:      Opcode
    aa*:          bool
    tc*:          bool
    rd*:          bool
    ra*:          bool
    rcode*:       RCode
    questions*:   seq[Question]
    answers*:     seq[ResourceRecord]
    authorities*: seq[ResourceRecord]
    additionals*: seq[ResourceRecord]

  DnsError* = object of CatchableError

func newMessage*(id: uint16; rd = true): Message =
  Message(id: id, qr: mtQuery, opcode: opQuery, rd: rd, rcode: rcNoError)

func addQuestion*(m: var Message; name: string; qType = rTypeA;
                  qClass = rClassIN) =
  m.questions.add(Question(name: name, qType: qType, qClass: qClass))

# ---------------------------------------------------------------------------
# Wire-format encoding
# ---------------------------------------------------------------------------

proc writeU16(buf: var seq[byte]; v: uint16) =
  buf.add byte(v shr 8)
  buf.add byte(v and 0xff)

proc writeU32(buf: var seq[byte]; v: uint32) =
  buf.writeU16 uint16((v shr 16) and 0xffff)
  buf.writeU16 uint16(v and 0xffff)

proc writeName(buf: var seq[byte]; name: string) =
  if name.len == 0:
    buf.add 0
    return
  for label in name.split('.'):
    if label.len == 0 or label.len > 63:
      raise newException(DnsError, "invalid label in name: '" & name & "'")
    buf.add byte(label.len)
    for c in label:
      buf.add byte(c)
  buf.add 0

proc encode*(m: Message): seq[byte] =
  ## Serialize a `Message` to DNS wire format.
  result.writeU16 m.id
  var flags = 0'u16
  flags = flags or (uint16(ord(m.qr)) shl 15)
  flags = flags or (uint16(ord(m.opcode)) shl 11)
  if m.aa: flags = flags or (1'u16 shl 10)
  if m.tc: flags = flags or (1'u16 shl 9)
  if m.rd: flags = flags or (1'u16 shl 8)
  if m.ra: flags = flags or (1'u16 shl 7)
  flags = flags or uint16(ord(m.rcode))
  result.writeU16 flags
  result.writeU16 uint16(m.questions.len)
  result.writeU16 uint16(m.answers.len)
  result.writeU16 uint16(m.authorities.len)
  result.writeU16 uint16(m.additionals.len)
  for q in m.questions:
    result.writeName q.name
    result.writeU16 uint16(ord(q.qType))
    result.writeU16 uint16(ord(q.qClass))
  for rr in m.answers & m.authorities & m.additionals:
    result.writeName rr.name
    result.writeU16 uint16(ord(rr.rType))
    result.writeU16 uint16(ord(rr.rClass))
    result.writeU32 rr.ttl
    result.writeU16 uint16(rr.rdata.len)
    for c in rr.rdata:
      result.add byte(c)

# ---------------------------------------------------------------------------
# Wire-format decoding
# ---------------------------------------------------------------------------

proc readU16(buf: seq[byte]; pos: var int): uint16 =
  if pos + 2 > buf.len:
    raise newException(DnsError, "truncated message")
  result = (uint16(buf[pos]) shl 8) or uint16(buf[pos + 1])
  pos += 2

proc readU32(buf: seq[byte]; pos: var int): uint32 =
  result = (uint32(readU16(buf, pos)) shl 16) or uint32(readU16(buf, pos))

proc readName(buf: seq[byte]; pos: var int; jumpBudget: var int): string =
  ## Read a (possibly compressed) domain name. `cursor` walks the bytes that
  ## spell the name (possibly following backward compression pointers) while
  ## `readPos` records where the outer message should continue after the name
  ## — past the first pointer, not into the jumped tail. Pointers may only
  ## point backwards, so each jump reduces `jumpBudget` to bound the work.
  let start = pos
  var readPos = pos
  var cursor = pos
  var jumped = false
  while true:
    if cursor >= buf.len:
      raise newException(DnsError, "truncated name")
    let len = int(buf[cursor])
    if len == 0:
      if not jumped: readPos = cursor + 1
      break
    if (len and 0xc0) == 0xc0:
      if cursor + 1 >= buf.len:
        raise newException(DnsError, "truncated pointer")
      let target = ((len and 0x3f) shl 8) or int(buf[cursor + 1])
      if not jumped:
        readPos = cursor + 2
        jumped = true
      if target >= start or target >= buf.len:
        raise newException(DnsError, "invalid compression pointer")
      dec jumpBudget
      if jumpBudget < 0:
        raise newException(DnsError, "too many compression jumps")
      cursor = target
    else:
      if cursor + 1 + len > buf.len:
        raise newException(DnsError, "truncated label")
      if result.len > 0: result.add '.'
      for i in 0 ..< len:
        result.add char(buf[cursor + 1 + i])
      cursor += 1 + len
  pos = readPos

proc readQuestion(buf: seq[byte]; pos: var int): Question =
  var budget = 16
  result.name = readName(buf, pos, budget)
  let qType = readU16(buf, pos)
  let qClass = readU16(buf, pos)
  if qType > uint16(high(RecordType)) or qClass > uint16(high(RecordClass)):
    raise newException(DnsError, "unsupported qtype/qclass")
  # `cast` keeps out-of-band hole values (e.g. obsolete type 3) representable;
  # `case` on them falls through to `else` in consumers.
  result.qType = cast[RecordType](qType)
  result.qClass = cast[RecordClass](qClass)

proc readRR(buf: seq[byte]; pos: var int): ResourceRecord =
  var budget = 16
  result.name = readName(buf, pos, budget)
  let rType = readU16(buf, pos)
  let rClass = readU16(buf, pos)
  if rType > uint16(high(RecordType)) or rClass > uint16(high(RecordClass)):
    raise newException(DnsError, "unsupported record type/class")
  result.rType = cast[RecordType](rType)
  result.rClass = cast[RecordClass](rClass)
  result.ttl = readU32(buf, pos)
  let rdlen = int(readU16(buf, pos))
  if pos + rdlen > buf.len:
    raise newException(DnsError, "truncated rdata")
  result.rdata = newString(rdlen)
  for i in 0 ..< rdlen:
    result.rdata[i] = char(buf[pos + i])
  pos += rdlen

proc decode*(data: seq[byte]): Message =
  ## Parse a DNS wire-format message. Throws `DnsError` on malformed input.
  var pos = 0
  result.id = readU16(data, pos)
  let flags = readU16(data, pos)
  result.qr = MessageType((flags shr 15) and 1)
  let op = (flags shr 11) and 0xf
  result.opcode = cast[Opcode](op)
  result.aa = ((flags shr 10) and 1) == 1
  result.tc = ((flags shr 9) and 1) == 1
  result.rd = ((flags shr 8) and 1) == 1
  result.ra = ((flags shr 7) and 1) == 1
  let rc = flags and 0xf
  result.rcode = if rc <= 5'u16: RCode(rc) else: rcServerErr
  let nq = int(readU16(data, pos))
  let na = int(readU16(data, pos))
  let nns = int(readU16(data, pos))
  let nar = int(readU16(data, pos))
  for _ in 0 ..< nq:
    result.questions.add readQuestion(data, pos)
  for _ in 0 ..< na:
    result.answers.add readRR(data, pos)
  for _ in 0 ..< nns:
    result.authorities.add readRR(data, pos)
  for _ in 0 ..< nar:
    result.additionals.add readRR(data, pos)

# ---------------------------------------------------------------------------
# High-level helpers
# ---------------------------------------------------------------------------

func rdataToIP*(rr: ResourceRecord): string =
  ## Interpret `rr.rdata` as a human-readable IP (A or AAAA).
  case rr.rType
  of rTypeA:
    if rr.rdata.len != 4:
      raise newException(DnsError, "malformed A record")
    for i, b in rr.rdata:
      if i > 0: result.add '.'
      result.add $ord(b)
  of rTypeAAAA:
    if rr.rdata.len != 16:
      raise newException(DnsError, "malformed AAAA record")
    for i in countup(0, 14, 2):
      if i > 0: result.add ':'
      result.add toHex((ord(rr.rdata[i]) shl 8) or ord(rr.rdata[i + 1]), 4)
  else:
    raise newException(DnsError, "record is not an IP address")

proc resolve*(name: string; qType = rTypeA; server = "8.8.8.8";
              port = Port(53); timeoutMs = 3000): seq[ResourceRecord] =
  ## Send a query to `server` over UDP and return the answers.
  ## Raises `DnsError` if no response arrives within `timeoutMs`.
  let sock = newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
  defer: sock.close
  let msg = block:
    var m = newMessage(0x1234)
    m.addQuestion(name, qType)
    m
  let wire = cast[string](encode(msg))
  sock.sendTo(server, port, wire)
  let sel = newSelector[int]()
  defer: sel.close
  sel.registerHandle(sock.getFd, {Event.Read}, 0)
  if sel.select(timeoutMs).len == 0:
    raise newException(DnsError, "no response from " & server &
                                 " within " & $timeoutMs & "ms")
  var resp = newString(4096)
  var addrFrom = ""
  var portFrom = Port(0)
  let n = sock.recvFrom(resp, 4096, addrFrom, portFrom)
  if n <= 0:
    raise newException(DnsError, "no response from " & server)
  let parsed = decode(cast[seq[byte]](resp[0 ..< n]))
  if parsed.id != msg.id:
    raise newException(DnsError, "mismatched response id")
  if parsed.qr != mtResponse:
    raise newException(DnsError, "not a response")
  case parsed.rcode
  of rcNoError: discard
  of rcNameErr: raise newException(DnsError, "name does not exist: " & name)
  else: raise newException(DnsError, "server error rcode=" & $ord(parsed.rcode))
  result = parsed.answers
