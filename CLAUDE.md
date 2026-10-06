# Build a Tower (Roblox)

Round-based party game (see ROADMAP.md "Core concept"): 6 matchmade players share a
5:00 clock to build a tower and climb it themselves (unclimbed = invalid, out of the round).
Then everyone races each valid tower (2:30, ghosts, no collision). First to the top wins,
and if nobody gets there the builder wins. After the race: winner replay, 1-5 star vote,
coin donations, Medal gifts. Winning towers are saved. Players also have a home island
for free building. Secrets (fake walls, invisible platforms, jump
pads, teleporters) are core: anyone who finds them may use them.

## Scope
Full game per ROADMAP.md. Round-mode milestones R1-R7 in order (Paulo, 2026-10-06); the M1-M7 code is reused where it fits.

## Tooling
- Rojo 7.7 (`rojo serve`, plugin in Vinegar's `.../drive_c/users/frelse/AppData/Local/Roblox/Plugins`), Wally, Selene, StyLua via rokit (`rokit.toml`).
- Strict Luau everywhere (`--!strict`, `.luaurc`).
- Before committing: `selene src tests` and `stylua src tests`.
- Studio MCP (`robloxstudio`, Linux-native): Edit-mode use only (see Playtesting).
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

## Playtesting and screenshots
Check every visual change yourself: build an Edit-mode preview with `tools/preview_plot.luau` and capture Studio with `tools/studio_shot.sh OUT.png` (xwd: never raises or focuses the window; windows on top show up in the shot). Look at the image before calling it done.
Never start a playtest or send keyboard/mouse input (xdotool) on your own: it steals Paulo's focus. Edit-mode MCP calls are fine: run the specs with `tools/run_specs_edit.luau` via execute_luau (it bypasses Studio's require cache). For Play-mode checks use the QA harness (tests/QA.server.luau + qa/QAClient.client.luau): set ServerStorage attribute RunQA=true in Edit, start a playtest via the MCP, read the JSON report from get_playtest_output (testResult), clear RunQA. It plays through remotes without input or focus changes, works only in tower slot 3 and aborts if it can't switch there. The Studio MCP plugin only talks to port 58741.
