--[[
	InventoryController.lua
	Bottom inventory bar showing the player's collected streamers.
	Displays numbered slots (1–9 visible, scrollable for more).
	Backpack button opens full inventory view.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local Streamers = require(ReplicatedStorage.Shared.Config.Streamers)
local Effects = require(ReplicatedStorage.Shared.Config.Effects)
local UIHelper = require(script.Parent.UIHelper)

-- Helper: get streamer ID from an inventory item (supports old string or new {id, effect} format)
local function getItemId(item)
	if type(item) == "table" then return item.id end
	if type(item) == "string" then return item end
	return nil
end
local function getItemEffect(item)
	if type(item) == "table" then return item.effect end
	return nil
end

local InventoryController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local SellRequest = RemoteEvents:WaitForChild("SellRequest")

-- Lazy-loaded SacrificeController to check queued indices
local SacrificeController = nil

-- State
local inventory = {}           -- mirror of server inventory
local selectedIndex = nil      -- currently selected inventory index
local onSelectionChanged = {}  -- callbacks when selection changes

-- UI refs
local screenGui
local barContainer
local slotsFrame
local slots = {}               -- index -> { frame, iconLabel, rarityLabel, numberLabel }
local backpackButton
local selectedLabel

-- How many slots visible in hotbar
local VISIBLE_SLOTS = 9

-------------------------------------------------
-- BUILD SLOT
-------------------------------------------------

local EMPTY_SLOT_COLOR = Color3.fromRGB(40, 35, 60)

local function createSlot(parent, slotNumber)
	local slotSize = DesignConfig.Sizes.InventorySlotSize

	local frame = UIHelper.CreateRoundedFrame({
		Name = "Slot_" .. slotNumber,
		Size = slotSize,
		Color = EMPTY_SLOT_COLOR,
		CornerRadius = UDim.new(0, 10),
		StrokeColor = Color3.fromRGB(80, 75, 110),
		Parent = parent,
	})

	local numberLabel = Instance.new("TextLabel")
	numberLabel.Name = "Number"
	numberLabel.Size = UDim2.new(0, 16, 0, 14)
	numberLabel.Position = UDim2.new(0, 3, 0, 2)
	numberLabel.BackgroundTransparency = 1
	numberLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
	numberLabel.Font = Enum.Font.FredokaOne
	numberLabel.TextSize = 11
	numberLabel.Text = tostring(slotNumber)
	numberLabel.TextXAlignment = Enum.TextXAlignment.Left
	numberLabel.TextYAlignment = Enum.TextYAlignment.Top
	numberLabel.ZIndex = 3
	numberLabel.Parent = frame

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.Size = UDim2.new(1, -4, 0.5, 0)
	iconLabel.Position = UDim2.new(0.5, 0, 0.25, 0)
	iconLabel.AnchorPoint = Vector2.new(0.5, 0)
	iconLabel.BackgroundTransparency = 1
	iconLabel.TextColor3 = Color3.new(1, 1, 1)
	iconLabel.Font = Enum.Font.FredokaOne
	iconLabel.TextScaled = true
	iconLabel.Text = ""
	iconLabel.ZIndex = 3
	iconLabel.Parent = frame

	local iconStroke = Instance.new("UIStroke")
	iconStroke.Color = Color3.fromRGB(0, 0, 0)
	iconStroke.Thickness = 1.5
	iconStroke.Transparency = 0.2
	iconStroke.Parent = iconLabel

	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Name = "Rarity"
	rarityLabel.Size = UDim2.new(1, -4, 0, 14)
	rarityLabel.Position = UDim2.new(0.5, 0, 1, -2)
	rarityLabel.AnchorPoint = Vector2.new(0.5, 1)
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.TextColor3 = Color3.new(1, 1, 1)
	rarityLabel.Font = Enum.Font.FredokaOne
	rarityLabel.TextSize = 10
	rarityLabel.Text = ""
	rarityLabel.ZIndex = 3
	rarityLabel.Parent = frame

	local rarStroke = Instance.new("UIStroke")
	rarStroke.Color = Color3.fromRGB(0, 0, 0)
	rarStroke.Thickness = 1.2
	rarStroke.Transparency = 0.3
	rarStroke.Parent = rarityLabel

	local clickBtn = Instance.new("TextButton")
	clickBtn.Name = "ClickZone"
	clickBtn.Size = UDim2.new(1, 0, 1, 0)
	clickBtn.BackgroundTransparency = 1
	clickBtn.Text = ""
	clickBtn.ZIndex = 5
	clickBtn.Parent = frame

	clickBtn.MouseButton1Click:Connect(function()
		InventoryController.SelectSlot(slotNumber)
	end)

	local bounceTween = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local idleSize = slotSize
	local hoverSize = UDim2.new(idleSize.X.Scale * 1.08, idleSize.X.Offset * 1.08, idleSize.Y.Scale * 1.08, idleSize.Y.Offset * 1.08)

	clickBtn.MouseEnter:Connect(function()
		TweenService:Create(frame, bounceTween, { Size = hoverSize }):Play()
	end)
	clickBtn.MouseLeave:Connect(function()
		TweenService:Create(frame, bounceTween, { Size = idleSize }):Play()
	end)

	return {
		frame = frame,
		iconLabel = iconLabel,
		rarityLabel = rarityLabel,
		numberLabel = numberLabel,
	}
end

-------------------------------------------------
-- UPDATE SLOTS
-------------------------------------------------

local function updateSlotVisuals()
	-- Lazy-load SacrificeController (avoid circular dependency at require-time)
	if not SacrificeController then
		local ok, mod = pcall(function() return require(script.Parent.SacrificeController) end)
		if ok then SacrificeController = mod end
	end
	local queuedSet = SacrificeController and SacrificeController.GetQueuedIndices and SacrificeController.GetQueuedIndices() or {}

	for i = 1, VISIBLE_SLOTS do
		local slotData = slots[i]
		if not slotData then continue end

		local item = inventory[i]
		local streamerId = getItemId(item)
		local effect = getItemEffect(item)
		local stroke = slotData.frame:FindFirstChildOfClass("UIStroke")
		local isQueued = streamerId and queuedSet[i]

		local oldEffectTag = slotData.frame:FindFirstChild("EffectTag")
		if oldEffectTag then oldEffectTag:Destroy() end

		if isQueued then
			slotData.iconLabel.Text = ""
			slotData.rarityLabel.Text = ""
			slotData.frame.BackgroundColor3 = EMPTY_SLOT_COLOR
			if stroke then
				stroke.Color = Color3.fromRGB(80, 75, 110); stroke.Thickness = 1.5
			end
		elseif streamerId then
			local info = Streamers.ById[streamerId]
			local rarityColor = DesignConfig.RarityColors[info and info.rarity or "Common"]
				or Color3.fromRGB(170, 170, 170)

			local effectInfo = effect and Effects.ByName[effect] or nil
			local displayColor = effectInfo and effectInfo.color or rarityColor

			local displayName = info and info.displayName or "?"

			slotData.iconLabel.Text = string.sub(displayName, 1, 6)
			slotData.iconLabel.TextColor3 = Color3.new(1, 1, 1)

			slotData.rarityLabel.Text = info and info.rarity:upper() or ""
			slotData.rarityLabel.TextColor3 = Color3.new(1, 1, 1)

			if effectInfo then
				local effectTag = Instance.new("TextLabel")
				effectTag.Name = "EffectTag"
				effectTag.Size = UDim2.new(1, -4, 0, 14)
				effectTag.Position = UDim2.new(0.5, 0, 0, 14)
				effectTag.AnchorPoint = Vector2.new(0.5, 0)
				effectTag.BackgroundTransparency = 1
				effectTag.Text = effectInfo.prefix:upper()
				effectTag.TextColor3 = effectInfo.color
				effectTag.Font = Enum.Font.FredokaOne
				effectTag.TextSize = 11
				effectTag.TextScaled = false
				effectTag.ZIndex = 4
				effectTag.Parent = slotData.frame

				local etStroke = Instance.new("UIStroke")
				etStroke.Color = Color3.fromRGB(0, 0, 0)
				etStroke.Thickness = 1.5
				etStroke.Parent = effectTag
			end

			local bgR = math.clamp(math.floor(rarityColor.R * 255 * 0.55 + 25), 0, 255)
			local bgG = math.clamp(math.floor(rarityColor.G * 255 * 0.55 + 20), 0, 255)
			local bgB = math.clamp(math.floor(rarityColor.B * 255 * 0.55 + 30), 0, 255)
			slotData.frame.BackgroundColor3 = Color3.fromRGB(bgR, bgG, bgB)

			if stroke then
				stroke.Color = rarityColor
				stroke.Thickness = i == selectedIndex and 3.5 or 2
			end
		else
			slotData.iconLabel.Text = ""
			slotData.rarityLabel.Text = ""
			slotData.frame.BackgroundColor3 = EMPTY_SLOT_COLOR
			if stroke then
				stroke.Color = Color3.fromRGB(80, 75, 110)
				stroke.Thickness = 1.5
			end
		end

		if stroke and i == selectedIndex then
			stroke.Color = Color3.fromRGB(255, 255, 100)
			stroke.Thickness = 3.5
		end
	end

	-- Update selected item label
	if selectedLabel then
		if selectedIndex and inventory[selectedIndex] then
			local item = inventory[selectedIndex]
			local streamerId = getItemId(item)
			local effect = getItemEffect(item)
			local info = Streamers.ById[streamerId]
			local displayName = info and info.displayName or (streamerId or "?")
			if effect then
				local effectInfo = Effects.ByName[effect]
				if effectInfo then displayName = effectInfo.prefix .. " " .. displayName end
			end
			selectedLabel.Text = "Selected: " .. displayName
			selectedLabel.Visible = true
		else
			selectedLabel.Text = ""
			selectedLabel.Visible = false
		end
	end
end

-------------------------------------------------
-- BUILD UI
-------------------------------------------------

function InventoryController.Init()
	screenGui = UIHelper.CreateScreenGui("InventoryGui", 6)
	screenGui.Parent = playerGui

	-- Bottom bar container
	barContainer = UIHelper.CreateRoundedFrame({
		Name = "InventoryBar",
		Size = UDim2.new(0, (VISIBLE_SLOTS * 60) + 80, 0, 72),
		Position = UDim2.new(0.5, 0, 1, -10),
		AnchorPoint = Vector2.new(0.5, 1),
		Color = DesignConfig.Colors.InventoryBg,
		CornerRadius = UDim.new(0, 12),
		StrokeColor = Color3.fromRGB(60, 60, 90),
		Parent = screenGui,
	})

	-- Padding
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = barContainer

	-- Slots container
	slotsFrame = Instance.new("Frame")
	slotsFrame.Name = "Slots"
	slotsFrame.Size = UDim2.new(1, -64, 1, 0)
	slotsFrame.Position = UDim2.new(0, 0, 0, 0)
	slotsFrame.BackgroundTransparency = 1
	slotsFrame.Parent = barContainer

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.Parent = slotsFrame

	-- Create slots
	for i = 1, VISIBLE_SLOTS do
		slots[i] = createSlot(slotsFrame, i)
	end

	-- Backpack button with real icon (right side)
	backpackButton = Instance.new("ImageButton")
	backpackButton.Name = "BackpackBtn"
	backpackButton.Size = UDim2.new(0, 52, 0, 52)
	backpackButton.Position = UDim2.new(1, -2, 0.5, 0)
	backpackButton.AnchorPoint = Vector2.new(1, 0.5)
	backpackButton.BackgroundColor3 = Color3.fromRGB(80, 70, 120)
	backpackButton.Image = "rbxassetid://12878997124"
	backpackButton.ScaleType = Enum.ScaleType.Fit
	backpackButton.BorderSizePixel = 0
	backpackButton.Parent = barContainer

	local bpCorner = Instance.new("UICorner")
	bpCorner.CornerRadius = UDim.new(0, 8)
	bpCorner.Parent = backpackButton

	local bpStroke = Instance.new("UIStroke")
	bpStroke.Color = Color3.fromRGB(120, 100, 200)
	bpStroke.Thickness = 1
	bpStroke.Parent = backpackButton

	-- Item count badge on backpack
	local countBadge = UIHelper.CreateRoundedFrame({
		Name = "CountBadge",
		Size = UDim2.new(0, 22, 0, 16),
		Position = UDim2.new(1, -2, 0, -2),
		AnchorPoint = Vector2.new(1, 0),
		Color = DesignConfig.Colors.Accent,
		CornerRadius = UDim.new(0, 6),
		Parent = backpackButton,
	})

	local countText = Instance.new("TextLabel")
	countText.Name = "Count"
	countText.Size = UDim2.new(1, 0, 1, 0)
	countText.BackgroundTransparency = 1
	countText.TextColor3 = Color3.new(0, 0, 0)
	countText.Font = DesignConfig.Fonts.Primary
	countText.TextScaled = true
	countText.Text = "0"
	countText.Parent = countBadge

	-- Selected item label (above the bar)
	selectedLabel = Instance.new("TextLabel")
	selectedLabel.Name = "SelectedLabel"
	selectedLabel.Size = UDim2.new(0, 300, 0, 24)
	selectedLabel.Position = UDim2.new(0.5, 0, 0, -4)
	selectedLabel.AnchorPoint = Vector2.new(0.5, 1)
	selectedLabel.BackgroundTransparency = 1
	selectedLabel.TextColor3 = DesignConfig.Colors.InventorySelected
	selectedLabel.Font = DesignConfig.Fonts.Primary
	selectedLabel.TextSize = 16
	selectedLabel.Text = ""
	selectedLabel.Visible = false
	selectedLabel.Parent = barContainer
end

-------------------------------------------------
-- SELECTION
-------------------------------------------------

function InventoryController.SelectSlot(slotIndex: number)
	-- Don't allow selecting items that are queued for sacrifice
	if not SacrificeController then
		local ok, mod = pcall(function() return require(script.Parent.SacrificeController) end)
		if ok then SacrificeController = mod end
	end
	local queuedSet = SacrificeController and SacrificeController.GetQueuedIndices and SacrificeController.GetQueuedIndices() or {}
	if queuedSet[slotIndex] then return end

	if selectedIndex == slotIndex then
		-- Deselect
		selectedIndex = nil
	else
		-- Select if there's an item
		if inventory[slotIndex] then
			selectedIndex = slotIndex
		else
			selectedIndex = nil
		end
	end

	updateSlotVisuals()

	-- Fire callbacks
	for _, cb in ipairs(onSelectionChanged) do
		task.spawn(cb, selectedIndex, selectedIndex and inventory[selectedIndex])
	end
end

function InventoryController.GetSelectedItem(): (number?, string?)
	if selectedIndex and inventory[selectedIndex] then
		return selectedIndex, getItemId(inventory[selectedIndex])
	end
	return nil, nil
end

function InventoryController.SelectByItem(streamerId: string, effect: string?): boolean
	if not streamerId then return false end
	local foundIndex = nil
	for i, item in ipairs(inventory) do
		if getItemId(item) == streamerId then
			if effect == nil or getItemEffect(item) == effect then
				foundIndex = i
				break
			end
		end
	end
	if not foundIndex then
		return false
	end

	selectedIndex = foundIndex
	updateSlotVisuals()
	for _, cb in ipairs(onSelectionChanged) do
		task.spawn(cb, selectedIndex, inventory[selectedIndex])
	end
	return true
end

function InventoryController.ClearSelection()
	selectedIndex = nil
	updateSlotVisuals()
	for _, cb in ipairs(onSelectionChanged) do
		task.spawn(cb, nil, nil)
	end
end

function InventoryController.OnSelectionChanged(callback)
	table.insert(onSelectionChanged, callback)
end

function InventoryController.RefreshVisuals()
	updateSlotVisuals()
end

-------------------------------------------------
-- DATA SYNC
-------------------------------------------------

function InventoryController.UpdateInventory(newInventory, newStorage)
	inventory = newInventory or {}

	-- Update backpack count (hotbar + storage total)
	local storageCount = newStorage and #newStorage or 0
	local totalCount = #inventory + storageCount
	local countBadge = backpackButton and backpackButton:FindFirstChild("CountBadge")
	if countBadge then
		local countText = countBadge:FindFirstChild("Count")
		if countText then
			countText.Text = tostring(totalCount)
		end
	end

	-- If selected index is now out of range or the item at that index changed, deselect and notify
	local wasSelected = selectedIndex
	if selectedIndex and (selectedIndex > #inventory or not inventory[selectedIndex]) then
		selectedIndex = nil
	end

	updateSlotVisuals()

	if wasSelected and not selectedIndex then
		for _, cb in ipairs(onSelectionChanged) do
			task.spawn(cb, nil, nil)
		end
	end
end

--- Called when a new item is added to inventory (for animation)
function InventoryController.FlashNewItem(streamerId: string)
	-- Find the slot with this item (usually the last one)
	for i = #inventory, 1, -1 do
		local itemId = getItemId(inventory[i])
		if itemId == streamerId and i <= VISIBLE_SLOTS then
			local slotData = slots[i]
			if slotData then
				-- Flash animation
				local effect = getItemEffect(inventory[i])
				local effectInfo = effect and Effects.ByName[effect] or nil
				local info = Streamers.ById[streamerId]
				local color = effectInfo and effectInfo.color
					or DesignConfig.RarityColors[info and info.rarity or "Common"]
					or Color3.fromRGB(170, 170, 170)

				TweenService:Create(slotData.frame, TweenInfo.new(0.15), {
					BackgroundColor3 = color,
				}):Play()
				task.delay(0.3, function()
					TweenService:Create(slotData.frame, TweenInfo.new(0.3), {
						BackgroundColor3 = DesignConfig.Colors.InventorySlot,
					}):Play()
				end)
			end
			break
		end
	end
end

-------------------------------------------------
-- EQUIP SELECTED ITEM TO PAD
-------------------------------------------------

function InventoryController.EquipSelectedToPad(padSlot: number)
	-- Base placement is disabled.
	-- Keep method for compatibility with existing callers.
	return false
end

--- Sell the selected item
function InventoryController.SellSelected(): boolean
	if not selectedIndex then return false end
	local item = inventory[selectedIndex]
	local streamerId = getItemId(item)
	if not streamerId then return false end

	SellRequest:FireServer(streamerId)
	selectedIndex = nil
	updateSlotVisuals()
	-- Notify listeners (drop held model, etc.)
	for _, cb in ipairs(onSelectionChanged) do
		task.spawn(cb, nil, nil)
	end
	return true
end

return InventoryController
