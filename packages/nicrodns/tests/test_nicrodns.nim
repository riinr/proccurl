import std/unittest
import nicrodns

suite "nicrodns message encode/decode":
  test "round-trips a query":
    let wire = block:
      var m = newMessage(0xbeef)
      m.addQuestion("example.com", rTypeA)
      encode(m)
    let parsed = decode(wire)
    check parsed.id == 0xbeef
    check parsed.qr == mtQuery
    check parsed.rd
    check parsed.questions.len == 1
    check parsed.questions[0].name == "example.com"
    check parsed.questions[0].qType == rTypeA

  test "round-trips a response with compressed names":
    let wire = block:
      var m = newMessage(1)
      m.qr = mtResponse
      m.ra = true
      m.answers.add ResourceRecord(
        name: "example.com", rType: rTypeA, rClass: rClassIN,
        ttl: 300, rdata: "\x7f\x00\x00\x01")
      encode(m)
    let parsed = decode(wire)
    check parsed.qr == mtResponse
    check parsed.answers.len == 1
    check parsed.answers[0].name == "example.com"
    check parsed.answers[0].ttl == 300
    check parsed.answers[0].rdataToIP == "127.0.0.1"

  test "decodes a real hand-built compressed response":
    # Query example.com A, answer with a compression pointer back to QNAME.
    var wire: seq[byte]
    proc u16(v: uint16) =
      wire.add byte(v shr 8); wire.add byte(v and 0xff)
    u16(0x2222)
    u16(0x8180) # response, rd+ra
    u16(1); u16(1); u16(0); u16(0)
    for b in [byte(7), byte('e'), byte('x'), byte('a'), byte('m'),
              byte('p'), byte('l'), byte('e'),
              byte(3), byte('c'), byte('o'), byte('m'), byte(0)]:
      wire.add b
    u16(1); u16(1) # qtype A, qclass IN
    # answer: name = pointer to offset 12
    wire.add byte 0xc0; wire.add byte 12
    u16(1); u16(1) # A, IN
    u16(1); u16(0x2c) # ttl 300
    u16(4) # rdlen
    wire.add byte 93; wire.add byte 184; wire.add byte 216; wire.add byte 34

    let parsed = decode(wire)
    check parsed.questions[0].name == "example.com"
    check parsed.answers[0].name == "example.com"
    check parsed.answers[0].rdataToIP == "93.184.216.34"

  test "rejects a forward compression pointer":
    var wire: seq[byte]
    proc u16(v: uint16) =
      wire.add byte(v shr 8); wire.add byte(v and 0xff)
    u16(0)
    u16(0)
    u16(1); u16(0); u16(0); u16(0)
    wire.add byte 0xc0; wire.add byte 30
    u16(1); u16(1)
    expect DnsError:
      discard decode(wire)

  test "rdataToIP formats AAAA":
    let rr = ResourceRecord(name: "a.example", rType: rTypeAAAA,
                            rClass: rClassIN, ttl: 0,
                            rdata: "\x20\x01\x0d\xb8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01")
    check rr.rdataToIP == "2001:0DB8:0000:0000:0000:0000:0000:0001"
