--[[
	HoldController.lua
	When a player clicks an inventory item, clone the streamer's 3D model
	from ReplicatedStorage.StreamerModels and weld it above the player's head.
	Model is full-size (same height as the player character).
	A BillboardGui floats above with big bubble-font text showing:
	  - Effect name (if any, in effect color)
	  - Streamer display name (large, in rarity color)
	  - Rarity tier
	  - Cash per second in big friendly numbers
	Click the same slot again to drop.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Streamers = require(ReplicatedStorage.Shared.Config.Streamers)
local Effects = require(ReplicatedStorage.Shared.Config.Effects)
local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)

local HoldController = {}

local player = Players.LocalPlayer
local modelsFolder = ReplicatedStorage:FindFirstChild("StreamerModels")

-- Currently held state
local heldModel = nil
local heldStreamerId = nil
local heldEffect = nil
local billboardGui = nil

-- Kid-friendly bubble font
local BUBBLE_FONT = Enum.Font.FredokaOne

-------------------------------------------------
-- FORMAT NUMBERS (with commas)
-------------------------------------------------

local function formatNumber(n)
	local s = tostring(math.floor(n))
	local formatted = ""
	local len = #s
	for i = 1, len do
		formatted = formatted .. string.sub(s, i, i)
		if (len - i) % 3 == 0 and i < len then
			formatted = formatted .. ","
		end
	end
	return formatted
end

-------------------------------------------------
-- OUTLINED TEXT HELPER
-- Creates a TextLabel with a thick UIStroke outline
-- so it pops against any background (like the reference)
-------------------------------------------------

local function makeOutlinedLabel(props)
	local label = Instance.new("TextLabel")
	label.Name = props.Name or "Label"
	label.Size = props.Size or UDim2.new(1, 0, 0, 30)
	label.Position = props.Position or UDim2.new(0.5, 0, 0, 0)
	label.AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0)
	label.BackgroundTransparency = 1
	label.Text = props.Text or ""
	label.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	label.Font = props.Font or BUBBLE_FONT
	label.TextSize = props.TextSize or 24
	label.TextScaled = props.TextScaled or false
	label.TextWrapped = true
	label.RichText = false
	label.Parent = props.Parent

	-- Thick dark outline for readability
	local stroke = Instance.new("UIStroke")
	stroke.Color = props.StrokeColor or Color3.fromRGB(0, 0, 0)
	stroke.Thickness = props.StrokeThickness or 2
	stroke.Transparency = 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label

	return label
end

-------------------------------------------------
-- BILLBOARD GUI — floating text above the model
-- Style: big bold bubble letters, no box background
-- Matches the reference screenshot
-------------------------------------------------

local function createBillboard(adornee, streamerInfo, effect)
	local effectInfo = effect and Effects.ByName[effect] or nil
	local rarityColor = DesignConfig.RarityColors[streamerInfo.rarity] or Color3.fromRGB(170, 170, 170)

	-- Calculate cash
	local cashPerSec = streamerInfo.cashPerSecond or 0
	if effectInfo and effectInfo.cashMultiplier then
		cashPerSec = cashPerSec * effectInfo.cashMultiplier
	end

	-- Count how many lines we need to size the billboard
	local lineCount = 3 -- name + rarity + cash
	if effectInfo then lineCount = lineCount + 1 end
	local totalHeight = lineCount * 38 + 10

	local bb = Instance.new("BillboardGui")
	bb.Name = "HeldStreamerInfo"
	bb.Size = UDim2.new(0, 260, 0, totalHeight)
	bb.StudsOffset = Vector3.new(0, 2.5, 0) -- above the model's head
	bb.AlwaysOnTop = true
	bb.Adornee = adornee
	bb.MaxDistance = 80

	-- No background — just floating text like the reference
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundTransparency = 1
	container.Parent = bb

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 2)
	layout.Parent = container

	-- 1) Effect name (if any) — e.g. "Acid" in green
	if effectInfo then
		makeOutlinedLabel({
			Name = "EffectLabel",
			Size = UDim2.new(1, 0, 0, 30),
			Text = effectInfo.prefix,
			TextColor3 = effectInfo.color,
			Font = BUBBLE_FONT,
			TextSize = 22,
			StrokeThickness = 2,
			Parent = container,
		}).LayoutOrder = 1
	end

	-- 2) Streamer name — BIG and bold, rarity color
	makeOutlinedLabel({
		Name = "NameLabel",
		Size = UDim2.new(1, 0, 0, 38),
		Text = streamerInfo.displayName,
		TextColor3 = rarityColor,
		Font = BUBBLE_FONT,
		TextSize = 32,
		StrokeThickness = 3,
		Parent = container,
	}).LayoutOrder = 2

	-- 3) Rarity — smaller, same rarity color
	makeOutlinedLabel({
		Name = "RarityLabel",
		Size = UDim2.new(1, 0, 0, 24),
		Text = streamerInfo.rarity,
		TextColor3 = rarityColor,
		Font = BUBBLE_FONT,
		TextSize = 18,
		StrokeThickness = 2,
		Parent = container,
	}).LayoutOrder = 3

	-- 4) Cash per second — big green bubble numbers
	makeOutlinedLabel({
		Name = "CashLabel",
		Size = UDim2.new(1, 0, 0, 36),
		Text = formatNumber(cashPerSec) .. "/s",
		TextColor3 = Color3.fromRGB(80, 255, 80),
		Font = BUBBLE_FONT,
		TextSize = 30,
		StrokeThickness = 3,
		Parent = container,
	}).LayoutOrder = 4

	return bb
