--[[
	PotionService.lua
	Server-side potion management.
	Tracks active luck/cash potions per player with expiry times.
	Time stacks (+5 min each use, max 3 hours). Multiplier does NOT stack (replaced).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Potions = require(ReplicatedStorage.Shared.Config.Potions)

local PotionService = {}

local PlayerData -- set in Init

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local BuyPotionRequest = RemoteEvents:WaitForChild("BuyPotionRequest")
local BuyPotionResult = RemoteEvents:WaitForChild("BuyPotionResult")
local PotionUpdate = RemoteEvents:WaitForChild("PotionUpdate")

-- Per-player active potions: { [userId] = { Luck = {multiplier, expiresAt}, Cash = {multiplier, expiresAt} } }
local activeEffects = {}

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
	local now = os.clock()
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
	PotionUpdate:FireClient(player, payload)
end

-------------------------------------------------
-- BUY / CONSUME POTION
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

	-- Check if a potion of the same TYPE is already active
	local effects = getEffects(player.UserId)
	local now = os.clock()
	local existing = effects[potionType]

	if existing and existing.expiresAt > now then
		-- Already active — only allow buying the SAME tier (stacks time)
		if existing.tier ~= tier then
			BuyPotionResult:FireClient(player, {
				success = false,
				reason = "You already have " .. potionType .. " Potion " .. tostring(existing.tier) .. " active! You can only stack the same tier to add more time.",
			})
			return
		end

		-- Same tier: add time (max 3 hours), keep same multiplier
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
-- PUBLIC API (used by SpinService / EconomyService)
-------------------------------------------------

--- Get the active luck multiplier for a player (1 if no potion)
function PotionService.GetLuckMultiplier(player): number
	local effects = activeEffects[player.UserId]
	if not effects or not effects.Luck then return 1 end
	if effects.Luck.expiresAt <= os.clock() then
		effects.Luck = nil
		return 1
	end
	return effects.Luck.multiplier
end

--- Clear all active potions for a player (used on rebirth)
function PotionService.ClearPotions(player)
	activeEffects[player.UserId] = {}
	sendPotionUpdate(player)
end

--- Get the active cash multiplier for a player (1 if no potion)
function PotionService.GetCashMultiplier(player): number
	local effects = activeEffects[player.UserId]
	if not effects or not effects.Cash then return 1 end
	if effects.Cash.expiresAt <= os.clock() then
		effects.Cash = nil
		return 1
	end
	return effects.Cash.multiplier
end

-------------------------------------------------
-- INIT
-------------------------------------------------

function PotionService.Init(playerDataModule)
	PlayerData = playerDataModule

	BuyPotionRequest.OnServerEvent:Connect(function(player, potionType, tier)
		handleBuyPotion(player, potionType, tier)
	end)

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
	end)
end

return PotionService
