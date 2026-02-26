--[[
	Server Entry Point — Spin the Streamer
	Initializes all server services in the correct order,
	builds the world, and sets up per-player bases.
]]

local services = script.Parent.services

-- Load WorldBuilder first and build world immediately so map/stalls/bases exist
-- even if a later service fails to load
local WorldBuilder = require(services.WorldBuilder)
WorldBuilder.Build()

-- Now load services that depend on config (Streamers, etc.)
local PlayerData     = require(services.PlayerData)
local SpinService    = require(services.SpinService)
local EconomyService = require(services.EconomyService)
local RebirthService = require(services.RebirthService)
local StoreService   = require(services.StoreService)
local BaseService    = require(services.BaseService)
local IndexService    = require(services.IndexService)
local GemShopService  = require(services.GemShopService)
local SacrificeService = require(services.SacrificeService)
local ReceiptHandler   = require(services.ReceiptHandler)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Remove duplicate RemoteEvents (Studio can save extras alongside Rojo-synced ones)
do
	local remotes = ReplicatedStorage:WaitForChild("RemoteEvents")
	local seen = {}
	for _, child in ipairs(remotes:GetChildren()) do
		if child:IsA("RemoteEvent") then
			if seen[child.Name] then
				child:Destroy()
			else
				seen[child.Name] = true
			end
		end
	end
end

-- Spin stand: add ProximityPrompt so players can open the crate shop
local hub = Workspace:WaitForChild("Hub") -- wait until hub exists
do
	-- Prefer the full stall model if it exists, otherwise fall back to the sign part
	local stallSpin = hub:FindFirstChild("Stall_Spin")
	local basePart: BasePart? = nil

	if stallSpin and stallSpin:IsA("Model") then
		basePart = stallSpin:FindFirstChildWhichIsA("BasePart") or stallSpin.PrimaryPart
	end

	if not basePart then
		-- Fallback path: use the sign part created by WorldBuilder (Sign_Spin)
		local signSpin = hub:FindFirstChild("Sign_Spin")
		if signSpin and signSpin:IsA("BasePart") then
			basePart = signSpin
		end
	end

	if basePart then
		-- Create a small invisible part in FRONT of the stand, near player height,
		-- so the E prompt appears at the front instead of on top.
		local frontAnchor = Instance.new("Part")
		frontAnchor.Name = "SpinPromptAnchor"
		frontAnchor.Size = Vector3.new(1, 2, 1)
		frontAnchor.Transparency = 1
		frontAnchor.CanCollide = false
		frontAnchor.Anchored = true

		-- Move a bit in front of the stand, forced to near-ground player height
		local pos = basePart.Position
		frontAnchor.Position = Vector3.new(pos.X, 5, pos.Z + 5)
		frontAnchor.Parent = hub

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Open"
		prompt.ObjectText = "Spin Stand"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = 14
		prompt.HoldDuration = 0
		prompt.Parent = frontAnchor

		local OpenSpinStandGui = ReplicatedStorage.RemoteEvents:WaitForChild("OpenSpinStandGui")
		prompt.Triggered:Connect(function(player)
			OpenSpinStandGui:FireClient(player)
		end)

		print("[Server] Spin stand ProximityPrompt added at front of stall")
	else
		warn("[Server] Could not find a part to attach Spin stand ProximityPrompt")
	end
end

