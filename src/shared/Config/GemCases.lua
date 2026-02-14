--[[
	GemCases.lua
	Gem case definitions.
	- Regular cases: cost gems, weighted RNG for specific streamers (no effect).
	- Effect cases: cost gems, contain ALL streamers with a specific effect.
	  Uses a "compression" formula so higher-tier (more expensive) cases give
	  better odds at rarer streamers.  weight = (1/odds) ^ compression
	- "All In" case: 99.9% default Rakai, 0.1% Void xQc.
]]

local GemCases = {}

-------------------------------------------------
-- REGULAR CASES (fixed item pools, no effect)
-------------------------------------------------
GemCases.RegularCases = {
	{
		id       = "GemCase1",
		name     = "Gem Case 1",
		cost     = 300,
		color    = Color3.fromRGB(100, 200, 255),
		items = {
			{ streamerId = "Marlon",     chance = 60,  displayName = "Marlon" },
			{ streamerId = "Shroud",     chance = 22,  displayName = "Shroud" },
			{ streamerId = "Cinna",      chance = 16,  displayName = "Cinna" },
			{ streamerId = "Kai Cenat",  chance = 1.5, displayName = "Kai Cenat" },
			{ streamerId = "IShowSpeed", chance = 0.5, displayName = "IShowSpeed" },
		},
	},
}

-------------------------------------------------
-- EFFECT CASES
-- Each case contains ALL streamers but with the given effect.
-- `compression` controls how "flat" the distribution is (lower = flatter = rarer streamers more accessible).
-------------------------------------------------
GemCases.EffectCases = {
	{ id = "AcidCase",      effect = "Acid",      name = "Acid Case",      cost = 100,   color = Color3.fromRGB(50, 255, 50),    compression = 0.70 },
	{ id = "SnowCase",      effect = "Snow",      name = "Snow Case",      cost = 300,   color = Color3.fromRGB(180, 220, 255),   compression = 0.60 },
	{ id = "LavaCase",      effect = "Lava",      name = "Lava Case",      cost = 700,   color = Color3.fromRGB(255, 100, 20),    compression = 0.50 },
	{ id = "LightningCase", effect = "Lightning",  name = "Lightning Case", cost = 1000,  color = Color3.fromRGB(255, 255, 80),    compression = 0.42 },
	{ id = "ShadowCase",    effect = "Shadow",     name = "Shadow Case",    cost = 2000,  color = Color3.fromRGB(100, 60, 140),    compression = 0.35 },
	{ id = "GlitchyCase",   effect = "Glitchy",    name = "Glitchy Case",   cost = 3500,  color = Color3.fromRGB(0, 255, 255),     compression = 0.28 },
	{ id = "LunarCase",     effect = "Lunar",      name = "Lunar Case",     cost = 5000,  color = Color3.fromRGB(200, 220, 255),   compression = 0.22 },
	{ id = "SolarCase",     effect = "Solar",      name = "Solar Case",     cost = 7500,  color = Color3.fromRGB(255, 220, 60),    compression = 0.17 },
	{ id = "VoidCase",      effect = "Void",       name = "Void Case",      cost = 10000, color = Color3.fromRGB(80, 40, 120),     compression = 0.13 },
}

-------------------------------------------------
-- ALL IN CASE
-------------------------------------------------
GemCases.AllInCase = {
	id    = "AllInCase",
	name  = "ALL IN",
	cost  = 500,
	color = Color3.fromRGB(255, 60, 60),
	items = {
		{ streamerId = "Rakai", effect = nil,    chance = 99.9, displayName = "Rakai" },
		{ streamerId = "XQC",   effect = "Void", chance = 0.1,  displayName = "Void xQc" },
	},
}

-------------------------------------------------
-- LOOKUP TABLES (all cases by id)
-------------------------------------------------
GemCases.ById = {}
for _, c in ipairs(GemCases.RegularCases) do
	GemCases.ById[c.id] = c
end
for _, c in ipairs(GemCases.EffectCases) do
	GemCases.ById[c.id] = c
end
GemCases.ById[GemCases.AllInCase.id] = GemCases.AllInCase

return GemCases
