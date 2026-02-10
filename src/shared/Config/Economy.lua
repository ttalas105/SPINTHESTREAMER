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
Economy.Crate1LuckBonus = 0.10   -- +10% luck
Economy.Crate2LuckBonus = 0.30  -- +30% luck

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
