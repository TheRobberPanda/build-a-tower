--!strict
-- Game-wide tunables. Grid coordinates are integer cells; GRID_STUDS converts to studs.

local Config = {
	SCHEMA_VERSION = 1,

	GRID_STUDS = 4,
	PLOT_CELLS_X = 16, -- valid x: 0..PLOT_CELLS_X-1
	PLOT_CELLS_Z = 16,
	PLOT_CELLS_Y = 64, -- valid y: 0..PLOT_CELLS_Y-1
	PIECE_BUDGET = 150,
	TOWER_NAME_MAX = 24,

	-- DataStores
	PLAYER_STORE = "Players_v1",
	PUBLISHED_STORE = "Towers_v1",
	BROWSE_STORE = "Browse_v1",
	LEADERBOARD_PREFIX = "LB_v1_",
	REPORTS_STORE = "Reports_v1",
	REPORTS_TO_HIDE = 5, -- distinct reporters before a tower version leaves the browse list
	AUTOSAVE_SECONDS = 120,
	LOCK_STALE_SECONDS = 5 * 120, -- 5x autosave; an older lock means its server died
	LOAD_LOCK_RETRIES = 5, -- how often to retry when another server holds the lock
	LOAD_LOCK_WAIT = 4,
	DS_ATTEMPTS = 5,
	DS_BASE_DELAY = 1,
	DS_MAX_DELAY = 16,

	-- Mechanics (shared so client launch and server allowance match)
	JUMP_PAD_SPEED = table.freeze({ 70, 95, 120 }), -- by power 1..3, studs/s upward
	TELEPORT_COOLDOWN = 1.5,

	-- AntiCheat (only checked during runs)
	AC_SAMPLE_SECONDS = 0.2,
	AC_MAX_RISE_SPEED = 60, -- normal jump peaks ~53 studs/s
	AC_SPEED_FACTOR = 1.5, -- allowed horizontal speed = WalkSpeed * factor + slack
	AC_SPEED_SLACK = 6,
	AC_TELEPORT_RADIUS = 10,
	AC_FLAGS_TO_FAIL = 3,

	-- Runs
	MAX_RUN_MS = 60 * 60 * 1000,
	MIN_RUN_MS = 1000,
}

return table.freeze(Config)
