--[[
	Server Entry Point — Spin the Streamer
	Initializes all server services in the correct order,
	builds the world, and sets up per-player bases.
]]

local services = script.Parent.services

-- Services
local PlayerData     = require(services.PlayerData)
local SpinService    = require(services.SpinService)
local EconomyService = require(services.EconomyService)
local RebirthService = require(services.RebirthService)
local StoreService   = require(services.StoreService)
local WorldBuilder   = require(services.WorldBuilder)
local BaseService    = require(services.BaseService)

-- Build the shared world (hub, stalls, decorations)
WorldBuilder.Build()

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

-- Initialize services (order matters: PlayerData first, then BaseService)
PlayerData.Init()
BaseService.Init(PlayerData)
SpinService.Init(PlayerData, BaseService)
EconomyService.Init(PlayerData)
RebirthService.Init(PlayerData, BaseService)
StoreService.Init(PlayerData, SpinService)

print("[Server] Spin the Streamer initialized! Map size: 400x1000 studs, 8 base slots")
