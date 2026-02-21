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
-- SPIN STAND CRATES (buy at stall for luck bonus)
-- Cases 1–3: unlocked before Rebirth 1. Cases 4–7: require Rebirth 1+.
-------------------------------------------------
Economy.Crate1Cost = 200   -- Case 1: +0% luck
Economy.Crate2Cost = 1000  -- Case 2: +5% luck
Economy.Crate3Cost = 4000  -- Case 3: +15% luck
Economy.Crate4Cost = 800
Economy.Crate5Cost = 1500
Economy.Crate6Cost = 3000
Economy.Crate7Cost = 6000

Economy.Crate1LuckBonus = 0     -- +0% luck (Case 1)
Economy.Crate2LuckBonus = 0.05  -- +5% luck (Case 2)
Economy.Crate3LuckBonus = 0.15  -- +15% luck (Case 3)
Economy.Crate4LuckBonus = 1.00  -- +100% luck (case 4)
Economy.Crate5LuckBonus = 2.00  -- +200% luck (case 5)
Economy.Crate6LuckBonus = 1.50  -- +150% luck
Economy.Crate7LuckBonus = 2.50  -- +250% luck

-------------------------------------------------
-- REBIRTH (7 levels)
-- First rebirth costs 1M; each gives +5% coin bonus and unlocks the next case.
-- Rebirth resets: cash + active potions.
-------------------------------------------------
Economy.MaxRebirths = 7

-- Cost for each rebirth level (1-indexed): Rebirth 1 = 1,000,000
Economy.RebirthCosts = { 1000000, 2, 3, 4, 5, 6, 7 }

-- Coin bonus per rebirth: cumulative +5% each
Economy.RebirthCoinBonusPercent = 5 -- per rebirth

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

--- Get the minimum rebirth level required to use a crate (1-indexed crate id)
--- Cases 1–3 = available before Rebirth 1 (rebirth 0). Case 4 = Rebirth 1, Case 5 = Rebirth 2, etc.
function Economy.GetCrateRebirthRequirement(crateId: number): number
	if crateId <= 3 then return 0 end
	return crateId - 3
end

--- Info for a specific rebirth level (1-indexed)
function Economy.GetRebirthInfo(rebirthLevel: number)
	if rebirthLevel < 1 or rebirthLevel > Economy.MaxRebirths then return nil end
	local cost = Economy.RebirthCosts[rebirthLevel]
	local coinBonus = rebirthLevel * Economy.RebirthCoinBonusPercent
	local unlocksCase = rebirthLevel + 3 -- rebirth 1 unlocks case 4, rebirth 2 unlocks case 5, etc.
	if unlocksCase > 7 then unlocksCase = nil end
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
