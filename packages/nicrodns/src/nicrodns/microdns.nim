## Bindings for libmicrodns (mDNS responder/discovery).
##
## Faithful wrapper around `microdns.h` / `rr.h` from the vendored C library
## in `clib/`. Struct layouts and bitfields are read straight from the C
## headers via the `header` pragma, so field access stays ABI-correct.
##
## Typical flow:
## 1. `mdnsInit` a context,
## 2. for discovery: `mdnsListen`, or for serving: `mdnsAnnounce` +
##    `mdnsServe`,
## 3. `mdnsDestroy` the context.
##
## See the C headers for the exact semantics of each callback.

# --- constants ---------------------------------------------------------------

const
  MDNS_PORT*   = 5353
  MDNS_ADDR_IPV4* = "224.0.0.251"
  MDNS_ADDR_IPV6* = "FF02::FB"

  # error codes (see clib/compat/compat.h)
  MDNS_STDERR* = -1
  MDNS_NETERR* = -2
  MDNS_LKPERR* = -3
  MDNS_ERROR*  = -4

  # positive status passed to `MdnsListenCallback`
  MDNS_LISTEN_GOODBYE* = 1

  # header flags (enum mdns_hdr_flag)
  FLAG_QR* = 1 shl 15
  FLAG_AA* = 1 shl 10
  FLAG_TC* = 1 shl  9
  FLAG_RD* = 1 shl  8
  FLAG_RA* = 1 shl  7
  FLAG_Z*  = 1 shl  6
  FLAG_AD* = 1 shl  5
  FLAG_CD* = 1 shl  4

# --- enums -------------------------------------------------------------------

type
  RrType* {.size: sizeof(cint).} = enum
    RR_A    = 0x01
    RR_PTR  = 0x0C
    RR_TXT  = 0x10
    RR_AAAA = 0x1C
    RR_SRV  = 0x21

  RrClass* {.size: sizeof(cint).} = enum
    RR_IN = 0x01

  MdnsAnnounceType* {.size: sizeof(cint).} = enum
    MDNS_ANNOUNCE_INITIAL
    MDNS_ANNOUNCE_RESPONSE
    MDNS_ANNOUNCE_GOODBYE

# --- header-provided types ---------------------------------------------------

  MdnsCtx* {.importc: "struct mdns_ctx", header: "<microdns/microdns.h>".} = object

  SockAddr* {.importc: "struct sockaddr", header: "<sys/socket.h>".} = object

  InAddr* {.importc: "struct in_addr", header: "<netinet/in.h>".} = object
    s_addr* {.importc.}: uint32

  In6Addr* {.importc: "struct in6_addr", header: "<netinet/in.h>".} = object
    s6_addr* {.importc.}: array[16, uint8]

  MdnsHdr* {.bycopy, importc: "struct mdns_hdr", header: "<microdns/microdns.h>".} = object
    id*       {.importc.}: uint16
    flags*    {.importc.}: uint16
    numQn*    {.importc: "num_qn"}: uint16
    numAnsRr* {.importc: "num_ans_rr"}: uint16
    numAuthRr*{.importc: "num_auth_rr"}: uint16
    numAddRr* {.importc: "num_add_rr"}: uint16

  RrDataSrv* {.bycopy, importc: "struct rr_data_srv", header: "<microdns/rr.h>".} = object
    priority* {.importc.}: uint16
    weight*   {.importc.}: uint16
    port*     {.importc.}: uint16
    target*   {.importc.}: cstring

  RrDataTxt* {.bycopy, importc: "struct rr_data_txt", header: "<microdns/rr.h>".} = object
    txt* {.importc.}: array[256, char]
    next*{.importc.}: ptr RrDataTxt

  RrDataPtr* {.bycopy, importc: "struct rr_data_ptr", header: "<microdns/rr.h>".} = object
    domain* {.importc.}: cstring

  RrDataA* {.bycopy, importc: "struct rr_data_a", header: "<microdns/rr.h>".} = object
    addrStr* {.importc: "addr_str"}: array[16, char]
    address* {.importc: "addr"}: InAddr

  RrDataAAAA* {.bycopy, importc: "struct rr_data_aaaa", header: "<microdns/rr.h>".} = object
    addrStr* {.importc: "addr_str"}: array[46, char]
    address* {.importc: "addr"}: In6Addr

  RrData* {.union, bycopy, importc: "union rr_data", header: "<microdns/rr.h>".} = object
    SRV*  {.importc.}: RrDataSrv
    TXT*  {.importc.}: ptr RrDataTxt
    PTR*  {.importc.}: RrDataPtr
    A*    {.importc.}: RrDataA
    AAAA* {.importc.}: RrDataAAAA

  RrEntry* {.bycopy, importc: "struct rr_entry", header: "<microdns/rr.h>".} = object
    name*    {.importc.}: cstring
    rType*   {.importc: "type"}: uint16
    rrClass* {.importc: "rr_class"}: uint16
    msbit*   {.importc.}: uint16
    ttl*     {.importc.}: uint32
    dataLen* {.importc: "data_len"}: uint16
    data*    {.importc.}: RrData
    next*    {.importc.}: ptr RrEntry

