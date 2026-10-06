--!strict
-- Game-wide tunables. Grid coordinates are integer cells; GRID_STUDS converts to studs.

local Config = {
	SCHEMA_VERSION = 1,

	GRID_STUDS = 6, -- bigger cells = faster building (a block is still jumpable)
	PLOT_CELLS_X = 16, -- valid x: 0..PLOT_CELLS_X-1
	PLOT_CELLS_Z = 16,
	PLOT_CELLS_MAX = 24, -- home island after every expansion (+2 cells per expansion)
	PLOT_CELLS_Y = 64, -- valid y: 0..PLOT_CELLS_Y-1
	-- Round towers only (home islands are empty): fixed tower frame in the middle (cells; x0/z0 inclusive, x1/z1
	-- exclusive): four corner pillars and an unremovable floor every `level` rows,
	-- hollow in between so players can build inside it as well as around it.
	CORE = table.freeze({ x0 = 5, x1 = 11, z0 = 5, z1 = 11, level = 6, levels = 5, height = 30 }),
	PIECE_BUDGET = 150, -- at level 1; grows with level (Progression.budget)
	PIECE_BUDGET_MAX = 300,
	PIECE_BUDGET_STORED = 400, -- largest tower any player can have (level cap + Builder Pass)
	DECOR_MAX = 60,
	TOWER_SLOTS = 3, -- free slots; Builder Pass adds PASS_EXTRA_SLOTS
	PASS_EXTRA_SLOTS = 2,
	PASS_EXTRA_BUDGET = 100,
	MAX_TOWER_SLOTS = 5,
	MAX_LEVEL = 50,
	TOWER_NAME_MAX = 24,

	-- DataStores
	PLAYER_STORE = "Players_v1",
	PUBLISHED_STORE = "Towers_v1",
	BROWSE_STORE = "Browse_v1",
	LEADERBOARD_PREFIX = "LB_v1_",
	SEASON_LB_PREFIX = "LBS_v1_", -- + yyyymm_owner_hash16: monthly boards
	REPORTS_STORE = "Reports_v1",
	STATS_STORE = "Stats_v1",
	POPULAR_STORE = "Popular_v1",
	HARDEST_STORE = "Hardest_v1",
	STATS_FLUSH_SECONDS = 60,
	DIFFICULTY_MIN_STARTS = 10, -- attempts before a tower gets a difficulty label
	LIKED_MAX = 300, -- likes remembered per player (oldest dropped)
	REPORTS_TO_HIDE = 5, -- distinct reporters before a tower version leaves the browse list
	AUTOSAVE_SECONDS = 120,
	LOCK_STALE_SECONDS = 5 * 120, -- 5x autosave; an older lock means its server died
	LOAD_LOCK_RETRIES = 5, -- how often to retry when another server holds the lock
	LOAD_LOCK_WAIT = 4,
	DS_ATTEMPTS = 5,
	DS_BASE_DELAY = 1,
	DS_MAX_DELAY = 16,

	-- Mechanics (shared so client launch and server allowance match)
	-- by power 1..3, studs/s upward. v = sqrt(2 * 196.2 * h): power 1 clears one
	-- tower level (CORE.level cells = 36 studs) with room to land, 2 and 3 more.
	JUMP_PAD_SPEED = table.freeze({ 128, 150, 172 }),
	TELEPORT_COOLDOWN = 1.5,
	CONVEYOR_SPEED = 26, -- studs/s; AntiCheat adds this to the horizontal limit
	CRUMBLE_DELAY = 0.9,
	CRUMBLE_RESPAWN = 3,
	COLLAPSE_DELAY = 3, -- red (badly supported) pieces crumble this long after an edit
	COLLAPSE_HOPS = 4, -- support distance that glows red (PlotService) and collapses
	DOOR_OPEN_SECONDS = 6,
	DAY_SECONDS = 300, -- one full day/night cycle (a build phase)

	-- AntiCheat (only checked during runs)
	AC_SAMPLE_SECONDS = 0.2,
	AC_MAX_RISE_SPEED = 60, -- normal jump peaks ~53 studs/s
	AC_SPEED_FACTOR = 1.5, -- allowed horizontal speed = WalkSpeed * factor + slack
	AC_SPEED_SLACK = 6,
	SPRINT_SPEED = 26, -- WalkSpeed while sprinting (walk is 16); AntiCheat assumes it
	AC_TELEPORT_RADIUS = 10,
	AC_FLAGS_TO_FAIL = 3,
	AC_HOVER_SECONDS = 1.2, -- airborne without descending for longer than this = hover
	AC_FLAG_DECAY_SECONDS = 10, -- one flag forgiven per this many clean seconds (lag spikes)

	-- Badge asset ids from the Creator Dashboard; 0 = not created yet.
	BADGES = table.freeze({
		FirstPublish = 2148506926772295,
		FirstRace = 1564852800504017,
		WallWalker = 4295287596393535, -- went through a fake wall in a race
		GhostStep = 3145026699510500, -- stood on an invisible platform
		PortalHopper = 4196301637642163, -- used a teleporter
		Launched = 1993541554624605, -- used a jump pad
		Doorman = 4380317943630227, -- opened a door with a button
		SecretHunter = 20121175002839, -- 10 secrets found in total
		RecordHolder = 1990899061187345, -- best time on any tower
		FeaturedPodium = 3418646324776591, -- top 3 on the weekly featured tower
		ContestWinner = 0, -- top 3 in a build contest
	}),
	SECRET_BADGES = table.freeze({
		FakeWall = "WallWalker",
		InvisiblePlatform = "GhostStep",
		Teleporter = "PortalHopper",
		JumpPad = "Launched",
		Button = "Doorman",
	}),
	SECRET_HUNTER_COUNT = 10,

	-- Builder rewards (credited when others finish / like your published tower)
	CREDITS_STORE = "Credits_v1",
	XP_PER_FINISH = 10,
	XP_PER_LIKE = 25,
	BRICKS_PER_FINISH = 5,
	BRICKS_PER_LIKE = 10,
	BRICKS_DAILY_CAP = 500, -- per builder per UTC day, against alt-account farming

	-- Social
	INBOX_STORE = "Inbox_v1",
	INBOX_MAX = 20,
	LIVE_RACE_LOBBY_SECONDS = 20,
	LIVE_RACE_MAX = 8,
	FEATURED_PREFIX = "Featured_v1_w", -- + week number: weekly likes per tower
	FEATURED_SETTLE_STORE = "FeaturedSettled_v1", -- week -> settled flag (prizes given once)
	FEATURED_PODIUM_BRICKS = 200,

	-- Replays
	REPLAYS_STORE = "Replays_v1",
	PATH_SAMPLE_SECONDS = 0.1,
	PATH_MAX_SAMPLES = 6000, -- 10 minutes; longer runs keep only the first 10 minutes

	-- Monetization (Creator Dashboard ids; 0 = not created yet, hidden in the shop)
	GAME_PASSES = table.freeze({
		BuilderPass = 2006811632, -- +budget, +2 tower slots, exclusive materials (199 R$)
		VIP = 2005953617, -- plot themes (149 R$)
	}),
	BRICK_PRODUCTS = table.freeze({ -- dev product id -> Bricks granted
		[3716745154] = 500, -- 49 R$
		[3716745157] = 1500, -- 129 R$
	}),
	RECEIPTS_KEPT = 50, -- recent purchase ids remembered per player (dedupe)

	-- Live ops (UTC unix seconds)
	EVENT_PIECES = table.freeze({ -- piece id -> { from, to }: placeable only in this window
		[18] = table.freeze({ 1791763200, 1793750400 }), -- Pumpkin: 2026-10-12 .. 2026-11-04
	}),
	CONTESTS = table.freeze({
		table.freeze({
			id = "2026_halloween",
			theme = "Spooky towers",
			starts = 1791763200, -- 2026-10-12
			votingFrom = 1793145600, -- 2026-10-28
			ends = 1793750400, -- 2026-11-04
		}),
	}),
	CONTEST_STORE_PREFIX = "Contest_v1_", -- + id: OrderedDataStore of votes per entry
	CONTEST_VOTES = 3, -- votes per player per contest
	CONTEST_PRIZE_BRICKS = 500,

	-- Rounds (RoundService). In Studio, ServerStorage attribute RoundFast=true divides times by 10.
	ROUND_MIN_PLAYERS = 1, -- alone you still build and verify against the clock
	ROUND_WAIT_SECONDS = 20, -- intermission before a round
	BUILD_SECONDS = 300,
	RACE_SECONDS = 150,
	VOTE_SECONDS = 20,
	RESULTS_SECONDS = 12,
	ROUND_BUDGET = 150,
	COINS_RACE_WIN = 40, -- first to the top of someone's tower
	COINS_BUILDER_WIN = 40, -- per race nobody finished
	COINS_VALID = 15, -- built and climbed your tower in time
	COINS_PER_STAR = 4, -- builder gets this per star received
	DONATE_AMOUNTS = table.freeze({ 10, 50 }),
	STARTER_COINS = 500, -- once per player, to buy island decorations

	-- Runs
	MAX_RUN_MS = 60 * 60 * 1000,
	MIN_RUN_MS = 1000,
}

return table.freeze(Config)
