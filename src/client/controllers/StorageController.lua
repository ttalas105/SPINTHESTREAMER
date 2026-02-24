--[[
	StorageController.lua
	Storage UI — modal panel showing overflow streamers (max 200).
	Players can click a storage item to "pick it up", then click a
	hotbar slot to swap them. Sort by rarity or cash earned.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")

local Streamers    = require(ReplicatedStorage.Shared.Config.Streamers)
local Effects      = require(ReplicatedStorage.Shared.Config.Effects)
local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local UIHelper     = require(script.Parent.UIHelper)
local HUDController = require(script.Parent.HUDController)

local StorageController = {}

-- Lazy-loaded SacrificeController for checking queued indices
local SacrificeController = nil

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RemoteEvents   = ReplicatedStorage:WaitForChild("RemoteEvents")
local StorageAction  = RemoteEvents:WaitForChild("StorageAction")
local StorageResult  = RemoteEvents:WaitForChild("StorageResult")

local screenGui, modalFrame
local gridFrame, headerLabel
local isOpen = false
local sortMode = "rarity"
local selectedStorageIdx = nil

local FONT   = Enum.Font.FredokaOne
local FONT2  = Enum.Font.GothamBold
local BG     = Color3.fromRGB(14, 12, 28)
local ACCENT = Color3.fromRGB(255, 165, 50)
local STORAGE_MAX = 200

local RARITY_ORDER = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5 }

-------------------------------------------------
-- HELPERS
-------------------------------------------------

local function getItemInfo(item)
	local id = type(item) == "table" and item.id or item
	local effect = type(item) == "table" and item.effect or nil
	local info = Streamers.ById[id]
	return id, effect, info
end

local function getCashValue(item)
	local id, effect, info = getItemInfo(item)
	if not info then return 0 end
	local base = info.cashPerSecond or 0
	if effect then
		local ei = Effects.ByName[effect]
		if ei and ei.cashMultiplier then base = base * ei.cashMultiplier end
	end
	return base
end

local function formatNumber(n)
	if n >= 1e6 then return string.format("%.1fM", n / 1e6)
	elseif n >= 1e3 then return string.format("%.1fK", n / 1e3)
	else return tostring(n) end
end

-------------------------------------------------
-- BUILD GRID
-------------------------------------------------

local function clearGrid()
	if gridFrame then
		for _, c in ipairs(gridFrame:GetChildren()) do
			if not c:IsA("UIGridLayout") and not c:IsA("UIPadding") then
				c:Destroy()
			end
		end
	end
end

local STORAGE_OFFSET = 1000

local function buildGrid()
	if not gridFrame then return end
	clearGrid()

	-- Lazy-load SacrificeController
	if not SacrificeController then
		local ok, mod = pcall(function() return require(script.Parent.SacrificeController) end)
		if ok then SacrificeController = mod end
	end
	local queuedSet = SacrificeController and SacrificeController.GetQueuedIndices and SacrificeController.GetQueuedIndices() or {}

	local storage = HUDController.Data.storage or {}

	-- Update header
	if headerLabel then
		headerLabel.Text = "Storage (" .. #storage .. "/" .. STORAGE_MAX .. ")"
	end

	if #storage == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, 0, 0, 60)
		empty.BackgroundTransparency = 1
		empty.Text = "Storage is empty! Spin more to fill it up."
		empty.TextColor3 = Color3.fromRGB(120, 120, 150)
		empty.Font = FONT2; empty.TextSize = 16; empty.TextWrapped = true
		empty.Parent = gridFrame
		return
	end

	-- Build sorted index list
	local indices = {}
	for i = 1, #storage do table.insert(indices, i) end

	if sortMode == "rarity" then
		table.sort(indices, function(a, b)
			local _, ea, ia = getItemInfo(storage[a])
			local _, eb, ib = getItemInfo(storage[b])
			local ra = (ia and RARITY_ORDER[ia.rarity] or 0)
			local rb = (ib and RARITY_ORDER[ib.rarity] or 0)
			if ra ~= rb then return ra > rb end
			local hasEffA = ea and 1 or 0
			local hasEffB = eb and 1 or 0
			if hasEffA ~= hasEffB then return hasEffA > hasEffB end
			return a < b
		end)
	elseif sortMode == "cash" then
		table.sort(indices, function(a, b)
			local ca = getCashValue(storage[a])
			local cb = getCashValue(storage[b])
			if ca ~= cb then return ca > cb end
			return a < b
		end)
	end

	for _, si in ipairs(indices) do
		local item = storage[si]
		local id, effect, info = getItemInfo(item)
		if not info then continue end

		-- Completely hide items queued for sacrifice
		local virtualIdx = STORAGE_OFFSET + si
		if queuedSet[virtualIdx] then continue end

		local effectInfo = effect and Effects.ByName[effect] or nil
		local rarityColor = DesignConfig.RarityColors[info.rarity] or Color3.fromRGB(170, 170, 170)
		local displayColor = effectInfo and effectInfo.color or rarityColor
		local displayName = info.displayName or id
		if effectInfo then displayName = effectInfo.prefix .. " " .. displayName end

		local card = Instance.new("TextButton")
		card.Name = "Storage_" .. si
		card.Size = UDim2.new(0, 90, 0, 100)
		if si == selectedStorageIdx then
			card.BackgroundColor3 = Color3.fromRGB(60, 60, 100)
		else
			card.BackgroundColor3 = Color3.fromRGB(24, 22, 42)
		end
		card.BorderSizePixel = 0; card.Text = ""; card.AutoButtonColor = false
		card.Parent = gridFrame
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)
		local stroke = Instance.new("UIStroke", card)
		if si == selectedStorageIdx then
			stroke.Color = Color3.fromRGB(255, 220, 80); stroke.Thickness = 3
		else
			stroke.Color = displayColor; stroke.Thickness = 1
		end

		-- Rarity bar at top
		local topBar = Instance.new("Frame")
		topBar.Size = UDim2.new(1, 0, 0, 4)
		topBar.BackgroundColor3 = displayColor; topBar.BorderSizePixel = 0
		topBar.Parent = card
		Instance.new("UICorner", topBar).CornerRadius = UDim.new(0, 2)

		-- Effect badge
		if effectInfo then
			local badge = Instance.new("TextLabel")
			badge.Size = UDim2.new(1, 0, 0, 12)
			badge.Position = UDim2.new(0, 0, 0, 6)
			badge.BackgroundTransparency = 1
			badge.Text = effectInfo.prefix:upper()
			badge.TextColor3 = effectInfo.color
			badge.Font = Enum.Font.GothamBold; badge.TextSize = 9
			badge.Parent = card
		end

		-- Name
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -6, 0, 32)
		nameLabel.Position = UDim2.new(0.5, 0, 0, effectInfo and 20 or 10)
		nameLabel.AnchorPoint = Vector2.new(0.5, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = displayName
		nameLabel.TextColor3 = displayColor
		nameLabel.Font = FONT; nameLabel.TextSize = 12; nameLabel.TextWrapped = true
		nameLabel.Parent = card

		-- Rarity
		local rarLabel = Instance.new("TextLabel")
		rarLabel.Size = UDim2.new(1, 0, 0, 14)
		rarLabel.Position = UDim2.new(0.5, 0, 1, -30)
		rarLabel.AnchorPoint = Vector2.new(0.5, 0)
		rarLabel.BackgroundTransparency = 1
		rarLabel.Text = info.rarity
		rarLabel.TextColor3 = rarityColor
		rarLabel.Font = FONT2; rarLabel.TextSize = 10
		rarLabel.Parent = card

		-- Cash
		local cashLabel = Instance.new("TextLabel")
		cashLabel.Size = UDim2.new(1, 0, 0, 14)
		cashLabel.Position = UDim2.new(0.5, 0, 1, -16)
		cashLabel.AnchorPoint = Vector2.new(0.5, 0)
		cashLabel.BackgroundTransparency = 1
		cashLabel.Text = "$" .. formatNumber(getCashValue(item)) .. "/s"
		cashLabel.TextColor3 = Color3.fromRGB(130, 200, 130)
		cashLabel.Font = FONT2; cashLabel.TextSize = 9
		cashLabel.Parent = card

		-- Click to select/deselect
		local capSI = si
		card.MouseButton1Click:Connect(function()
			if selectedStorageIdx == capSI then
				selectedStorageIdx = nil
			else
				selectedStorageIdx = capSI
			end
			buildGrid()
		end)
	end
end

-------------------------------------------------
-- BUILD HOTBAR PREVIEW (for drop targets)
-------------------------------------------------

local hotbarPreviewFrame = nil

local function buildHotbarPreview()
	if hotbarPreviewFrame then
		for _, c in ipairs(hotbarPreviewFrame:GetChildren()) do
			if not c:IsA("UIListLayout") then c:Destroy() end
		end
	end
	if not hotbarPreviewFrame then return end

	local inv = HUDController.Data.inventory or {}
	local HOTBAR_MAX = 9

	for i = 1, HOTBAR_MAX do
		local item = inv[i]
		local id, effect, info = nil, nil, nil
		if item then id, effect, info = getItemInfo(item) end
		local effectInfo = effect and Effects.ByName[effect] or nil
		local rarityColor = info and DesignConfig.RarityColors[info.rarity] or Color3.fromRGB(60, 60, 80)
		local displayColor = effectInfo and effectInfo.color or rarityColor

		local slot = Instance.new("TextButton")
		slot.Name = "HotbarSlot_" .. i
		slot.Size = UDim2.new(0, 72, 0, 72)
		slot.BackgroundColor3 = item and Color3.fromRGB(24, 22, 42) or Color3.fromRGB(18, 16, 34)
		slot.BorderSizePixel = 0; slot.Text = ""; slot.AutoButtonColor = false
		slot.Parent = hotbarPreviewFrame
		Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 8)
		local sStroke = Instance.new("UIStroke", slot)
		sStroke.Color = item and displayColor or Color3.fromRGB(50, 50, 70)
		sStroke.Thickness = 1

		-- Slot number
		local numLabel = Instance.new("TextLabel")
		numLabel.Size = UDim2.new(0, 16, 0, 14)
		numLabel.Position = UDim2.new(0, 2, 0, 2)
		numLabel.BackgroundTransparency = 1
		numLabel.Text = tostring(i)
		numLabel.TextColor3 = Color3.fromRGB(80, 80, 100)
		numLabel.Font = FONT2; numLabel.TextSize = 10
		numLabel.TextXAlignment = Enum.TextXAlignment.Left
		numLabel.Parent = slot

		if item and info then
			local displayName = info.displayName or id
			if effectInfo then displayName = effectInfo.prefix .. " " .. displayName end

			if effectInfo then
				local eb = Instance.new("TextLabel")
				eb.Size = UDim2.new(1, 0, 0, 10)
				eb.Position = UDim2.new(0, 0, 0, 5)
				eb.BackgroundTransparency = 1
				eb.Text = effectInfo.prefix:upper()
				eb.TextColor3 = effectInfo.color
				eb.Font = Enum.Font.GothamBold; eb.TextSize = 8
				eb.Parent = slot
			end

			local nl = Instance.new("TextLabel")
			nl.Size = UDim2.new(1, -4, 0, 22)
			nl.Position = UDim2.new(0.5, 0, 0.3, 0)
			nl.AnchorPoint = Vector2.new(0.5, 0)
			nl.BackgroundTransparency = 1
			nl.Text = string.sub(displayName, 1, 7)
			nl.TextColor3 = displayColor
			nl.Font = FONT; nl.TextScaled = true
			nl.Parent = slot

			local rl = Instance.new("TextLabel")
			rl.Size = UDim2.new(1, 0, 0, 12)
			rl.Position = UDim2.new(0.5, 0, 1, -14)
			rl.AnchorPoint = Vector2.new(0.5, 0)
			rl.BackgroundTransparency = 1
			rl.Text = info.rarity
			rl.TextColor3 = rarityColor
			rl.Font = FONT2; rl.TextSize = 9
			rl.Parent = slot
		else
			local el = Instance.new("TextLabel")
			el.Size = UDim2.new(1, 0, 1, 0)
			el.BackgroundTransparency = 1
			el.Text = "Empty"
			el.TextColor3 = Color3.fromRGB(60, 60, 80)
			el.Font = FONT2; el.TextSize = 11
			el.Parent = slot
		end

		-- Click: if a storage item is selected, swap/move it here
		local capI = i
		slot.MouseButton1Click:Connect(function()
			if selectedStorageIdx then
				local capSI = selectedStorageIdx
				selectedStorageIdx = nil
				if item then
					StorageAction:FireServer("swap", capI, capSI)
				else
					StorageAction:FireServer("toHotbar", capSI, capI)
				end
			end
		end)
	end
