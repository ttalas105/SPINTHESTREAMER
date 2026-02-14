--[[
	LuckChances.lua
	Computes rarity drop chances using the two-phase rarity-first system (same as SpinService).
	1 luck = +1% drop luck. Crate luck stacks additively.
]]

local LuckChances = {}

local RARITY_BASE_WEIGHTS = {
	Common    = 1000,
	Rare      = 100,
	Epic      = 10,
	Legendary = 1,
	Mythic    = 0.1,
}

local RARITY_ORDER = { "Common", "Rare", "Epic", "Legendary", "Mythic" }

local RARITY_EXPONENTS = {
	Common    = -3,
	Rare      =  1,
	Epic      =  2,
	Legendary =  3,
	Mythic    =  4,
}

function LuckChances.GetRarityChances(luckMultiplier: number): { [string]: number }
	local L = math.max(1, luckMultiplier or 1)
	local rarityWeights = {}
	local total = 0
	for _, rarity in ipairs(RARITY_ORDER) do
		local base = RARITY_BASE_WEIGHTS[rarity]
		local exp = RARITY_EXPONENTS[rarity]
		local w = base * (L ^ exp)
		rarityWeights[rarity] = w
		total = total + w
	end
	local chances = {}
	for _, rarity in ipairs(RARITY_ORDER) do
		chances[rarity] = rarityWeights[rarity] / total
	end
	return chances
end

-- Total luck multiplier from: 1 + (playerLuck/100) + (crateLuckBonus); 1 luck = 1%
function LuckChances.LuckMultFromPlayerAndCrate(playerLuck: number, crateLuckBonus: number): number
	local playerPercent = (playerLuck or 0) / 100
	return 1 + playerPercent + (crateLuckBonus or 0)
end

return LuckChances
