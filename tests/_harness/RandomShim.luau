--!strict
--[[
	RandomShim: a `Random`-compatible generator for Lune (xorshift128, 32-bit lanes).
	Deterministic for a given seed, so weight tests are repeatable. Not the engine's generator;
	tests assert distributions, never exact sequences.
]]

local RandomShim = {}
RandomShim.__index = RandomShim

local TWO_POW_32 = 4294967296

local function splitmix(seed: number): number
	local z = bit32.band(seed + 0x9E3779B9, 0xFFFFFFFF)
	z = bit32.band(bit32.bxor(z, bit32.rshift(z, 16)) * 0x85EBCA6B, 0xFFFFFFFF)
	z = bit32.band(bit32.bxor(z, bit32.rshift(z, 13)) * 0xC2B2AE35, 0xFFFFFFFF)
	return bit32.bxor(z, bit32.rshift(z, 16))
end

function RandomShim.new(seed: number?): any
	local base = if seed == nil then os.clock() * 1e6 else seed
	local integerSeed = bit32.band(math.floor(math.abs(base)), 0xFFFFFFFF)
	local self = setmetatable({}, RandomShim)
	self.x = splitmix(integerSeed)
	self.y = splitmix(integerSeed + 1)
	self.z = splitmix(integerSeed + 2)
	self.w = splitmix(integerSeed + 3)
	if self.x == 0 and self.y == 0 and self.z == 0 and self.w == 0 then
		self.w = 1
	end
	return self
end

local function nextUint32(self: any): number
	local t = bit32.bxor(self.x, bit32.lshift(self.x, 11))
	self.x = self.y
	self.y = self.z
	self.z = self.w
	self.w = bit32.bxor(bit32.bxor(self.w, bit32.rshift(self.w, 19)), bit32.bxor(t, bit32.rshift(t, 8)))
	return self.w
end

function RandomShim.NextNumber(self: any, min: number?, max: number?): number
	local unit = nextUint32(self) / TWO_POW_32
	if min == nil then
		return unit
	end
	return min + unit * ((max or 1) - min)
end

function RandomShim.NextInteger(self: any, min: number, max: number): number
	local span = max - min + 1
	return min + (nextUint32(self) % span)
end

function RandomShim.Clone(self: any): any
	local copy = setmetatable({}, RandomShim)
	copy.x, copy.y, copy.z, copy.w = self.x, self.y, self.z, self.w
	return copy
end

function RandomShim.Shuffle(self: any, list: { any })
	for index = #list, 2, -1 do
		local swap = self:NextInteger(1, index)
		list[index], list[swap] = list[swap], list[index]
	end
end

return RandomShim
