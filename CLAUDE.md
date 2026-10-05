# Build a Tower (Roblox)

Players build parkour/obby towers on their plot, must climb their own tower in a
server-timed test run to publish it (verify-to-publish), and others race published
towers for per-tower leaderboards. Secrets (fake walls, invisible platforms, jump
pads, teleporters) are core: anyone who finds them may use them.

## V1 scope (do not exceed)
One plot per player, 8 piece types, piece budget, verify-to-publish, browse list,
best times per tower. Later: secret badges, builder-vs-average hints, replays,
difficulty labels, creator rewards, live races.

## Tooling
- Rojo 7.7 (`rojo serve`, plugin in Vinegar's `.../drive_c/users/frelse/AppData/Local/Roblox/Plugins`), Wally, Selene, StyLua via rokit (`rokit.toml`).
- Strict Luau everywhere (`--!strict`, `.luaurc`).
- Before committing: `selene src tests` and `stylua src tests`.
- Studio MCP (`robloxstudio`, Linux-native) is connected: use it to playtest and read output.
- Tests: TestEZ specs in `tests/` (`*.spec.luau`), run automatically by `tests/RunTests.server.luau` when you press Play in Studio.

## Layout
- `src/shared` -> ReplicatedStorage.Shared: Config, PieceDefs, Types, Remotes, TowerCodec (pure tower logic).
- `src/server` -> ServerScriptService.Server: `Main.server.luau` bootstrap, `Services/` (PlotService, DataService, TowerService, AntiCheat, MechanicsService, RunTimerService), `Lib/` pure/injectable (ProfileStore, PublishedStore, Retry, SessionLock, RateLimiter, MovementCheck).
- `src/client` -> StarterPlayerScripts.Client: `init.client.luau` bootstrap, `State`, `UI/` (Theme, Kit), `Controllers/` (Build, UI, Mechanics).

## Rules
- Server-authoritative. Clients send intents (place type X at cell, rotation); server validates ownership, bounds, type, budget, overlap.
- Every remote: validate types and ranges (NaN/inf/fractions), rate-limit per player. Run timers measured on the server only.
- AntiCheat checks movement (fly/teleport/speed), never the route. Jump pads and teleporters must register their expected displacement so secrets stay legal.
- Piece type ids in PieceDefs are persisted: never renumber or reuse.

## Persistence
- Tower format: `{v=schema, pieces={{t,x,y,z,r,p?}}}` (grid ints, r 0-3).
- Player record (`Players_v1`, key `u_<userId>`): `{v, lock={j=jobId,t}, data=PlayerData, quarantine?}`. UpdateAsync only, retry+backoff, budget check, session lock (stale after 5x autosave), staggered autosave, PlayerRemoving + BindToClose release.
- Load failure = kick (never play on a default profile). Newer schema = refuse, never overwrite. Bad pieces are dropped on load; the original is kept in `quarantine`.
- `verifiedHash` = TowerCodec.hash of the tower the builder finished. Any edit clears it; publish requires it to equal the current hash.
- Published: `Towers_v1` (key ownerId), browse OrderedDataStore `Browse_v1` (publishedAt), leaderboards `LB_v1_<owner>_<hash16>` (best ms, ascending; only improvements written).

## UI rules
Mobile first: Scale sizing, UIAspectRatioConstraint, safe insets, keep thumbstick and jump areas clear during runs. Screens: build hotbar (8 pieces + budget), run HUD/timer, publish dialog, browse list, leaderboard, results.

## Assets and money
- Free assets only: Creator Store, Roblox audio, CC0 (Kenney, Quaternius, Poly Haven, ambientCG). No NC licences. Strip scripts from free models. Log in CREDITS.md.
- OpenRouter key in `.env` (gitignored). Never print or commit it.
- $10 hard budget, tracked in BUDGET.md. Paid calls are pre-approved (2026-10-05) but log every charge and never exceed the budget.

## Working with Paulo
Direct, short messages. Numbered steps for Studio actions. Commit after each working step. Use the roblox-dev skills when relevant.

## Screenshots
Play-mode screenshots: the MCP capture only works in Edit mode, so raise the Studio window with xdotool and grab it with PIL ImageGrab (X11/Cinnamon), then restore focus.
