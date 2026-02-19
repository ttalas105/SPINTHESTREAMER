--[[
	PotionService.lua
	Server-side potion management.
	Tracks active luck/cash/prismatic potions per player with expiry times.
	Time stacks (+5 min each use, max 3 hours). Multiplier does NOT stack (replaced).
	Prismatic (Robux) boosts both luck and cash simultaneously (x7).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local Potions = require(ReplicatedStorage.Shared.Config.Potions)

local PotionService = {}

local PlayerData -- set in Init

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local BuyPotionRequest = RemoteEvents:WaitForChild("BuyPotionRequest")
local BuyPotionResult = RemoteEvents:WaitForChild("BuyPotionResult")
local PotionUpdate = RemoteEvents:WaitForChild("PotionUpdate")

-- Per-player active potions:
-- { [userId] = { Luck = {multiplier, tier, expiresAt}, Cash = {...}, Prismatic = {...} } }
local activeEffects = {}

-- Per-player pending Prismatic potion count (bought with Robux, consumed one at a time)
local prismaticInventory = {} -- { [userId] = count }

-------------------------------------------------
-- HELPERS
-------------------------------------------------

local function getEffects(userId)
	if not activeEffects[userId] then
		activeEffects[userId] = {}
	end
	return activeEffects[userId]
end

local function sendPotionUpdate(player)
	local effects = getEffects(player.UserId)
	local now = os.time()
	local payload = {}
	for potionType, info in pairs(effects) do
		if info.expiresAt > now then
			payload[potionType] = {
				multiplier = info.multiplier,
				tier = info.tier,
				remaining = math.ceil(info.expiresAt - now),
			}
		end
	end
	-- Include prismatic inventory count
	payload._prismaticCount = prismaticInventory[player.UserId] or 0
	PotionUpdate:FireClient(player, payload)
end

-------------------------------------------------
-- BUY / CONSUME POTION (Luck/Cash — in-game currency)
-------------------------------------------------

local function handleBuyPotion(player, potionType, tier)
	-- Validate
	if type(potionType) ~= "string" or type(tier) ~= "number" then
		BuyPotionResult:FireClient(player, { success = false, reason = "Invalid request." })
		return
	end

	local potionInfo = Potions.Get(potionType, tier)
	if not potionInfo then
		BuyPotionResult:FireClient(player, { success = false, reason = "Unknown potion." })
		return
	end

	-- Check cash
	local data = PlayerData.Get(player)
	if not data then
		BuyPotionResult:FireClient(player, { success = false, reason = "Data not loaded." })
		return
	end

	if data.cash < potionInfo.cost then
		BuyPotionResult:FireClient(player, { success = false, reason = "Not enough cash!" })
		return
	end

	-- Check conflicts with Prismatic (Prismatic covers both Luck + Cash)
	local effects = getEffects(player.UserId)
	local now = os.time()
	local prismatic = effects.Prismatic
	if prismatic and prismatic.expiresAt > now then
		BuyPotionResult:FireClient(player, {
			success = false,
			reason = "You have a Prismatic Potion active! It already boosts " .. potionType .. ".",
		})
		return
	end

	-- Check if a potion of the same TYPE is already active
	local existing = effects[potionType]
	if existing and existing.expiresAt > now then
		if existing.tier ~= tier then
			BuyPotionResult:FireClient(player, {
				success = false,
				reason = "You already have " .. potionType .. " Potion " .. tostring(existing.tier) .. " active! You can only stack the same tier to add more time.",
			})
			return
		end

		-- Same tier: add time (max 3 hours)
		data.cash = data.cash - potionInfo.cost
		local currentRemaining = existing.expiresAt - now
		local newRemaining = math.min(currentRemaining + Potions.DURATION_PER_USE, Potions.MAX_DURATION)
		existing.expiresAt = now + newRemaining
	else
		-- No active potion: start fresh
		data.cash = data.cash - potionInfo.cost
		effects[potionType] = {
			multiplier = potionInfo.multiplier,
			tier = potionInfo.tier,
			expiresAt = now + Potions.DURATION_PER_USE,
		}
	end

	PlayerData.Replicate(player)
	sendPotionUpdate(player)
	BuyPotionResult:FireClient(player, {
		success = true,
		potionType = potionType,
		tier = potionInfo.tier,
		name = potionInfo.name,
	})
end

-------------------------------------------------
-- PRISMATIC POTION (Robux)
-------------------------------------------------

-- Consume one prismatic potion from inventory (activate or extend time)
local function handleUsePrismatic(player)
	local userId = player.UserId
	local count = prismaticInventory[userId] or 0
	if count <= 0 then
		BuyPotionResult:FireClient(player, {
			success = false,
			reason = "You have no Prismatic Potions! Purchase some first.",
		})
		return
	end

	local effects = getEffects(userId)
	local now = os.time()

	-- Check conflicts: cannot use Prismatic if Luck or Cash potion is active
	local luckActive = effects.Luck and effects.Luck.expiresAt > now
	local cashActive = effects.Cash and effects.Cash.expiresAt > now
	if luckActive or cashActive then
		local activeType = luckActive and "Luck" or "Cash"
		BuyPotionResult:FireClient(player, {
			success = false,
			reason = "You have a " .. activeType .. " Potion active! Wait for it to expire before using Prismatic.",
		})
		return
	end

	-- Use one potion
	prismaticInventory[userId] = count - 1

	local existing = effects.Prismatic
	if existing and existing.expiresAt > now then
		-- Stack time
		local currentRemaining = existing.expiresAt - now
		local newRemaining = math.min(currentRemaining + Potions.DURATION_PER_USE, Potions.MAX_DURATION)
		existing.expiresAt = now + newRemaining
	else
		-- Start fresh
		effects.Prismatic = {
			multiplier = Potions.Prismatic.multiplier,
			tier = 0, -- Prismatic has no tier
			expiresAt = now + Potions.DURATION_PER_USE,
		}
	end

	sendPotionUpdate(player)
	BuyPotionResult:FireClient(player, {
		success = true,
		potionType = "Prismatic",
		tier = 0,
		name = Potions.Prismatic.name,
	})
end

-- Grant prismatic potions after Robux purchase
local function grantPrismaticPotions(player, amount)
	local userId = player.UserId
	prismaticInventory[userId] = (prismaticInventory[userId] or 0) + amount
	sendPotionUpdate(player)
	BuyPotionResult:FireClient(player, {
		success = true,
		potionType = "PrismaticPurchase",
		tier = 0,
		name = amount .. "x Prismatic Potion" .. (amount > 1 and "s" or ""),
		amount = amount,
	})
end

-------------------------------------------------
-- PUBLIC API (used by SpinService / EconomyService)
-------------------------------------------------

--- Get the active luck multiplier for a player (1 if no potion)
function PotionService.GetLuckMultiplier(player): number
	local effects = activeEffects[player.UserId]
	if not effects then return 1 end

	local now = os.time()

	-- Sacrifice "Feeling Lucky" overrides: 0 or 2 for 10 min
	if effects.SacrificeLuck and effects.SacrificeLuck.expiresAt > now then
		return effects.SacrificeLuck.multiplier
	end
	if effects.SacrificeLuck and effects.SacrificeLuck.expiresAt <= now then effects.SacrificeLuck = nil end

	-- Check Prismatic first (it covers luck)
	if effects.Prismatic and effects.Prismatic.expiresAt > now then
		return effects.Prismatic.multiplier
	end

	if effects.Luck and effects.Luck.expiresAt > now then
		return effects.Luck.multiplier
	end

	-- Cleanup expired
	if effects.Luck and effects.Luck.expiresAt <= now then effects.Luck = nil end
	if effects.Prismatic and effects.Prismatic.expiresAt <= now then effects.Prismatic = nil end

	return 1
end

--- Set temporary luck modifier from Sacrifice "Feeling Lucky" (multiplier 0 or 2, duration in seconds)
function PotionService.SetSacrificeLuck(player, multiplier: number, durationSeconds: number)
	local effects = getEffects(player.UserId)
	effects.SacrificeLuck = {
		multiplier = multiplier,
		expiresAt = os.time() + durationSeconds,
	}
	sendPotionUpdate(player)
end

--- Get the active cash multiplier for a player (1 if no potion)
function PotionService.GetCashMultiplier(player): number
	local effects = activeEffects[player.UserId]
	if not effects then return 1 end

	local now = os.time()

	-- Check Prismatic first (it covers cash)
	if effects.Prismatic and effects.Prismatic.expiresAt > now then
		return effects.Prismatic.multiplier
	end

	if effects.Cash and effects.Cash.expiresAt > now then
		return effects.Cash.multiplier
	end

	-- Cleanup expired
	if effects.Cash and effects.Cash.expiresAt <= now then effects.Cash = nil end
	if effects.Prismatic and effects.Prismatic.expiresAt <= now then effects.Prismatic = nil end

	return 1
end

--- Grant prismatic potions (called by ReceiptHandler after Robux purchase)
function PotionService.GrantPrismaticPotions(player, amount)
	grantPrismaticPotions(player, amount)
end

--- Clear all active potions for a player (used on rebirth)
function PotionService.ClearPotions(player)
	activeEffects[player.UserId] = {}
	-- Note: prismatic inventory (bought with Robux) and SacrificeLuck are cleared
	sendPotionUpdate(player)
end

-------------------------------------------------
-- INIT
-------------------------------------------------

function PotionService.Init(playerDataModule)
	PlayerData = playerDataModule

	-- Regular potion purchases (in-game cash)
	BuyPotionRequest.OnServerEvent:Connect(function(player, potionType, tier)
		if potionType == "UsePrismatic" then
			handleUsePrismatic(player)
		else
			handleBuyPotion(player, potionType, tier)
		end
	end)

	-- SECURITY FIX: ProcessReceipt is now handled by ReceiptHandler.lua
	-- Do NOT set MarketplaceService.ProcessReceipt here (only one callback allowed)

	-- Periodic update: send timer updates to all players every 1 second
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in ipairs(Players:GetPlayers()) do
				if activeEffects[player.UserId] then
					sendPotionUpdate(player)
				end
			end
		end
	end)

	-- Cleanup on leave
	Players.PlayerRemoving:Connect(function(player)
		activeEffects[player.UserId] = nil
		prismaticInventory[player.UserId] = nil
	end)
end

return PotionService
