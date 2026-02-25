--[[
	Economy.lua
	All economy constants: spin cost, rebirth cost formula,
	sell prices by rarity, passive income rate.
]]

local Economy = {}

-------------------------------------------------
-- SPIN (base spin is FREE to keep players engaged)
-------------------------------------------------
Economy.SpinCost = 0          -- free base spin
Economy.SpinCost5 = 0         -- free 5-pack
Economy.SpinCost10 = 0        -- free 10-pack

-------------------------------------------------
-- SPIN STAND CASES (18 total, buy at stall for luck bonus)
-- Cases 1-3 are free (no rebirth). Case N (4-18) requires Rebirth N-3.
-- Case costs scale aggressively — the real cash sink.
-------------------------------------------------
Economy.TotalCases = 18

Economy.CrateCosts = {
	0,          -- Case 1:  Free
	500,        -- Case 2
	1500,       -- Case 3
	5000,       -- Case 4
	15000,      -- Case 5
	40000,      -- Case 6
	100000,     -- Case 7
	250000,     -- Case 8
	500000,     -- Case 9
	1000000,    -- Case 10
	2500000,    -- Case 11
	5000000,    -- Case 12
	10000000,   -- Case 13
	25000000,   -- Case 14
	50000000,   -- Case 15
	100000000,  -- Case 16
	250000000,  -- Case 17
	500000000,  -- Case 18
}

