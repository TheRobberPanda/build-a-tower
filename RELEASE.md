# Release plan

Target: public release **2026-10-21**. V1 scope only (see CLAUDE.md).
Steps marked **(Paulo)** need you in Studio or on the Creator Dashboard; the rest is code.

## 1. Finish the game (Oct 5–9)
- [x] Jump pad power / teleporter channel picker, restart button, unpaired-teleporter warning, personal best on results
- [ ] First-time hints in build mode (empty plot, no Finish yet)
- [ ] Lobby feel: lighting, skybox, simple ambient sound (free assets, CREDITS.md)
- [ ] Sounds: place, delete, jump pad, teleport, finish
- [ ] Max players vs plot spacing: set MaxPlayers (8) and check every plot fits
- [ ] Browse empty state ("No towers yet, be the first")
- [ ] **(Paulo)** Playtest checkpoint: one Studio session, ~15 min, I drive and screenshot

## 2. Private test (Oct 10–14)
- [ ] **(Paulo)** Publish the place to Roblox (private), enable Studio API access for DataStores
- [ ] Two-client local server test: browse, race, leaderboard, publish
- [ ] Mobile device emulation pass (phone + tablet): hotbar, tools, run HUD clear of thumbstick/jump
- [ ] DataStore check: rejoin keeps tower, session lock across servers, newer-schema refusal
- [ ] Fix everything found

## 3. Store page (Oct 15–18)
- [ ] Icon (512) and 3 thumbnails (1920x1080), within BUDGET.md
- [ ] Title, description, genre (Obby), tags
- [ ] **(Paulo)** Maturity questionnaire, set public settings, devices: phone/tablet/PC/console off
- [ ] **(Paulo)** Build and publish 3–5 seed towers so browse isn't empty

## 4. Soft launch (Oct 19–20)
- [ ] **(Paulo)** Make public, share with friends only
- [ ] Watch Creator Dashboard error reports and DataStore errors; hotfix

## 5. Public (Oct 21)
- [ ] Announce; keep watching errors for a week
- After: secret badges, difficulty labels, creator rewards (post-V1 list)
