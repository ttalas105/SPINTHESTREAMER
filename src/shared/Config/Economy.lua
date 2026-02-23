--[[
	Economy.lua
	All economy constants: spin cost, rebirth cost formula,
	sell prices by rarity, passive income rate.
]]

local Economy = {}

-------------------------------------------------
-- SPIN
-------------------------------------------------
Economy.SpinCost = 100        -- cash per single spin
Economy.SpinCost5 = 450       -- discounted 5-pack
Economy.SpinCost10 = 800      -- discounted 10-pack

-------------------------------------------------
-- SPIN STAND CASES (18 total, buy at stall for luck bonus)
-- Case 1 is free (no rebirth). Case N (2-18) requires Rebirth N-1.
-------------------------------------------------
Economy.TotalCases = 18

Economy.CrateCosts = {
	100,       -- Case 1
	300,       -- Case 2
	600,       -- Case 3
	1000,      -- Case 4
	2000,      -- Case 5
	3500,      -- Case 6
	5500,      -- Case 7
	8000,      -- Case 8
	12000,     -- Case 9
	18000,     -- Case 10
	28000,     -- Case 11
	42000,     -- Case 12
	65000,     -- Case 13
	100000,    -- Case 14
	150000,    -- Case 15
	225000,    -- Case 16
	350000,    -- Case 17
	500000,    -- Case 18
}

Economy.CrateLuckBonuses = {
	0,       -- Case 1:  +0%
	0.05,    -- Case 2:  +5%
	0.15,    -- Case 3:  +15%
	0.30,    -- Case 4:  +30%
	0.50,    -- Case 5:  +50%
	0.75,    -- Case 6:  +75%
	1.00,    -- Case 7:  +100%
	1.50,    -- Case 8:  +150%
	2.00,    -- Case 9:  +200%
	3.00,    -- Case 10: +300%
	4.00,    -- Case 11: +400%
	5.00,    -- Case 12: +500%
	6.50,    -- Case 13: +650%
	8.00,    -- Case 14: +800%
	10.00,   -- Case 15: +1000%
	12.50,   -- Case 16: +1250%
	15.00,   -- Case 17: +1500%
	20.00,   -- Case 18: +2000%
}

Economy.CrateImageIds = {
	"rbxassetid://77068968088917",  -- Case 1
	"rbxassetid://103035672107983", -- Case 2
	"rbxassetid://126662755699680", -- Case 3
	"rbxassetid://96984490714060",  -- Case 4
	"rbxassetid://133028981319076", -- Case 5
	"rbxassetid://117927435828773", -- Case 6
	"rbxassetid://99511304131085",  -- Case 7
	"rbxassetid://91698336063054",  -- Case 8
	"rbxassetid://135861190644609", -- Case 9
	"rbxassetid://82689313831165",  -- Case 10
	"rbxassetid://77071400509917",  -- Case 11
	"rbxassetid://130216295179680", -- Case 12
	"rbxassetid://84935046324931",  -- Case 13
	"rbxassetid://106996470609349", -- Case 14
	"rbxassetid://115504007548064", -- Case 15
	"rbxassetid://102873440096716", -- Case 16
	"rbxassetid://126496434664236", -- Case 17
	"rbxassetid://94765664565476",  -- Case 18
}

Economy.CrateNames = {
	"Starter Case",     -- 1
	"Bronze Case",      -- 2
	"Silver Case",      -- 3
	"Gold Case",        -- 4
	"Platinum Case",    -- 5
	"Emerald Case",     -- 6
	"Diamond Case",     -- 7
	"Ruby Case",        -- 8
	"Sapphire Case",    -- 9
	"Crystal Case",     -- 10
	"Amethyst Case",    -- 11
	"Obsidian Case",    -- 12
	"Phoenix Case",     -- 13
	"Celestial Case",   -- 14
	"Cosmic Case",      -- 15
	"Inferno Case",     -- 16
	"Astral Case",      -- 17
	"Ultimate Case",    -- 18
}

Economy.CrateRarities = {
	"Common",     -- 1
	"Common",     -- 2
	"Uncommon",   -- 3
	"Uncommon",   -- 4
	"Rare",       -- 5
	"Rare",       -- 6
	"Epic",       -- 7
	"Epic",       -- 8
	"Epic",       -- 9
	"Legendary",  -- 10
	"Legendary",  -- 11
	"Legendary",  -- 12
	"Mythic",     -- 13
	"Mythic",     -- 14
	"Mythic",     -- 15
	"Godly",      -- 16
	"Godly",      -- 17
	"Godly",      -- 18
}

-------------------------------------------------
-- REBIRTH (19 levels)
-- Each gives +5% coin bonus. Rebirths 1-17 unlock cases 2-18.
-- Rebirth resets: cash + active potions.
-------------------------------------------------
Economy.MaxRebirths = 19

Economy.RebirthCosts = {
	1000000,       -- Rebirth 1:  $1M
	3000000,       -- Rebirth 2:  $3M
	7500000,       -- Rebirth 3:  $7.5M
	15000000,      -- Rebirth 4:  $15M
	30000000,      -- Rebirth 5:  $30M
	50000000,      -- Rebirth 6:  $50M
	85000000,      -- Rebirth 7:  $85M
	140000000,     -- Rebirth 8:  $140M
	225000000,     -- Rebirth 9:  $225M
	350000000,     -- Rebirth 10: $350M
	550000000,     -- Rebirth 11: $550M
	850000000,     -- Rebirth 12: $850M
	1300000000,    -- Rebirth 13: $1.3B
	2000000000,    -- Rebirth 14: $2B
	3000000000,    -- Rebirth 15: $3B
	4500000000,    -- Rebirth 16: $4.5B
	7000000000,    -- Rebirth 17: $7B
	10000000000,   -- Rebirth 18: $10B
	15000000000,   -- Rebirth 19: $15B
}

