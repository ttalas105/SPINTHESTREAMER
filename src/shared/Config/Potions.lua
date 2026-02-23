--[[
	Potions.lua
	Potion definitions: Luck potions, Cash (Gold) potions, and Prismatic (premium).
	Each has 3 tiers with increasing multipliers (Luck/Cash).
	Prismatic is a single-tier premium potion (Robux) that boosts both luck AND cash x7.
	Duration: 5 minutes per use. Time stacks up to 3 hours. Multiplier does NOT stack.
]]

local Potions = {}

-- Duration in seconds
Potions.DURATION_PER_USE = 5 * 60  -- 5 minutes
Potions.MAX_DURATION = 3 * 60 * 60 -- 3 hours

-- Luck3 and Prismatic imageIds = pending (no decal yet).
Potions.Types = {
	Luck = {
		{ tier = 1, name = "Luck Potion 1",  multiplier = 2,   cost = 10000,    rarity = "Common",   color = Color3.fromRGB(80, 255, 100),  imageId = "rbxassetid://117397968445761", desc = "+2x luck multiplier for 5m" },
		{ tier = 2, name = "Luck Potion 2",  multiplier = 3,   cost = 100000,   rarity = "Rare",     color = Color3.fromRGB(50, 220, 80),   imageId = "rbxassetid://79599948950862",  desc = "+3x luck multiplier for 5m", rebirthRequired = 3 },
		{ tier = 3, name = "Luck Potion 3",  multiplier = 5,   cost = 1000000,  rarity = "Epic",     color = Color3.fromRGB(30, 180, 60),   imageId = "", desc = "+5x luck multiplier for 5m", rebirthRequired = 8 },
	},
	Cash = {
		{ tier = 1, name = "Money Potion 1", multiplier = 2,   cost = 10000,    rarity = "Common",   color = Color3.fromRGB(255, 220, 60),  imageId = "rbxassetid://77682596035149",  desc = "+2x money multiplier for 5m" },
		{ tier = 2, name = "Money Potion 2", multiplier = 3,   cost = 100000,   rarity = "Rare",     color = Color3.fromRGB(255, 190, 40),  imageId = "rbxassetid://130221704783075", desc = "+3x money multiplier for 5m", rebirthRequired = 5 },
		{ tier = 3, name = "Money Potion 3", multiplier = 5,   cost = 1000000,  rarity = "Epic",     color = Color3.fromRGB(255, 160, 20),  imageId = "rbxassetid://132127116771235", desc = "+5x money multiplier for 5m", rebirthRequired = 10 },
	},
}

-- Prismatic potion: premium (Robux). Boosts BOTH luck and cash x5.
-- Single tier only. Stacks time, not buffs. Same stacking rules apply.
Potions.Prismatic = {
	name = "Prismatic Potion",
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

-- Developer Product IDs (set these in Roblox Game Settings > Monetization)
-- IMPORTANT: Create Developer Products in your game settings and paste the IDs here
Potions.PrismaticProductIds = {
	[1]  = 0,  -- Replace 0 with the Developer Product ID for 1 Prismatic Potion (60 Robux)
	[5]  = 0,  -- Replace 0 with the Developer Product ID for 5 Prismatic Potions (240 Robux)
	[10] = 0,  -- Replace 0 with the Developer Product ID for 10 Prismatic Potions (480 Robux)
}

-- Reverse lookup: productId -> pack amount
Potions.ProductIdToAmount = {}
for amount, productId in pairs(Potions.PrismaticProductIds) do
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
