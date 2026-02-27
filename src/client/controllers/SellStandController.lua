--[[
	SellStandController.lua
	Sell UI — dark-themed panel matching the Case Shop / Potion Shop style.
	3D streamer model previews with rotating viewports, sorted by sell price.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local Streamers = require(ReplicatedStorage.Shared.Config.Streamers)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Effects = require(ReplicatedStorage.Shared.Config.Effects)
local UIHelper = require(script.Parent.UIHelper)
local HUDController = require(script.Parent.HUDController)

local SellStandController = {}
local SacrificeController = nil

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local OpenSellStandGui = RemoteEvents:WaitForChild("OpenSellStandGui")
local SellByIndexRequest = RemoteEvents:WaitForChild("SellByIndexRequest")
local SellAllRequest = RemoteEvents:WaitForChild("SellAllRequest")
local SellResult = RemoteEvents:WaitForChild("SellResult")

local screenGui, overlay, modalFrame
local isOpen = false
local scrollFrame, sellAllBtn, totalLabel, countLabel, emptyLabel
local listLayoutRef
local hotbarTabBtn, storageTabBtn
local activeSection = "hotbar" -- "hotbar" | "storage"

local FONT = Enum.Font.FredokaOne
local FONT_SUB = Enum.Font.GothamBold
local MODAL_BG = Color3.fromRGB(30, 25, 45)
local RED = Color3.fromRGB(220, 55, 55)
local RED_DARK = Color3.fromRGB(160, 30, 30)
local GREEN = Color3.fromRGB(80, 220, 100)
local MODAL_W, MODAL_H = 480, 540

local bounceTween = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CASH_TOUCH_SOUND_ID = "rbxassetid://7112275565"
local CASH_SOUND_START_OFFSET = 0.28

local lastInventorySnapshot = ""
local STORAGE_OFFSET = 1000
local cachedCashTouchSound = nil

-------------------------------------------------
-- HELPERS
-------------------------------------------------

local function getItemId(item)
	if type(item) == "table" then return item.id end
	if type(item) == "string" then return item end
	return nil
end

local function getItemEffect(item)
	if type(item) == "table" then return item.effect end
	return nil
end

local function calcSellPrice(item)
	local streamerId = getItemId(item)
	local effect = getItemEffect(item)
	local info = Streamers.ById[streamerId]
	if not info then return 0 end
	local price = Economy.SellPrices[info.rarity] or Economy.SellPrices.Common
	if effect and effect ~= "" then
		price = price * (Economy.EffectSellMultiplier or 1.5)
	end
	return math.floor(price)
end

local function fmtNum(n)
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

local function formatOdds(odds)
	if not odds or odds < 1 then return "" end
	return "1/" .. fmtNum(odds)
end

local function buildInventorySnapshot(inventory, storage)
	local parts = {}
	for i, item in ipairs(inventory or {}) do
		local id = getItemId(item) or "?"
		local eff = getItemEffect(item) or ""
		parts[#parts + 1] = "i:" .. i .. ":" .. id .. ":" .. eff
	end
	for i, item in ipairs(storage or {}) do
		local id = getItemId(item) or "?"
		local eff = getItemEffect(item) or ""
		parts[#parts + 1] = "s:" .. i .. ":" .. id .. ":" .. eff
	end
	return table.concat(parts, "|")
end

local function addStroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.new(0, 0, 0)
	s.Thickness = thickness or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = parent
	return s
end

local function getCashTouchSound()
	if cachedCashTouchSound and cachedCashTouchSound.Parent then
		return cachedCashTouchSound
	end
	for _, child in ipairs(SoundService:GetChildren()) do
		if child:IsA("Sound") and child.SoundId == CASH_TOUCH_SOUND_ID then
			cachedCashTouchSound = child
			return child
		end
	end
	return nil
end

local function playSellCashSound()
	local sfx = getCashTouchSound()
	if sfx then
		local clone = sfx:Clone()
		clone.Parent = SoundService
		clone.TimePosition = CASH_SOUND_START_OFFSET
		SoundService:PlayLocalSound(clone)
		clone.Ended:Connect(function()
			if clone and clone.Parent then clone:Destroy() end
		end)
		task.delay(2, function()
			if clone and clone.Parent then clone:Destroy() end
		end)
	end
end

local function updateSectionButtons()
	if not hotbarTabBtn or not storageTabBtn then return end
	local hotbarActive = activeSection == "hotbar"
	hotbarTabBtn.BackgroundColor3 = hotbarActive and Color3.fromRGB(80, 210, 120) or Color3.fromRGB(55, 50, 80)
	hotbarTabBtn.TextColor3 = hotbarActive and Color3.new(1, 1, 1) or Color3.fromRGB(180, 180, 210)
	storageTabBtn.BackgroundColor3 = (not hotbarActive) and Color3.fromRGB(80, 210, 120) or Color3.fromRGB(55, 50, 80)
	storageTabBtn.TextColor3 = (not hotbarActive) and Color3.new(1, 1, 1) or Color3.fromRGB(180, 180, 210)
end

local function getSacrificeQueuedSet()
	-- Lazy-load SacrificeController to exclude queued items
	if not SacrificeController then
		local ok, mod = pcall(function() return require(script.Parent.SacrificeController) end)
		if ok then SacrificeController = mod end
	end
	return SacrificeController and SacrificeController.GetQueuedIndices and SacrificeController.GetQueuedIndices() or {}
end

-- BUILD ITEM CARD
-------------------------------------------------

local function buildItemCard(item, originalIndex, source, parent)
	local streamerId = getItemId(item)
	local effect = getItemEffect(item)
	local info = Streamers.ById[streamerId]
	if not info then return nil, 0 end

	local effectInfo = effect and Effects.ByName[effect] or nil
	local sellPrice = calcSellPrice(item)
	local rarityInfo = Rarities.ByName[info.rarity]
	local rarityColor = rarityInfo and rarityInfo.color or Color3.fromRGB(170, 170, 170)
	local displayColor = effectInfo and effectInfo.color or rarityColor
	local displayName = info.displayName
	if effectInfo then displayName = effectInfo.prefix .. " " .. displayName end

	local cardHeight = effectInfo and 130 or 110
	local card = Instance.new("Frame")
	card.Name = "Card_" .. originalIndex
	card.Size = UDim2.new(1, -12, 0, cardHeight)
	card.BackgroundColor3 = Color3.fromRGB(40, 35, 60)
	card.BorderSizePixel = 0
	card.Parent = parent
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = displayColor
	cardStroke.Thickness = 1.5
	cardStroke.Transparency = 0.5
	cardStroke.Parent = card

	-- Lightweight preview badge (replaces expensive 3D viewport)
	local previewSize = 72
	local preview = Instance.new("Frame")
	preview.Name = "PreviewBadge"
	preview.Size = UDim2.new(0, previewSize, 0, previewSize)
	preview.Position = UDim2.new(0, 10, 0.5, 0)
	preview.AnchorPoint = Vector2.new(0, 0.5)
	preview.BackgroundColor3 = Color3.fromRGB(25, 22, 42)
	preview.BackgroundTransparency = 0.15
	preview.BorderSizePixel = 0
	preview.Parent = card
	Instance.new("UICorner", preview).CornerRadius = UDim.new(0, 10)
	local pStroke = Instance.new("UIStroke")
	pStroke.Color = displayColor
	pStroke.Thickness = 1.5
	pStroke.Transparency = 0.35
	pStroke.Parent = preview

	local previewText = Instance.new("TextLabel")
	previewText.Size = UDim2.new(1, -8, 1, -8)
	previewText.Position = UDim2.new(0.5, 0, 0.5, 0)
	previewText.AnchorPoint = Vector2.new(0.5, 0.5)
	previewText.BackgroundTransparency = 1
	previewText.Text = string.upper(string.sub(displayName, 1, 2))
	previewText.TextColor3 = displayColor
	previewText.Font = FONT
	previewText.TextSize = 28
	previewText.Parent = preview
	addStroke(previewText, Color3.new(0, 0, 0), 1.2)

	-- Info area (middle)
	local textX = previewSize + 18

	-- Effect badge
	if effectInfo then
		local badge = Instance.new("Frame")
		badge.Size = UDim2.new(0, 70, 0, 20)
		badge.Position = UDim2.new(0, textX, 0, 8)
		badge.BackgroundColor3 = effectInfo.color
		badge.BackgroundTransparency = 0.6
		badge.BorderSizePixel = 0
		badge.Parent = card
		Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 5)
		local bLabel = Instance.new("TextLabel")
		bLabel.Size = UDim2.new(1, 0, 1, 0)
		bLabel.BackgroundTransparency = 1
		bLabel.Text = effectInfo.prefix:upper()
		bLabel.TextColor3 = effectInfo.color
		bLabel.Font = FONT_SUB
		bLabel.TextSize = 10
		bLabel.Parent = badge
		addStroke(bLabel, Color3.new(0, 0, 0), 0.8)
	end

	-- Name
	local nameY = effectInfo and 26 or 12
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(0, 240, 0, 28)
	nameLabel.Position = UDim2.new(0, textX, 0, nameY)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = displayName
	nameLabel.TextColor3 = displayColor
	nameLabel.Font = FONT
	nameLabel.TextSize = 20
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = card
	addStroke(nameLabel, Color3.new(0, 0, 0), 1)

	-- Rarity + odds
	local baseOdds = info.odds or 0
	local effectOdds = baseOdds
	if effectInfo then effectOdds = math.floor(baseOdds * effectInfo.rarityMult) end
	local oddsStr = formatOdds(effectOdds)

	local rarLine = Instance.new("TextLabel")
	rarLine.Size = UDim2.new(0, 240, 0, 18)
	rarLine.Position = UDim2.new(0, textX, 0, nameY + 28)
	rarLine.BackgroundTransparency = 1
	rarLine.Text = info.rarity .. (oddsStr ~= "" and ("  •  " .. oddsStr) or "")
	rarLine.TextColor3 = Color3.fromRGB(140, 135, 160)
	rarLine.Font = FONT_SUB
	rarLine.TextSize = 14
	rarLine.TextXAlignment = Enum.TextXAlignment.Left
	rarLine.Parent = card

	-- $/sec
	local cashLine = Instance.new("TextLabel")
	cashLine.Size = UDim2.new(0, 240, 0, 18)
	cashLine.Position = UDim2.new(0, textX, 0, nameY + 48)
	cashLine.BackgroundTransparency = 1
	cashLine.Text = "$" .. fmtNum(sellPrice)
	cashLine.TextColor3 = Color3.fromRGB(100, 255, 120)
	cashLine.Font = FONT_SUB
	cashLine.TextSize = 14
	cashLine.TextXAlignment = Enum.TextXAlignment.Left
	cashLine.Parent = card

	-- Sell button (right side)
	local sellBtn = Instance.new("TextButton")
	sellBtn.Name = "SellBtn"
	sellBtn.Size = UDim2.new(0, 80, 0, 44)
	sellBtn.Position = UDim2.new(1, -14, 0.5, 0)
	sellBtn.AnchorPoint = Vector2.new(1, 0.5)
	sellBtn.BackgroundColor3 = RED
	sellBtn.Text = ""
	sellBtn.BorderSizePixel = 0
	sellBtn.AutoButtonColor = false
	sellBtn.Parent = card
	Instance.new("UICorner", sellBtn).CornerRadius = UDim.new(0, 10)
	local sbStroke = Instance.new("UIStroke")
	sbStroke.Color = RED_DARK
	sbStroke.Thickness = 1.5
	sbStroke.Parent = sellBtn

	local sellText = Instance.new("TextLabel")
	sellText.Size = UDim2.new(1, 0, 1, 0)
	sellText.BackgroundTransparency = 1
	sellText.Text = "SELL"
	sellText.TextColor3 = Color3.new(1, 1, 1)
	sellText.Font = FONT
	sellText.TextSize = 18
	sellText.Parent = sellBtn
	addStroke(sellText, Color3.new(0, 0, 0), 1)

	sellBtn.MouseEnter:Connect(function()
		TweenService:Create(sellBtn, bounceTween, {
			Size = UDim2.new(0, 86, 0, 48),
			BackgroundColor3 = Color3.fromRGB(255, 75, 75),
		}):Play()
	end)
	sellBtn.MouseLeave:Connect(function()
		TweenService:Create(sellBtn, bounceTween, {
			Size = UDim2.new(0, 80, 0, 44),
			BackgroundColor3 = RED,
		}):Play()
	end)
	sellBtn.MouseButton1Click:Connect(function()
		local queuedSet = getSacrificeQueuedSet()
		local virtualIndex = source == "storage" and (STORAGE_OFFSET + originalIndex) or originalIndex
		if queuedSet[virtualIndex] then
			return
		end
		SellByIndexRequest:FireServer(originalIndex, source, queuedSet)
	end)

	return card, sellPrice
end

-------------------------------------------------
-- BUILD INVENTORY LIST
-------------------------------------------------

local function clearScrollFrame()
	if not scrollFrame then return end
	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
end

local function clampSellScrollBounds()
	if not scrollFrame or not listLayoutRef then return end
	local contentH = listLayoutRef.AbsoluteContentSize.Y + 6
	local viewH = scrollFrame.AbsoluteSize.Y
	local canvasH = math.max(contentH, viewH)
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, canvasH)
	local maxY = math.max(0, contentH - viewH)
	local y = math.clamp(scrollFrame.CanvasPosition.Y, 0, maxY)
	if y ~= scrollFrame.CanvasPosition.Y then
		scrollFrame.CanvasPosition = Vector2.new(scrollFrame.CanvasPosition.X, y)
	end
end

local function buildInventoryList(force)
	if not scrollFrame then return end
	local inventory = HUDController.Data.inventory or {}
	local storage = HUDController.Data.storage or {}
	local snapshot = activeSection .. "|" .. buildInventorySnapshot(inventory, storage)
	if not force and snapshot == lastInventorySnapshot then return end
	lastInventorySnapshot = snapshot

	clearScrollFrame()
	local totalValue = 0

	local visibleCount = activeSection == "hotbar" and #inventory or #storage
	if visibleCount == 0 then
		if emptyLabel then emptyLabel.Visible = true end
		if sellAllBtn then
			sellAllBtn.Visible = (#inventory + #storage) > 0
		end
		if totalLabel then totalLabel.Text = "Total: $0" end
		if countLabel then countLabel.Text = "0 streamers" end
		if emptyLabel then
			if activeSection == "hotbar" then
				emptyLabel.Text = "Your hotbar is empty!"
			else
				emptyLabel.Text = "Your storage is empty!"
			end
		end
		return
	end

	if emptyLabel then emptyLabel.Visible = false end

	local queuedSet = getSacrificeQueuedSet()

	local sortedEntries = {}
	if activeSection == "hotbar" then
		for i = 1, #inventory do
			if not queuedSet[i] then
				table.insert(sortedEntries, {
					item = inventory[i],
					index = i,
					source = "inventory",
				})
			end
		end
	else
		for i = 1, #storage do
			local vi = STORAGE_OFFSET + i
			if not queuedSet[vi] then
				table.insert(sortedEntries, {
					item = storage[i],
					index = i,
					source = "storage",
				})
			end
		end
	end
	table.sort(sortedEntries, function(a, b)
		return calcSellPrice(a.item) > calcSellPrice(b.item)
	end)

	for _, entry in ipairs(sortedEntries) do
		local _, price = buildItemCard(entry.item, entry.index, entry.source, scrollFrame)
		totalValue = totalValue + (price or 0)
	end

	-- Spacer so the last card can scroll above the fixed SELL ALL button.
	local bottomSpacer = Instance.new("Frame")
	bottomSpacer.Name = "BottomSpacer"
	bottomSpacer.Size = UDim2.new(1, -12, 0, 72)
	bottomSpacer.BackgroundTransparency = 1
	bottomSpacer.BorderSizePixel = 0
	bottomSpacer.Parent = scrollFrame

	if totalLabel then totalLabel.Text = "Total: $" .. fmtNum(totalValue) end
	if countLabel then
		local totalCount = #sortedEntries
		countLabel.Text = totalCount .. " streamer" .. (totalCount ~= 1 and "s" or "")
	end
	if sellAllBtn then
		sellAllBtn.Visible = #sortedEntries > 0
	end

	local listLayout = scrollFrame:FindFirstChildOfClass("UIListLayout")
	if listLayout then
		clampSellScrollBounds()
	end
end

-------------------------------------------------
-- OPEN / CLOSE
-------------------------------------------------

function SellStandController.Open()
	if isOpen then return end
	isOpen = true
	activeSection = "hotbar"
	lastInventorySnapshot = ""
	updateSectionButtons()
	if modalFrame then
		overlay.Visible = true
		modalFrame.Visible = true
		buildInventoryList(true)
		UIHelper.ScaleIn(modalFrame, 0.25)
	end
end

function SellStandController.IsOpen()
	return isOpen
end

function SellStandController.Close()
	if not isOpen then return end
	isOpen = false
	lastInventorySnapshot = ""
	if overlay then overlay.Visible = false end
	if modalFrame then UIHelper.ScaleOut(modalFrame, 0.2) end
end

-------------------------------------------------
-- INIT
-------------------------------------------------

function SellStandController.Init()
	screenGui = UIHelper.CreateScreenGui("SellStandGui", 8)
	screenGui.Parent = playerGui

	-- Dim overlay
	overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.45
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.ZIndex = 1
	overlay.Parent = screenGui

	-- Modal
	modalFrame = Instance.new("Frame")
	modalFrame.Name = "SellModal"
	modalFrame.Size = UDim2.new(0, MODAL_W, 0, MODAL_H)
	modalFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	modalFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	modalFrame.BackgroundColor3 = MODAL_BG
	modalFrame.BorderSizePixel = 0
	modalFrame.Visible = false
	modalFrame.ZIndex = 2
	modalFrame.ClipsDescendants = true
	modalFrame.Parent = screenGui

	Instance.new("UICorner", modalFrame).CornerRadius = UDim.new(0, 20)
	local mStroke = Instance.new("UIStroke")
	mStroke.Color = Color3.fromRGB(70, 60, 100)
	mStroke.Thickness = 1.5
	mStroke.Transparency = 0.3
	mStroke.Parent = modalFrame
	UIHelper.CreateShadow(modalFrame)
	UIHelper.MakeResponsiveModal(modalFrame, MODAL_W, MODAL_H)

	-- ===== HEADER =====
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 60)
	header.BackgroundTransparency = 1
	header.ZIndex = 3
	header.Parent = modalFrame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0.6, 0, 0, 32)
	title.Position = UDim2.new(0, 20, 0, 12)
	title.BackgroundTransparency = 1
	title.Text = "Sell Stand"
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Font = FONT
	title.TextSize = 28
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 3
	title.Parent = header
	addStroke(title, Color3.new(0, 0, 0), 1.5)

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 40, 0, 40)
	closeBtn.Position = UDim2.new(1, -14, 0, 10)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = RED
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = FONT
	closeBtn.TextSize = 20
	closeBtn.BorderSizePixel = 0
	closeBtn.AutoButtonColor = false
	closeBtn.ZIndex = 5
	closeBtn.Parent = modalFrame
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1, 0)
	local cStroke = Instance.new("UIStroke")
	cStroke.Color = RED_DARK
	cStroke.Thickness = 1.5
	cStroke.Parent = closeBtn
	addStroke(closeBtn, Color3.fromRGB(80, 0, 0), 1)

	closeBtn.MouseEnter:Connect(function()
		TweenService:Create(closeBtn, bounceTween, { Size = UDim2.new(0, 46, 0, 46), BackgroundColor3 = Color3.fromRGB(255, 75, 75) }):Play()
	end)
	closeBtn.MouseLeave:Connect(function()
		TweenService:Create(closeBtn, bounceTween, { Size = UDim2.new(0, 40, 0, 40), BackgroundColor3 = RED }):Play()
	end)
	closeBtn.MouseButton1Click:Connect(function() SellStandController.Close() end)

	-- Divider
	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(1, -30, 0, 1)
	divider.Position = UDim2.new(0.5, 0, 0, 62)
	divider.AnchorPoint = Vector2.new(0.5, 0)
	divider.BackgroundColor3 = Color3.fromRGB(60, 55, 80)
	divider.BorderSizePixel = 0
	divider.ZIndex = 3
	divider.Parent = modalFrame

	-- ===== INFO ROW =====
	local infoRow = Instance.new("Frame")
	infoRow.Size = UDim2.new(1, -30, 0, 24)
	infoRow.Position = UDim2.new(0.5, 0, 0, 102)
	infoRow.AnchorPoint = Vector2.new(0.5, 0)
	infoRow.BackgroundTransparency = 1
	infoRow.ZIndex = 3
	infoRow.Parent = modalFrame

	totalLabel = Instance.new("TextLabel")
	totalLabel.Size = UDim2.new(0.6, 0, 1, 0)
	totalLabel.BackgroundTransparency = 1
	totalLabel.Text = "Total: $0"
	totalLabel.TextColor3 = GREEN
	totalLabel.Font = FONT
	totalLabel.TextSize = 16
	totalLabel.TextXAlignment = Enum.TextXAlignment.Left
	totalLabel.ZIndex = 3
	totalLabel.Parent = infoRow
	addStroke(totalLabel, Color3.new(0, 0, 0), 1)

	countLabel = nil

	-- ===== SECTION TABS =====
	hotbarTabBtn = Instance.new("TextButton")
	hotbarTabBtn.Name = "HotbarTabBtn"
	hotbarTabBtn.Size = UDim2.new(0, 120, 0, 30)
	hotbarTabBtn.Position = UDim2.new(0, 20, 0, 70)
	hotbarTabBtn.BackgroundColor3 = Color3.fromRGB(80, 210, 120)
	hotbarTabBtn.Text = "Hotbar"
	hotbarTabBtn.TextColor3 = Color3.new(1, 1, 1)
	hotbarTabBtn.Font = FONT
	hotbarTabBtn.TextSize = 16
	hotbarTabBtn.BorderSizePixel = 0
	hotbarTabBtn.ZIndex = 4
	hotbarTabBtn.Parent = modalFrame
	Instance.new("UICorner", hotbarTabBtn).CornerRadius = UDim.new(0, 8)

	storageTabBtn = Instance.new("TextButton")
	storageTabBtn.Name = "StorageTabBtn"
	storageTabBtn.Size = UDim2.new(0, 120, 0, 30)
	storageTabBtn.Position = UDim2.new(0, 146, 0, 70)
	storageTabBtn.BackgroundColor3 = Color3.fromRGB(55, 50, 80)
	storageTabBtn.Text = "Storage"
	storageTabBtn.TextColor3 = Color3.fromRGB(180, 180, 210)
	storageTabBtn.Font = FONT
	storageTabBtn.TextSize = 16
	storageTabBtn.BorderSizePixel = 0
	storageTabBtn.ZIndex = 4
	storageTabBtn.Parent = modalFrame
	Instance.new("UICorner", storageTabBtn).CornerRadius = UDim.new(0, 8)

	hotbarTabBtn.MouseButton1Click:Connect(function()
		if activeSection == "hotbar" then return end
		activeSection = "hotbar"
		updateSectionButtons()
		lastInventorySnapshot = ""
		buildInventoryList(true)
	end)
	storageTabBtn.MouseButton1Click:Connect(function()
		if activeSection == "storage" then return end
		activeSection = "storage"
		updateSectionButtons()
		lastInventorySnapshot = ""
		buildInventoryList(true)
	end)

	-- ===== SCROLL LIST =====
	scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ItemList"
	scrollFrame.Size = UDim2.new(1, -20, 1, -220)
	scrollFrame.Position = UDim2.new(0.5, 0, 0, 134)
	scrollFrame.AnchorPoint = Vector2.new(0.5, 0)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 5
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 80, 150)
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.None
	scrollFrame.ScrollingDirection = Enum.ScrollingDirection.Y
	scrollFrame.ElasticBehavior = Enum.ElasticBehavior.Never
	scrollFrame.ZIndex = 3
	scrollFrame.Parent = modalFrame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = scrollFrame
	listLayoutRef = layout

	-- Keep scroll bounds clamped at all times (mouse wheel momentum, resize, etc.).
	scrollFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(clampSellScrollBounds)
	scrollFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(clampSellScrollBounds)
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(clampSellScrollBounds)

	local scrollPad = Instance.new("UIPadding")
	scrollPad.PaddingTop = UDim.new(0, 6)
	scrollPad.Parent = scrollFrame

	-- Empty state
	emptyLabel = Instance.new("TextLabel")
	emptyLabel.Size = UDim2.new(1, -20, 0, 80)
	emptyLabel.Position = UDim2.new(0.5, 0, 0.3, 0)
	emptyLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.Text = "Your hotbar is empty!"
	emptyLabel.TextColor3 = Color3.fromRGB(120, 115, 140)
	emptyLabel.Font = FONT
	emptyLabel.TextSize = 16
	emptyLabel.TextWrapped = true
	emptyLabel.Visible = false
	emptyLabel.ZIndex = 3
	emptyLabel.Parent = modalFrame

	-- ===== SELL ALL BUTTON =====
	sellAllBtn = Instance.new("TextButton")
	sellAllBtn.Name = "SellAllBtn"
	sellAllBtn.Size = UDim2.new(1, -30, 0, 46)
	sellAllBtn.Position = UDim2.new(0.5, 0, 1, -12)
	sellAllBtn.AnchorPoint = Vector2.new(0.5, 1)
	sellAllBtn.BackgroundColor3 = RED
	sellAllBtn.Text = ""
	sellAllBtn.BorderSizePixel = 0
	sellAllBtn.AutoButtonColor = false
	sellAllBtn.Visible = false
	sellAllBtn.ZIndex = 5
	sellAllBtn.Parent = modalFrame
	Instance.new("UICorner", sellAllBtn).CornerRadius = UDim.new(0, 12)
	local saStroke = Instance.new("UIStroke")
	saStroke.Color = RED_DARK
	saStroke.Thickness = 1.5
	saStroke.Parent = sellAllBtn
	local saGrad = Instance.new("UIGradient")
	saGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(240, 70, 70)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 30, 30)),
	})
	saGrad.Rotation = 90
	saGrad.Parent = sellAllBtn

	local sellAllText = Instance.new("TextLabel")
	sellAllText.Size = UDim2.new(1, 0, 1, 0)
	sellAllText.BackgroundTransparency = 1
	sellAllText.Text = "SELL ALL"
	sellAllText.TextColor3 = Color3.new(1, 1, 1)
	sellAllText.Font = FONT
	sellAllText.TextSize = 20
	sellAllText.ZIndex = 6
	sellAllText.Parent = sellAllBtn
	addStroke(sellAllText, Color3.new(0, 0, 0), 1.5)

	local saIdle = UDim2.new(1, -30, 0, 46)
	local saHover = UDim2.new(1, -24, 0, 50)
	sellAllBtn.MouseEnter:Connect(function()
		TweenService:Create(sellAllBtn, bounceTween, { Size = saHover, BackgroundColor3 = Color3.fromRGB(255, 75, 75) }):Play()
	end)
	sellAllBtn.MouseLeave:Connect(function()
		TweenService:Create(sellAllBtn, bounceTween, { Size = saIdle, BackgroundColor3 = RED }):Play()
	end)
	sellAllBtn.MouseButton1Click:Connect(function()
		local source = activeSection == "storage" and "storage" or "hotbar"
		local queuedSet = getSacrificeQueuedSet()
		SellAllRequest:FireServer(source, queuedSet)
	end)

	-------------------------------------------------
	-- EVENTS
	-------------------------------------------------

	HUDController.OnDataUpdated(function()
		if isOpen then buildInventoryList(false) end
	end)

	SellResult.OnClientEvent:Connect(function(data)
		if data.success and isOpen then
			playSellCashSound()
			task.wait(0.1)
			lastInventorySnapshot = ""
			buildInventoryList(true)
		end
	end)

	OpenSellStandGui.OnClientEvent:Connect(function()
		local TutorialController = require(script.Parent.TutorialController)
		if TutorialController.IsActive() then return end
		if isOpen then
			SellStandController.Close()
		else
			SellStandController.Open()
		end
	end)

	modalFrame.Visible = false
end

function SellStandController.RefreshList()
	if isOpen then
		lastInventorySnapshot = ""
		buildInventoryList(true)
	end
end

return SellStandController
