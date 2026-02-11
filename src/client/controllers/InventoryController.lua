--[[
	InventoryController.lua
	Bottom inventory bar showing the player's collected streamers.
	Displays numbered slots (1–9 visible, scrollable for more).
	Click a slot to select an item, then click a pad to equip it.
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
local EquipRequest = RemoteEvents:WaitForChild("EquipRequest")
local SellRequest = RemoteEvents:WaitForChild("SellRequest")

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

local function createSlot(parent, slotNumber)
	local slotSize = DesignConfig.Sizes.InventorySlotSize

	local frame = UIHelper.CreateRoundedFrame({
		Name = "Slot_" .. slotNumber,
		Size = slotSize,
		Color = DesignConfig.Colors.InventorySlot,
		CornerRadius = UDim.new(0, 8),
		StrokeColor = Color3.fromRGB(70, 70, 100),
		Parent = parent,
	})

	-- Slot number (top-left corner)
	local numberLabel = Instance.new("TextLabel")
	numberLabel.Name = "Number"
	numberLabel.Size = UDim2.new(0, 16, 0, 16)
	numberLabel.Position = UDim2.new(0, 2, 0, 2)
	numberLabel.BackgroundTransparency = 1
	numberLabel.TextColor3 = DesignConfig.Colors.TextMuted
	numberLabel.Font = DesignConfig.Fonts.Secondary
	numberLabel.TextSize = 12
	numberLabel.Text = tostring(slotNumber)
	numberLabel.TextXAlignment = Enum.TextXAlignment.Left
	numberLabel.TextYAlignment = Enum.TextYAlignment.Top
	numberLabel.Parent = frame

	-- Streamer initial (center)
	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.Size = UDim2.new(1, -4, 0.55, 0)
	iconLabel.Position = UDim2.new(0.5, 0, 0.2, 0)
	iconLabel.AnchorPoint = Vector2.new(0.5, 0)
	iconLabel.BackgroundTransparency = 1
	iconLabel.TextColor3 = DesignConfig.Colors.White
	iconLabel.Font = DesignConfig.Fonts.Primary
	iconLabel.TextScaled = true
	iconLabel.Text = ""
	iconLabel.Parent = frame

	-- Rarity text (bottom)
	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Name = "Rarity"
	rarityLabel.Size = UDim2.new(1, -4, 0.25, 0)
	rarityLabel.Position = UDim2.new(0.5, 0, 0.75, 0)
	rarityLabel.AnchorPoint = Vector2.new(0.5, 0)
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.TextColor3 = DesignConfig.Colors.TextSecondary
	rarityLabel.Font = DesignConfig.Fonts.Secondary
	rarityLabel.TextScaled = true
	rarityLabel.Text = ""
	rarityLabel.Parent = frame

	-- Click detection
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

	-- Hover effect
	local tweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	clickBtn.MouseEnter:Connect(function()
		if slotNumber ~= selectedIndex then
			TweenService:Create(frame, tweenInfo, {
				BackgroundColor3 = DesignConfig.Colors.ButtonHover,
			}):Play()
		end
	end)
	clickBtn.MouseLeave:Connect(function()
		if slotNumber ~= selectedIndex then
			TweenService:Create(frame, tweenInfo, {
				BackgroundColor3 = DesignConfig.Colors.InventorySlot,
			}):Play()
		end
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
	for i = 1, VISIBLE_SLOTS do
		local slotData = slots[i]
		if not slotData then continue end

		local item = inventory[i]
		local streamerId = getItemId(item)
		local effect = getItemEffect(item)
		local stroke = slotData.frame:FindFirstChildOfClass("UIStroke")

		-- Remove old effect tag if present
		local oldEffectTag = slotData.frame:FindFirstChild("EffectTag")
		if oldEffectTag then oldEffectTag:Destroy() end

		if streamerId then
			local info = Streamers.ById[streamerId]
			local rarityColor = DesignConfig.RarityColors[info and info.rarity or "Common"]
				or Color3.fromRGB(170, 170, 170)

			-- Effect: override display color with effect color
			local effectInfo = effect and Effects.ByName[effect] or nil
			local displayColor = effectInfo and effectInfo.color or rarityColor

			local displayName = info and info.displayName or "?"
			if effectInfo then
				displayName = effectInfo.prefix .. " " .. displayName
			end

			slotData.iconLabel.Text = string.sub(displayName, 1, 5)
			slotData.iconLabel.TextColor3 = displayColor
			slotData.rarityLabel.Text = info and info.rarity or ""
			slotData.rarityLabel.TextColor3 = displayColor

			-- Show small effect tag at top of slot
			if effectInfo then
				local effectTag = Instance.new("TextLabel")
				effectTag.Name = "EffectTag"
				effectTag.Size = UDim2.new(1, 0, 0, 12)
				effectTag.Position = UDim2.new(0, 0, 0, 1)
				effectTag.BackgroundTransparency = 1
				effectTag.Text = effectInfo.prefix:upper()
				effectTag.TextColor3 = effectInfo.color
				effectTag.Font = Enum.Font.GothamBold
				effectTag.TextSize = 10
				effectTag.TextScaled = false
				effectTag.Parent = slotData.frame
			end

			-- Tint the slot background slightly with display color
			if i == selectedIndex then
				slotData.frame.BackgroundColor3 = Color3.fromRGB(
					math.floor(displayColor.R * 255 * 0.3 + 50 * 0.7),
					math.floor(displayColor.G * 255 * 0.3 + 50 * 0.7),
					math.floor(displayColor.B * 255 * 0.3 + 70 * 0.7)
				)
			else
				slotData.frame.BackgroundColor3 = DesignConfig.Colors.InventorySlot
			end
		else
			slotData.iconLabel.Text = ""
			slotData.rarityLabel.Text = ""
			slotData.frame.BackgroundColor3 = DesignConfig.Colors.InventorySlot
		end

		-- Selection highlight
		if stroke then
			if i == selectedIndex then
				stroke.Color = DesignConfig.Colors.InventorySelected
				stroke.Thickness = 3
			else
				stroke.Color = Color3.fromRGB(70, 70, 100)
				stroke.Thickness = 1
			end
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
	bpStroke.Thickness = 2
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

function InventoryController.ClearSelection()
	selectedIndex = nil
	updateSlotVisuals()
end

function InventoryController.OnSelectionChanged(callback)
	table.insert(onSelectionChanged, callback)
end

-------------------------------------------------
-- DATA SYNC
-------------------------------------------------

function InventoryController.UpdateInventory(newInventory)
	inventory = newInventory or {}

	-- Update backpack count
	local countBadge = backpackButton and backpackButton:FindFirstChild("CountBadge")
	if countBadge then
		local countText = countBadge:FindFirstChild("Count")
		if countText then
			countText.Text = tostring(#inventory)
		end
	end

	-- If selected index is now out of range, deselect
	if selectedIndex and selectedIndex > #inventory then
		selectedIndex = nil
	end

	updateSlotVisuals()
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
	if not selectedIndex then return false end
	local item = inventory[selectedIndex]
	local streamerId = getItemId(item)
	if not streamerId then return false end

	-- Fire equip request (server matches by streamer id)
	EquipRequest:FireServer(streamerId, padSlot)
	selectedIndex = nil
	updateSlotVisuals()
	return true
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
	return true
end

return InventoryController
