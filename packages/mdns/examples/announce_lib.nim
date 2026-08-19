## Using the `mdns` package as a library.
##
## Run it on the same host as `mdns --browse _http._tcp` (or any DNS-SD
## browser) to see the service advertised and answered:
##
##   nim c -r examples/announce_lib.nim

import std/[net]
import mdns

let service = AnnouncedService(
  instance:   "My Library Server",
  serviceType: "_http._tcp",
  host:        "myserver",
  port:        Port(8080),
  txt:         @["path=/", "version=1.0"],
  addresses:   localIPv4Addrs())

let responder = newMdnsResponder(service)

# Probe for a unique name, then advertise it (RFC 6762 §8).
responder.announce(probe = true, repetitions = 2)
echo "announcing ", service.instance, " on ", service.serviceType.normServiceType

# Answer queries for the service until interrupted (RFC 6762 §6).
responder.serve()

# Unreachable in this example (serve blocks); on real shutdown:
#   responder.goodbye()
