--[[
	LuckChances.lua
	Computes rarity drop chances for a given luck multiplier (same formula as SpinService).
	Use for tuning / documentation: "What luck do I need for consistent Rare/Epic/Legendary/Mythic?"
]]

local Streamers = require(script.Parent.Config.Streamers)

local LOG_MAX_ODDS = math.log(10000000)

local function getRarityChances(luckMultiplier: number): { [string]: number }
	local list = Streamers.List
	if not list or #list == 0 then
		return { Common = 1, Rare = 0, Epic = 0, Legendary = 0, Mythic = 0 }
	end
	local weights = {}
	local totalWeight = 0
	for i, s in ipairs(list) do
		local odds = type(s.odds) == "number" and s.odds or 100
		if odds < 1 then odds = 100 end
		local w = 1 / odds
		if luckMultiplier and luckMultiplier > 1 then
			local rarityFactor = math.log(math.max(odds, 1)) / LOG_MAX_ODDS
			rarityFactor = math.max(0, math.min(1, rarityFactor))
			w = w * (luckMultiplier ^ (1 + rarityFactor))
		end
		weights[i] = w
		totalWeight = totalWeight + w
	end
	if totalWeight <= 0 then
		return { Common = 1, Rare = 0, Epic = 0, Legendary = 0, Mythic = 0 }
	end
	local byRarity = { Common = 0, Rare = 0, Epic = 0, Legendary = 0, Mythic = 0 }
	for i, s in ipairs(list) do
		local r = s.rarity or "Common"
		if byRarity[r] then
			byRarity[r] = byRarity[r] + (weights[i] / totalWeight)
		end
	end
	return byRarity
end

-- Total luck multiplier from: 1 + (playerLuckPercent/100) + (crateLuckBonus)
-- e.g. 5% player + Case 7 (250%) = 1 + 0.05 + 2.5 = 3.55
local function luckMultFromPlayerAndCrate(playerLuck: number, crateLuckBonus: number): number
	local playerPercent = math.floor(playerLuck / 20) / 100
	return 1 + playerPercent + crateLuckBonus
end

-- Call from Studio Command Bar: require(ReplicatedStorage.Shared.LuckChances).PrintLuckTable()
local function printLuckTable()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local LuckChances = require(ReplicatedStorage.Shared.LuckChances)
	print("=== Luck multiplier -> Rarity chances (%) ===")
	print("Mult  | Common | Rare  | Epic   | Legendary | Mythic  | Rare+  | Epic+  ")
	print("------|--------|-------|--------|-----------|---------|--------|--------")
	for _, L in ipairs({ 1, 2, 3, 3.55, 4, 5, 6, 8, 10, 15, 20, 30, 50 }) do
		local c = LuckChances.GetRarityChances(L)
		local rarePlus = (c.Rare + c.Epic + c.Legendary + c.Mythic) * 100
		local epicPlus = (c.Epic + c.Legendary + c.Mythic) * 100
		print(string.format("%.2f   | %5.1f%% | %4.1f%% | %5.2f%% | %8.3f%% | %6.4f%% | %4.1f%% | %5.2f%%",
			L, c.Common*100, c.Rare*100, c.Epic*100, c.Legendary*100, c.Mythic*100, rarePlus, epicPlus))
	end
	print("\n=== Player luck (with Case 7 = 250% crate) -> chances ===")
	print("Luck  | Mult   | Common | Rare+  | Epic+   | Leg+Myth")
	print("------|--------|--------|--------|---------|----------")
	for _, luck in ipairs({ 0, 100, 200, 400, 600, 1000, 1500, 2000, 3000, 5000, 10000 }) do
		local L = LuckChances.LuckMultFromPlayerAndCrate(luck, 2.5)
		local c = LuckChances.GetRarityChances(L)
		local rarePlus = (c.Rare + c.Epic + c.Legendary + c.Mythic) * 100
		local epicPlus = (c.Epic + c.Legendary + c.Mythic) * 100
		local legMyth = (c.Legendary + c.Mythic) * 100
		print(string.format("%5d | %5.2f  | %5.1f%% | %4.1f%% | %5.2f%% | %6.3f%%",
			luck, L, c.Common*100, rarePlus, epicPlus, legMyth))
	end
end

return {
	GetRarityChances = getRarityChances,
	LuckMultFromPlayerAndCrate = luckMultFromPlayerAndCrate,
	PrintLuckTable = printLuckTable,
}
