#!/bin/bash
# Ends a running Studio playtest via tests/StopListener.server.luau.
cd "$(dirname "$0")"
./mcp_call.sh execute_luau '{"code":"game:GetService(\"DataStoreService\"):GetDataStore(\"QA_v1\"):SetAsync(\"stop\", os.time()) return \"stop requested\""}'
