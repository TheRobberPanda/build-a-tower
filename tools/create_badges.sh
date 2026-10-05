#!/bin/bash
# Creates the remaining badges (free quota: 5 per experience per day; expectedCost=0
# makes Roblox refuse instead of charging). Prints "Name id" for each one created.
cd "$(dirname "$0")/.." && set -a && . ./.env && set +a
mk(){ r=$(curl -s -X POST "https://apis.roblox.com/legacy-badges/v1/universes/10769472981/badges" -H "x-api-key: $ROBLOX_OPEN_CLOUD_API_KEY" -F "name=$2" -F "description=$3" -F "paymentSourceType=1" -F "expectedCost=0" -F "isActive=true" -F "files=@marketing/final/badges/$1.png;type=image/png")
 id=$(echo "$r" | python3 -c "import sys,json;print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
 if [ -n "$id" ]; then echo "$1 $id"; else echo "$1 FAILED $r"; return 1; fi; }
mk Launched "Launched" "Ride a jump pad in a race." &&
mk Doorman "Doorman" "Open a hidden door with a button in a race." &&
mk SecretHunter "Secret Hunter" "Find 10 secrets across all your races." &&
mk RecordHolder "Record Holder" "Set the best time on any tower." &&
mk FeaturedPodium "Featured Podium" "Finish top 3 on the weekly featured tower." &&
mk ContestWinner "Contest Winner" "Place top 3 in a build contest."
