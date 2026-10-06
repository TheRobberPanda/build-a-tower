#!/bin/bash
# mcp.sh TOOL JSON_ARGS : call a tool on the port-58745 robloxstudio MCP server (stateless HTTP)
python3 - "$1" "$2" <<'PY'
import json,sys,urllib.request
tool,args=sys.argv[1],json.loads(sys.argv[2])
def call(body):
    req=urllib.request.Request("http://localhost:58745/mcp",json.dumps(body).encode(),{"Content-Type":"application/json","Accept":"application/json, text/event-stream"})
    raw=urllib.request.urlopen(req,timeout=120).read().decode()
    for line in raw.splitlines():
        if line.startswith("data:"):
            return json.loads(line[5:])
    return json.loads(raw)
r=call({"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":tool,"arguments":args}})
res=r.get("result",r)
for c in res.get("content",[]) if isinstance(res,dict) else []:
    print(c.get("text",""))
if "error" in r: print(r["error"])
PY