-- Upgrade stand (beside Spin): open luck upgrade UI
do
	local stallUpgrades = hub:FindFirstChild("Stall_Upgrades")
	local basePart = nil
	if stallUpgrades and stallUpgrades:IsA("Model") then
		basePart = stallUpgrades:FindFirstChildWhichIsA("BasePart") or stallUpgrades.PrimaryPart
	end
	if not basePart then
		local signUpgrades = hub:FindFirstChild("Sign_Upgrades")
		if signUpgrades and signUpgrades:IsA("BasePart") then
			basePart = signUpgrades
		end
	end
	if basePart then
		local frontAnchor = Instance.new("Part")
		frontAnchor.Name = "UpgradePromptAnchor"
		frontAnchor.Size = Vector3.new(1, 2, 1)
		frontAnchor.Transparency = 1
		frontAnchor.CanCollide = false
		frontAnchor.Anchored = true
		local pos = basePart.Position
		frontAnchor.Position = Vector3.new(pos.X, 5, pos.Z + 5)
		frontAnchor.Parent = hub
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Open"
		prompt.ObjectText = "Upgrades"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = 14
		prompt.HoldDuration = 0
		prompt.Parent = frontAnchor
		local OpenUpgradeStandGui = ReplicatedStorage.RemoteEvents:WaitForChild("OpenUpgradeStandGui")
		prompt.Triggered:Connect(function(player)
			OpenUpgradeStandGui:FireClient(player)
		end)
		print("[Server] Upgrade stand ProximityPrompt added")
	else
		warn("[Server] Could not find a part to attach Upgrade stand ProximityPrompt")
	end
end

-- Sell stand: open sell UI when player interacts
do
	local stallSell = hub:FindFirstChild("Stall_Sell")
	local basePart = nil
	if stallSell and stallSell:IsA("Model") then
		basePart = stallSell:FindFirstChildWhichIsA("BasePart") or stallSell.PrimaryPart
	end
	if not basePart then
		local signSell = hub:FindFirstChild("Sign_Sell")
		if signSell and signSell:IsA("BasePart") then
			basePart = signSell
		end
	end
	if basePart then
		local frontAnchor = Instance.new("Part")
		frontAnchor.Name = "SellPromptAnchor"
		frontAnchor.Size = Vector3.new(1, 2, 1)
		frontAnchor.Transparency = 1
		frontAnchor.CanCollide = false
		frontAnchor.Anchored = true
		local pos = basePart.Position
		frontAnchor.Position = Vector3.new(pos.X, 5, pos.Z + 5)
		frontAnchor.Parent = hub
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Open"
		prompt.ObjectText = "Sell Stand"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = 14
		prompt.HoldDuration = 0
		prompt.Parent = frontAnchor
		local OpenSellStandGui = ReplicatedStorage.RemoteEvents:WaitForChild("OpenSellStandGui")
		prompt.Triggered:Connect(function(player)
			OpenSellStandGui:FireClient(player)
		end)
		print("[Server] Sell stand ProximityPrompt added")
	else
		warn("[Server] Could not find a part to attach Sell stand ProximityPrompt")
	end
end

local PotionService  = require(services.PotionService)

-- Rebirth is accessed via the UI button (no physical stall needed)

-- Potion stand: open potion shop UI when player interacts
do
	local stallPotions = hub:FindFirstChild("Stall_Potions")
	local basePart = nil
	if stallPotions and stallPotions:IsA("Model") then
		basePart = stallPotions:FindFirstChildWhichIsA("BasePart") or stallPotions.PrimaryPart
	end
	if not basePart then
		local signPotions = hub:FindFirstChild("Sign_Potions")
		if signPotions and signPotions:IsA("BasePart") then
			basePart = signPotions
		end
	end
	if basePart then
		local frontAnchor = Instance.new("Part")
		frontAnchor.Name = "PotionPromptAnchor"
		frontAnchor.Size = Vector3.new(1, 2, 1)
		frontAnchor.Transparency = 1
		frontAnchor.CanCollide = false
		frontAnchor.Anchored = true
		local pos = basePart.Position
		frontAnchor.Position = Vector3.new(pos.X, 5, pos.Z + 5)
		frontAnchor.Parent = hub
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Open"
		prompt.ObjectText = "Potions"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = 14
		prompt.HoldDuration = 0
		prompt.Parent = frontAnchor
		local OpenPotionStandGui = ReplicatedStorage.RemoteEvents:WaitForChild("OpenPotionStandGui")
		prompt.Triggered:Connect(function(player)
			OpenPotionStandGui:FireClient(player)
		end)
		print("[Server] Potion stand ProximityPrompt added")
	else
		warn("[Server] Could not find a part to attach Potion stand ProximityPrompt")
	end