Economy.RebirthCoinBonusPercent = 5

--- Get the cost of the next rebirth (0-indexed rebirthCount)
function Economy.GetRebirthCost(currentRebirths: number): number
	local next = currentRebirths + 1
	if next > Economy.MaxRebirths then return math.huge end
	return Economy.RebirthCosts[next] or math.huge
end

--- Get the coin multiplier from rebirths (1.0 + rebirthCount * 0.05)
function Economy.GetRebirthCoinMultiplier(rebirthCount: number): number
	return 1 + (rebirthCount * Economy.RebirthCoinBonusPercent / 100)
end

--- Case 1 is free. Case N (2-18) requires Rebirth (N-1).
function Economy.GetCrateRebirthRequirement(crateId: number): number
	if crateId <= 1 then return 0 end
	return crateId - 1
end

--- Info for a specific rebirth level (1-indexed)
function Economy.GetRebirthInfo(rebirthLevel: number)
	if rebirthLevel < 1 or rebirthLevel > Economy.MaxRebirths then return nil end
	local cost = Economy.RebirthCosts[rebirthLevel]
	local coinBonus = rebirthLevel * Economy.RebirthCoinBonusPercent
	local unlocksCase = rebirthLevel + 1
	if unlocksCase > Economy.TotalCases then unlocksCase = nil end
	return {
		level = rebirthLevel,
		cost = cost,
		coinBonus = coinBonus,
		unlocksCase = unlocksCase,
	}
end

-------------------------------------------------
-- SELL PRICES (per rarity)
-------------------------------------------------
Economy.SellPrices = {
	Common    = 10,
	Rare      = 30,
	Epic      = 75,
	Legendary = 200,
	Mythic    = 500,
}

-------------------------------------------------
-- PASSIVE INCOME
-------------------------------------------------
Economy.PassiveIncomeRate   = 25   -- cash per interval
Economy.PassiveIncomeInterval = 60 -- seconds

-------------------------------------------------
-- LUCK (server-wide boost from Robux purchase)
-------------------------------------------------
Economy.DefaultLuckMultiplier = 1  -- 1x normal
Economy.BoostedLuckMultiplier = 2  -- 2x with boost

-------------------------------------------------
-- PERSONAL LUCK UPGRADE (at Upgrade stand; 1 luck = +1% drop luck)
-- First = 1,000, second = 4,000, then 4x each time (16k, 64k, ...)
-------------------------------------------------
Economy.LuckUpgradeCostFirst  = 1000   -- first upgrade
Economy.LuckUpgradeCostSecond = 4000   -- second upgrade
Economy.LuckUpgradeCostMultiplier = 4  -- each subsequent cost is 4x previous

--- Cost to buy the next +5 luck (based on current luck stat; each upgrade gives +5 luck)
--- First = 1,000, second = 4,000, then 4x each (16k, 64k, ...)
function Economy.GetLuckUpgradeCost(currentLuck: number): number
	local upgradesBought = math.floor((currentLuck or 0) / 5)
	return Economy.LuckUpgradeCostFirst * (Economy.LuckUpgradeCostMultiplier ^ upgradesBought)
end

-------------------------------------------------
-- CASH UPGRADE (coin multiplier at Upgrade stand; +2% cash per upgrade)
-- First = 1,000, second = 4,000, then 4x each time (16k, 64k, ...)
-------------------------------------------------
Economy.CashUpgradeCostFirst  = 1000
Economy.CashUpgradeCostSecond = 4000
Economy.CashUpgradeCostMultiplier = 4

--- Cost for the next cash multiplier upgrade (currentLevel = number of upgrades already bought)
function Economy.GetCashUpgradeCost(currentLevel: number): number
	if (currentLevel or 0) == 0 then return Economy.CashUpgradeCostFirst end
	if currentLevel == 1 then return Economy.CashUpgradeCostSecond end
	return Economy.CashUpgradeCostSecond * (Economy.CashUpgradeCostMultiplier ^ (currentLevel - 1))
end

-------------------------------------------------
-- ROBUX PRODUCT IDS (placeholder — set real ids in Studio)
-------------------------------------------------
Economy.Products = {
	ServerLuck   = 0, -- Developer Product ID
	Buy5Spins    = 0,
	Buy10Spins   = 0,
	DoubleCash   = 0,
	PremiumSlot  = 0, -- GamePass or Developer Product
}

-------------------------------------------------
-- 2x CASH MULTIPLIER
-------------------------------------------------
Economy.DoubleCashMultiplier = 2

-------------------------------------------------
-- GEMS (earned from Index / Collection)
-- Base per rarity; elemental variants multiply by IndexEffectMultipliers.
-------------------------------------------------
Economy.IndexGemRewards = {
	Common    = 45,
	Rare      = 80,
	Epic      = 120,
	Legendary = 250,
	Mythic    = 500,
}

-- Effect multiplier for Index claims: Acid x4, Snow x8, Lava x12, ... Void x36 (increments of 4)
Economy.IndexEffectMultipliers = {
	Acid      = 4,
	Snow      = 8,
	Lava      = 12,
	Lightning = 16,
	Shadow    = 20,
	Glitchy   = 24,
	Lunar     = 28,
	Solar     = 32,
	Void      = 36,
}

--- Get gem reward for claiming an Index entry (rarity + optional effect).
function Economy.GetIndexGemReward(rarity: string, effect: string?): number
	local base = Economy.IndexGemRewards[rarity] or Economy.IndexGemRewards.Common
	if not effect or effect == "" then
		return base
	end
	local mult = Economy.IndexEffectMultipliers[effect] or 1
	return math.floor(base * mult)
end

return Economy
