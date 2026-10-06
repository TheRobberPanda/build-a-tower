# Build a Tower — full game feature plan

## Core concept (Paulo, 2026-10-06) — supersedes the plot/publish loop below
Round-based party game for 6 players. The home place is the player's own island
(free building, same as today). From there they queue for a round.

**Round flow**
1. Matchmaking: MemoryStore queue in the home place; 6 players teleport to a reserved server of the round place.
2. Build + verify, one shared 5:00 clock: build, then climb your own tower. You can go back to building after a failed climb. If the clock runs out before you reach your top, your tower is invalid and you are out of the race (you lose).
3. Race: valid towers are played in order. All players run the same copy with no collision between players and see each other as ghosts. Time limit 2:30 (Config.RACE_SECONDS, about half the build clock). The first player to reach the top wins. If nobody reaches it, everyone loses and the builder wins.
4. Replay and vote: the builder's own verify climb from the build phase is replayed (server-recorded path, PathCodec; RunTimerService already saves it on verify), not the race winner's run. So a builder can hide a secret route, but then must verify by another route: climbing through the secret shows it to everyone. The others rate the tower 1-5 stars and can donate coins or gift a Medal to the builder.
5. Save: winning towers are saved automatically and feed "Most popular" (ranked by stars). Invalid towers are discarded.

**Economy**
- Medals (not Roblox badges): random drops while playing, with rarities. Trade them in for coins.
- Coins: buy more pieces, donate to builders.
- Pass: one-time Game Pass that unlocks special pieces (portals, jump pads and similar).

## Round-mode milestones (build in order)
| # | Feature | Reuses |
|---|---|---|
| R1 | Round place + RoundService state machine (Lobby, Build, Race xN, Replay/Vote, Results), slots for 6 towers | PlotService, TowerService, RunTimerService |
| R2 | Matchmaking queue + teleport, home island stays as is | MemoryStore, TeleportService |
| R3 | Race: shared tower copy, players don't collide, ghosts, 2:30 limit, builder wins if nobody finishes | LiveRaceService, AntiCheat |
| R4 | Builder's verify-climb replay + 1-5 star vote, auto-save winning towers, Most popular list | PathCodec, PublishedStore |
| R5 | Coins: donations, piece shop | ProgressionService (Bricks becomes Coins) |
| R6 | Medals: random drops, rarities, trade-in for coins, gifting. Replaces Roblox badges in Badges.luau | DataService (schema bump) |
| R7 | Pass: special pieces gated behind the Game Pass | MonetizationService |

Open: "winning towers" is read as towers whose round produced a winner (any valid raced tower). Confirm.

---

## Legacy plan (built; parts get reworked by R1-R7)

V1 (see RELEASE.md) ships the core loop: build → verify by climbing → publish → others race.
Everything below comes after V1 and stays out of the codebase until V1 is public.
Each milestone is shippable on its own. Sizes: S ≈ 1 day, M ≈ 2–4 days, L ≈ 1–2 weeks.

## Principles
- Secrets stay legal and rewarded: finding a shortcut is skill, never cheating.
- Every feature feeds one of the loops: **build** (creativity), **race** (mastery), **discover** (secrets), **social** (show off).
- Server-authoritative, persisted ids never reused, mobile first (same rules as CLAUDE.md).

---

## M1. Discovery and difficulty — DONE (799b550)
Goal: players find towers worth racing instead of scrolling a raw "newest" list.

| Feature | Size | Notes |
|---|---|---|
| Difficulty labels | M | Computed from data, not the builder: completion rate (finishes / starts) and median time. Buckets: Easy / Medium / Hard / Insane. Stored on the published record, refreshed by a periodic job. |
| Browse tabs | M | Newest, Popular (starts in last 7 days), Hardest, Friends. Each tab is its own OrderedDataStore. |
| Likes | S | One like per player per tower after finishing it. Feeds Popular. |
| Tower search by builder name | S | Username → userId → `Towers_v1`. |
| Tower card preview | M | Height, piece count, difficulty, best time, record holder. |
| Play counts | S | Starts and finishes per tower, batched writes. |

## M2. Secrets as a feature — DONE
Goal: make secrets the identity of the game.

