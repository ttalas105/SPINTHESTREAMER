--[[
	Streamers.lua
	All streamers with rarity and custom odds (1 in N).
	id = unique key (matches model name in ReplicatedStorage.StreamerModels)
	displayName = shown in UI
	rarity = must match a key in Rarities.lua
	odds = N for "1 in N" pull chance (used for weighted roll)
	cashPerSecond = income generated when placed on a base pad
]]

local Streamers = {}

Streamers.List = {
	-- COMMON (flattened within-tier spread: 4.4x instead of 10x)
	{ id = "Rakai",          displayName = "Rakai",           rarity = "Common",    odds = 5,        cashPerSecond = 15 },
	{ id = "Fanum",          displayName = "Fanum",           rarity = "Common",    odds = 7,        cashPerSecond = 25 },
	{ id = "Silky",          displayName = "Silky",           rarity = "Common",    odds = 10,       cashPerSecond = 35 },
	{ id = "Emiru",          displayName = "Emiru",           rarity = "Common",    odds = 14,       cashPerSecond = 50 },
	{ id = "Duke Dennis",    displayName = "Duke Dennis",     rarity = "Common",    odds = 18,       cashPerSecond = 65 },
	{ id = "Marlon",         displayName = "Marlon",          rarity = "Common",    odds = 22,       cashPerSecond = 85 },

	-- RARE (flattened: 5x spread instead of 25x)
	{ id = "Kreek Craft",    displayName = "Kreek Craft",     rarity = "Rare",      odds = 80,       cashPerSecond = 150 },
	{ id = "Valkyrae",       displayName = "Valkyrae",        rarity = "Rare",      odds = 110,      cashPerSecond = 200 },
	{ id = "Shroud",         displayName = "Shroud",          rarity = "Rare",      odds = 150,      cashPerSecond = 300 },
	{ id = "StableRonaldo",  displayName = "Stable Ronaldo",  rarity = "Rare",      odds = 210,      cashPerSecond = 450 },
	{ id = "Train",          displayName = "Trainwrecks",     rarity = "Rare",      odds = 290,      cashPerSecond = 650 },
	{ id = "Lacy",           displayName = "Lacy",            rarity = "Rare",      odds = 400,      cashPerSecond = 900 },

	-- EPIC (flattened: 6.25x spread instead of 18x)
	{ id = "Cinna",          displayName = "Cinna",           rarity = "Epic",      odds = 4000,     cashPerSecond = 4000 },
	{ id = "CaseOh",         displayName = "CaseOh",          rarity = "Epic",      odds = 6000,     cashPerSecond = 7000 },
	{ id = "Pokimane",       displayName = "Pokimane",        rarity = "Epic",      odds = 9000,     cashPerSecond = 12000 },
	{ id = "Adapt",          displayName = "Adapt",           rarity = "Epic",      odds = 13000,    cashPerSecond = 18000 },
	{ id = "OhnePixel",      displayName = "ohnePixel",       rarity = "Epic",      odds = 18000,    cashPerSecond = 28000 },
	{ id = "JasondaWeen",    displayName = "JasondaWeen",     rarity = "Epic",      odds = 25000,    cashPerSecond = 40000 },

	-- LEGENDARY (tightened: 4.5x spread)
	{ id = "Ninja",          displayName = "Ninja",           rarity = "Legendary", odds = 200000,   cashPerSecond = 250000 },
	{ id = "Kai Cenat",      displayName = "Kai Cenat",       rarity = "Legendary", odds = 450000,   cashPerSecond = 500000 },
	{ id = "Jynxzi",         displayName = "Jynxzi",          rarity = "Legendary", odds = 900000,   cashPerSecond = 1000000 },

	-- MYTHIC (kept ~2x spread)
	{ id = "IShowSpeed",     displayName = "IShowSpeed",      rarity = "Mythic",    odds = 10000000, cashPerSecond = 5000000 },
	{ id = "XQC",            displayName = "xQc",             rarity = "Mythic",    odds = 18000000, cashPerSecond = 10000000 },
}

-- Build lookup by id for quick access
Streamers.ById = {}
for _, s in ipairs(Streamers.List) do
	Streamers.ById[s.id] = s
end

-- Build list by rarity
Streamers.ByRarity = {}
for _, s in ipairs(Streamers.List) do
	if not Streamers.ByRarity[s.rarity] then
		Streamers.ByRarity[s.rarity] = {}
	end
	table.insert(Streamers.ByRarity[s.rarity], s)
end

return Streamers
