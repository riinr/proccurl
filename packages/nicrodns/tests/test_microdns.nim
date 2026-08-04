import std/unittest
import nicrodns/microdns

suite "microdns wrapper":
  test "mdns_strerror returns a message":
    var buf = newString(128)
    let rc = mdnsStrerror(MDNS_NETERR, buf.cstring, buf.len.csize_t)
    check rc == 0
    check buf.len > 0

  test "mdns_init and mdns_destroy":
    var ctx: ptr MdnsCtx
    check mdnsInit(addr ctx, nil, MDNS_PORT.cushort) == 0
    check ctx != nil
    check mdnsDestroy(ctx) == 0

  test "rr_entry field access through C header":
    var e = create(RrEntry)
    defer: dealloc(e)
    e.name = "myservice._http._tcp.local"
    e.rType = uint16(RR_SRV)
    e.rrClass = uint16(RR_IN)
    e.msbit = 1
    e.ttl = 120
    e.data.SRV.priority = 10
    e.data.SRV.weight = 5
    e.data.SRV.port = 8080
    e.data.SRV.target = "host.local"
    check e.rType == uint16(RR_SRV)
    check e.rrClass == uint16(RR_IN)
    check e.msbit == 1
    check e.ttl == 120
    check e.data.SRV.priority == 10
    check e.data.SRV.weight == 5
    check e.data.SRV.port == 8080
    check $e.data.SRV.target == "host.local"

  test "linked-list iterator":
    var
      head = create(RrEntry)
      tail = create(RrEntry)
    defer:
      dealloc(head)
      dealloc(tail)
    head.name = "one.local"
    head.next = tail
    tail.name = "two.local"
    tail.next = nil
    var names: seq[string]
    for entry in entries(head):
      names.add $entry.name
    check names == @["one.local", "two.local"]
