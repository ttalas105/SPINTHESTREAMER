--[[
	GemCases.lua
	Gem case definitions.
	- Regular cases: cost gems, weighted RNG for specific streamers (no effect).
	- Effect cases: cost gems, contain ALL streamers with a specific effect.
	  Uses a "compression" formula so higher-tier (more expensive) cases give
	  better odds at rarer streamers.  weight = (1/odds) ^ compression
	- Special cases: unique themed cases with creative pools.
]]

local GemCases = {}

-------------------------------------------------
-- REGULAR CASES (fixed item pools, no effect)
-------------------------------------------------
GemCases.RegularCases = {
	{
		id       = "GemCase1",
		name     = "Starter Case",
		cost     = 200,
		color    = Color3.fromRGB(100, 200, 255),
		items = {
			{ streamerId = "Silky",        chance = 32,   displayName = "Silky" },
			{ streamerId = "Emiru",        chance = 25,   displayName = "Emiru" },
			{ streamerId = "Duke Dennis",  chance = 20,   displayName = "Duke Dennis" },
			{ streamerId = "Marlon",       chance = 13,   displayName = "Marlon" },
			{ streamerId = "Kreek Craft",  chance = 7,    displayName = "Kreek Craft" },
			{ streamerId = "Valkyrae",     chance = 3,    displayName = "Valkyrae" },
		},
	},
	{
		id       = "GemCase2",
		name     = "Rare Hunters",
		cost     = 500,
		color    = Color3.fromRGB(60, 150, 255),
		items = {
			{ streamerId = "Shroud",         chance = 32,   displayName = "Shroud" },
			{ streamerId = "StableRonaldo",  chance = 25,   displayName = "Stable Ronaldo" },
			{ streamerId = "Train",          chance = 18,   displayName = "Trainwrecks" },
			{ streamerId = "Lacy",           chance = 13,   displayName = "Lacy" },
			{ streamerId = "Cinna",          chance = 9,    displayName = "Cinna" },
			{ streamerId = "CaseOh",         chance = 3,    displayName = "CaseOh" },
		},
	},
	{
		id       = "GemCase3",
		name     = "Epic Crate",
		cost     = 1500,
		color    = Color3.fromRGB(170, 80, 255),
		items = {
			{ streamerId = "Cinna",        chance = 28,   displayName = "Cinna" },
			{ streamerId = "CaseOh",       chance = 24,   displayName = "CaseOh" },
			{ streamerId = "Pokimane",     chance = 20,   displayName = "Pokimane" },
			{ streamerId = "Adapt",        chance = 14,   displayName = "Adapt" },
			{ streamerId = "OhnePixel",    chance = 8,    displayName = "ohnePixel" },
			{ streamerId = "JasondaWeen",  chance = 4.5,  displayName = "JasondaWeen" },
			{ streamerId = "Ninja",        chance = 1.5,  displayName = "Ninja" },
		},
	},
	{
		id       = "GemCase4",
		name     = "Legendary Drop",
		cost     = 5000,
		color    = Color3.fromRGB(255, 200, 40),
		items = {
			{ streamerId = "OhnePixel",    chance = 28,   displayName = "ohnePixel" },
			{ streamerId = "JasondaWeen",  chance = 25,   displayName = "JasondaWeen" },
			{ streamerId = "Ninja",        chance = 22,   displayName = "Ninja" },
			{ streamerId = "Kai Cenat",    chance = 14,   displayName = "Kai Cenat" },
			{ streamerId = "Jynxzi",       chance = 7,    displayName = "Jynxzi" },
			{ streamerId = "IShowSpeed",   chance = 3,    displayName = "IShowSpeed" },
			{ streamerId = "XQC",          chance = 1,    displayName = "xQc" },
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
-- SPECIAL CASES (unique themed pools)
-------------------------------------------------
GemCases.SpecialCases = {
	-- ALL IN: the classic gamble
	{
		id    = "AllInCase",
		name  = "ALL IN",
		cost  = 500,
		color = Color3.fromRGB(255, 60, 60),
		items = {
			{ streamerId = "Rakai", effect = nil,    chance = 99.9, displayName = "Rakai" },
			{ streamerId = "XQC",   effect = "Void", chance = 0.1,  displayName = "Void xQc" },
		},
	},
	-- Queens Case: female streamer exclusive
	{
		id    = "QueensCase",
		name  = "Queens Case",
		cost  = 400,
		color = Color3.fromRGB(255, 130, 200),
		items = {
			{ streamerId = "Emiru",     chance = 38,  displayName = "Emiru" },
			{ streamerId = "Valkyrae",  chance = 28,  displayName = "Valkyrae" },
			{ streamerId = "Lacy",      chance = 18,  displayName = "Lacy" },
			{ streamerId = "Pokimane",  chance = 12,  displayName = "Pokimane" },
			{ streamerId = "Cinna",     chance = 4,   displayName = "Cinna" },
		},
	},
	-- Lucky Seven: 7 streamers, each spanning a different tier
	{
		id    = "LuckySevenCase",
		name  = "Lucky Seven",
		cost  = 777,
		color = Color3.fromRGB(255, 215, 0),
		items = {
			{ streamerId = "Fanum",      chance = 25,   displayName = "Fanum" },
			{ streamerId = "Shroud",     chance = 20,   displayName = "Shroud" },
			{ streamerId = "Cinna",      chance = 18,   displayName = "Cinna" },
			{ streamerId = "Adapt",      chance = 15,   displayName = "Adapt" },
			{ streamerId = "Ninja",      chance = 12,   displayName = "Ninja" },
			{ streamerId = "Kai Cenat",  chance = 7,    displayName = "Kai Cenat" },
			{ streamerId = "IShowSpeed", chance = 3,    displayName = "IShowSpeed" },
		},
	},
	-- 50/50 Gambler: all or nothing
	{
		id    = "FiftyFiftyCase",
		name  = "50/50 Gambler",
		cost  = 1000,
		color = Color3.fromRGB(255, 255, 100),
		items = {
			{ streamerId = "Rakai",       chance = 50, displayName = "Rakai" },
			{ streamerId = "JasondaWeen", chance = 50, displayName = "JasondaWeen" },
		},
	},
	-- Mythic or Bust: huge gamble for the big prize
	{
		id    = "MythicOrBustCase",
		name  = "Mythic or Bust",
		cost  = 8000,
		color = Color3.fromRGB(255, 50, 50),
		items = {
			{ streamerId = "Rakai",      chance = 93,  displayName = "Rakai" },
			{ streamerId = "IShowSpeed", chance = 4.5, displayName = "IShowSpeed" },
			{ streamerId = "XQC",        chance = 2.5, displayName = "xQc" },
		},
	},
	-- W Rizz: fan-favorite crowd-pleasers
	{
		id    = "WRizzCase",
		name  = "W Rizz",
		cost  = 600,
		color = Color3.fromRGB(255, 100, 150),
		items = {
			{ streamerId = "Duke Dennis",   chance = 28,  displayName = "Duke Dennis" },
			{ streamerId = "StableRonaldo", chance = 22,  displayName = "Stable Ronaldo" },
			{ streamerId = "Kai Cenat",     chance = 18,  displayName = "Kai Cenat" },
			{ streamerId = "Fanum",         chance = 15,  displayName = "Fanum" },
			{ streamerId = "IShowSpeed",    chance = 10,  displayName = "IShowSpeed" },
			{ streamerId = "Jynxzi",        chance = 7,   displayName = "Jynxzi" },
		},
	},
	-- OG Case: classic gaming legends
	{
		id    = "OGCase",
		name  = "OG Legends",
		cost  = 3000,
		color = Color3.fromRGB(200, 180, 255),
		items = {
			{ streamerId = "Shroud",    chance = 30,  displayName = "Shroud" },
			{ streamerId = "Ninja",     chance = 25,  displayName = "Ninja" },
			{ streamerId = "Train",     chance = 20,  displayName = "Trainwrecks" },
			{ streamerId = "XQC",       chance = 10,  displayName = "xQc" },
			{ streamerId = "Pokimane",  chance = 10,  displayName = "Pokimane" },
			{ streamerId = "Adapt",     chance = 5,   displayName = "Adapt" },
		},
	},
}

-- Backward-compat alias so existing code referencing AllInCase still works
GemCases.AllInCase = GemCases.SpecialCases[1]

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
for _, c in ipairs(GemCases.SpecialCases) do
	GemCases.ById[c.id] = c
end

return GemCases