Economy.CrateLuckBonuses = {
	0,       -- Case 1:  +0%
	0.03,    -- Case 2:  +3%
	0.06,    -- Case 3:  +6%
	0.10,    -- Case 4:  +10%
	0.15,    -- Case 5:  +15%
	0.22,    -- Case 6:  +22%
	0.30,    -- Case 7:  +30%
	0.40,    -- Case 8:  +40%
	0.50,    -- Case 9:  +50%
	0.65,    -- Case 10: +65%
	0.80,    -- Case 11: +80%
	0.90,    -- Case 12: +90%
	1.10,    -- Case 13: +110%
	1.25,    -- Case 14: +125%
	1.40,    -- Case 15: +140%
	1.50,    -- Case 16: +150%
	1.75,    -- Case 17: +175%
	2.00,    -- Case 18: +200%
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
	"Scrap Case",        -- 1
	"Basic Case",        -- 2
	"Lucky Case",        -- 3
	"Polished Case",     -- 4
	"Shiny Case",        -- 5
	"Mystic Case",       -- 6
	"Inferno Case",      -- 7
	"Neon Case",         -- 8
	"Cosmic Case",       -- 9
	"Radiant Case",      -- 10
	"Celestial Case",    -- 11
	"Abyss Case",        -- 12
	"Iridescent Case",   -- 13
	"Angelic Case",      -- 14
	"Time Case",         -- 15
	"Tidal Case",        -- 16
	"Infinity Case",     -- 17
	"Prismatic Case",    -- 18
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
-- Escalating coin bonuses: 5% early, up to 20% late.
-- Rebirths 1-15 unlock cases 4-18.
-- Rebirth resets: cash + active potions.
-------------------------------------------------
Economy.MaxRebirths = 19

Economy.RebirthCosts = {
	750000,        -- Rebirth 1:  $750K  (achievable in ~20-30 min)
	2500000,       -- Rebirth 2:  $2.5M  (another ~20-30 min)
	7000000,       -- Rebirth 3:  $7M    (first hour done)
	18000000,      -- Rebirth 4:  $18M   (~1 hour)
	40000000,      -- Rebirth 5:  $40M   (~1 hour)
	80000000,      -- Rebirth 6:  $80M   (~1 hour)
	150000000,     -- Rebirth 7:  $150M  (~1 hour)
	275000000,     -- Rebirth 8:  $275M  (~1 hour)
	500000000,     -- Rebirth 9:  $500M  (getting longer)
	850000000,     -- Rebirth 10: $850M
	1500000000,    -- Rebirth 11: $1.5B
	2500000000,    -- Rebirth 12: $2.5B
	4000000000,    -- Rebirth 13: $4B
	7000000000,    -- Rebirth 14: $7B
	12000000000,   -- Rebirth 15: $12B
	20000000000,   -- Rebirth 16: $20B
	35000000000,   -- Rebirth 17: $35B
	60000000000,   -- Rebirth 18: $60B
	100000000000,  -- Rebirth 19: $100B
}

-- Escalating rebirth bonus percentages per level
Economy.RebirthBonusPerLevel = {
	5,  5,  5,  5,  5,    -- Rebirths 1-5:   +5% each
	8,  8,  8,  8,  8,    -- Rebirths 6-10:  +8% each
	12, 12, 12, 12, 12,   -- Rebirths 11-15: +12% each
	20, 20, 20, 20,       -- Rebirths 16-19: +20% each
}

--- Get the cost of the next rebirth (0-indexed rebirthCount)
function Economy.GetRebirthCost(currentRebirths: number): number
	local next = currentRebirths + 1
	if next > Economy.MaxRebirths then return math.huge end
	return Economy.RebirthCosts[next] or math.huge
end

--- Get the coin multiplier from rebirths (escalating per-level bonuses)
function Economy.GetRebirthCoinMultiplier(rebirthCount: number): number
	local totalPercent = 0
	for i = 1, math.min(rebirthCount, Economy.MaxRebirths) do
		totalPercent = totalPercent + (Economy.RebirthBonusPerLevel[i] or 5)
	end
	return 1 + (totalPercent / 100)
end

--- Total bonus percent at a given rebirth level
function Economy.GetRebirthBonusPercent(rebirthLevel: number): number
	local totalPercent = 0
	for i = 1, math.min(rebirthLevel, Economy.MaxRebirths) do
		totalPercent = totalPercent + (Economy.RebirthBonusPerLevel[i] or 5)
	end
	return totalPercent
end

--- Cases 1-3 are free. Case N (4-18) requires Rebirth (N-3).
function Economy.GetCrateRebirthRequirement(crateId: number): number
	if crateId <= 3 then return 0 end
	return crateId - 3
end

--- Info for a specific rebirth level (1-indexed)
function Economy.GetRebirthInfo(rebirthLevel: number)
	if rebirthLevel < 1 or rebirthLevel > Economy.MaxRebirths then return nil end
	local cost = Economy.RebirthCosts[rebirthLevel]
	local coinBonus = Economy.GetRebirthBonusPercent(rebirthLevel)
	local unlocksCase = rebirthLevel + 3
	if unlocksCase > Economy.TotalCases then unlocksCase = nil end
	return {
		level = rebirthLevel,
		cost = cost,
		coinBonus = coinBonus,
		unlocksCase = unlocksCase,
	}
end

-------------------------------------------------
-- SELL PRICES (per rarity — meaningful amounts)
-- Effect streamers sell for 1.5x the base rarity price.
-------------------------------------------------
Economy.SellPrices = {
	Common    = 500,
	Rare      = 5000,
	Epic      = 75000,
	Legendary = 750000,
	Mythic    = 7500000,
}

Economy.EffectSellMultiplier = 1.5

-------------------------------------------------
-- PASSIVE INCOME (disabled — players earn from streamers/selling only)
-------------------------------------------------
Economy.PassiveIncomeRate   = 0   -- no passive cash
Economy.PassiveIncomeInterval = 1  -- every second (unused when rate is 0)

-------------------------------------------------
-- LUCK (server-wide boost from Robux purchase)
-------------------------------------------------
Economy.DefaultLuckMultiplier = 1  -- 1x normal
Economy.BoostedLuckMultiplier = 2  -- 2x with boost

-------------------------------------------------
-- PERSONAL LUCK UPGRADE (at Upgrade stand; 1 luck = +1% drop luck)
-- First = 1,000, then 3x each time (gentler than 4x)
-------------------------------------------------
Economy.LuckUpgradeCostFirst  = 1000
Economy.LuckUpgradeCostMultiplier = 3

--- Cost to buy the next +5 luck
function Economy.GetLuckUpgradeCost(currentLuck: number): number
	local upgradesBought = math.floor((currentLuck or 0) / 5)
	return Economy.LuckUpgradeCostFirst * (Economy.LuckUpgradeCostMultiplier ^ upgradesBought)
end

-------------------------------------------------
-- CASH UPGRADE (coin multiplier at Upgrade stand; +2% cash per upgrade)
-- First = 1,000, then 3x each time
-------------------------------------------------
Economy.CashUpgradeCostFirst  = 1000
Economy.CashUpgradeCostMultiplier = 3

--- Cost for the next cash multiplier upgrade
function Economy.GetCashUpgradeCost(currentLevel: number): number
	local level = currentLevel or 0
	return Economy.CashUpgradeCostFirst * (Economy.CashUpgradeCostMultiplier ^ level)
end

-------------------------------------------------
-- ROBUX PRODUCT IDS (placeholder — set real ids in Studio)
-------------------------------------------------
Economy.Products = {
	ServerLuck   = 0,
	Buy5Spins    = 0,
	Buy10Spins   = 0,
	DoubleCash   = 0,
	PremiumSlot  = 0,
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
	Common    = 50,
	Rare      = 100,
	Epic      = 200,
	Legendary = 400,
	Mythic    = 800,
}

Economy.IndexEffectMultipliers = {
	Acid      = 3,
	Snow      = 5,
	Lava      = 10,
	Lightning = 20,
	Shadow    = 40,
	Glitchy   = 100,
	Lunar     = 200,
	Solar     = 500,
	Void      = 1000,
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

-------------------------------------------------
-- PITY SYSTEM
-- Guaranteed rarity after N spins without hitting that tier.
-- Counter resets when a streamer of that rarity (or higher) is obtained.
-------------------------------------------------
Economy.PityThresholds = {
	Rare      = 200,
	Epic      = 2000,
	Legendary = 15000,
	Mythic    = 75000,
}

return Economy
