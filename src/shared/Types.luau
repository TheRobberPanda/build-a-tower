--!strict

export type PieceDef = {
	id: number,
	name: string,
	size: { number }, -- {x, y, z} cells
	props: { [string]: { number } }, -- key -> {min, max}
	maxCount: number?,
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

-- Everything persisted per player (inside the session-locked record).
export type PlayerData = {
	tower: Tower,
	towerName: string,
	verifiedHash: string?, -- hash of the tower version the builder completed
	publishedHash: string?,
	liked: { [string]: string }, -- ownerId -> tower hash liked (one like per version)
	likedOrder: { string }, -- oldest first, capped at Config.LIKED_MAX
}

export type PublishedTower = {
	v: number,
	owner: number,
	name: string,
	hash: string,
	pieces: { Piece },
	publishedAt: number,
}

return nil
