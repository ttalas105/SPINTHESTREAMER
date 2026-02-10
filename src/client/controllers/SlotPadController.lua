--[[
	SlotPadController.lua
	Manages the visual state of plot pads in the world.
	Listens for player data updates and reflects:
	- Unlocked vs locked pads
	- Equipped streamer on unlocked pads
	- Glow effects on unlocked pads
	- Floating lock text on locked pads
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local SlotsConfig = require(ReplicatedStorage.Shared.Config.SlotsConfig)
local Streamers = require(ReplicatedStorage.Shared.Config.Streamers)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)

local SlotPadController = {}

local player = Players.LocalPlayer
local pads = {} -- padIndex -> { part, billboard, light, equippedLabel }

-------------------------------------------------
-- FIND PADS IN WORLD
-------------------------------------------------

local function findPads()
	local lanesFolder = Workspace:WaitForChild("PlotLanes", 10)
	if not lanesFolder then
		warn("[SlotPadController] PlotLanes folder not found!")
		return
	end

	for _, laneFolder in ipairs(lanesFolder:GetChildren()) do
		if laneFolder:IsA("Folder") then
			for _, pad in ipairs(laneFolder:GetChildren()) do
				if pad:IsA("BasePart") and pad.Name:match("^Pad_") then
					local indexStr = pad.Name:match("Pad_(%d+)")
					local index = tonumber(indexStr)
					if index then
						pads[index] = {
							part = pad,
							billboard = nil,
							light = nil,
							equippedLabel = nil,
						}
					end
				end
			end
		end
	end
end

-------------------------------------------------
-- UPDATE PAD VISUALS
-------------------------------------------------

local function updatePad(padIndex, isUnlocked, equippedStreamerId)
	local padData = pads[padIndex]
	if not padData then return end

	local part = padData.part

	-- Update color and material
	local targetColor = isUnlocked and DesignConfig.Colors.PadUnlocked or DesignConfig.Colors.PadLocked
	local targetMaterial = isUnlocked and Enum.Material.Neon or Enum.Material.SmoothPlastic

	TweenService:Create(part, TweenInfo.new(0.5), {
		Color = targetColor,
	}):Play()
	part.Material = targetMaterial

	-- Update or create glow light
	local existingLight = part:FindFirstChildOfClass("PointLight")
	if isUnlocked then
		if not existingLight then
			local light = Instance.new("PointLight")
			light.Color = DesignConfig.Colors.PadGlow
			light.Brightness = 0.8
			light.Range = 12
			light.Parent = part
			padData.light = light
		end
	else
		if existingLight then
			existingLight:Destroy()
			padData.light = nil
		end
	end

	-- Update billboard (lock text or equipped streamer)
	-- Remove old billboard content
	local existingBillboard = part:FindFirstChildOfClass("BillboardGui")
	if existingBillboard then
		existingBillboard:Destroy()
	end

	if isUnlocked and equippedStreamerId then
		-- Show equipped streamer
		local streamerInfo = Streamers.ById[equippedStreamerId]
		if streamerInfo then
			local rarityInfo = Rarities.ByName[streamerInfo.rarity]

			local bb = Instance.new("BillboardGui")
			bb.Size = UDim2.new(6, 0, 3, 0)
			bb.StudsOffset = Vector3.new(0, 3, 0)
			bb.AlwaysOnTop = false
			bb.Parent = part

			local frame = Instance.new("Frame")
			frame.Size = UDim2.new(1, 0, 1, 0)
			frame.BackgroundColor3 = rarityInfo and rarityInfo.color or Color3.fromRGB(100, 100, 100)
			frame.BackgroundTransparency = 0.3
			frame.BorderSizePixel = 0
			frame.Parent = bb

			local cornerUI = Instance.new("UICorner")
			cornerUI.CornerRadius = UDim.new(0.15, 0)
			cornerUI.Parent = frame

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(1, 0, 0.6, 0)
			nameLabel.BackgroundTransparency = 1
			nameLabel.TextColor3 = DesignConfig.Colors.White
			nameLabel.Font = DesignConfig.Fonts.Primary
			nameLabel.TextScaled = true
			nameLabel.Text = streamerInfo.displayName
			nameLabel.Parent = frame

			local rarityLabel = Instance.new("TextLabel")
			rarityLabel.Size = UDim2.new(1, 0, 0.4, 0)
			rarityLabel.Position = UDim2.new(0, 0, 0.6, 0)
			rarityLabel.BackgroundTransparency = 1
			rarityLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
			rarityLabel.Font = DesignConfig.Fonts.Secondary
			rarityLabel.TextScaled = true
			rarityLabel.Text = streamerInfo.rarity
			rarityLabel.Parent = frame
		end
	elseif isUnlocked then
		-- Show "EMPTY SLOT"
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.new(5, 0, 1.5, 0)
		bb.StudsOffset = Vector3.new(0, 3, 0)
		bb.AlwaysOnTop = false
		bb.Parent = part

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.fromRGB(150, 255, 180)
		label.Font = DesignConfig.Fonts.Secondary
		label.TextScaled = true
		label.Text = "EMPTY SLOT"
		label.Parent = bb
	end
	-- Locked pads keep their original billboard from WorldBuilder
end

-------------------------------------------------
-- REFRESH ALL PADS
-------------------------------------------------

function SlotPadController.Refresh(playerData)
	if not playerData then return end

	local totalSlots = playerData.totalSlots or 1
	local equipped = playerData.equippedStreamers or {}

	for padIndex, _ in pairs(pads) do
		local isUnlocked = padIndex <= totalSlots
		local equippedStreamerId = equipped[tostring(padIndex)]
		updatePad(padIndex, isUnlocked, equippedStreamerId)
	end
end

-------------------------------------------------
-- INIT
-------------------------------------------------

function SlotPadController.Init()
	-- Wait for world to be built, then find pads
	task.spawn(function()
		task.wait(2) -- give WorldBuilder time to finish
		findPads()
	end)
end

return SlotPadController
