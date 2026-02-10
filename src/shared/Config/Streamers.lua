--[[
	Streamers.lua
	All 24 streamers with rarity assignments.
	id = unique key (matches model name in ReplicatedStorage.StreamerModels)
	displayName = shown in UI
	rarity = must match a key in Rarities.lua
]]

local Streamers = {}

Streamers.List = {
	-- COMMON (8 streamers)
	{ id = "Marlon",         displayName = "Marlon",          rarity = "Common" },
	{ id = "Adapt",          displayName = "Adapt",           rarity = "Common" },
	{ id = "Silky",          displayName = "Silky",           rarity = "Common" },
	{ id = "Fanum",          displayName = "Fanum",           rarity = "Common" },
	{ id = "Agent00",        displayName = "Agent 00",        rarity = "Common" },
	{ id = "Yourrage",       displayName = "YourRAGE",        rarity = "Common" },
	{ id = "Ludwig",         displayName = "Ludwig",          rarity = "Common" },
	{ id = "Rakai",          displayName = "Rakai",           rarity = "Common" },

	-- RARE (6 streamers)
	{ id = "Jynxy",          displayName = "Jynxy",           rarity = "Rare" },
	{ id = "Lacy",           displayName = "Lacy",            rarity = "Rare" },
	{ id = "Tfue",           displayName = "Tfue",            rarity = "Rare" },
	{ id = "Ninja",          displayName = "Ninja",           rarity = "Rare" },
	{ id = "Shroud",         displayName = "Shroud",          rarity = "Rare" },
	{ id = "StableRonaldo",  displayName = "Stable Ronaldo",  rarity = "Rare" },

	-- EPIC (5 streamers)
	{ id = "Casoh",          displayName = "Casoh",           rarity = "Epic" },
	{ id = "Cinna",          displayName = "Cinna",           rarity = "Epic" },
	{ id = "Emiru",          displayName = "Emiru",           rarity = "Epic" },
	{ id = "Pokimane",       displayName = "Pokimane",        rarity = "Epic" },
	{ id = "OhnePixel",      displayName = "ohnePixel",       rarity = "Epic" },

	-- LEGENDARY (3 streamers)
	{ id = "XQC",            displayName = "xQc",             rarity = "Legendary" },
	{ id = "Speed",          displayName = "IShowSpeed",      rarity = "Legendary" },
	{ id = "KaiCenat",       displayName = "Kai Cenat",       rarity = "Legendary" },

	-- MYTHIC (2 streamers)
	{ id = "JasondaWeen",    displayName = "JasondaWeen",     rarity = "Mythic" },
	{ id = "Valkerie",       displayName = "Valkerie",        rarity = "Mythic" },
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
