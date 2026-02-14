--[[
	Potions.lua
	Potion definitions: Luck potions and Cash (Gold) potions.
	Each has 3 tiers with increasing multipliers.
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