end

-- Gem Shop stand: open gem shop UI when player interacts
do
	local stallGems = hub:FindFirstChild("Stall_Gems")
	local basePart = nil
	if stallGems and stallGems:IsA("Model") then
		basePart = stallGems:FindFirstChildWhichIsA("BasePart") or stallGems.PrimaryPart
	end
	if not basePart then
		local signGems = hub:FindFirstChild("Sign_Gems")
		if signGems and signGems:IsA("BasePart") then
			basePart = signGems
		end
	end
	if basePart then
		local frontAnchor = Instance.new("Part")
		frontAnchor.Name = "GemShopPromptAnchor"
		frontAnchor.Size = Vector3.new(1, 2, 1)
		frontAnchor.Transparency = 1
		frontAnchor.CanCollide = false
		frontAnchor.Anchored = true
		local pos = basePart.Position
		frontAnchor.Position = Vector3.new(pos.X, 5, pos.Z + 5)
		frontAnchor.Parent = hub
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Open"
		prompt.ObjectText = "Gem Shop"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = 14
		prompt.HoldDuration = 0
		prompt.Parent = frontAnchor
		local OpenGemShopGui = ReplicatedStorage.RemoteEvents:WaitForChild("OpenGemShopGui")
		prompt.Triggered:Connect(function(player)
			OpenGemShopGui:FireClient(player)
		end)
		print("[Server] Gem Shop stand ProximityPrompt added")
	else
		warn("[Server] Could not find a part to attach Gem Shop ProximityPrompt")
	end
end

-- Sacrifice stand: open sacrifice UI when player interacts
do
	local stallSacrifice = hub:FindFirstChild("Stall_Sacrifice")
	local basePart = nil
	if stallSacrifice and stallSacrifice:IsA("Model") then
		basePart = stallSacrifice:FindFirstChildWhichIsA("BasePart") or stallSacrifice.PrimaryPart
	end
	if not basePart then
		local signSacrifice = hub:FindFirstChild("Sign_Sacrifice")
		if signSacrifice and signSacrifice:IsA("BasePart") then
			basePart = signSacrifice
		end
	end
	if basePart then
		local frontAnchor = Instance.new("Part")
		frontAnchor.Name = "SacrificePromptAnchor"
		frontAnchor.Size = Vector3.new(1, 2, 1)
		frontAnchor.Transparency = 1
		frontAnchor.CanCollide = false
		frontAnchor.Anchored = true
		local pos = basePart.Position
		frontAnchor.Position = Vector3.new(pos.X, 5, pos.Z + 5)
		frontAnchor.Parent = hub
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Open"
		prompt.ObjectText = "Sacrifice"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = 14
		prompt.HoldDuration = 0
		prompt.Parent = frontAnchor
		local OpenSacrificeGui = ReplicatedStorage.RemoteEvents:WaitForChild("OpenSacrificeGui")
		prompt.Triggered:Connect(function(player)
			OpenSacrificeGui:FireClient(player)
		end)
		print("[Server] Sacrifice stand ProximityPrompt added")
	else
		warn("[Server] Could not find a part to attach Sacrifice stand ProximityPrompt")
	end
end

