--!strict
-- Per-player notifications delivered on next join ("your record was beaten").
-- Messages are built by the server from templates, never from player text.
-- key = userId -> { { t = unix time, text = string } } newest last, capped.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Retry = require(script.Parent.Retry)

export type Message = { t: number, text: string }

export type Deps = {
	store: any,
	now: () -> number,
	wait: (number) -> (),
	budgetReady: (() -> boolean)?,
	log: ((string) -> ())?,
}

local InboxStore = {}
InboxStore.__index = InboxStore

export type InboxStore = typeof(setmetatable({} :: { _deps: Deps, _retry: Retry.Options }, InboxStore))

function InboxStore.new(deps: Deps): InboxStore
	return setmetatable({
		_deps = deps,
		_retry = {
			attempts = Config.DS_ATTEMPTS,
			baseDelay = Config.DS_BASE_DELAY,
			maxDelay = Config.DS_MAX_DELAY,
			wait = deps.wait,
			budgetReady = deps.budgetReady,
			log = deps.log,
		},
	}, InboxStore)
end

local function clean(raw: any): { Message }
	local out: { Message } = {}
	if type(raw) == "table" then
		for _, m in raw do
			if
				type(m) == "table"
				and type(m.t) == "number"
				and type(m.text) == "string"
				and #m.text <= 200
			then
				table.insert(out, { t = m.t, text = m.text })
			end
		end
	end
	return out
end

function InboxStore.push(self: InboxStore, userId: number, text: string): boolean
	local msg = { t = self._deps.now(), text = string.sub(text, 1, 200) }
	local ok = Retry.call(self._retry, function()
		return self._deps.store:UpdateAsync(tostring(userId), function(old: any)
			local list = clean(old)
			table.insert(list, msg)
			while #list > Config.INBOX_MAX do
				table.remove(list, 1)
			end
			return list
		end)
	end)
	return ok
end

-- Returns all messages and clears the inbox.
function InboxStore.take(self: InboxStore, userId: number): { Message }
	local taken: { Message } = {}
	local ok = Retry.call(self._retry, function()
		return self._deps.store:UpdateAsync(tostring(userId), function(old: any)
			taken = clean(old)
			if #taken == 0 then
				return nil
			end
			return {}
		end)
	end)
	return if ok then taken else {}
end

return InboxStore
