--[[
	PotionService.lua
	Server-side potion management.
	Tracks active luck/cash/divine potions per player with expiry times.
	Time stacks (+5 min each use, max 3 hours). Multiplier does NOT stack (replaced).
	Divine (Robux) boosts both luck and cash simultaneously (x5).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local Potions = require(ReplicatedStorage.Shared.Config.Potions)

local PotionService = {}

local PlayerData -- set in Init
local QuestService -- set via SetQuestService after Init

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local BuyPotionRequest = RemoteEvents:WaitForChild("BuyPotionRequest")
local BuyPotionResult = RemoteEvents:WaitForChild("BuyPotionResult")
local PotionUpdate = RemoteEvents:WaitForChild("PotionUpdate")

-- Per-player active potions:
-- { [userId] = { Luck = {multiplier, tier, expiresAt}, Cash = {...}, Divine = {...} } }
local activeEffects = {}

-- Per-player pending Divine potion count (bought with Robux, consumed one at a time)
local divineInventory = {} -- { [userId] = count }

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
	-- Include divine inventory count
	payload._divineCount = divineInventory[player.UserId] or 0
	PotionUpdate:FireClient(player, payload)
end

-------------------------------------------------
-- BUY / CONSUME POTION (Luck/Cash — in-game currency)
-------------------------------------------------

local function handleBuyPotion(player, potionType, tier)
	if not PlayerData.IsTutorialComplete(player) then
		BuyPotionResult:FireClient(player, { success = false, reason = "Complete the tutorial first!" })
		return
	end
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

	-- Check rebirth requirement
	local rebirthRequired = potionInfo.rebirthRequired or 0
	if rebirthRequired > 0 then
		local rebirthCount = PlayerData.GetRebirthCount(player)
		if rebirthCount < rebirthRequired then
			BuyPotionResult:FireClient(player, {
				success = false,
				reason = "Requires Rebirth " .. rebirthRequired .. "! (You are Rebirth " .. rebirthCount .. ")",
			})
			return
		end
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

	-- Check conflicts with Divine (Divine covers both Luck + Cash)
	local effects = getEffects(player.UserId)
	local now = os.time()
	local divine = effects.Divine
	if divine and divine.expiresAt > now then
		BuyPotionResult:FireClient(player, {
			success = false,
			reason = "You have a Divine Potion active! It already boosts " .. potionType .. ".",
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
	if QuestService then
		QuestService.Increment(player, "potionsBought", 1)
	end
end

-------------------------------------------------
-- DIVINE POTION (Robux)
-------------------------------------------------

-- Consume one divine potion from inventory (activate or extend time)
local function handleUseDivine(player)
	local userId = player.UserId
	local count = divineInventory[userId] or 0
	if count <= 0 then
		BuyPotionResult:FireClient(player, {
			success = false,
			reason = "You have no Divine Potions! Purchase some first.",
		})
		return
	end

	local effects = getEffects(userId)
	local now = os.time()

	-- Check conflicts: cannot use Divine if Luck or Cash potion is active
	local luckActive = effects.Luck and effects.Luck.expiresAt > now
	local cashActive = effects.Cash and effects.Cash.expiresAt > now
	if luckActive or cashActive then
		local activeType = luckActive and "Luck" or "Cash"
		BuyPotionResult:FireClient(player, {
			success = false,
			reason = "You have a " .. activeType .. " Potion active! Wait for it to expire before using Divine.",
		})
		return
	end

	-- Use one potion
	divineInventory[userId] = count - 1

	local existing = effects.Divine
	if existing and existing.expiresAt > now then
		-- Stack time
		local currentRemaining = existing.expiresAt - now
		local newRemaining = math.min(currentRemaining + Potions.DURATION_PER_USE, Potions.MAX_DURATION)
		existing.expiresAt = now + newRemaining
	else
		-- Start fresh
		effects.Divine = {
			multiplier = Potions.Divine.multiplier,
			tier = 0,
			expiresAt = now + Potions.DURATION_PER_USE,
		}
	end

	sendPotionUpdate(player)
	BuyPotionResult:FireClient(player, {
		success = true,
		potionType = "Divine",
		tier = 0,
		name = Potions.Divine.name,
	})
end

-- Grant divine potions after Robux purchase
local function grantDivinePotions(player, amount)
	local userId = player.UserId
	divineInventory[userId] = (divineInventory[userId] or 0) + amount
	sendPotionUpdate(player)
	BuyPotionResult:FireClient(player, {
		success = true,
		potionType = "DivinePurchase",
		tier = 0,
		name = amount .. "x Divine Potion" .. (amount > 1 and "s" or ""),
		amount = amount,
	})
	if QuestService then
		QuestService.Increment(player, "potionsBought", amount)
	end
end

-------------------------------------------------
-- PUBLIC API (used by SpinService / EconomyService)
-------------------------------------------------

--- Set QuestService reference (called from Main.server.lua after all services are initialized)
function PotionService.SetQuestService(qs)
	QuestService = qs
end

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

	-- Check Divine first (it covers luck)
	if effects.Divine and effects.Divine.expiresAt > now then
		return effects.Divine.multiplier
	end

	if effects.Luck and effects.Luck.expiresAt > now then
		return effects.Luck.multiplier
	end

	-- Cleanup expired
	if effects.Luck and effects.Luck.expiresAt <= now then effects.Luck = nil end
	if effects.Divine and effects.Divine.expiresAt <= now then effects.Divine = nil end

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

	-- Check Divine first (it covers cash)
	if effects.Divine and effects.Divine.expiresAt > now then
		return effects.Divine.multiplier
	end

	if effects.Cash and effects.Cash.expiresAt > now then
		return effects.Cash.multiplier
	end

	-- Cleanup expired
	if effects.Cash and effects.Cash.expiresAt <= now then effects.Cash = nil end
	if effects.Divine and effects.Divine.expiresAt <= now then effects.Divine = nil end

	return 1
end

--- Grant divine potions (called by ReceiptHandler after Robux purchase)
function PotionService.GrantDivinePotions(player, amount)
	grantDivinePotions(player, amount)
end

--- Clear all active potions for a player (used on rebirth)
function PotionService.ClearPotions(player)
	activeEffects[player.UserId] = {}
	-- Note: divine inventory (bought with Robux) and SacrificeLuck are cleared
	sendPotionUpdate(player)
end

-------------------------------------------------
-- INIT
-------------------------------------------------

function PotionService.Init(playerDataModule)
	PlayerData = playerDataModule

	-- Regular potion purchases (in-game cash)
	BuyPotionRequest.OnServerEvent:Connect(function(player, potionType, tier)
		if potionType == "UseDivine" then
			handleUseDivine(player)
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
		divineInventory[player.UserId] = nil
	end)
end

return PotionService
