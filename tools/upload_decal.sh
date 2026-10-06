#!/bin/bash
# upload_decal.sh FILE.png "Name" : uploads an image as a Decal via Open Cloud and
# prints the decal asset id (resolve the Image id in Studio with InsertService).
set -e
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
req=$(python3 -c 'import json,sys;print(json.dumps({"assetType":"Decal","displayName":sys.argv[1],"description":"Build a Tower","creationContext":{"creator":{"userId":sys.argv[2]}}}))' "$2" "$ROBLOX_CREATOR_USER_ID")
op=$(curl -s -X POST https://apis.roblox.com/assets/v1/assets -H "x-api-key: $ROBLOX_OPEN_CLOUD_API_KEY" \
  -F "request=$req" -F "fileContent=@$1;type=image/png" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])')
for i in $(seq 1 30); do
  r=$(curl -s "https://apis.roblox.com/assets/v1/$op" -H "x-api-key: $ROBLOX_OPEN_CLOUD_API_KEY")
  id=$(echo "$r" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("response",{}).get("assetId","") if d.get("done") else "")')
  [ -n "$id" ] && { echo "$id"; exit 0; }
  sleep 2
done
echo "timeout: $r" >&2; exit 1
