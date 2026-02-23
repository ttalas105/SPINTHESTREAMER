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
-- Starter Case, Rare Hunters, Epic Crate, Legendary Drop removed from gem store.
-------------------------------------------------
GemCases.RegularCases = {}

-------------------------------------------------
-- EFFECT CASES
-- Each case contains ALL streamers but with the given effect.
-- `compression` controls how "flat" the distribution is (lower = flatter = rarer streamers more accessible).
-------------------------------------------------
-- All effect cases use Lightning case odds (compression = 0.42)
GemCases.EffectCases = {
	{ id = "AcidCase",      effect = "Acid",      name = "Acid Case",      cost = 800,    rebirthRequired = 0,  color = Color3.fromRGB(50, 255, 50),    compression = 0.42, logoDecalId = 140731222251378, pictureDecalId = 70677539062100,  logoImageId = "rbxassetid://106022165638688", pictureImageId = "rbxassetid://77653297317137" },
	{ id = "SnowCase",      effect = "Snow",      name = "Snow Case",      cost = 1500,   rebirthRequired = 2,  color = Color3.fromRGB(180, 220, 255),   compression = 0.42, logoDecalId = 122281038871207, pictureDecalId = 72856434029284,  logoImageId = "rbxassetid://129861999711220", pictureImageId = "rbxassetid://84473682665692" },
	{ id = "LavaCase",      effect = "Lava",      name = "Lava Case",      cost = 3000,   rebirthRequired = 4,  color = Color3.fromRGB(255, 100, 20),    compression = 0.42, logoDecalId = 88446146523624,  pictureDecalId = 113163893650100, logoImageId = "rbxassetid://70978737223660",  pictureImageId = "rbxassetid://81387227723064" },
	{ id = "LightningCase", effect = "Lightning",  name = "Lightning Case", cost = 5000,  rebirthRequired = 6,  color = Color3.fromRGB(255, 255, 80),    compression = 0.42, logoDecalId = 82785037374863,  pictureDecalId = 125845773409315, logoImageId = "rbxassetid://109285700967085", pictureImageId = "rbxassetid://105315968839248" },
	{ id = "ShadowCase",    effect = "Shadow",     name = "Shadow Case",    cost = 8000,  rebirthRequired = 8,  color = Color3.fromRGB(100, 60, 140),    compression = 0.42, logoDecalId = 119205587806607, pictureDecalId = 71276747470276,  logoImageId = "rbxassetid://108280725908337", pictureImageId = "rbxassetid://96598727991252" },
	{ id = "GlitchyCase",   effect = "Glitchy",    name = "Glitchy Case",   cost = 12000, rebirthRequired = 10, color = Color3.fromRGB(0, 255, 255),     compression = 0.42, logoDecalId = 106193845040729, pictureDecalId = 110881405837585, logoImageId = "rbxassetid://139648005730009", pictureImageId = "rbxassetid://134848230615869" },
	{ id = "LunarCase",     effect = "Lunar",      name = "Lunar Case",     cost = 20000, rebirthRequired = 13, color = Color3.fromRGB(200, 220, 255),   compression = 0.42, logoDecalId = 138615019713440, pictureDecalId = 93336563085507,  logoImageId = "rbxassetid://138975330292478", pictureImageId = "rbxassetid://79169383651597" },
	{ id = "SolarCase",     effect = "Solar",      name = "Solar Case",     cost = 35000, rebirthRequired = 16, color = Color3.fromRGB(255, 220, 60),    compression = 0.42, logoDecalId = 95353296948690,  pictureDecalId = 73067986687655,  logoImageId = "rbxassetid://72920890729278",  pictureImageId = "rbxassetid://86930873609580" },
	{ id = "VoidCase",      effect = "Void",       name = "Void Case",      cost = 50000, rebirthRequired = 19, color = Color3.fromRGB(80, 40, 120),     compression = 0.42, logoDecalId = 94035448669971,  pictureDecalId = 84829230512116,  logoImageId = "rbxassetid://79498114124783",  pictureImageId = "rbxassetid://107424131791937" },
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
