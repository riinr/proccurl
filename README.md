# procCurl

### What?

Linux command/lib POC to use libcurl without¹ linking


### Why?

Every time we have to make a http request, we have some options:

1. Dynamic link our application with some SSL lib
  - pros:
    - Small executable size
    - Easier to update SSL lib
  - cons:
    - Easy to have incompatibility problems, system version won't match;
    - Easy to have conflict problems when it tries to install same lib twice;

2. Static link our application with some SSL lib
  - pros:
    - Less conflict/incompatibility problems
    - Easier to install
  - cons:
    - Larger executable size
    - Harder to update SSL lib

We're trying to make a small size, easier to update, easier to install, less conflict prone application.


### How?

Dividing our application in two:

- One dynamic (or static)¹ linked with libcurl, lets call it "proccurl"
- Other our actual application that will communicate with previous one, following defined __PROTOCOLS__.

It should be similar to [UCSPI](https://cr.yp.to/proto/ucspi.txt), but, we may differ in communication.

It should be similar to [MCP](https://modelcontextprotocol.io/docs/getting-started/intro), but, we may differ in communication.


## More details

1. Your app starts proccurl with `protocols`:
    1. proccurl returns a list of protocol ids separeted by new line.
2. Your app reads protocols to check if it knowns any of its protocols.
4. Your app starts proccurl with `proccurl connect --protocol {protocol}`.
    1. the comunication between your app and proccurl is defined by the protocol.
5. There are currently only one protocol implemented:
    1. [stdio-v1+jsonl-v1+json-rpc-v2+open-rpc-v1](./PROTOCOLS/STDIO-v1_JSONL-v1_JSON-RPC-v2_OPEN-RPC-v1.md)

__Example:__

```
echo '
{"jsonrpc": "2.0", "id": 1, "method": "/_API/v1"}
{"jsonrpc": "2.0", "id": 2, "method": "/curl/v0/get",  "params": { "url": "https://yesno.wtf/api"}}
{"jsonrpc": "2.0", "id": 3, "method": "/curl/v0/post", "params": { "url": "https://yesno.wtf/api", "body": "some content"}}
'|proccurl connect --protocol stdio-v1+jsonl-v1+json-rpc-v2
```

## TODO:

- [ ] Define spec (almost completed)
- [ ] Other CURL methods, other than GET, POST

