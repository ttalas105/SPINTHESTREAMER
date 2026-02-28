--[[
	Potions.lua
	Potion definitions: Luck potions, Cash (Gold) potions, and Divine (premium).
	Each has 3 tiers with increasing multipliers (Luck/Cash).
	Divine is a single-tier premium potion (Robux) that boosts both luck AND cash x5.
	Duration: Luck/Cash = 5 minutes per use, Divine = 15 minutes per use.
	Time stacks up to 3 hours. Multiplier does NOT stack.
]]

local Potions = {}

-- Duration in seconds
Potions.DURATION_PER_USE = 5 * 60            -- Luck/Cash: 5 minutes
Potions.DIVINE_DURATION_PER_USE = 15 * 60    -- Divine: 15 minutes
Potions.MAX_DURATION = 3 * 60 * 60           -- 3 hours

-- All potion imageIds assigned.
Potions.Types = {
	Luck = {
		{ tier = 1, name = "Luck Potion 1",  multiplier = 1.2, cost = 10000,    rarity = "Common",   color = Color3.fromRGB(80, 255, 100),  imageId = "rbxassetid://117397968445761", desc = "+1.2x luck multiplier for 5m" },
		{ tier = 2, name = "Luck Potion 2",  multiplier = 2,   cost = 100000,   rarity = "Rare",     color = Color3.fromRGB(50, 220, 80),   imageId = "rbxassetid://79599948950862",  desc = "+2x luck multiplier for 5m", rebirthRequired = 3 },
		{ tier = 3, name = "Luck Potion 3",  multiplier = 4,   cost = 1000000,  rarity = "Epic",     color = Color3.fromRGB(30, 180, 60),   imageId = "rbxassetid://72042325851221", desc = "+4x luck multiplier for 5m", rebirthRequired = 8 },
	},
	Cash = {
		{ tier = 1, name = "Money Potion 1", multiplier = 1.2, cost = 10000,    rarity = "Common",   color = Color3.fromRGB(255, 220, 60),  imageId = "rbxassetid://77682596035149",  desc = "+1.2x money multiplier for 5m" },
		{ tier = 2, name = "Money Potion 2", multiplier = 2,   cost = 100000,   rarity = "Rare",     color = Color3.fromRGB(255, 190, 40),  imageId = "rbxassetid://130221704783075", desc = "+2x money multiplier for 5m", rebirthRequired = 5 },
		{ tier = 3, name = "Money Potion 3", multiplier = 4,   cost = 1000000,  rarity = "Epic",     color = Color3.fromRGB(255, 160, 20),  imageId = "rbxassetid://132127116771235", desc = "+4x money multiplier for 5m", rebirthRequired = 10 },
	},
}

-- Divine potion: premium (Robux). Boosts BOTH luck and cash x5.
-- Single tier only. Stacks time, not buffs. Same stacking rules apply.
Potions.Divine = {
	name = "Divine Potion",
	multiplier = 5,
	color = Color3.fromRGB(255, 120, 255),
	imageId = "rbxassetid://126494728573780",
	desc = "5x luck and money multiplier for 15 minutes",
	packs = {
		{ amount = 1,  robux = 99,  label = "x1",  tag = nil },
		{ amount = 3,  robux = 199, label = "x3",  tag = nil },
		{ amount = 10, robux = 599, label = "x10", tag = nil },
	},
}

-- Developer Product IDs for Divine Potion packs
Potions.DivineProductIds = {
	[1]  = 3545295679,
	[3]  = 3545295909,
	[10] = 3545296046,
}

-- Reverse lookup: productId -> pack amount
Potions.ProductIdToAmount = {}
for amount, productId in pairs(Potions.DivineProductIds) do
	if productId > 0 then
		Potions.ProductIdToAmount[productId] = amount
	end
end

-- Quick lookup
function Potions.Get(potionType: string, tier: number)
	local list = Potions.Types[potionType]
	if not list then return nil end
	for _, p in ipairs(list) do
		if p.tier == tier then return p end
	end
	return nil
end

return Potions
