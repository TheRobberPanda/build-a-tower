--!strict

export type PieceDef = {
	id: number,
	name: string,
	size: { number }, -- {x, y, z} cells
	props: { [string]: { number } }, -- key -> {min, max}
	maxCount: number?,
	hint: string?, -- one-line description shown when selected
	decor: boolean?, -- decoration: no collision, outside the piece budget
}

-- Persisted piece: t=typeId, x/y/z grid ints, r=rotation 0-3, p=props
export type Piece = {
	t: number,
	x: number,
	y: number,
	z: number,
	r: number,
	p: { [string]: number }?,
}

export type Tower = {
	v: number,
	pieces: { Piece },
}

export type SavedSlot = { tower: Tower, name: string, verifiedHash: string? }

-- Everything persisted per player (inside the session-locked record).
export type PlayerData = {
	tower: Tower,
	towerName: string,
	verifiedHash: string?, -- hash of the tower version the builder completed
	publishedHash: string?,
	liked: { [string]: string }, -- ownerId -> tower hash liked (one like per version)
	likedOrder: { string }, -- oldest first, capped at Config.LIKED_MAX
	secretsFound: number, -- secret kinds used per finished race, summed
	xp: number,
	bricks: number,
	material: string, -- Cosmetics key for the tower
	activeSlot: number, -- 1..Config.TOWER_SLOTS; tower/towerName/verifiedHash belong to it
	slots: { [string]: SavedSlot }, -- the inactive slots, keyed "1".."3"
	unlocked: { [string]: boolean }, -- materials and trails bought with Bricks
	trail: string?, -- equipped Cosmetics trail key
	theme: string, -- VIP plot theme key
	receipts: { string }, -- recent dev product purchase ids (dedupe), oldest first
	contestVotes: { [string]: { number } }, -- contest id -> owner ids voted for
}

export type PublishedTower = {
	v: number,
	owner: number,
	name: string,
	hash: string,
	pieces: { Piece },
	publishedAt: number,
	mat: string?, -- Cosmetics material key
}

return nil
