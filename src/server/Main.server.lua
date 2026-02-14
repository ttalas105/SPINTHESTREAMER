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

-- Spin stand: add ProximityPrompt so players can open the crate shop
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
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

		-- Move a bit in front of the stand (negative Z) and slightly above ground
		local pos = basePart.Position
		frontAnchor.Position = pos + Vector3.new(0, 2, -3)
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
		frontAnchor.Position = pos + Vector3.new(0, 2, -3)
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
		frontAnchor.Position = pos + Vector3.new(0, 2, -3)
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

-- Rebirth stand: open rebirth UI when player interacts
do
	local stallRebirth = hub:FindFirstChild("Stall_Rebirth")
	local basePart = nil
	if stallRebirth and stallRebirth:IsA("Model") then
		basePart = stallRebirth:FindFirstChildWhichIsA("BasePart") or stallRebirth.PrimaryPart
	end
	if not basePart then
		local signRebirth = hub:FindFirstChild("Sign_Rebirth")
		if signRebirth and signRebirth:IsA("BasePart") then
			basePart = signRebirth
		end
	end
	if basePart then
		local frontAnchor = Instance.new("Part")
		frontAnchor.Name = "RebirthPromptAnchor"
		frontAnchor.Size = Vector3.new(1, 2, 1)
		frontAnchor.Transparency = 1
		frontAnchor.CanCollide = false
		frontAnchor.Anchored = true
		local pos = basePart.Position
		frontAnchor.Position = pos + Vector3.new(0, 2, -3)
		frontAnchor.Parent = hub
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Open"
		prompt.ObjectText = "Rebirth"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = 14
		prompt.HoldDuration = 0
		prompt.Parent = frontAnchor
		local OpenRebirthGui = ReplicatedStorage.RemoteEvents:WaitForChild("OpenRebirthGui")
		prompt.Triggered:Connect(function(player)
			OpenRebirthGui:FireClient(player)
		end)
		print("[Server] Rebirth stand ProximityPrompt added")
	else
		warn("[Server] Could not find a part to attach Rebirth stand ProximityPrompt")
	end
end

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
		frontAnchor.Position = pos + Vector3.new(0, 2, -3)
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

-- Initialize services (order matters: PlayerData first, then BaseService)
PlayerData.Init()
PotionService.Init(PlayerData)
BaseService.Init(PlayerData)
SpinService.Init(PlayerData, BaseService, PotionService)
EconomyService.Init(PlayerData, PotionService)
RebirthService.Init(PlayerData, BaseService, PotionService)
StoreService.Init(PlayerData, SpinService)

print("[Server] Spin the Streamer initialized! Map size: 400x1000 studs, 8 base slots")
