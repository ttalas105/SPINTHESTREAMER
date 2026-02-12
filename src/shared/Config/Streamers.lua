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
	-- COMMON
	{ id = "Rakai",          displayName = "Rakai",           rarity = "Common",    odds = 2,        cashPerSecond = 10 },
	{ id = "Fanum",          displayName = "Fanum",           rarity = "Common",    odds = 5,        cashPerSecond = 22 },
	{ id = "Silky",          displayName = "Silky",           rarity = "Common",    odds = 7,        cashPerSecond = 30 },
	{ id = "Emiru",          displayName = "Emiru",           rarity = "Common",    odds = 12,       cashPerSecond = 40 },
	{ id = "Duke Dennis",    displayName = "Duke Dennis",     rarity = "Common",    odds = 20,       cashPerSecond = 60 },
	{ id = "Marlon",         displayName = "Marlon",          rarity = "Common",    odds = 22,       cashPerSecond = 90 },

	-- RARE
	{ id = "Kreek Craft",    displayName = "Kreek Craft",     rarity = "Rare",      odds = 40,       cashPerSecond = 100 },
	{ id = "Valkyrae",       displayName = "Valkyrae",        rarity = "Rare",      odds = 50,       cashPerSecond = 120 },
	{ id = "Shroud",         displayName = "Shroud",          rarity = "Rare",      odds = 100,      cashPerSecond = 150 },
	{ id = "StableRonaldo",  displayName = "Stable Ronaldo",  rarity = "Rare",      odds = 200,      cashPerSecond = 300 },
	{ id = "Train",          displayName = "Trainwrecks",     rarity = "Rare",      odds = 500,      cashPerSecond = 500 },
	{ id = "Lacy",           displayName = "Lacy",            rarity = "Rare",      odds = 1000,     cashPerSecond = 1000 },

	-- EPIC
	{ id = "Cinna",          displayName = "Cinna",           rarity = "Epic",      odds = 2000,     cashPerSecond = 3000 },
	{ id = "Casoh",          displayName = "Casoh",           rarity = "Epic",      odds = 5000,     cashPerSecond = 6500 },
	{ id = "Pokimane",       displayName = "Pokimane",        rarity = "Epic",      odds = 8500,     cashPerSecond = 10000 },
	{ id = "Adapt",          displayName = "Adapt",           rarity = "Epic",      odds = 13000,    cashPerSecond = 18000 },
	{ id = "OhnePixel",      displayName = "ohnePixel",       rarity = "Epic",      odds = 23000,    cashPerSecond = 30000 },
	{ id = "JasondaWeen",    displayName = "JasondaWeen",     rarity = "Epic",      odds = 36000,    cashPerSecond = 50000 },

	-- LEGENDARY
	{ id = "Ninja",          displayName = "Ninja",           rarity = "Legendary", odds = 100000,   cashPerSecond = 200000 },
	{ id = "Kai Cenat",      displayName = "Kai Cenat",       rarity = "Legendary", odds = 500000,   cashPerSecond = 500000 },
	{ id = "Jynxzi",         displayName = "Jynxzi",          rarity = "Legendary", odds = 1000000,  cashPerSecond = 1000000 },

	-- MYTHIC
	{ id = "IShowSpeed",     displayName = "IShowSpeed",      rarity = "Mythic",    odds = 5000000,  cashPerSecond = 5000000 },
	{ id = "XQC",            displayName = "xQc",             rarity = "Mythic",    odds = 10000000, cashPerSecond = 10000000 },
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