# --- callbacks ---------------------------------------------------------------

  MdnsListenCallback* {.importc: "mdns_listen_callback",
                        header: "<microdns/microdns.h>".} = proc (
    cookie: pointer; status: cint; entry: ptr RrEntry) {.cdecl.}

  MdnsAnnounceCallback* {.importc: "mdns_announce_callback",
                          header: "<microdns/microdns.h>".} = proc (
    cookie: pointer; sockAddr: ptr SockAddr; service: cstring;
    typ: cint) {.cdecl.}

  MdnsStopFunc* {.importc: "mdns_stop_func",
                  header: "<microdns/microdns.h>".} = proc (
    cookie: pointer): bool {.cdecl.}

# --- functions ---------------------------------------------------------------

proc mdnsInit*(ctx: ptr ptr MdnsCtx; address: cstring; port: cushort): cint
  {.cdecl, importc: "mdns_init", header: "<microdns/microdns.h>".}

proc mdnsDestroy*(ctx: ptr MdnsCtx): cint
  {.cdecl, importc: "mdns_destroy", header: "<microdns/microdns.h>".}

proc mdnsEntriesSend*(ctx: ptr MdnsCtx; hdr: ptr MdnsHdr;
                      entries: ptr RrEntry): cint
  {.cdecl, importc: "mdns_entries_send", header: "<microdns/microdns.h>".}

proc mdnsEntriesPrint*(entry: ptr RrEntry)
  {.cdecl, importc: "mdns_entries_print", header: "<microdns/microdns.h>".}

proc mdnsStrerror*(error: cint; buf: cstring; n: csize_t): cint
  {.cdecl, importc: "mdns_strerror", header: "<microdns/microdns.h>".}

proc mdnsListen*(ctx: ptr MdnsCtx; names: cstringArray; nbNames: cuint;
                 typ: RrType; interval: cuint; stop: MdnsStopFunc;
                 callback: MdnsListenCallback; pCookie: pointer): cint
  {.cdecl, importc: "mdns_listen", header: "<microdns/microdns.h>".}

proc mdnsAnnounce*(ctx: ptr MdnsCtx; typ: RrType;
                   callback: MdnsAnnounceCallback; pCookie: pointer): cint
  {.cdecl, importc: "mdns_announce", header: "<microdns/microdns.h>".}

proc mdnsServe*(ctx: ptr MdnsCtx; stop: MdnsStopFunc; pCookie: pointer): cint
  {.cdecl, importc: "mdns_serve", header: "<microdns/microdns.h>".}

proc mdnsRequestInitialAnnounce*(ctx: ptr MdnsCtx; service: cstring)
  {.cdecl, importc: "mdns_request_initial_announce",
   header: "<microdns/microdns.h>".}

# --- helpers -----------------------------------------------------------------

iterator entries*(head: ptr RrEntry): ptr RrEntry =
  ## Iterate a linked list of `RrEntry` nodes starting at `head`.
  var cur = head
  while cur != nil:
    yield cur
    cur = cur.next
