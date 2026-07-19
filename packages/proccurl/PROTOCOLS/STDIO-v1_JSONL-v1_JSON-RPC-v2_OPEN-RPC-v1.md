# stdio-v1+jsonl-v1+json-rpc-v2

## Description

Simplest RPC a command could implement.

## Transport

- STDIN: your app should send methods
- STDOUT: your app should read responses
- STDERR: application couldn't start (ie. wrong command/protocol name), or couldn't deserialize the message (ie. bad JSON format)

## Serialization

Both STDIN and STDOUT must be encoded as JSONL, it means one JSON object each line.

Empty and blank lines are ignored.

## Data format

STDIN lines must be a JSON-RPC-v2 valid request.

STDOUT lines will be a JSON-RPC-v2 valid response.

## Methods

First version will use CURL v8, but since methods aren't well defined yet, this is called _0_

## Examples:
Sequential requests

```bash
echo '
{"jsonrpc": "2.0", "id": 1, "method": "/_API/v1"}
{"jsonrpc": "2.0", "id": 2, "method": "/curl/v0/get",  "params": { "url": "https://yesno.wtf/api"}}
{"jsonrpc": "2.0", "id": 3, "method": "/curl/v0/post", "params": { "url": "https://yesno.wtf/api", "body": "{ \"json\": \"as body\"}"}}
'|\
proccurl connect --protocol stdio-v1+jsonl-v1+json-rpc-v2
```

Batch requests
```bash
echo '{"jsonrpc": "2.0", "id": 1, "method": "/curl/v0/batch", "params": { "requests": [{"id": 2, "method": "/curl/v0/get",  "params": { "url": "https://yesno.wtf/api"}}, {"id": 3, "method": "/curl/v0/get",  "params": { "url": "https://yesno.wtf/api"}}]}}'|\
    ./bin/proccurl connect --protocol stdio-v1+jsonl-v1+json-rpc-v2
```

## References

- POSIX stdio
- [JSONL 1.0](https://jsonlines.org/)
- [JSON-RPC 2.0](https://www.jsonrpc.org/specification)
- [OpenRPC](https://open-rpc.org)

