--!strict
-- In-memory stand-in for DataStore/OrderedDataStore. `failNext` makes the next N calls throw.

local FakeDataStore = {}
FakeDataStore.__index = FakeDataStore

local function copy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = copy(x)
	end
	return out
end

function FakeDataStore.new()
	return setmetatable({ data = {} :: { [string]: any }, failNext = 0, writes = 0 }, FakeDataStore)
end

function FakeDataStore:_maybeFail()
	if self.failNext > 0 then
		self.failNext -= 1
		error("fake datastore failure")
	end
end

function FakeDataStore:UpdateAsync(key: string, fn: (any, any) -> any): any
	self:_maybeFail()
	local new = fn(copy(self.data[key]), nil)
	if new ~= nil then
		self.data[key] = copy(new)
		self.writes += 1
	end
	return copy(new)
end

function FakeDataStore:GetAsync(key: string): any
	self:_maybeFail()
	return copy(self.data[key])
end

function FakeDataStore:SetAsync(key: string, value: any)
	self:_maybeFail()
	self.data[key] = copy(value)
	self.writes += 1
end

function FakeDataStore:GetSortedAsync(ascending: boolean, pageSize: number)
	self:_maybeFail()
	local items = {}
	for k, v in self.data do
		table.insert(items, { key = k, value = v })
	end
	table.sort(items, function(a, b)
		if ascending then
			return a.value < b.value
		end
		return a.value > b.value
	end)
	local page = {}
	for i = 1, math.min(pageSize, #items) do
		page[i] = items[i]
	end
	return {
		GetCurrentPage = function()
			return page
		end,
	}
end

return FakeDataStore
