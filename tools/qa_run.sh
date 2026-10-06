#!/bin/bash
# Runs the QA playtest end to end and prints the report.
S="$(dirname "$0")"
sleep 2
"$S/mcp_call.sh" execute_luau '{"code":"game.ServerStorage:SetAttribute(\"RunQA\", true)"}' >/dev/null
"$S/mcp_call.sh" start_playtest '{"mode":"play"}'
for i in $(seq 1 110); do r=$("$S/mcp_call.sh" get_playtest_output '{}'); echo "$r" | grep -q '"isRunning":false' && break; sleep 5; done
"$S/mcp_call.sh" execute_luau '{"code":"game.ServerStorage:SetAttribute(\"RunQA\", nil)"}' >/dev/null
echo "$r" > /tmp/bat_qa.json
python3 - <<PY
import json
d=json.load(open('/tmp/bat_qa.json'))
if 'testResult' not in d: print(d); raise SystemExit
t=json.loads(d['testResult'])
c=t['client']; print('seconds',t['seconds'])
if isinstance(c,str): print(c)
else:
  print('passed',c['passed'],'/',c['total'], c.get('aborted',''))
  for s in c['steps']: print('OK  ' if s['ok'] else 'FAIL', s['step'], '|', s.get('detail'))
  print('client log:'); [print('  ',l) for l in c['clientLog']]
print('server log:'); [print('  ',l) for l in t['serverLog']]
PY
"$S/mcp_call.sh" execute_luau '{"code":"local v = game:GetService(\"DataStoreService\"):GetDataStore(\"Players_v1\"):GetAsync(\"u_757790113\")\nreturn \"saved data after QA: active=\" .. v.data.activeSlot .. \" tower=\" .. #v.data.tower.pieces .. \" lock=\" .. tostring(v.lock)"}'
