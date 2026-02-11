--[[
	Streamers.lua
	All streamers with rarity and custom odds (1 in N).
	id = unique key (matches model name in ReplicatedStorage.StreamerModels)
	displayName = shown in UI
	rarity = must match a key in Rarities.lua
	odds = N for "1 in N" pull chance (used for weighted roll)
]]

local Streamers = {}

Streamers.List = {
	-- COMMON
	{ id = "Rakai",          displayName = "Rakai",           rarity = "Common",  odds = 2 },
	{ id = "Fanum",          displayName = "Fanum",          rarity = "Common",   odds = 5 },
	{ id = "Silky",          displayName = "Silky",          rarity = "Common",   odds = 7 },
	{ id = "Emiru",          displayName = "Emiru",          rarity = "Common",   odds = 12 },
	{ id = "DukeDennis",     displayName = "Duke Dennis",    rarity = "Common",  odds = 20 },
	{ id = "Marlon",         displayName = "Marlon",         rarity = "Common",   odds = 22 },

	-- RARE
	{ id = "KreekCraft",     displayName = "Kreek Craft",    rarity = "Rare",     odds = 40 },
	{ id = "Valkerie",       displayName = "Valkerie",       rarity = "Rare",     odds = 50 },
	{ id = "Shroud",         displayName = "Shroud",        rarity = "Rare",     odds = 100 },
	{ id = "StableRonaldo",  displayName = "Stable Ronaldo", rarity = "Rare",    odds = 200 },
	{ id = "Trainwrecks",    displayName = "Trainwrecks",    rarity = "Rare",     odds = 500 },
	{ id = "Lacy",           displayName = "Lacy",           rarity = "Rare",     odds = 1000 },

	-- EPIC
	{ id = "Cinna",          displayName = "Cinna",          rarity = "Epic",     odds = 2000 },
	{ id = "Casoh",          displayName = "Casoh",          rarity = "Epic",     odds = 5000 },
	{ id = "Pokimane",       displayName = "Pokimane",       rarity = "Epic",     odds = 8500 },
	{ id = "Adapt",          displayName = "Adapt",          rarity = "Epic",     odds = 13000 },
	{ id = "OhnePixel",      displayName = "ohnePixel",      rarity = "Epic",    odds = 23000 },
	{ id = "JasondaWeen",    displayName = "JasondaWeen",    rarity = "Epic",     odds = 36000 },

	-- LEGENDARY
	{ id = "Ninja",          displayName = "Ninja",          rarity = "Legendary", odds = 100000 },
	{ id = "KaiCenat",       displayName = "Kai Cenat",      rarity = "Legendary", odds = 500000 },
	{ id = "Jynxy",          displayName = "Jynxy",          rarity = "Legendary", odds = 1000000 },

	-- MYTHIC
	{ id = "Speed",          displayName = "IShowSpeed",    rarity = "Mythic",   odds = 5000000 },
	{ id = "XQC",            displayName = "xQc",            rarity = "Mythic",   odds = 10000000 },
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