end

-------------------------------------------------
-- ATTACH MODEL — held in hand like a sword / tool
-- Small figurine, arm extends out, model floats
-- above the hand. Strips all asset junk first.
-------------------------------------------------

local function getRightHand()
	local character = player.Character
	if not character then return nil end
	return character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
end

local function clearHeld()
	if heldModel then
		heldModel:Destroy()
		heldModel = nil
	end
	if billboardGui then
		billboardGui:Destroy()
		billboardGui = nil
	end
	heldStreamerId = nil
	heldEffect = nil
end

-- Strip built-in name tags, scripts, GUIs from asset models
-- but KEEP Humanoid, Shirt, Pants, Accessories (needed for clothes to render)
local function cleanModel(model)
	local toDestroy = {}
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BillboardGui") or desc:IsA("SurfaceGui")
			or desc:IsA("Script") or desc:IsA("LocalScript") or desc:IsA("ModuleScript")
			or desc:IsA("ClickDetector") or desc:IsA("ProximityPrompt")
			or desc:IsA("Sound")
		then
			table.insert(toDestroy, desc)
		end
	end
	for _, obj in ipairs(toDestroy) do
		pcall(function() obj:Destroy() end)
	end
	-- Keep the Humanoid (required for Shirt/Pants/Accessories to render)
	-- but disable health bar and animations so it doesn't interfere
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		-- Remove the Animator so it doesn't play idle animations
		local animator = hum:FindFirstChildOfClass("Animator")
		if animator then animator:Destroy() end
		local animController = model:FindFirstChildOfClass("AnimationController")
		if animController then animController:Destroy() end
	end
end

local function attachModel(modelTemplate, streamerInfo, effect)
	local character = player.Character
	if not character then return end
	local rightHand = getRightHand()
	if not rightHand then return end

	-- Clone and clean
	local clone = modelTemplate:Clone()
	clone.Name = "HeldStreamer"
	cleanModel(clone)

	-- Find or wrap primary part
	local primaryPart = clone.PrimaryPart
	if not primaryPart then
		primaryPart = clone:FindFirstChildWhichIsA("BasePart")
	end
	if not primaryPart then
		if clone:IsA("BasePart") then
			local wrapper = Instance.new("Model")
			wrapper.Name = "HeldStreamer"
			clone.Parent = wrapper
			wrapper.PrimaryPart = clone
			clone = wrapper
			primaryPart = clone.PrimaryPart
		else
			clone:Destroy()
			return
		end
	end

	-- Disable collisions + physics on every part
	for _, part in ipairs(clone:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Anchored = false
			part.Massless = true
		end
	end

	-- Scale to a nice hand-held figurine size (~4 studs tall)
	-- This is like holding a small action figure / trophy
	local TARGET_HEIGHT = 4.0
	local okBB, _, modelSize = pcall(function() return clone:GetBoundingBox() end)
	if okBB and modelSize and modelSize.Y > 0 then
		local scale = TARGET_HEIGHT / modelSize.Y
		clone:ScaleTo(scale)
	end

	-- Parent to character
	clone.Parent = character

	-- Weld to right hand so it looks like holding a sword/item
	-- The model sits directly above the hand, slightly in front
	local weld = Instance.new("Motor6D")
	weld.Name = "HeldStreamerWeld"
	weld.Part0 = rightHand
	weld.Part1 = primaryPart
	-- C0: offset from the hand
	--   Y = up (lift the model so its base is at hand level)
	--   Z = forward (slightly in front of the hand)
	weld.C0 = CFrame.new(0, 2.5, -0.5)
	weld.C1 = CFrame.new(0, 0, 0)
	weld.Parent = rightHand

	heldModel = clone

	-- Billboard floats above the figurine
	billboardGui = createBillboard(primaryPart, streamerInfo, effect)
	billboardGui.Parent = clone
end

-------------------------------------------------
-- PUBLIC API
-------------------------------------------------

function HoldController.Hold(item)
	if item == nil then
		clearHeld()
		return
	end

	local streamerId = type(item) == "table" and item.id or item
	local effect = type(item) == "table" and item.effect or nil

	-- Toggle off if already holding the same item
	if heldStreamerId == streamerId and heldEffect == effect then
		clearHeld()
		return
	end

	clearHeld()

	-- Find models folder
	if not modelsFolder then
		modelsFolder = ReplicatedStorage:FindFirstChild("StreamerModels")
	end
	if not modelsFolder then
		heldStreamerId = streamerId
		heldEffect = effect
		return
	end

	local modelTemplate = modelsFolder:FindFirstChild(streamerId)
	if not modelTemplate then
		heldStreamerId = streamerId
		heldEffect = effect
		return
	end

	local streamerInfo = Streamers.ById[streamerId]
	if not streamerInfo then return end

	heldStreamerId = streamerId
	heldEffect = effect
	attachModel(modelTemplate, streamerInfo, effect)
end

function HoldController.IsHolding(): boolean
	return heldStreamerId ~= nil
end

function HoldController.GetHeld()
	return heldStreamerId, heldEffect
end

function HoldController.Drop()
	clearHeld()
end

function HoldController.Init()
	modelsFolder = ReplicatedStorage:FindFirstChild("StreamerModels")

	player.CharacterAdded:Connect(function()
		heldModel = nil
		billboardGui = nil
		heldStreamerId = nil
		heldEffect = nil
	end)
end

return HoldController