| Feature | Size | Notes |
|---|---|---|
| Secret badges | M | Per run, detect use of fake wall / invisible platform / teleporter / jump pad shortcut. Roblox badges: "Wall Walker", "Ghost Step", "Portal Hopper", "Found 10 secrets". |
| Secret counter on towers | S | "3 secrets hidden" shown on the card, not where they are. Builder sees how many racers found each one. |
| Builder hints vs average | M | After a race: "You were 12 s slower than average on this tower" and a per-secret "found by 18% of racers". |
| New secret pieces | L | Crumbling platform, conveyor, one-way wall, timed door, hidden button that opens a door. New ids 9+, never reuse. Each needs an AntiCheat allowance. |

## M3. Replays and ghosts — DONE
Goal: mastery loop. Learn routes from better players.

| Feature | Size | Notes |
|---|---|---|
| Server-recorded run path | M | Sample root position every 0.1 s on the server during runs. Compress (delta + quantize) and store only for the top 10 per tower. |
| Ghost racing | M | Race against the record ghost or your own best. Client-only translucent rig. |
| Replay viewer | M | Watch top runs with a free camera. |
| Split times | S | Checkpoint splits from a new Checkpoint piece. |

## M4. Builder progression and rewards — DONE
Goal: reasons to keep building.

| Feature | Size | Notes |
|---|---|---|
| Builder XP and levels | M | XP from your towers being finished and liked. Levels unlock piece budget (150 → 300), plot height, cosmetic materials. |
| Creator rewards | M | Currency (Bricks) when others finish your tower, capped per day to block farming with alt accounts. |
| Piece materials and colours | M | Cosmetic only, unlocked by level or Bricks. Fake walls must still be able to copy any material. |
| Multiple tower slots | M | Keep 3 towers, publish one at a time per slot. Data schema v2 with migration. |
| Decorations | M | Non-collidable props (plants, lights, signs) that don't count toward the budget. Signs are text-filtered. |

## M5. Social and live play — DONE
| Feature | Size | Notes |
|---|---|---|
| Visit plot | S | Teleport to anyone's plot in the server and watch them build. |
| Live races | L | 2–8 players race the same tower at once from a lobby pad. Separate copies of the tower per racer, or one shared copy with collisions between players turned off. |
| Weekly featured tower | M | Hand-picked or top liked. Global leaderboard with a badge for the top 3. |
| Co-building | L | Invite a friend to build on your plot. Owner keeps publish rights. |
| Friend notifications | S | "Your record on X was beaten" via in-game inbox. |

## M6. Monetization — DONE (ids stay 0 until passes/products exist)
No pay to win: times and leaderboards are never for sale.

| Item | Type | Notes |
|---|---|---|
| Builder Pass | Game pass | +100 budget, 2 extra tower slots, exclusive materials. |
| Trails and run effects | Dev products / Bricks | Cosmetic only. |
| VIP plot themes | Game pass | Plot base skins, skyboxes. |
| Premium payouts | Free | Engagement-based payouts; the loops above drive this. |

## M7. Events and live ops — DONE (schedule in Config.EVENT_PIECES / Config.CONTESTS)
- Seasonal build contests with a theme and a voted winner.
- Limited time pieces (e.g. a Halloween fake door).
- Monthly leaderboard resets for a "season best" next to the all-time best.

---

## Tech work that unlocks the above
| Item | Needed by | Size |
|---|---|---|
| Schema v2 migration path (multiple towers, currency, XP) | M4 | M |
| Stats aggregation job (difficulty, popularity) using MemoryStore + periodic DataStore flush | M1 | M |
| Path recording and compression lib, unit tested | M3 | M |
| Moderation: report a tower, auto-hide after N reports, review queue | M1 | M |
| Analytics events (funnel: join → place → verify → publish → race) | Launch + 1 week | S |
| Server error dashboard checks in the release routine | Launch | S |

## Suggested order
1. Launch V1 (RELEASE.md, Oct 21).
2. Analytics and moderation (first week, required to grow safely).
3. M1 Discovery → M2 Secrets → M3 Replays → M4 Progression → M5 Social → M6 Monetization.
4. Re-plan after each milestone from the funnel data: whatever step loses most players gets fixed first.
