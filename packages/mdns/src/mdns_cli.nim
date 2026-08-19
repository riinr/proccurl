## mdns — command-line front-end for the `mdns` library.
##
## Builds the `mdns` binary (see `mdns.nimble`). All protocol logic lives in
## `mdns.nim`; this file only parses command-line arguments and prints results.

import std/[net, strutils, parseopt, tables]
import mdns

const Usage = """mdns — Multicast DNS (RFC 6762) service discovery and advertising

Usage:
  mdns [options] [interface-ip]

Searches for mDNS announcements on the network reached through `interface-ip`
(a local IP that belongs to the interface you want to listen on). If omitted,
the default interface is used.

Options:
  -q, --query <type>    Service type to browse (default: _services._dns-sd._udp)
  -t, --timeout <sec>   Seconds to listen for announcements (default: 5)
  -a, --announce <inst> Advertise a service and answer queries for it
  -n, --name <name>     Host name for --announce (default: hostname)
  -p, --port <port>     Port for --announce
  -s, --serve           After announcing, keep answering queries until Ctrl-C
  -x, --txt <k=v>       TXT entry for --announce (repeatable)
  -q, --query <type>    Service type to advertise for --announce (default: _http._tcp)
  -6, --ipv6            Use the IPv6 multicast group ff02::fb instead of IPv4
  -h, --help            Show this help
"""

type
  Options = object
    interfaceIp: string
    serviceType: string
    timeoutMs: int
    ipv6: bool
    announce: bool
    serve: bool
    name: string
    port: int
    txt: seq[string]
    instance: string

proc parseOptions(): Options =
  result.serviceType = MdnsDefaultType
  result.timeoutMs = 5000
  result.name = hostName()
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
      of "announce", "a": result.announce = true; result.instance = takeValue(p.key)
      of "name", "n": result.name = takeValue(p.key)
      of "port", "p": result.port = parseInt(takeValue(p.key))
      of "txt", "x": result.txt.add takeValue(p.key)
      of "serve", "s": result.serve = true
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
  if opts.announce:
    if opts.port == 0:
      echo "mdns: --announce requires --port"
      quit 1
    let addrs =
      if opts.interfaceIp.len > 0: @[opts.interfaceIp]
      else: localIPv4Addrs()
    if addrs.len == 0:
      echo "mdns: no IPv4 address available to advertise; pass an interface IP"
      quit 1
    let svc = AnnouncedService(
      instance: opts.instance, serviceType: opts.serviceType,
      host: opts.name, port: Port(opts.port),
      txt: opts.txt, addresses: addrs)
    echo "mdns: announcing ", opts.instance, " on ",
         opts.serviceType.normServiceType, " port ", opts.port,
         " via ", group, ":", MdnsPort, " (", addrs.join(", "), ")"
    announce(svc, opts.interfaceIp, opts.ipv6, probe = true, repetitions = 2)
    if opts.serve:
      echo "mdns: answering queries until Ctrl-C"
      respond(svc, opts.interfaceIp, opts.ipv6)
    return
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
