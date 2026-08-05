import std/[unittest, tables, strutils]
import mdns

# Build a DNS/mDNS wire message by hand (no response encoder in the module).
proc nameBytes(name: string): seq[byte] =
  for label in name.split('.'):
    if label.len == 0: continue
    result.add byte(label.len)
    for c in label: result.add byte(c)
  result.add 0

proc u16(v: uint16): seq[byte] = @[byte(v shr 8), byte(v and 0xff)]

proc rr(name: string; rtype: uint16; rclass: uint16; ttl: uint32;
        rdata: seq[byte]): seq[byte] =
  result = nameBytes(name)
  result.add u16(rtype)
  result.add u16(rclass)
  result.add @[byte(ttl shr 24), byte(ttl shr 16), byte(ttl shr 8), byte(ttl)]
  result.add u16(uint16(rdata.len))
  result.add rdata

suite "mdns wire decoding":
  test "encodeBrowseQuery builds a PTR query for .local":
    let q = encodeBrowseQuery("_http._tcp")
    # header: id=0, flags=0, qdcount=1, an/ns/ar=0
    check q[0] == 0 and q[1] == 0
    check q[2] == 0 and q[3] == 0
    check q[4] == 0 and q[5] == 1
    check q[6] == 0 and q[7] == 0
    check q[8] == 0 and q[9] == 0
    check q[10] == 0 and q[11] == 0
    # QTYPE=PTR(12), QCLASS=QU|IN (0x8001)
    check q[^4] == 0 and q[^3] == 12
    check q[^2] == 0x80 and q[^1] == 0x01

  test "decodeMessage parses a response with PTR/SRV/TXT/A":
    var wire = @[byte 0, 0, 0x84, 0x00]   # id=0, QR=1
    wire.add u16(0)                       # qdcount
    wire.add u16(4)                       # ancount
    wire.add u16(0)                       # nscount
    wire.add u16(0)                       # arcount
    # PTR: _http._tcp.local. -> MyPrinter._http._tcp.local.
    wire.add rr("_http._tcp.local", 12, 0x8001, 4500,
                nameBytes("MyPrinter._http._tcp.local"))
    # SRV: MyPrinter._http._tcp.local. -> printer.local.:8080
    var srv = @[byte 0, 0, 0, 0, 0x1f, 0x90]  # prio, weight, port 8080
    srv.add nameBytes("printer.local")
    wire.add rr("MyPrinter._http._tcp.local", 33, 0x8001, 120, srv)
    # TXT: MyPrinter._http._tcp.local. -> "key=value"
    var txt = @[byte 9]
    for c in "key=value": txt.add byte(c)
    wire.add rr("MyPrinter._http._tcp.local", 16, 0x8001, 120, txt)
    # A: printer.local. -> 192.168.1.50
    wire.add rr("printer.local", 1, 0x8001, 120, @[byte 192, 168, 1, 50])

    let m = decodeMessage(wire)
    check m.qr
    check m.answers.len == 4

    var services = initTable[string, Service]()
    collectMessage(services, m)
    check services.len == 1
    let svc = services["MyPrinter._http._tcp.local."]
    check svc.serviceType == "_http._tcp.local."
    check svc.host == "printer.local."
    check svc.port == 8080
    check svc.addresses == @["192.168.1.50"]
    check svc.txt == @["key=value"]

  test "decodeMessage rejects a truncated message":
    expect MdnsError:
      discard decodeMessage(@[byte 0, 0, 0x84, 0x00, 0, 1])