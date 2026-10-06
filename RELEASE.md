# Release plan

Target: public release **2026-10-21**. V1 scope only (see CLAUDE.md).
Steps marked **(Paulo)** need you in Studio or on the Creator Dashboard; the rest is code.

## 1. Finish the game (Oct 5–9)
- [x] Jump pad power / teleporter channel picker, restart button, unpaired-teleporter warning, personal best on results
- [x] First-time hints in build mode (empty plot, no Finish yet)
- [x] Lighting: Future, atmosphere, bloom, colour correction (default.project.json)
- [x] Ambient sound
- [x] Sound hooks: place, delete, jump pad, teleport, finish, fail, ambient (src/shared/Sounds.luau)
- [x] Sound ids: Kenney CC0 SFX + generated ambient loop (CREDITS.md)
- [ ] **(Paulo)** Server size 6 on the Creator Dashboard (one round per server)
- [x] Browse empty state
- [ ] **(Paulo)** Playtest checkpoint: one Studio session, ~15 min, I drive and screenshot

- [x] Analytics: onboarding funnel (join → place → test run → verified → published), race events

- [x] Tower reports: 5 distinct reports hide that tower version from browse and block republishing it (Reports_v1)

## 2. Private test (Oct 10–14)
- [ ] **(Paulo)** Publish the place to Roblox (private), enable Studio API access for DataStores
- [ ] **(Paulo)** Multiplayer round session (2+ accounts): race, ghosts, vote, donate, results
- [ ] Mobile device emulation pass (phone + tablet): hotbar, tools, run HUD clear of thumbstick/jump
- [ ] DataStore check: rejoin keeps tower, session lock across servers, newer-schema refusal
- [ ] Fix everything found

## 3. Store page (Oct 15–18)
- [x] Icon: 2 variants in marketing/final (A tower, B secret wall) for A/B
- [x] 3 thumbnails in marketing/final/thumb_1-3.png (race one to recapture with real racers)
- [x] Title, description, genre (Obby) in marketing/description.md
- [ ] **(Paulo)** Maturity questionnaire, set public settings, devices: phone/tablet/PC/console off
- [ ] **(Paulo)** Build and publish 3–5 seed towers so browse isn't empty

- [x] Badges 1-5 created via Open Cloud (FirstPublish, FirstRace, WallWalker, GhostStep, PortalHopper); icons in marketing/final/badges
- [x] Badges 6-10 created 2026-10-06; ContestWinner: run tools/create_badges.sh on 2026-10-07
- [x] Game passes (Builder Pass 199, VIP 149) and Bricks packs (500 = 49, 1500 = 129) created with icons; ids in Config

## 4. Soft launch (Oct 19–20)
- [ ] **(Paulo)** Make public, share with friends only
- [ ] Watch Creator Dashboard error reports and DataStore errors; hotfix

## 5. Public (Oct 21)
- [ ] Announce; keep watching errors for a week
- After: secret badges, difficulty labels, creator rewards (post-V1 list)
