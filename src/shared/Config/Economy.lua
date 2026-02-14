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
-------------------------------------------------
Economy.Crate1Cost = 50
Economy.Crate2Cost = 200
Economy.Crate3Cost = 400
Economy.Crate4Cost = 800
Economy.Crate5Cost = 1500
Economy.Crate6Cost = 3000
Economy.Crate7Cost = 6000

Economy.Crate1LuckBonus = 0.10   -- +10% luck
Economy.Crate2LuckBonus = 0.30   -- +30% luck
Economy.Crate3LuckBonus = 0.60   -- +60% luck (case 3)
Economy.Crate4LuckBonus = 1.00  -- +100% luck (case 4)
Economy.Crate5LuckBonus = 2.00  -- +200% luck (case 5)
Economy.Crate6LuckBonus = 1.50  -- +150% luck
Economy.Crate7LuckBonus = 2.50  -- +250% luck

-------------------------------------------------
-- REBIRTH (7 levels: $1, $2, $3, $4, $5, $6, $7)
-- Each rebirth gives +5% coin bonus and unlocks the next case.
-- Rebirth resets: cash + active potions.
-------------------------------------------------
Economy.MaxRebirths = 7

-- Cost for each rebirth level (1-indexed)
Economy.RebirthCosts = { 1, 2, 3, 4, 5, 6, 7 }

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
--- Case 1 = always available (rebirth 0), Case 2 = rebirth 1, etc.
function Economy.GetCrateRebirthRequirement(crateId: number): number
	if crateId <= 1 then return 0 end
	return crateId - 1
end

--- Info for a specific rebirth level (1-indexed)
function Economy.GetRebirthInfo(rebirthLevel: number)
	if rebirthLevel < 1 or rebirthLevel > Economy.MaxRebirths then return nil end
	local cost = Economy.RebirthCosts[rebirthLevel]
	local coinBonus = rebirthLevel * Economy.RebirthCoinBonusPercent
	local unlocksCase = rebirthLevel + 1 -- rebirth 1 unlocks case 2, etc.
	if unlocksCase > 7 then unlocksCase = nil end -- rebirth 7 doesn't unlock a new case
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
-------------------------------------------------
Economy.LuckUpgradeCostFirst  = 1000   -- first upgrade (+5 luck)
Economy.LuckUpgradeCostSecond = 5000   -- second upgrade (+5 more luck); 3rd+ use this for now
Economy.LuckUpgradeCostPerPoint = 5000 -- fallback for 3rd+ upgrades

--- Cost to buy the next +5 luck (based on current luck stat)
function Economy.GetLuckUpgradeCost(currentLuck: number): number
	if currentLuck <= 200 then return Economy.LuckUpgradeCostFirst end
	if currentLuck <= 205 then return Economy.LuckUpgradeCostSecond end
	return Economy.LuckUpgradeCostPerPoint or Economy.LuckUpgradeCostSecond
end

-------------------------------------------------
-- CASH UPGRADE (coin multiplier at Upgrade stand; +2% cash per upgrade)
-------------------------------------------------
Economy.CashUpgradeCost = 1   -- $1 per upgrade (placeholder)

--- Cost for the next cash multiplier upgrade
function Economy.GetCashUpgradeCost(currentLevel: number): number
	return Economy.CashUpgradeCost
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
-------------------------------------------------
Economy.IndexGemRewards = {
	Common    = 2,
	Rare      = 5,
	Epic      = 10,
	Legendary = 25,
	Mythic    = 50,
}

return Economy
