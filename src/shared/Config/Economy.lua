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
-- REBIRTH
-------------------------------------------------
Economy.RebirthBaseCost = 1000
Economy.RebirthCostMultiplier = 1.8 -- each rebirth costs more

--- Get the cost of the next rebirth
function Economy.GetRebirthCost(currentRebirths: number): number
	return math.floor(Economy.RebirthBaseCost * (Economy.RebirthCostMultiplier ^ currentRebirths))
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
-- PERSONAL LUCK UPGRADE (at Upgrade stand; every 20 luck = +1% drop luck)
-------------------------------------------------
Economy.LuckUpgradeCostFirst  = 1000   -- first upgrade (+1 luck)
Economy.LuckUpgradeCostSecond = 5000   -- second upgrade (+1 more luck); 3rd+ use this for now
Economy.LuckUpgradeCostPerPoint = 5000 -- fallback for 3rd+ upgrades

--- Cost to buy the next +1 luck (based on current luck stat)
function Economy.GetLuckUpgradeCost(currentLuck: number): number
	if currentLuck == 0 then return Economy.LuckUpgradeCostFirst end
	if currentLuck == 1 then return Economy.LuckUpgradeCostSecond end
	return Economy.LuckUpgradeCostPerPoint or Economy.LuckUpgradeCostSecond
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

return Economy
