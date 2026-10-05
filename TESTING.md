# Test plan

Everything below is built but has only been checked without playing: Selene, StyLua,
58 TestEZ specs, every script compiling, and every module loading in Edit mode.
Nothing has been played yet. Work top to bottom; note anything odd next to its line.

Setup: `rojo serve`, connect Rojo in Studio, enable Studio API access for DataStores
(Game Settings → Security) so saving works in Play.

## A. Solo (Play, 1 player) — about 20 min
1. **Build:** place every piece 1–18 from the hotbar (scroll it sideways; keys 1–9 and 0 work too). Selecting a piece shows a one-line description above the hotbar. The Pumpkin (18) only shows between Oct 12 and Nov 4.
2. **Settings:** select Jump Pad, Teleport, Button, Door or Flag. The Setting button cycles power/channel (F on PC). Teleporters/buttons/doors/flags change colour by channel.
3. **Budget:** Pieces counter goes up for normal pieces, not for Plant/Lamp/Flag/Pumpkin.
4. **Hints:** empty plot shows "Tap the grid…"; without a Finish "Top it off…"; a lone teleporter shows "Teleporter channel N needs a partner".
5. **Sounds:** place/delete clicks, background music.
6. **Test run:** Test Run → timer, Restart and Quit buttons. Restart resets the timer.
7. **Mechanics in a run:** jump pad (all 3 powers), teleporter pair, fake wall (walk through), invisible platform, crumble (falls ~0.6 s after landing, back after 3 s), conveyor (carries you), one-way wall (pass from behind only), button opens same-colour doors for 6 s.
8. **Checkpoint:** touch one → "Checkpoint 1  0:xx" toast. Then reset your character (Esc → Reset): you respawn on the checkpoint and the run continues.
9. **AntiCheat:** none of step 7 should end the run with "Run invalid".
10. **Finish:** jingle, "Tower verified!". Menu → Publish with a name → works.
11. **My Towers (Menu → My Towers):** switch to slot 2 (empty tower), build, switch back (slot 1 intact, still verified). Materials: Plastic equipped; others locked by level/Bricks.
12. **Shop (under the level badge):** trails listed with Brick prices; passes/packs hidden until their ids are set.
13. **Rejoin:** stop and Play again. Tower, slots, material and name are kept.

## B. Two players (Test → Clients and Servers, 2 players) — about 20 min
1. **Browse:** Player 2 opens Menu → Browse. Tabs: Featured, (Contest after Oct 12), New, Popular, Hardest, Friends. Player 1's tower is in New with height, likes, "N secrets hidden".
2. **Race:** Player 2 races it. If Player 1 has a time, a ghost runs alongside. Finishing shows time, a "found a fake wall…" or "vs average" line, and a Like button.
3. **Like:** works once. Pressing it twice, or liking without finishing, does nothing.
4. **Leaderboard:** Times → list with Watch buttons, an "All time / This month" toggle, and Report. Watch plays the run with the camera following; "Stop watching" returns.
5. **Builder view:** Player 1 opens Times on their own tower: "a fake wall found by X% of racers" lines.
6. **Record beaten:** Player 1 races Player 2's tower slower than P2's record, then P2 beats P1's record somewhere. A toast appears for the beaten player.
7. **Players panel (Menu → Players):** Visit teleports to the other plot. Invite → the other gets Join/No thanks → Join → builds on the host plot ("Back to my plot" button). Host can't be edited during the host's test run.
8. **Live race:** P1 opens Browse and presses Live on P2's tower. The banner shows on both screens; P2 can't join their own tower's race. Add a 3rd player if possible. After 20 s everyone starts; opponents show as coloured ghosts; standings appear; final standings after all finish/quit.
9. **Report:** 5 different reporters are needed to hide a tower. With 2 players, just check that Report doesn't error.

## C. Things only you can check
- Progression: XP/Bricks arrive after another player finishes or likes your tower (stats flush every 60 s, claim on join and every 2 min).
- Badges award once ids are in `Config.BADGES`.
- Passes and Bricks packs once ids are in `Config.GAME_PASSES` / `Config.BRICK_PRODUCTS` (test purchases in Studio are free).
- Weekly featured tower and contest prizes settle after the week/contest ends (hourly check).

Report back with the step numbers that failed and any red errors in Output.