-- Storage actions (swap, move between hotbar/storage)
do
	local StorageAction = ReplicatedStorage.RemoteEvents:WaitForChild("StorageAction")
	local StorageResult = ReplicatedStorage.RemoteEvents:WaitForChild("StorageResult")

	StorageAction.OnServerEvent:Connect(function(player, action, arg1, arg2)
		-- SECURITY FIX: Validate action type
		if type(action) ~= "string" then
			StorageResult:FireClient(player, { success = false, reason = "Invalid request." })
			return
		end
		if action == "swap" then
			local hotbarIdx = tonumber(arg1)
			local storageIdx = tonumber(arg2)
			if not hotbarIdx or not storageIdx then
				StorageResult:FireClient(player, { success = false, reason = "Invalid indices." })
				return
			end
			local ok = PlayerData.SwapHotbarStorage(player, hotbarIdx, storageIdx)
			StorageResult:FireClient(player, { success = ok, action = "swap" })
		elseif action == "toHotbar" then
			local storageIdx = tonumber(arg1)
			local hotbarIdx = arg2 and tonumber(arg2) or nil
			if not storageIdx then
				StorageResult:FireClient(player, { success = false, reason = "Invalid index." })
				return
			end
			local ok = PlayerData.MoveStorageToHotbar(player, storageIdx, hotbarIdx)
			StorageResult:FireClient(player, { success = ok, action = "toHotbar" })
		elseif action == "toStorage" then
			local hotbarIdx = tonumber(arg1)
			if not hotbarIdx then
				StorageResult:FireClient(player, { success = false, reason = "Invalid index." })
				return
			end
			local ok = PlayerData.MoveHotbarToStorage(player, hotbarIdx)
			if not ok then
				StorageResult:FireClient(player, { success = false, reason = "Storage is full!" })
			else
				StorageResult:FireClient(player, { success = true, action = "toStorage" })
			end
		end
	end)
	print("[Server] Storage actions wired")
end

-- Tutorial completion handler
do
	local TutorialComplete = ReplicatedStorage.RemoteEvents:WaitForChild("TutorialComplete")
	TutorialComplete.OnServerEvent:Connect(function(player)
		PlayerData.WithLock(player, function()
			local data = PlayerData._cache[player.UserId]
			if not data then return end
			if data.tutorialComplete then return end
			data.tutorialComplete = true
			PlayerData.Replicate(player)
		end)
	end)
end

-- Ensure new remote events exist before services init
do
	local remotes = ReplicatedStorage:WaitForChild("RemoteEvents")
	local newRemotes = { "ClaimQuestReward", "QuestUpdate" }
	for _, name in ipairs(newRemotes) do
		if not remotes:FindFirstChild(name) then
			local re = Instance.new("RemoteEvent")
			re.Name = name
			re.Parent = remotes
		end
	end
end

local QuestService = require(services.QuestService)
local LeaderboardService = require(services.LeaderboardService)

-- Initialize services (order matters: PlayerData first, then BaseService)
PlayerData.Init()
PotionService.Init(PlayerData)
BaseService.Init(PlayerData, PotionService)
QuestService.Init(PlayerData)
SpinService.Init(PlayerData, BaseService, PotionService, QuestService)
EconomyService.Init(PlayerData, PotionService, QuestService)
RebirthService.Init(PlayerData, BaseService, PotionService, QuestService)
StoreService.Init(PlayerData, SpinService)
IndexService.Init(PlayerData, QuestService)
GemShopService.Init(PlayerData, QuestService)
SacrificeService.Init(PlayerData, PotionService, QuestService)
ReceiptHandler.Init(PlayerData, SpinService)
LeaderboardService.Init(PlayerData)
PotionService.SetQuestService(QuestService)

-------------------------------------------------
-- DEBUG: Give all streamers (Studio only)
-------------------------------------------------
do
	local RunService = game:GetService("RunService")
	if RunService:IsStudio() then
		local Streamers = require(ReplicatedStorage.Shared.Config.Streamers)
		local remotes = ReplicatedStorage:WaitForChild("RemoteEvents")
		local debugRemote = remotes:FindFirstChild("DebugGiveAll")
		if not debugRemote then
			debugRemote = Instance.new("RemoteEvent")
			debugRemote.Name = "DebugGiveAll"
			debugRemote.Parent = remotes
		end
		debugRemote.OnServerEvent:Connect(function(player)
			print("[DEBUG] Giving all streamers to " .. player.Name)
			for _, s in ipairs(Streamers.List) do
				PlayerData.AddToInventory(player, s.id)
			end
			PlayerData.Replicate(player)
			print("[DEBUG] Done — gave " .. #Streamers.List .. " streamers")
		end)
		print("[Server] Debug: DebugGiveAll remote active (Studio only)")
	end
end

print("[Server] Spin the Streamer initialized! Map size: 400x1000 studs, 8 base slots")
