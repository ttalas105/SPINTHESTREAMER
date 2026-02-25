--[[
	HoldController.lua
	Streamer floats next to the player's hand. Not a Tool, not welded, not parented
	to the character. Just an anchored model in Workspace that follows the hand
	position every frame. Player can move freely. No collision, no falling.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Streamers = require(ReplicatedStorage.Shared.Config.Streamers)
local Effects = require(ReplicatedStorage.Shared.Config.Effects)
local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local VFXHelper = require(ReplicatedStorage.Shared.VFXHelper)

local HoldController = {}

local player = Players.LocalPlayer
local modelsFolder = ReplicatedStorage:FindFirstChild("StreamerModels")

local heldModel = nil
local heldStreamerId = nil
local heldEffect = nil
local followConn = nil  -- RenderStepped connection

local BUBBLE_FONT = Enum.Font.FredokaOne

-------------------------------------------------
-- HELPERS
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
	local stroke = Instance.new("UIStroke")
	stroke.Color = props.StrokeColor or Color3.fromRGB(0, 0, 0)
	stroke.Thickness = props.StrokeThickness or 2
	stroke.Transparency = 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
	return label
end

local function createBillboard(adornee, streamerInfo, effect)
	local effectInfo = effect and Effects.ByName[effect] or nil
	local rarityColor = DesignConfig.RarityColors[streamerInfo.rarity] or Color3.fromRGB(170, 170, 170)
	local cashPerSec = streamerInfo.cashPerSecond or 0
	if effectInfo and effectInfo.cashMultiplier then
		cashPerSec = cashPerSec * effectInfo.cashMultiplier
	end
	local lineCount = 3
	if effectInfo then lineCount = lineCount + 1 end
	local totalHeight = lineCount * 38 + 10

	local bb = Instance.new("BillboardGui")
	bb.Name = "HeldStreamerInfo"
	bb.Size = UDim2.new(0, 260, 0, totalHeight)
	bb.StudsOffset = Vector3.new(0, 5, 0)
	bb.AlwaysOnTop = true
	bb.Adornee = adornee
	bb.MaxDistance = 80
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

	if effectInfo then
		makeOutlinedLabel({
			Name = "EffectLabel", Size = UDim2.new(1, 0, 0, 30),
			Text = effectInfo.prefix, TextColor3 = effectInfo.color,
			TextSize = 22, StrokeThickness = 2, Parent = container,
		}).LayoutOrder = 1
	end
	makeOutlinedLabel({
		Name = "NameLabel", Size = UDim2.new(1, 0, 0, 38),
		Text = streamerInfo.displayName, TextColor3 = rarityColor,
		TextSize = 32, StrokeThickness = 3, Parent = container,
	}).LayoutOrder = 2
	makeOutlinedLabel({
		Name = "RarityLabel", Size = UDim2.new(1, 0, 0, 24),
		Text = streamerInfo.rarity, TextColor3 = rarityColor,
		TextSize = 18, StrokeThickness = 2, Parent = container,
	}).LayoutOrder = 3
	makeOutlinedLabel({
		Name = "CashLabel", Size = UDim2.new(1, 0, 0, 36),
		Text = formatNumber(cashPerSec) .. "/s",
		TextColor3 = Color3.fromRGB(80, 255, 80),
		TextSize = 30, StrokeThickness = 3, Parent = container,
	}).LayoutOrder = 4

	return bb
end

-------------------------------------------------
-- CLEAR
-------------------------------------------------

local function clearHeld()
	if followConn then
		followConn:Disconnect()
		followConn = nil
	end
	if heldModel then
		pcall(function() heldModel:Destroy() end)
		heldModel = nil
	end
	heldStreamerId = nil
	heldEffect = nil
end

-------------------------------------------------
-- CLEAN MODEL: strip scripts, GUIs, sounds
-- KEEP Humanoid + Motor6Ds + Shirt/Pants/Accessories (needed for clothes)
-- Humanoid is disabled so it does nothing; model is anchored in Workspace
-------------------------------------------------

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

	-- Keep Humanoid for clothes but fully disable it
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.PlatformStand = true
		hum.BreakJointsOnDeath = false
		pcall(function()
			for _, st in ipairs(Enum.HumanoidStateType:GetEnumItems()) do
				if st ~= Enum.HumanoidStateType.None then
					pcall(function() hum:SetStateEnabled(st, false) end)
				end
			end
		end)
		local animator = hum:FindFirstChildOfClass("Animator")
		if animator then animator:Destroy() end
		local animCtrl = model:FindFirstChildOfClass("AnimationController")
		if animCtrl then animCtrl:Destroy() end
	end

	-- Preload clothing textures so they render immediately
	local toPreload = {}
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("Shirt") or desc:IsA("Pants") or desc:IsA("ShirtGraphic") or desc:IsA("Decal") then
			table.insert(toPreload, desc)
		end
	end
	if #toPreload > 0 then
		pcall(function() ContentProvider:PreloadAsync(toPreload) end)
	end

	-- Anchor every part and disable all collision/interaction
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Massless = true
		end
	end
end

-------------------------------------------------
-- ATTACH: clone model, clean it, start following hand
-------------------------------------------------

local function attachModel(modelTemplate, streamerInfo, effect)
	local character = player.Character
	if not character then return end

	local clone = modelTemplate:Clone()
	clone.Name = "HeldStreamer"
	cleanModel(clone)

	-- Find primary part
	local primaryPart = clone.PrimaryPart
	if not primaryPart then
		primaryPart = clone:FindFirstChildWhichIsA("BasePart")
	end
	if not primaryPart then
		clone:Destroy()
		return
	end
	clone.PrimaryPart = primaryPart

	-- Keep the model at its original size (no shrinking)

	-- Parent to Workspace (not character — no physics interaction)
	clone.Parent = workspace
	heldModel = clone

	-- Billboard
	local bb = createBillboard(primaryPart, streamerInfo, effect)
	bb.Parent = clone

	-- Compute Y offset so the model's feet sit at a consistent height (before VFX)
	local pivotToBottom = 0
	do
		local ok, bbCF, bbSize = pcall(function() return clone:GetBoundingBox() end)
		if ok and bbCF and bbSize then
			local pivotY = clone:GetPivot().Position.Y
			local bottomY = bbCF.Position.Y - (bbSize.Y / 2)
			pivotToBottom = pivotY - bottomY
		end
	end

	-- Attach element VFX/aura
	if effect then
		local effectName = type(effect) == "table" and effect.name or effect
		VFXHelper.Attach(clone, effectName)
	end

	-- Follow hand every render frame. Model is anchored so PivotTo just sets CFrame.
	followConn = RunService.RenderStepped:Connect(function()
		local char = player.Character
		if not char then return end
		if not heldModel or not heldModel.Parent or not heldModel.PrimaryPart then
			return
		end

		local root = char:FindFirstChild("HumanoidRootPart")
		if not root then return end

		local groundY = root.CFrame.Position.Y - 3
		local baseCF = root.CFrame * CFrame.new(2.5, 0, -2)
		local pos = Vector3.new(baseCF.Position.X, groundY + pivotToBottom, baseCF.Position.Z)
		local _, yRot, _ = root.CFrame:ToEulerAnglesYXZ()
		heldModel:PivotTo(CFrame.new(pos) * CFrame.Angles(0, yRot, 0))
		VFXHelper.Reposition(heldModel)
	end)
end

local function normalizeModelKey(value: string): string
	local s = string.lower(value or "")
	s = string.gsub(s, "[%s_%-%./]", "")
	return s
end

local function findStreamerModelTemplate(streamerId: string)
	if not modelsFolder then
		modelsFolder = ReplicatedStorage:FindFirstChild("StreamerModels")
	end
	if not modelsFolder or not streamerId then
		return nil
	end
	local exact = modelsFolder:FindFirstChild(streamerId)
	if exact then
		return exact
	end
	local wanted = normalizeModelKey(streamerId)
	for _, child in ipairs(modelsFolder:GetChildren()) do
		if normalizeModelKey(child.Name) == wanted then
			return child
		end
	end
	return nil
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

	-- Always clear and re-hold; toggle logic is handled by InventoryController.SelectSlot
	clearHeld()

	local modelTemplate = findStreamerModelTemplate(streamerId)
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
		clearHeld()
	end)
end

return HoldController
