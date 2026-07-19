import std/[random, json, os]


randomize()

for i in 0..20.rand:
  echo %*{"jsonrpc": "2.0", "id": i, "method": "/curl/v0/get", "params": {"url": "https://yesno.wtf/api"}}
  echo "   "
  sleep 1000.rand
