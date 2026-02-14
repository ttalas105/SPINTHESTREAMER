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

Potions.Types = {
	Luck = {
		{ tier = 1, name = "Luck Potion I",   multiplier = 1.5, cost = 1, color = Color3.fromRGB(80, 255, 100) },
		{ tier = 2, name = "Luck Potion II",  multiplier = 3,   cost = 1, color = Color3.fromRGB(50, 220, 80)  },
		{ tier = 3, name = "Luck Potion III", multiplier = 4,   cost = 1, color = Color3.fromRGB(30, 180, 60)  },
	},
	Cash = {
		{ tier = 1, name = "Cash Potion I",   multiplier = 1.5, cost = 1, color = Color3.fromRGB(255, 220, 60)  },
		{ tier = 2, name = "Cash Potion II",  multiplier = 3,   cost = 1, color = Color3.fromRGB(255, 190, 40)  },
		{ tier = 3, name = "Cash Potion III", multiplier = 4,   cost = 1, color = Color3.fromRGB(255, 160, 20)  },
	},
}

-- Prismatic potion: premium (Robux). Boosts BOTH luck and cash x7.
-- Single tier only. Stacks time, not buffs. Same stacking rules apply.
Potions.Prismatic = {
	name = "Prismatic Potion",
	multiplier = 7,        -- x7 luck AND x7 cash
	color = Color3.fromRGB(255, 120, 255), -- rainbow-ish pink/purple base
	-- Robux prices for packs
	packs = {
		{ amount = 1,  robux = 60,  label = "1 Potion",   tag = nil },
		{ amount = 5,  robux = 240, label = "5 Potions",  tag = "Get 1 FREE!" },
		{ amount = 10, robux = 480, label = "10 Potions", tag = "Get 2 FREE!" },
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