end

-------------------------------------------------
-- INIT / OPEN / CLOSE
-------------------------------------------------

function StorageController.Init()
	screenGui = UIHelper.CreateScreenGui("StorageGui", 9)
	screenGui.Parent = playerGui

	modalFrame = Instance.new("Frame")
	modalFrame.Name = "StorageModal"
	modalFrame.Size = UDim2.new(0, 860, 0, 620)
	modalFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	modalFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	modalFrame.BackgroundColor3 = BG; modalFrame.BorderSizePixel = 0
	modalFrame.Visible = false; modalFrame.ClipsDescendants = true
	modalFrame.Parent = screenGui
	Instance.new("UICorner", modalFrame).CornerRadius = UDim.new(0, 24)
	local mStroke = Instance.new("UIStroke", modalFrame)
	mStroke.Color = ACCENT; mStroke.Thickness = 1.5; mStroke.Transparency = 0.3
	UIHelper.CreateShadow(modalFrame)
	UIHelper.MakeResponsiveModal(modalFrame, 860, 620)

	-- Title bar
	local titleBar = Instance.new("Frame")
	titleBar.Size = UDim2.new(1, 0, 0, 50)
	titleBar.BackgroundColor3 = Color3.fromRGB(20, 18, 36); titleBar.BorderSizePixel = 0
	titleBar.Parent = modalFrame
	Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 20)

	headerLabel = Instance.new("TextLabel")
	headerLabel.Size = UDim2.new(1, -120, 1, 0)
	headerLabel.Position = UDim2.new(0, 16, 0, 0)
	headerLabel.BackgroundTransparency = 1
	headerLabel.Text = "Storage (0/" .. STORAGE_MAX .. ")"
	headerLabel.TextColor3 = ACCENT; headerLabel.Font = FONT; headerLabel.TextSize = 24
	headerLabel.TextXAlignment = Enum.TextXAlignment.Left
	headerLabel.Parent = titleBar

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 36, 0, 36)
	closeBtn.Position = UDim2.new(1, -44, 0.5, 0)
	closeBtn.AnchorPoint = Vector2.new(0, 0.5)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	closeBtn.Text = "X"; closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = FONT; closeBtn.TextSize = 18; closeBtn.BorderSizePixel = 0
	closeBtn.Parent = titleBar
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1, 0)
	closeBtn.MouseButton1Click:Connect(function() StorageController.Close() end)

	-- Sort buttons row
	local sortRow = Instance.new("Frame")
	sortRow.Size = UDim2.new(1, -20, 0, 34)
	sortRow.Position = UDim2.new(0, 10, 0, 54)
	sortRow.BackgroundTransparency = 1; sortRow.Parent = modalFrame
	local sortLayout = Instance.new("UIListLayout", sortRow)
	sortLayout.FillDirection = Enum.FillDirection.Horizontal
	sortLayout.Padding = UDim.new(0, 8); sortLayout.VerticalAlignment = Enum.VerticalAlignment.Center

	local function makeSortBtn(text, mode)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 120, 0, 30)
		btn.BackgroundColor3 = sortMode == mode and Color3.fromRGB(60, 60, 100) or Color3.fromRGB(30, 28, 50)
		btn.Text = text; btn.TextColor3 = sortMode == mode and ACCENT or Color3.fromRGB(140, 140, 170)
		btn.Font = FONT2; btn.TextSize = 13; btn.BorderSizePixel = 0
		btn.Parent = sortRow
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
		btn.MouseButton1Click:Connect(function()
			sortMode = mode
			selectedStorageIdx = nil
			StorageController.Refresh()
		end)
		return btn
	end

	makeSortBtn("Sort: Rarity", "rarity")
	makeSortBtn("Sort: Cash", "cash")

	-- Info label
	local infoLabel = Instance.new("TextLabel")
	infoLabel.Size = UDim2.new(0, 400, 0, 30)
	infoLabel.BackgroundTransparency = 1
	infoLabel.Text = "Click a storage item, then click a hotbar slot to swap"
	infoLabel.TextColor3 = Color3.fromRGB(100, 100, 130)
	infoLabel.Font = FONT2; infoLabel.TextSize = 12; infoLabel.TextWrapped = true
	infoLabel.Parent = sortRow

	-- Hotbar preview row (bottom)
	local hotbarSection = Instance.new("Frame")
	hotbarSection.Name = "HotbarPreview"
	hotbarSection.Size = UDim2.new(1, -20, 0, 90)
	hotbarSection.Position = UDim2.new(0, 10, 1, -100)
	hotbarSection.BackgroundColor3 = Color3.fromRGB(18, 16, 34)
	hotbarSection.BorderSizePixel = 0; hotbarSection.Parent = modalFrame
	Instance.new("UICorner", hotbarSection).CornerRadius = UDim.new(0, 12)
	Instance.new("UIStroke", hotbarSection).Color = Color3.fromRGB(50, 50, 70)

	local hbLabel = Instance.new("TextLabel")
	hbLabel.Size = UDim2.new(0, 80, 0, 14)
	hbLabel.Position = UDim2.new(0, 8, 0, 2)
	hbLabel.BackgroundTransparency = 1
	hbLabel.Text = "HOTBAR"
	hbLabel.TextColor3 = Color3.fromRGB(100, 100, 130)
	hbLabel.Font = FONT2; hbLabel.TextSize = 10
	hbLabel.TextXAlignment = Enum.TextXAlignment.Left
	hbLabel.Parent = hotbarSection

	hotbarPreviewFrame = Instance.new("Frame")
	hotbarPreviewFrame.Size = UDim2.new(1, -10, 0, 72)
	hotbarPreviewFrame.Position = UDim2.new(0, 5, 0, 16)
	hotbarPreviewFrame.BackgroundTransparency = 1
	hotbarPreviewFrame.Parent = hotbarSection
	local hbLayout = Instance.new("UIListLayout", hotbarPreviewFrame)
	hbLayout.FillDirection = Enum.FillDirection.Horizontal
	hbLayout.Padding = UDim.new(0, 4)
	hbLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	hbLayout.VerticalAlignment = Enum.VerticalAlignment.Center

	-- Grid area (scrollable)
	gridFrame = Instance.new("ScrollingFrame")
	gridFrame.Name = "StorageGrid"
	gridFrame.Size = UDim2.new(1, -20, 1, -200)
	gridFrame.Position = UDim2.new(0, 10, 0, 92)
	gridFrame.BackgroundTransparency = 1; gridFrame.BorderSizePixel = 0
	gridFrame.ScrollBarThickness = 6; gridFrame.ScrollBarImageColor3 = ACCENT
	gridFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	gridFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	gridFrame.Parent = modalFrame

	local gl = Instance.new("UIGridLayout", gridFrame)
	gl.CellSize = UDim2.new(0, 90, 0, 100)
	gl.CellPadding = UDim2.new(0, 6, 0, 6)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	Instance.new("UIPadding", gridFrame).PaddingTop = UDim.new(0, 4)

	-- Listen for storage results (toast on error)
	StorageResult.OnClientEvent:Connect(function(result)
		if not result.success and result.reason then
			-- Show a brief toast
			local toast = Instance.new("TextLabel")
			toast.Size = UDim2.new(0, 300, 0, 40)
			toast.Position = UDim2.new(0.5, 0, 0, 16)
			toast.AnchorPoint = Vector2.new(0.5, 0)
			toast.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
			toast.Text = result.reason; toast.TextColor3 = Color3.new(1, 1, 1)
			toast.Font = FONT; toast.TextSize = 16; toast.BorderSizePixel = 0
			toast.Parent = modalFrame
			Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 10)
			task.delay(2, function()
				if toast.Parent then toast:Destroy() end
			end)
		end
	end)
end

function StorageController.IsOpen()
	return isOpen
end

function StorageController.Open()
	if isOpen then StorageController.Close(); return end
	isOpen = true
	selectedStorageIdx = nil
	if modalFrame then
		modalFrame.Visible = true
		StorageController.Refresh()
		UIHelper.ScaleIn(modalFrame, 0.2)
	end
end

function StorageController.Close()
	if not isOpen then return end
	isOpen = false
	selectedStorageIdx = nil
	if modalFrame then UIHelper.ScaleOut(modalFrame, 0.2) end
end

function StorageController.Refresh()
	if not isOpen then return end
	buildGrid()
	buildHotbarPreview()
end

return StorageController
