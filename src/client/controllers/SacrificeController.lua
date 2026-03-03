--[[
	SacrificeController.lua
	Sacrifice UI — GemShop-style sidebar + content.

	Queue-based flow:
	- Each sacrifice has a persistent queue (stored server-side in PlayerData.sacrificeQueues).
	- When a player adds a streamer to a queue, it leaves their inventory/storage
	  and moves into the queue. The queue acts as its own storage spot.
	- Items in queues persist across sessions.
	- When the queue is full, the player can exchange for gems.
	- Players can remove items from the queue at any time (returns to inventory/storage).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")

local Sacrifice    = require(ReplicatedStorage.Shared.Config.Sacrifice)
local Streamers    = require(ReplicatedStorage.Shared.Config.Streamers)
local Effects      = require(ReplicatedStorage.Shared.Config.Effects)
local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local UIHelper     = require(script.Parent.UIHelper)
local HUDController = require(script.Parent.HUDController)
local StoreController = require(script.Parent.StoreController)

local SacrificeController = {}

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RemoteEvents     = ReplicatedStorage:WaitForChild("RemoteEvents")
local OpenSacrificeGui = RemoteEvents:WaitForChild("OpenSacrificeGui")
local SacrificeRequest = RemoteEvents:WaitForChild("SacrificeRequest")
local SacrificeResult  = RemoteEvents:WaitForChild("SacrificeResult")
local SacrificeQueueAction = RemoteEvents:WaitForChild("SacrificeQueueAction")

local screenGui, modalFrame
local contentFrame
local rarityBarFrame
local topTabBtns = {}
local activeTopTab = "gems"
local activeGemRarity = 1
local isOpen       = false

local sidebars = {}
local sidebarBtnLists = { onetime = {}, elemOnetime = {} }
local activeTabId  = nil
local confirmFrame = nil
local pickerFrame  = nil
local onOpenCallbacks = {}
local onCloseCallbacks = {}
local onQueueChanged = {}
local rarityBtns = {}

local FONT   = Enum.Font.FredokaOne
local FONT2  = Enum.Font.GothamBold
local BG     = Color3.fromRGB(45, 35, 75)
local ACCENT = Color3.fromRGB(255, 100, 120)

local S = 1
local function sx(n) return math.floor(n * S + 0.5) end

local STORAGE_OFFSET = 1000

-------------------------------------------------
-- HELPERS
-------------------------------------------------

local function formatNumber(n)
	local s = tostring(math.floor(n))
	local f = ""
	for i = 1, #s do
		f = f .. s:sub(i, i)
		if (#s - i) % 3 == 0 and i < #s then f = f .. "," end
	end
	return f
end

local function getItemInfo(item)
	local id = type(item) == "table" and item.id or item
	local effect = type(item) == "table" and item.effect or nil
	local info = Streamers.ById[id]
	return id, effect, info
end

local function getQueueItems(queueId)
	local queues = HUDController.Data.sacrificeQueues or {}
	return queues[queueId] or {}
end

local function fireQueueChanged()
	for _, cb in ipairs(onQueueChanged) do
		task.spawn(cb)
	end
end

-------------------------------------------------
-- SERVER QUEUE ACTIONS
-------------------------------------------------

local function requestQueueAdd(queueId, sourceType, sourceIndex)
	SacrificeQueueAction:FireServer("add", queueId, sourceType, sourceIndex)
end

local function requestQueueRemove(queueId, queueIndex)
	SacrificeQueueAction:FireServer("remove", queueId, queueIndex)
end

local function requestQueueClear(queueId)
	SacrificeQueueAction:FireServer("clear", queueId)
end

local function requestQueueAutoFill(queueId, filterType, filterArg1, filterArg2, maxCount)
	SacrificeQueueAction:FireServer("autoFill", queueId, filterType, filterArg1, filterArg2, maxCount)
end

-------------------------------------------------
-- AVATAR SLOT HELPER
-------------------------------------------------

local function buildAvatarSlot(slot, streamerId)
	local fallback = Instance.new("TextLabel")
	fallback.Size = UDim2.new(1, 0, 1, 0)
	fallback.BackgroundTransparency = 1
	local dn = Streamers.ById[streamerId] and Streamers.ById[streamerId].displayName or streamerId
	fallback.Text = dn:sub(1, 2):upper()
	fallback.TextColor3 = Color3.fromRGB(200, 255, 200)
	fallback.Font = FONT
	fallback.TextSize = sx(18)
	fallback.Parent = slot
end

-------------------------------------------------
-- CONFIRMATION DIALOG
-------------------------------------------------

local function showConfirmation(message, onYes)
	if confirmFrame then confirmFrame:Destroy() end
	local dim = Instance.new("TextButton")
	dim.Size = UDim2.new(1, 0, 1, 0); dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.4; dim.Text = ""; dim.ZIndex = 50
	dim.BorderSizePixel = 0; dim.Parent = modalFrame

	local box = Instance.new("Frame")
	box.Size = UDim2.new(0, sx(340), 0, sx(180)); box.Position = UDim2.new(0.5, 0, 0.5, 0)
	box.AnchorPoint = Vector2.new(0.5, 0.5); box.BackgroundColor3 = Color3.fromRGB(55, 45, 90)
	box.BorderSizePixel = 0; box.ZIndex = 51; box.Parent = dim
	Instance.new("UICorner", box).CornerRadius = UDim.new(0, 18)
	local bs = Instance.new("UIStroke", box); bs.Color = ACCENT; bs.Thickness = 2.5

	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1, -sx(20), 0, sx(30)); t.Position = UDim2.new(0.5, 0, 0, sx(14))
	t.AnchorPoint = Vector2.new(0.5, 0); t.BackgroundTransparency = 1
	t.Text = "Are you sure?"; t.TextColor3 = Color3.fromRGB(255, 200, 100)
	t.Font = FONT; t.TextSize = sx(22); t.ZIndex = 52; t.Parent = box

	local ml = Instance.new("TextLabel")
	ml.Size = UDim2.new(1, -sx(24), 0, sx(50)); ml.Position = UDim2.new(0.5, 0, 0, sx(46))
	ml.AnchorPoint = Vector2.new(0.5, 0); ml.BackgroundTransparency = 1
	ml.Text = message; ml.TextColor3 = Color3.fromRGB(200, 200, 220)
	ml.Font = FONT2; ml.TextSize = sx(15); ml.TextWrapped = true; ml.ZIndex = 52; ml.Parent = box

	local function dismiss() if dim.Parent then dim:Destroy() end; confirmFrame = nil end
	dim.MouseButton1Click:Connect(dismiss)

	local yb = Instance.new("TextButton")
	yb.Size = UDim2.new(0, sx(140), 0, sx(42)); yb.Position = UDim2.new(0.5, -sx(6), 1, -sx(16))
	yb.AnchorPoint = Vector2.new(1, 1); yb.BackgroundColor3 = Color3.fromRGB(60, 180, 80)
	yb.Text = "YES, DO IT"; yb.TextColor3 = Color3.new(1, 1, 1)
	yb.Font = FONT; yb.TextSize = sx(16); yb.BorderSizePixel = 0; yb.ZIndex = 52; yb.Parent = box
	Instance.new("UICorner", yb).CornerRadius = UDim.new(0, sx(10))
	UIHelper.AddPuffyGradient(yb)
	yb.MouseButton1Click:Connect(function() dismiss(); if onYes then onYes() end end)

	local nb = Instance.new("TextButton")
	nb.Size = UDim2.new(0, sx(140), 0, sx(42)); nb.Position = UDim2.new(0.5, sx(6), 1, -sx(16))
	nb.AnchorPoint = Vector2.new(0, 1); nb.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	nb.Text = "CANCEL"; nb.TextColor3 = Color3.new(1, 1, 1)
	nb.Font = FONT; nb.TextSize = sx(16); nb.BorderSizePixel = 0; nb.ZIndex = 52; nb.Parent = box
	Instance.new("UICorner", nb).CornerRadius = UDim.new(0, sx(10))
	UIHelper.AddPuffyGradient(nb)
	nb.MouseButton1Click:Connect(dismiss)

	confirmFrame = dim
	box.Size = UDim2.new(0, sx(170), 0, sx(90))
	TweenService:Create(box, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, sx(340), 0, sx(180)),
	}):Play()
end

-------------------------------------------------
-- TOAST
-------------------------------------------------

local function showToast(text, color, dur)
	color = color or Color3.fromRGB(80, 220, 100); dur = dur or 3
	local toast = Instance.new("Frame")
	toast.Size = UDim2.new(0.55, 0, 0, sx(62)); toast.Position = UDim2.new(0.5, 0, 0, -sx(70))
	toast.AnchorPoint = Vector2.new(0.5, 0); toast.BackgroundColor3 = color
	toast.BorderSizePixel = 0; toast.ZIndex = 60; toast.Parent = modalFrame
	Instance.new("UICorner", toast).CornerRadius = UDim.new(0, sx(18))
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -sx(24), 1, 0); lbl.Position = UDim2.new(0.5, 0, 0.5, 0)
	lbl.AnchorPoint = Vector2.new(0.5, 0.5); lbl.BackgroundTransparency = 1
	lbl.Text = text; lbl.TextColor3 = Color3.new(1, 1, 1)
	lbl.Font = FONT; lbl.TextSize = sx(20); lbl.TextWrapped = true; lbl.ZIndex = 61; lbl.Parent = toast
	TweenService:Create(toast, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, sx(10)),
	}):Play()
	task.delay(dur, function()
		if not toast.Parent then return end
		TweenService:Create(toast, TweenInfo.new(0.2), { Position = UDim2.new(0.5, 0, 0, -sx(70)) }):Play()
		task.delay(0.25, function() if toast.Parent then toast:Destroy() end end)
	end)
end

-------------------------------------------------
-- PICKER POPUP (pick a streamer from inventory/storage to add to queue)
-------------------------------------------------

local function closePicker()
	if pickerFrame then pickerFrame:Destroy(); pickerFrame = nil end
end

local function showPicker(title, filterFn, queueId, onDone)
	closePicker()
	local inv = HUDController.Data.inventory or {}
	local sto = HUDController.Data.storage or {}

	local eligible = {}
	for i, item in ipairs(inv) do
		if filterFn(item) then
			table.insert(eligible, { item = item, sourceType = "hotbar", sourceIndex = i })
		end
	end
	for i, item in ipairs(sto) do
		if filterFn(item) then
			table.insert(eligible, { item = item, sourceType = "storage", sourceIndex = i })
		end
	end

	local dim = Instance.new("TextButton")
	dim.Size = UDim2.new(1, 0, 1, 0); dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.35; dim.Text = ""; dim.ZIndex = 40
	dim.BorderSizePixel = 0; dim.Parent = modalFrame
	dim.MouseButton1Click:Connect(closePicker)

	local popup = Instance.new("Frame")
	popup.Size = UDim2.new(0, sx(540), 0, sx(440))
	popup.Position = UDim2.new(0.5, 0, 0.5, 0); popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.BackgroundColor3 = Color3.fromRGB(50, 40, 80); popup.BorderSizePixel = 0; popup.ZIndex = 41
	popup.ClipsDescendants = true; popup.Parent = dim
	Instance.new("UICorner", popup).CornerRadius = UDim.new(0, sx(22))
	local ps = Instance.new("UIStroke", popup); ps.Color = Color3.fromRGB(255, 220, 80); ps.Thickness = 2.5

	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.new(1, -sx(70), 0, sx(42)); tl.Position = UDim2.new(0.5, 0, 0, sx(12))
	tl.AnchorPoint = Vector2.new(0.5, 0); tl.BackgroundTransparency = 1
	tl.Text = title; tl.TextColor3 = Color3.fromRGB(255, 220, 100)
	tl.Font = FONT; tl.TextSize = sx(24); tl.ZIndex = 42; tl.Parent = popup

	local cb = Instance.new("TextButton")
	cb.Size = UDim2.new(0, sx(42), 0, sx(42)); cb.Position = UDim2.new(1, -sx(14), 0, sx(10))
	cb.AnchorPoint = Vector2.new(1, 0); cb.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	cb.Text = "X"; cb.TextColor3 = Color3.new(1, 1, 1); cb.Font = FONT; cb.TextSize = sx(20)
	cb.BorderSizePixel = 0; cb.ZIndex = 43; cb.Parent = popup
	Instance.new("UICorner", cb).CornerRadius = UDim.new(1, 0)
	cb.MouseButton1Click:Connect(closePicker)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -sx(14), 1, -sx(62)); scroll.Position = UDim2.new(0, sx(8), 0, sx(56))
	scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = sx(5); scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; scroll.ZIndex = 42; scroll.Parent = popup

	local grid = Instance.new("UIGridLayout", scroll)
	grid.CellSize = UDim2.new(0, sx(100), 0, sx(120)); grid.CellPadding = UDim2.new(0, sx(8), 0, sx(8))
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local sp = Instance.new("UIPadding", scroll)
	sp.PaddingLeft = UDim.new(0, 8); sp.PaddingTop = UDim.new(0, 6)

	if #eligible == 0 then
		local nl = Instance.new("TextLabel")
		nl.Size = UDim2.new(1, -sx(20), 0, sx(68)); nl.Position = UDim2.new(0.5, 0, 0, sx(20))
		nl.AnchorPoint = Vector2.new(0.5, 0); nl.BackgroundTransparency = 1
		nl.Text = "No eligible streamers!"; nl.TextColor3 = Color3.fromRGB(150, 150, 170)
		nl.Font = FONT; nl.TextSize = sx(18); nl.TextWrapped = true
		nl.ZIndex = 42; nl.Parent = scroll
	end

	for order, entry in ipairs(eligible) do
		local item = entry.item
		local id, eff, info = getItemInfo(item)
		local rColor = DesignConfig.RarityColors[info and info.rarity or "Common"] or Color3.new(1, 1, 1)
		local effectInfo = eff and Effects.ByName[eff] or nil
		local displayColor = effectInfo and effectInfo.color or rColor

		local cell = Instance.new("TextButton")
		cell.Size = UDim2.new(0, sx(100), 0, sx(120))
		cell.BackgroundColor3 = Color3.fromRGB(50, 42, 80); cell.BorderSizePixel = 0
		cell.Text = ""; cell.LayoutOrder = order; cell.ZIndex = 42; cell.Parent = scroll
		Instance.new("UICorner", cell).CornerRadius = UDim.new(0, sx(12))
		local cs = Instance.new("UIStroke", cell); cs.Color = rColor; cs.Thickness = 2; cs.Transparency = 0.2

		local pvpS = sx(48)
		local pvp = Instance.new("Frame")
		pvp.Size = UDim2.new(0, pvpS, 0, pvpS)
		pvp.Position = UDim2.new(0.5, 0, 0, sx(8))
		pvp.AnchorPoint = Vector2.new(0.5, 0)
		pvp.BackgroundColor3 = Color3.fromRGB(30, 26, 50)
		pvp.BackgroundTransparency = 0.15
		pvp.BorderSizePixel = 0; pvp.ZIndex = 43; pvp.Parent = cell
		Instance.new("UICorner", pvp).CornerRadius = UDim.new(1, 0)
		local avatarText = Instance.new("TextLabel")
		avatarText.Size = UDim2.new(1, 0, 1, 0)
		avatarText.BackgroundTransparency = 1
		avatarText.Text = string.upper((info and info.displayName or id):sub(1, 2))
		avatarText.TextColor3 = Color3.fromRGB(220, 240, 255)
		avatarText.Font = FONT; avatarText.TextSize = sx(14); avatarText.ZIndex = 44
		avatarText.Parent = pvp

		local nameY = sx(8) + pvpS + sx(4)
		local nl2 = Instance.new("TextLabel")
		nl2.Size = UDim2.new(1, -sx(8), 0, sx(18)); nl2.Position = UDim2.new(0.5, 0, 0, nameY)
		nl2.AnchorPoint = Vector2.new(0.5, 0); nl2.BackgroundTransparency = 1
		nl2.Text = info and info.displayName or id; nl2.TextColor3 = rColor
		nl2.Font = FONT; nl2.TextSize = sx(12); nl2.TextTruncate = Enum.TextTruncate.AtEnd
		nl2.ZIndex = 43; nl2.Parent = cell

		if eff then
			local el = Instance.new("TextLabel")
			el.Size = UDim2.new(1, -sx(8), 0, sx(14)); el.Position = UDim2.new(0.5, 0, 0, nameY + sx(16))
			el.AnchorPoint = Vector2.new(0.5, 0); el.BackgroundTransparency = 1
			el.Text = eff; el.TextColor3 = effectInfo and effectInfo.color or Color3.fromRGB(180, 180, 180)
			el.Font = FONT2; el.TextSize = sx(10); el.ZIndex = 43; el.Parent = cell
		end

		local rl = Instance.new("TextLabel")
		rl.Size = UDim2.new(1, 0, 0, sx(16)); rl.Position = UDim2.new(0.5, 0, 1, -sx(18))
		rl.AnchorPoint = Vector2.new(0.5, 0); rl.BackgroundTransparency = 1
		rl.Text = info and info.rarity or "?"; rl.TextColor3 = rColor
		rl.Font = FONT2; rl.TextSize = sx(11); rl.ZIndex = 43; rl.Parent = cell

		local srcLbl = Instance.new("TextLabel")
		srcLbl.Size = UDim2.new(0, sx(50), 0, sx(12)); srcLbl.Position = UDim2.new(1, -sx(4), 0, sx(4))
		srcLbl.AnchorPoint = Vector2.new(1, 0); srcLbl.BackgroundTransparency = 1
		srcLbl.Text = entry.sourceType == "storage" and "STORAGE" or ""
		srcLbl.TextColor3 = Color3.fromRGB(100, 100, 130)
		srcLbl.Font = FONT2; srcLbl.TextSize = sx(8); srcLbl.ZIndex = 44; srcLbl.Parent = cell

		local capEntry = entry
		cell.MouseButton1Click:Connect(function()
			closePicker()
			requestQueueAdd(queueId, capEntry.sourceType, capEntry.sourceIndex)
			if onDone then onDone() end
		end)
	end

	pickerFrame = dim
	UIHelper.ScaleIn(popup, 0.15)
end

-------------------------------------------------
-- CONTENT BUILDERS
-------------------------------------------------

local function clearContent()
	if not contentFrame then return end
	for _, c in ipairs(contentFrame:GetChildren()) do
		if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then c:Destroy() end
	end
end

local buildContent

-- =========== GEM TRADE CONTENT ===========
local function buildGemTradeContent(tradeIndex)
	clearContent()
	local trade = Sacrifice.GemTrades[tradeIndex]
	if not trade then return end

	local queueId = "GemTrade_" .. tradeIndex
	local queue = getQueueItems(queueId)
	local selected = #queue
	local need = trade.count
	local rc = DesignConfig.RarityColors[trade.rarity] or Color3.new(1, 1, 1)
	local canSacrifice = selected >= need

	local slotSize = sx(60)
	local slotGap = sx(8)
	local slotsPerRow = math.min(need, 10)
	local totalRows = math.ceil(need / slotsPerRow)
	local slotRowH = totalRows * (slotSize + slotGap) + sx(12)

	local slotContainer = Instance.new("Frame")
	slotContainer.Size = UDim2.new(1, -sx(12), 0, slotRowH)
	slotContainer.BackgroundColor3 = Color3.fromRGB(35, 30, 60); slotContainer.BorderSizePixel = 0
	slotContainer.Parent = contentFrame
	Instance.new("UICorner", slotContainer).CornerRadius = UDim.new(0, sx(16))
	local scStroke = Instance.new("UIStroke", slotContainer); scStroke.Color = rc; scStroke.Thickness = 2; scStroke.Transparency = 0.3

	local slotGrid = Instance.new("Frame")
	slotGrid.Size = UDim2.new(1, 0, 1, 0); slotGrid.BackgroundTransparency = 1; slotGrid.Parent = slotContainer

	local sgLayout = Instance.new("UIGridLayout", slotGrid)
	sgLayout.CellSize = UDim2.new(0, slotSize, 0, slotSize)
	sgLayout.CellPadding = UDim2.new(0, slotGap, 0, slotGap)
	sgLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sgLayout.SortOrder = Enum.SortOrder.LayoutOrder
	local sgPad = Instance.new("UIPadding", slotGrid)
	sgPad.PaddingTop = UDim.new(0, sx(8)); sgPad.PaddingBottom = UDim.new(0, sx(4))

	for i = 1, need do
		local item = queue[i]
		local isFilled = item ~= nil
		local slot = Instance.new("TextButton")
		slot.Size = UDim2.new(0, slotSize, 0, slotSize)
		slot.BackgroundColor3 = isFilled and Color3.fromRGB(40, 120, 60) or Color3.fromRGB(50, 42, 80)
		slot.BorderSizePixel = 0; slot.LayoutOrder = i; slot.Text = ""; slot.Parent = slotGrid
		Instance.new("UICorner", slot).CornerRadius = UDim.new(1, 0)
		local slotStroke = Instance.new("UIStroke", slot)
		slotStroke.Color = isFilled and Color3.fromRGB(80, 240, 100) or rc
		slotStroke.Thickness = isFilled and 2.5 or 1.5
		slotStroke.Transparency = isFilled and 0 or 0.5

		if isFilled then
			local id = type(item) == "table" and item.id or (item or "?")
			buildAvatarSlot(slot, id)
			local capI = i
			slot.MouseButton1Click:Connect(function()
				requestQueueRemove(queueId, capI)
			end)
		else
			slot.MouseButton1Click:Connect(function()
				showPicker("Pick a " .. trade.rarity .. " streamer", function(itm)
					local _, _, info = getItemInfo(itm)
					return info and info.rarity == trade.rarity
				end, queueId, function()
					-- Rebuild after server processes
				end)
			end)
		end
	end

	local counterLbl = Instance.new("TextLabel")
	counterLbl.Size = UDim2.new(1, -sx(12), 0, sx(28))
	counterLbl.BackgroundTransparency = 1
	counterLbl.Text = selected .. " / " .. need .. " queued  —  " .. formatNumber(trade.gems) .. " Gems"
	counterLbl.TextColor3 = canSacrifice and Color3.fromRGB(100, 255, 120) or rc
	counterLbl.Font = FONT; counterLbl.TextSize = sx(20); counterLbl.Parent = contentFrame
	local cntStroke = Instance.new("UIStroke", counterLbl)
	cntStroke.Color = Color3.fromRGB(15, 10, 30); cntStroke.Thickness = 1.5
	cntStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	local actionRow = Instance.new("Frame")
	actionRow.Size = UDim2.new(1, -sx(12), 0, sx(64)); actionRow.BackgroundTransparency = 1; actionRow.Parent = contentFrame
	local arl = Instance.new("UIListLayout", actionRow)
	arl.FillDirection = Enum.FillDirection.Horizontal
	arl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	arl.VerticalAlignment = Enum.VerticalAlignment.Center; arl.Padding = UDim.new(0, sx(16))

	if canSacrifice then
		local mainBtn = Instance.new("TextButton")
		mainBtn.Size = UDim2.new(0, sx(260), 0, sx(56))
		mainBtn.BackgroundColor3 = rc
		mainBtn.Text = "SACRIFICE " .. formatNumber(trade.gems) .. " Gems"
		mainBtn.TextColor3 = Color3.new(1, 1, 1); mainBtn.Font = FONT; mainBtn.TextSize = sx(20)
		mainBtn.BorderSizePixel = 0; mainBtn.Parent = actionRow
		Instance.new("UICorner", mainBtn).CornerRadius = UDim.new(0, sx(16))
		UIHelper.AddPuffyGradient(mainBtn)
		mainBtn.MouseButton1Click:Connect(function()
			showConfirmation(
				("Sacrifice %d %s streamers for %s Gems?"):format(need, trade.rarity, formatNumber(trade.gems)),
				function()
					SacrificeRequest:FireServer("GemTrade", tradeIndex)
				end
			)
		end)
	end

	if not canSacrifice then
		local autoBtn = Instance.new("TextButton")
		autoBtn.Size = UDim2.new(0, sx(200), 0, sx(56))
		autoBtn.BackgroundColor3 = Color3.fromRGB(80, 160, 255)
		autoBtn.Text = "AUTO FILL"
		autoBtn.TextColor3 = Color3.new(1, 1, 1); autoBtn.Font = FONT; autoBtn.TextSize = sx(20)
		autoBtn.BorderSizePixel = 0; autoBtn.Parent = actionRow
		Instance.new("UICorner", autoBtn).CornerRadius = UDim.new(0, sx(16))
		UIHelper.AddPuffyGradient(autoBtn)
		autoBtn.MouseButton1Click:Connect(function()
			requestQueueAutoFill(queueId, "rarity", trade.rarity, nil, need)
		end)

		local addBtn = Instance.new("TextButton")
		addBtn.Size = UDim2.new(0, sx(200), 0, sx(56))
		addBtn.BackgroundColor3 = rc
		addBtn.Text = "PICK MANUALLY"
		addBtn.TextColor3 = Color3.new(1, 1, 1); addBtn.Font = FONT; addBtn.TextSize = sx(16)
		addBtn.BorderSizePixel = 0; addBtn.Parent = actionRow
		Instance.new("UICorner", addBtn).CornerRadius = UDim.new(0, sx(16))
		UIHelper.AddPuffyGradient(addBtn)
		addBtn.MouseButton1Click:Connect(function()
			showPicker("Pick a " .. trade.rarity .. " streamer", function(itm)
				local _, _, info = getItemInfo(itm)
				return info and info.rarity == trade.rarity
			end, queueId, nil)
		end)
	end

	if selected > 0 then
		local clrLink = Instance.new("TextButton")
		clrLink.Size = UDim2.new(0, sx(80), 0, sx(30))
		clrLink.BackgroundTransparency = 1; clrLink.Text = "Clear All"
		clrLink.TextColor3 = Color3.fromRGB(200, 160, 180); clrLink.Font = FONT; clrLink.TextSize = sx(15)
		clrLink.BorderSizePixel = 0; clrLink.Parent = actionRow
		clrLink.MouseButton1Click:Connect(function()
			requestQueueClear(queueId)
		end)
	end
end

-- Forward declaration for effect-based one-time content builder
local buildEffectOneTimeContent

-- =========== ONE-TIME CONTENT ===========
local function buildOneTimeContent(oneTimeId)
	clearContent()
	local cfg = Sacrifice.OneTime[oneTimeId]
	if not cfg then return end
	local done = (HUDController.Data.sacrificeOneTime or {})[oneTimeId]

	if cfg.req[1] and cfg.req[1].effectReq then
		buildEffectOneTimeContent(oneTimeId, cfg, done)
		return
	end

	local queueId = "OneTime_" .. oneTimeId
	local queue = getQueueItems(queueId)
	local accentColor = done and Color3.fromRGB(80, 220, 100) or Color3.fromRGB(255, 200, 60)

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, -sx(12), 0, sx(90))
	header.BackgroundColor3 = Color3.fromRGB(55, 45, 90); header.BorderSizePixel = 0; header.Parent = contentFrame
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, sx(18))
	Instance.new("UIStroke", header).Color = accentColor

	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.new(1, -sx(24), 0, sx(32)); tl.Position = UDim2.new(0.5, 0, 0, sx(10))
	tl.AnchorPoint = Vector2.new(0.5, 0); tl.BackgroundTransparency = 1
	tl.Text = cfg.name .. " — " .. formatNumber(cfg.gems) .. " Gems"
	tl.TextColor3 = accentColor
	tl.Font = FONT; tl.TextSize = sx(24); tl.Parent = header
	local otTStroke = Instance.new("UIStroke", tl)
	otTStroke.Color = Color3.new(0, 0, 0); otTStroke.Thickness = 2
	otTStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, -sx(24), 0, sx(36)); sub.Position = UDim2.new(0.5, 0, 0, sx(44))
	sub.AnchorPoint = Vector2.new(0.5, 0); sub.BackgroundTransparency = 1
	sub.Text = done and "You've already completed this!" or "Tap each slot to pick a streamer"
	sub.TextColor3 = Color3.fromRGB(200, 190, 230); sub.Font = FONT; sub.TextSize = sx(14)
	sub.TextWrapped = true; sub.Parent = header

	if done then return end

	local totalSlots = 0
	for _, r in ipairs(cfg.req) do totalSlots = totalSlots + (r.count or 1) end

	local slotSize = sx(60)
	local slotGap = sx(8)
	local slotsPerRow = math.min(totalSlots, 10)
	local totalRows = math.ceil(totalSlots / slotsPerRow)
	local slotRowH = totalRows * (slotSize + slotGap) + sx(12)

	local slotContainer = Instance.new("Frame")
	slotContainer.Size = UDim2.new(1, -sx(12), 0, slotRowH)
	slotContainer.BackgroundColor3 = Color3.fromRGB(35, 30, 60); slotContainer.BorderSizePixel = 0
	slotContainer.Parent = contentFrame
	Instance.new("UICorner", slotContainer).CornerRadius = UDim.new(0, sx(16))
	Instance.new("UIStroke", slotContainer).Color = Color3.fromRGB(255, 200, 60)

	local slotGrid = Instance.new("Frame")
	slotGrid.Size = UDim2.new(1, 0, 1, 0); slotGrid.BackgroundTransparency = 1; slotGrid.Parent = slotContainer
	local sgLayout = Instance.new("UIGridLayout", slotGrid)
	sgLayout.CellSize = UDim2.new(0, slotSize, 0, slotSize)
	sgLayout.CellPadding = UDim2.new(0, slotGap, 0, slotGap)
	sgLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sgLayout.SortOrder = Enum.SortOrder.LayoutOrder
	local sgPad = Instance.new("UIPadding", slotGrid)
	sgPad.PaddingTop = UDim.new(0, sx(8)); sgPad.PaddingBottom = UDim.new(0, sx(4))

	local queueIdx = 0
	local allFilled = true
	for si, r in ipairs(cfg.req) do
		local count = r.count or 1
		for c = 1, count do
			queueIdx = queueIdx + 1
			local item = queue[queueIdx]
			local isFilled = item ~= nil
			if not isFilled then allFilled = false end

			local slot = Instance.new("TextButton")
			slot.Size = UDim2.new(0, slotSize, 0, slotSize)
			slot.BackgroundColor3 = isFilled and Color3.fromRGB(40, 120, 60) or Color3.fromRGB(50, 42, 80)
			slot.BorderSizePixel = 0; slot.Text = ""; slot.LayoutOrder = queueIdx; slot.Parent = slotGrid
			Instance.new("UICorner", slot).CornerRadius = UDim.new(1, 0)
			local ss = Instance.new("UIStroke", slot)
			ss.Color = isFilled and Color3.fromRGB(80, 240, 100) or Color3.fromRGB(80, 70, 120)
			ss.Thickness = isFilled and 2.5 or 1.5
			ss.Transparency = isFilled and 0 or 0.5

			if isFilled then
				local sid = type(item) == "table" and item.id or item or "?"
				buildAvatarSlot(slot, sid)
				local capQI = queueIdx
				slot.MouseButton1Click:Connect(function()
					requestQueueRemove(queueId, capQI)
				end)
			else
				local reqLabel
				local displayId = r.streamerId and Streamers.ById[r.streamerId] and Streamers.ById[r.streamerId].displayName or r.streamerId
				if r.effect and r.streamerId then reqLabel = r.effect .. " " .. (displayId or "?")
				elseif r.streamerId then reqLabel = displayId or "?"
				elseif r.rarity then reqLabel = r.rarity
				else reqLabel = "?" end

				local pl = Instance.new("TextLabel")
				pl.Size = UDim2.new(1, -sx(4), 1, -sx(4)); pl.BackgroundTransparency = 1
				pl.Text = reqLabel; pl.TextColor3 = Color3.fromRGB(120, 110, 160)
				pl.Font = FONT; pl.TextSize = sx(10); pl.TextWrapped = true; pl.Parent = slot

				local capR = r
				slot.MouseButton1Click:Connect(function()
					local filterFn
					if capR.streamerId then
						filterFn = function(itm)
							local id = type(itm) == "table" and itm.id or itm
							if id ~= capR.streamerId then return false end
							if capR.effect ~= nil then
								local e = type(itm) == "table" and itm.effect or nil
								if e ~= capR.effect then return false end
							end
							return true
						end
					elseif capR.rarity then
						filterFn = function(itm)
							local id = type(itm) == "table" and itm.id or itm
							local info = Streamers.ById[id]
							return info and info.rarity == capR.rarity
						end
					end
					local pickerTitle = "Pick a "
					if capR.effect and capR.streamerId then
						local dn = Streamers.ById[capR.streamerId] and Streamers.ById[capR.streamerId].displayName or capR.streamerId
						pickerTitle = pickerTitle .. capR.effect .. " " .. dn
					else
						pickerTitle = pickerTitle .. (capR.streamerId or capR.rarity or "?")
					end
					if filterFn then
						showPicker(pickerTitle, filterFn, queueId, nil)
					end
				end)
			end
		end
	end

	local actionRow = Instance.new("Frame")
	actionRow.Size = UDim2.new(1, -sx(12), 0, sx(50)); actionRow.BackgroundTransparency = 1; actionRow.Parent = contentFrame
	local arl = Instance.new("UIListLayout", actionRow)
	arl.FillDirection = Enum.FillDirection.Horizontal
	arl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	arl.VerticalAlignment = Enum.VerticalAlignment.Center; arl.Padding = UDim.new(0, sx(14))

	if allFilled then
		local mainBtn = Instance.new("TextButton")
		mainBtn.Size = UDim2.new(0, sx(280), 0, sx(46)); mainBtn.BorderSizePixel = 0; mainBtn.Parent = actionRow
		Instance.new("UICorner", mainBtn).CornerRadius = UDim.new(0, sx(14))
		mainBtn.BackgroundColor3 = Color3.fromRGB(80, 220, 100)
		mainBtn.Text = "SACRIFICE FOR " .. formatNumber(cfg.gems) .. " GEMS"
		mainBtn.TextColor3 = Color3.new(1, 1, 1); mainBtn.Font = FONT; mainBtn.TextSize = sx(18)
		Instance.new("UIStroke", mainBtn).Color = Color3.fromRGB(50, 160, 65)
		UIHelper.AddPuffyGradient(mainBtn)
		local capId = oneTimeId
		mainBtn.MouseButton1Click:Connect(function()
			showConfirmation("Sacrifice these streamers for " .. formatNumber(cfg.gems) .. " Gems?", function()
				SacrificeRequest:FireServer("OneTime", capId)
			end)
		end)
	else
		local autoBtn = Instance.new("TextButton")
		autoBtn.Size = UDim2.new(0, sx(200), 0, sx(46)); autoBtn.BorderSizePixel = 0; autoBtn.Parent = actionRow
		Instance.new("UICorner", autoBtn).CornerRadius = UDim.new(0, sx(14))
		autoBtn.BackgroundColor3 = Color3.fromRGB(80, 160, 255)
		autoBtn.Text = "AUTO FILL"
		autoBtn.TextColor3 = Color3.new(1, 1, 1); autoBtn.Font = FONT; autoBtn.TextSize = sx(18)
		UIHelper.AddPuffyGradient(autoBtn)
		autoBtn.MouseButton1Click:Connect(function()
			for _, r in ipairs(cfg.req) do
				local count = r.count or 1
				if r.streamerId then
					requestQueueAutoFill(queueId, "exact", r.streamerId, r.effect, count)
				elseif r.rarity then
					requestQueueAutoFill(queueId, "rarity", r.rarity, nil, count)
				end
			end
		end)
	end

	if #queue > 0 then
		local clrLink = Instance.new("TextButton")
		clrLink.Size = UDim2.new(0, sx(80), 0, sx(24))
		clrLink.BackgroundTransparency = 1; clrLink.Text = "Clear"
		clrLink.TextColor3 = Color3.fromRGB(200, 100, 100)
		clrLink.Font = FONT2; clrLink.TextSize = sx(14); clrLink.Parent = actionRow
		clrLink.MouseButton1Click:Connect(function()
			requestQueueClear(queueId)
		end)
	end
end

-- =========== EFFECT-BASED ONE-TIME CONTENT ===========
buildEffectOneTimeContent = function(oneTimeId, cfg, done)
	clearContent()
	local r = cfg.req[1]
	local effectName = r.effectReq
	local need = r.count or 20
	local effectInfo = Effects.ByName[effectName]
	local effectColor = effectInfo and effectInfo.color or Color3.fromRGB(200, 200, 200)

	local queueId = "OneTime_" .. oneTimeId
	local queue = getQueueItems(queueId)
	local queued = #queue
	local accentColor = done and Color3.fromRGB(80, 220, 100) or effectColor

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, -sx(12), 0, sx(90))
	header.BackgroundColor3 = Color3.fromRGB(55, 45, 90); header.BorderSizePixel = 0; header.Parent = contentFrame
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, sx(18))
	Instance.new("UIStroke", header).Color = accentColor

	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.new(1, -sx(24), 0, sx(32)); tl.Position = UDim2.new(0.5, 0, 0, sx(10))
	tl.AnchorPoint = Vector2.new(0.5, 0); tl.BackgroundTransparency = 1
	tl.Text = cfg.name .. " — " .. formatNumber(cfg.gems) .. " Gems"
	tl.TextColor3 = accentColor
	tl.Font = FONT; tl.TextSize = sx(24); tl.Parent = header
	local eoTStroke = Instance.new("UIStroke", tl)
	eoTStroke.Color = Color3.new(0, 0, 0); eoTStroke.Thickness = 2
	eoTStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, -sx(24), 0, sx(36)); sub.Position = UDim2.new(0.5, 0, 0, sx(44))
	sub.AnchorPoint = Vector2.new(0.5, 0); sub.BackgroundTransparency = 1
	sub.Text = done and "Already completed!" or ("Sacrifice " .. need .. " " .. effectName .. " cards")
	sub.TextColor3 = Color3.fromRGB(200, 190, 230); sub.Font = FONT; sub.TextSize = sx(14)
	sub.TextWrapped = true; sub.Parent = header

	if done then return end

	local slotSize = sx(50)
	local slotGap = sx(6)
	local slotsPerRow = math.min(need, 10)
	local totalRows = math.ceil(need / slotsPerRow)
	local slotRowH = totalRows * (slotSize + slotGap) + sx(12)

	local slotContainer = Instance.new("Frame")
	slotContainer.Size = UDim2.new(1, -sx(12), 0, slotRowH + sx(34))
	slotContainer.BackgroundColor3 = Color3.fromRGB(35, 30, 60); slotContainer.BorderSizePixel = 0
	slotContainer.Parent = contentFrame
	Instance.new("UICorner", slotContainer).CornerRadius = UDim.new(0, sx(14))
	Instance.new("UIStroke", slotContainer).Color = effectColor

	local cntLabel = Instance.new("TextLabel")
	cntLabel.Size = UDim2.new(1, -sx(16), 0, sx(26)); cntLabel.Position = UDim2.new(0.5, 0, 0, sx(4))
	cntLabel.AnchorPoint = Vector2.new(0.5, 0); cntLabel.BackgroundTransparency = 1
	cntLabel.Text = queued .. " / " .. need .. " queued"
	cntLabel.TextColor3 = queued >= need and Color3.fromRGB(100, 255, 120) or effectColor
	cntLabel.Font = FONT; cntLabel.TextSize = sx(16); cntLabel.Parent = slotContainer

	local slotGrid = Instance.new("Frame")
	slotGrid.Size = UDim2.new(1, 0, 1, -sx(30)); slotGrid.Position = UDim2.new(0, 0, 0, sx(30))
	slotGrid.BackgroundTransparency = 1; slotGrid.Parent = slotContainer
	local sgLayout = Instance.new("UIGridLayout", slotGrid)
	sgLayout.CellSize = UDim2.new(0, slotSize, 0, slotSize)
	sgLayout.CellPadding = UDim2.new(0, slotGap, 0, slotGap)
	sgLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sgLayout.SortOrder = Enum.SortOrder.LayoutOrder
	local sgPad = Instance.new("UIPadding", slotGrid)
	sgPad.PaddingTop = UDim.new(0, sx(4)); sgPad.PaddingBottom = UDim.new(0, sx(4))

	for i = 1, need do
		local item = queue[i]
		local isFilled = item ~= nil
		local slot = Instance.new("TextButton")
		slot.Size = UDim2.new(0, slotSize, 0, slotSize)
		slot.BackgroundColor3 = isFilled and Color3.fromRGB(40, 120, 60) or Color3.fromRGB(50, 42, 80)
		slot.BorderSizePixel = 0; slot.LayoutOrder = i; slot.Text = ""; slot.Parent = slotGrid
		Instance.new("UICorner", slot).CornerRadius = UDim.new(1, 0)
		local slotStk = Instance.new("UIStroke", slot)
		slotStk.Color = isFilled and Color3.fromRGB(80, 240, 100) or effectColor
		slotStk.Thickness = isFilled and 2 or 1.5
		slotStk.Transparency = isFilled and 0 or 0.5

		if isFilled then
			local id = type(item) == "table" and item.id or (item or "?")
			buildAvatarSlot(slot, id)
			local capI = i
			slot.MouseButton1Click:Connect(function()
				requestQueueRemove(queueId, capI)
			end)
		else
			slot.MouseButton1Click:Connect(function()
				showPicker("Pick a " .. effectName .. " streamer", function(itm)
					local eff = type(itm) == "table" and itm.effect or nil
					return eff == effectName
				end, queueId, nil)
			end)
		end
	end

	local canSac = queued >= need
	local actionRow = Instance.new("Frame")
	actionRow.Size = UDim2.new(1, -sx(12), 0, sx(50)); actionRow.BackgroundTransparency = 1; actionRow.Parent = contentFrame
	local arl = Instance.new("UIListLayout", actionRow)
	arl.FillDirection = Enum.FillDirection.Horizontal
	arl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	arl.VerticalAlignment = Enum.VerticalAlignment.Center; arl.Padding = UDim.new(0, sx(14))

	if canSac then
		local mainBtn = Instance.new("TextButton")
		mainBtn.Size = UDim2.new(0, sx(280), 0, sx(46)); mainBtn.BorderSizePixel = 0; mainBtn.Parent = actionRow
		Instance.new("UICorner", mainBtn).CornerRadius = UDim.new(0, sx(14))
		mainBtn.BackgroundColor3 = Color3.fromRGB(80, 220, 100)
		mainBtn.Text = "SACRIFICE FOR " .. formatNumber(cfg.gems) .. " GEMS"
		mainBtn.TextColor3 = Color3.new(1, 1, 1); mainBtn.Font = FONT; mainBtn.TextSize = sx(18)
		Instance.new("UIStroke", mainBtn).Color = Color3.fromRGB(50, 160, 65)
		UIHelper.AddPuffyGradient(mainBtn)
		local capOneTimeId = oneTimeId
		mainBtn.MouseButton1Click:Connect(function()
			showConfirmation("Sacrifice " .. need .. " " .. effectName .. " cards for " .. formatNumber(cfg.gems) .. " Gems?", function()
				SacrificeRequest:FireServer("OneTime", capOneTimeId)
			end)
		end)
	else
		local autoBtn = Instance.new("TextButton")
		autoBtn.Size = UDim2.new(0, sx(200), 0, sx(46)); autoBtn.BorderSizePixel = 0; autoBtn.Parent = actionRow
		Instance.new("UICorner", autoBtn).CornerRadius = UDim.new(0, sx(14))
		autoBtn.BackgroundColor3 = Color3.fromRGB(80, 160, 255)
		autoBtn.Text = "AUTO FILL"
		autoBtn.TextColor3 = Color3.new(1, 1, 1); autoBtn.Font = FONT; autoBtn.TextSize = sx(18)
		UIHelper.AddPuffyGradient(autoBtn)
		autoBtn.MouseButton1Click:Connect(function()
			requestQueueAutoFill(queueId, "effect", effectName, nil, need)
		end)

		local addBtn = Instance.new("TextButton")
		addBtn.Size = UDim2.new(0, sx(200), 0, sx(46)); addBtn.BorderSizePixel = 0; addBtn.Parent = actionRow
		Instance.new("UICorner", addBtn).CornerRadius = UDim.new(0, sx(14))
		addBtn.BackgroundColor3 = effectColor
		addBtn.Text = "PICK MANUALLY"
		addBtn.TextColor3 = Color3.new(1, 1, 1); addBtn.Font = FONT; addBtn.TextSize = sx(16)
		Instance.new("UIStroke", addBtn).Color = effectColor
		UIHelper.AddPuffyGradient(addBtn)
		addBtn.MouseButton1Click:Connect(function()
			showPicker("Pick a " .. effectName .. " streamer", function(itm)
				local eff = type(itm) == "table" and itm.effect or nil
				return eff == effectName
			end, queueId, nil)
		end)
	end

	if queued > 0 then
		local clrLink = Instance.new("TextButton")
		clrLink.Size = UDim2.new(0, sx(80), 0, sx(24))
		clrLink.BackgroundTransparency = 1; clrLink.Text = "Clear"
		clrLink.TextColor3 = Color3.fromRGB(200, 100, 100)
		clrLink.Font = FONT2; clrLink.TextSize = sx(14); clrLink.Parent = actionRow
		clrLink.MouseButton1Click:Connect(function()
			requestQueueClear(queueId)
		end)
	end
end

-- =========== ELEMENTAL CONTENT ===========
local function buildElementalContent(effectName)
	clearContent()
	local rarities = { "Common", "Rare", "Epic", "Legendary" }
	local rc = DesignConfig.RarityColors
	local effectInfo = effectName and Effects.ByName[effectName] or nil
	local displayName = effectName or "Default"
	local effectColor = effectInfo and effectInfo.color or Color3.fromRGB(170, 170, 170)

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, -sx(12), 0, sx(90))
	header.BackgroundColor3 = Color3.fromRGB(55, 45, 90); header.BorderSizePixel = 0; header.Parent = contentFrame
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, sx(18))
	Instance.new("UIStroke", header).Color = effectColor

	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.new(1, -sx(24), 0, sx(32)); tl.Position = UDim2.new(0.5, 0, 0, sx(10))
	tl.AnchorPoint = Vector2.new(0.5, 0); tl.BackgroundTransparency = 1
	tl.Text = displayName .. " Elemental"
	tl.TextColor3 = effectColor; tl.Font = FONT; tl.TextSize = sx(24); tl.Parent = header
	local ts = Instance.new("UIStroke", tl)
	ts.Color = Color3.new(0, 0, 0); ts.Thickness = 2; ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, -sx(24), 0, sx(36)); sub.Position = UDim2.new(0.5, 0, 0, sx(44))
	sub.AnchorPoint = Vector2.new(0.5, 0); sub.BackgroundTransparency = 1
	sub.Text = "Tap streamers to queue. Combine into one " .. displayName .. " streamer!"
	sub.TextColor3 = Color3.fromRGB(200, 190, 230); sub.Font = FONT; sub.TextSize = sx(14)
	sub.TextWrapped = true; sub.Parent = header

	-- Elemental has no sidebar tabs; we show all rarities in one view
	-- (Elemental was removed from sidebar tabs, so this is only reachable if re-added)
end

-------------------------------------------------
-- SIDEBAR + TAB DISPATCH
-------------------------------------------------

local function highlightRarityBtn(idx)
	activeGemRarity = idx
	for _, rb in ipairs(rarityBtns) do
		local isActive = rb.idx == idx
		local trade = Sacrifice.GemTrades[rb.idx]
		local rColor = trade and DesignConfig.RarityColors[trade.rarity] or Color3.new(1, 1, 1)
		rb.btn.BackgroundColor3 = isActive and rColor or Color3.fromRGB(40, 35, 65)
		local lbl = rb.btn:FindFirstChild("RarLbl")
		if lbl then lbl.TextColor3 = isActive and Color3.new(1, 1, 1) or rColor end
		local glbl = rb.btn:FindFirstChild("GemLbl")
		if glbl then glbl.TextColor3 = isActive and Color3.fromRGB(240, 240, 255) or Color3.fromRGB(140, 130, 170) end
	end
end

local function highlightSidebar(tabId)
	activeTabId = tabId
	for _, list in pairs(sidebarBtnLists) do
		for _, info in ipairs(list) do
			local isActive = info.id == tabId
			info.btn.BackgroundColor3 = isActive and Color3.fromRGB(70, 55, 110) or Color3.fromRGB(40, 35, 65)
			local lbl = info.btn:FindFirstChild("TabLabel")
			if lbl then lbl.TextSize = isActive and sx(18) or sx(16) end
		end
	end
end

local TAB_COLORS = {
	gems        = Color3.fromRGB(255, 100, 120),
	onetime     = Color3.fromRGB(180, 130, 255),
	elemOnetime = Color3.fromRGB(80, 220, 200),
}

local function switchTopTab(tab)
	activeTopTab = tab

	for key, btn in pairs(topTabBtns) do
		local isActive = key == tab
		btn.BackgroundColor3 = isActive and (TAB_COLORS[key] or Color3.new(1,1,1)) or Color3.fromRGB(50, 42, 80)
		btn.TextColor3 = isActive and Color3.new(1, 1, 1) or Color3.fromRGB(180, 160, 210)
	end

	for key, frame in pairs(sidebars) do
		frame.Visible = (key == tab)
	end
	if rarityBarFrame then rarityBarFrame.Visible = (tab == "gems") end

	if contentFrame then
		if tab == "gems" then
			contentFrame.Size = UDim2.new(1, -sx(22), 1, -sx(148))
			contentFrame.Position = UDim2.new(0, sx(10), 0, sx(142))
		else
			local sf = sidebars[tab]
			local sideW = sf and sf.Size.X.Offset or sx(220)
			contentFrame.Size = UDim2.new(1, -sideW - sx(22), 1, -sx(100))
			contentFrame.Position = UDim2.new(0, sideW + sx(14), 0, sx(92))
		end
	end

	closePicker()

	if tab == "gems" then
		local idx = activeGemRarity or 1
		highlightRarityBtn(idx)
		activeTabId = "GemTrade_" .. idx
		buildGemTradeContent(idx)
	else
		local btnList = sidebarBtnLists[tab]
		if btnList and btnList[1] then
			buildContent(btnList[1].id)
		end
	end
end

buildContent = function(tabId)
	highlightSidebar(tabId)
	closePicker()
	if tabId:sub(1, 8) == "GemTrade" then
		buildGemTradeContent(tonumber(tabId:sub(10)))
	elseif Sacrifice.OneTime[tabId] then
		buildOneTimeContent(tabId)
	end
end

-------------------------------------------------
-- OPEN / CLOSE
-------------------------------------------------

function SacrificeController.Open()
	if isOpen then SacrificeController.Close(); return end
	isOpen = true
	if modalFrame then
		modalFrame.Visible = true
		switchTopTab("gems")
		UIHelper.ScaleIn(modalFrame, 0.2)
	end
	for _, cb in ipairs(onOpenCallbacks) do task.spawn(cb) end
end

function SacrificeController.Close()
	if not isOpen then return end
	isOpen = false
	closePicker()
	if confirmFrame then confirmFrame:Destroy(); confirmFrame = nil end
	if modalFrame then UIHelper.ScaleOut(modalFrame, 0.2) end
	for _, cb in ipairs(onCloseCallbacks) do task.spawn(cb) end
end

function SacrificeController.IsOpen()
	return isOpen
end

-------------------------------------------------
-- INIT
-------------------------------------------------

function SacrificeController.Init()
	screenGui = UIHelper.CreateScreenGui("SacrificeGui", 8)
	screenGui.Parent = playerGui

	modalFrame = Instance.new("Frame")
	modalFrame.Name = "SacrificeModal"
	modalFrame.Size = UDim2.new(0, sx(960), 0, sx(680))
	modalFrame.Position = UDim2.new(0.5, 0, 0.5, 0); modalFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	modalFrame.BackgroundColor3 = BG; modalFrame.BorderSizePixel = 0
	modalFrame.Visible = false; modalFrame.ClipsDescendants = true; modalFrame.Parent = screenGui
	Instance.new("UICorner", modalFrame).CornerRadius = UDim.new(0, sx(28))
	local mStroke = Instance.new("UIStroke", modalFrame)
	mStroke.Color = ACCENT; mStroke.Thickness = 2.5; mStroke.Transparency = 0.1
	UIHelper.CreateShadow(modalFrame)
	UIHelper.MakeResponsiveModal(modalFrame, 960, 680)

	local bgGrad = Instance.new("UIGradient", modalFrame)
	bgGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(210, 200, 230)),
	})
	bgGrad.Rotation = 90

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(0.5, 0, 0, sx(38)); titleLbl.Position = UDim2.new(0, sx(18), 0, sx(10))
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text = "SACRIFICE"; titleLbl.TextColor3 = Color3.fromRGB(240, 220, 255)
	titleLbl.Font = FONT; titleLbl.TextSize = sx(30); titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.Parent = modalFrame
	local tts = Instance.new("UIStroke", titleLbl)
	tts.Color = Color3.fromRGB(30, 20, 50); tts.Thickness = 2; tts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, sx(46), 0, sx(46)); closeBtn.Position = UDim2.new(1, -sx(14), 0, sx(10))
	closeBtn.AnchorPoint = Vector2.new(1, 0); closeBtn.BackgroundColor3 = Color3.fromRGB(255, 90, 90)
	closeBtn.Text = "X"; closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = FONT; closeBtn.TextSize = sx(24); closeBtn.BorderSizePixel = 0; closeBtn.ZIndex = 10
	closeBtn.Parent = modalFrame
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1, 0)
	local ccStroke = Instance.new("UIStroke", closeBtn)
	ccStroke.Color = Color3.fromRGB(180, 50, 50); ccStroke.Thickness = 2
	closeBtn.MouseButton1Click:Connect(function() SacrificeController.Close() end)

	local topTabBar = Instance.new("Frame")
	topTabBar.Size = UDim2.new(1, -sx(20), 0, sx(36)); topTabBar.Position = UDim2.new(0.5, 0, 0, sx(54))
	topTabBar.AnchorPoint = Vector2.new(0.5, 0); topTabBar.BackgroundTransparency = 1
	topTabBar.BorderSizePixel = 0; topTabBar.Parent = modalFrame
	local ttLayout = Instance.new("UIListLayout", topTabBar)
	ttLayout.FillDirection = Enum.FillDirection.Horizontal; ttLayout.Padding = UDim.new(0, sx(6))
	ttLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local tabDefs = {
		{ key = "gems",        label = "Gems",           order = 1 },
		{ key = "onetime",     label = "One Time",       order = 2 },
		{ key = "elemOnetime", label = "Elem One Time",  order = 3 },
	}
	for _, def in ipairs(tabDefs) do
		local tab = Instance.new("TextButton")
		tab.Size = UDim2.new(0, sx(148), 0, sx(36))
		tab.BackgroundColor3 = Color3.fromRGB(50, 42, 80)
		tab.Text = def.label; tab.TextColor3 = Color3.fromRGB(180, 160, 210)
		tab.Font = FONT; tab.TextSize = sx(14); tab.BorderSizePixel = 0
		tab.LayoutOrder = def.order; tab.Parent = topTabBar
		Instance.new("UICorner", tab).CornerRadius = UDim.new(0, sx(10))
		local capKey = def.key
		tab.MouseButton1Click:Connect(function() switchTopTab(capKey) end)
		topTabBtns[def.key] = tab
	end

	rarityBarFrame = Instance.new("Frame")
	rarityBarFrame.Size = UDim2.new(1, -sx(24), 0, sx(42)); rarityBarFrame.Position = UDim2.new(0.5, 0, 0, sx(94))
	rarityBarFrame.AnchorPoint = Vector2.new(0.5, 0); rarityBarFrame.BackgroundTransparency = 1
	rarityBarFrame.BorderSizePixel = 0; rarityBarFrame.Parent = modalFrame
	local rbLayout = Instance.new("UIListLayout", rarityBarFrame)
	rbLayout.FillDirection = Enum.FillDirection.Horizontal; rbLayout.Padding = UDim.new(0, sx(8))
	rbLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center; rbLayout.VerticalAlignment = Enum.VerticalAlignment.Center

	rarityBtns = {}
	for i, trade in ipairs(Sacrifice.GemTrades) do
		local rColor = DesignConfig.RarityColors[trade.rarity] or Color3.new(1, 1, 1)
		local rbtn = Instance.new("TextButton")
		rbtn.Size = UDim2.new(0, sx(170), 0, sx(40)); rbtn.BackgroundColor3 = Color3.fromRGB(40, 35, 65)
		rbtn.BorderSizePixel = 0; rbtn.Text = ""; rbtn.Parent = rarityBarFrame
		Instance.new("UICorner", rbtn).CornerRadius = UDim.new(0, sx(12))
		local rbStroke = Instance.new("UIStroke", rbtn); rbStroke.Color = rColor; rbStroke.Thickness = 1.5; rbStroke.Transparency = 0.4

		local rlbl = Instance.new("TextLabel")
		rlbl.Name = "RarLbl"; rlbl.Size = UDim2.new(0.55, 0, 1, 0); rlbl.Position = UDim2.new(0, sx(10), 0, 0)
		rlbl.BackgroundTransparency = 1; rlbl.Text = trade.rarity
		rlbl.TextColor3 = rColor; rlbl.Font = FONT; rlbl.TextSize = sx(15)
		rlbl.TextXAlignment = Enum.TextXAlignment.Left; rlbl.Parent = rbtn

		local glbl = Instance.new("TextLabel")
		glbl.Name = "GemLbl"; glbl.Size = UDim2.new(0.4, 0, 1, 0); glbl.Position = UDim2.new(1, -sx(10), 0, 0)
		glbl.AnchorPoint = Vector2.new(1, 0); glbl.BackgroundTransparency = 1
		glbl.Text = formatNumber(trade.gems); glbl.TextColor3 = Color3.fromRGB(140, 130, 170)
		glbl.Font = FONT; glbl.TextSize = sx(14); glbl.TextXAlignment = Enum.TextXAlignment.Right; glbl.Parent = rbtn

		local capIdx = i
		rbtn.MouseButton1Click:Connect(function()
			highlightRarityBtn(capIdx)
			activeTabId = "GemTrade_" .. capIdx
			buildGemTradeContent(capIdx)
		end)
		table.insert(rarityBtns, { btn = rbtn, idx = i })
	end

	local sidebarWidth = sx(220)
	local function makeSidebar(name)
		local sf = Instance.new("ScrollingFrame")
		sf.Name = name; sf.Size = UDim2.new(0, sidebarWidth, 1, -sx(96))
		sf.Position = UDim2.new(0, sx(6), 0, sx(92))
		sf.BackgroundColor3 = Color3.fromRGB(35, 28, 60); sf.BackgroundTransparency = 0.35
		sf.BorderSizePixel = 0; sf.ScrollBarThickness = sx(5); sf.ScrollBarImageColor3 = ACCENT
		sf.CanvasSize = UDim2.new(0, 0, 0, 0); sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
		sf.Visible = false; sf.Parent = modalFrame
		Instance.new("UICorner", sf).CornerRadius = UDim.new(0, sx(16))
		local ll = Instance.new("UIListLayout", sf); ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Padding = UDim.new(0, sx(5))
		local pd = Instance.new("UIPadding", sf)
		pd.PaddingTop = UDim.new(0, sx(10)); pd.PaddingLeft = UDim.new(0, sx(8))
		pd.PaddingRight = UDim.new(0, sx(8)); pd.PaddingBottom = UDim.new(0, sx(14))
		return sf
	end

	local function addTabTo(sidebarKey, sf, id, name, color, order)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 0, sx(40)); btn.BackgroundColor3 = Color3.fromRGB(40, 35, 65)
		btn.BorderSizePixel = 0; btn.LayoutOrder = order; btn.Text = ""; btn.Parent = sf
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, sx(12))
		local strip = Instance.new("Frame")
		strip.Size = UDim2.new(0, sx(5), 0.6, 0); strip.Position = UDim2.new(0, sx(5), 0.2, 0)
		strip.BackgroundColor3 = color; strip.BorderSizePixel = 0; strip.Parent = btn
		Instance.new("UICorner", strip).CornerRadius = UDim.new(0, 3)
		local lbl = Instance.new("TextLabel")
		lbl.Name = "TabLabel"; lbl.Size = UDim2.new(1, -sx(20), 1, 0); lbl.Position = UDim2.new(0, sx(16), 0, 0)
		lbl.BackgroundTransparency = 1; lbl.Text = name; lbl.TextColor3 = color
		lbl.Font = FONT; lbl.TextSize = sx(14); lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.TextTruncate = Enum.TextTruncate.AtEnd; lbl.Parent = btn
		local tabStroke = Instance.new("UIStroke", lbl)
		tabStroke.Color = Color3.fromRGB(15, 10, 30); tabStroke.Thickness = 1; tabStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		btn.MouseButton1Click:Connect(function() buildContent(id) end)
		table.insert(sidebarBtnLists[sidebarKey], { id = id, btn = btn })
	end

	local otSidebar = makeSidebar("OnetimeSidebar")
	sidebars.onetime = otSidebar
	local otTabs = {
		{ "CommonArmy",      "Common Army",      Color3.fromRGB(160, 160, 190) },
		{ "FatPeople",       "Fat People",       Color3.fromRGB(255, 200, 60)  },
		{ "GirlPower",       "Girl Power",       Color3.fromRGB(255, 130, 200) },
		{ "RareRoundup",     "Rare Roundup",     Color3.fromRGB(80, 180, 255)  },
		{ "ContentHouse",    "Content House",    Color3.fromRGB(255, 150, 80)  },
		{ "EpicEnsemble",    "Epic Ensemble",    Color3.fromRGB(200, 80, 220)  },
		{ "GamblingAddicts", "Gambling Addicts",  Color3.fromRGB(60, 220, 60)  },
		{ "TheOGs",          "The OGs",          Color3.fromRGB(180, 180, 180) },
		{ "FPSLegends",      "FPS Legends",      Color3.fromRGB(255, 80, 80)  },
		{ "TwitchRoyalty",   "Twitch Royalty",    Color3.fromRGB(180, 120, 255)},
		{ "TheUntouchables", "The Untouchables",  Color3.fromRGB(255, 50, 50) },
		{ "Rainbow",         "Rainbow",          Color3.fromRGB(120, 255, 200) },
		{ "MythicRoyale",    "Mythic Royale",    Color3.fromRGB(255, 215, 0)   },
	}
	for i, t in ipairs(otTabs) do addTabTo("onetime", otSidebar, t[1], t[2], t[3], i) end

	local eoSidebar = makeSidebar("ElemOnetimeSidebar")
	sidebars.elemOnetime = eoSidebar
	local eoTabs = {
		{ "AcidReflex",       "Acid Reflex",       Color3.fromRGB(50, 255, 50)   },
		{ "SnowyAvalanche",   "Snowy Avalanche",   Color3.fromRGB(180, 220, 255) },
		{ "LavaEruption",     "Lava Eruption",     Color3.fromRGB(255, 100, 20)  },
		{ "LightningStrike",  "Lightning Strike",  Color3.fromRGB(255, 255, 80)  },
		{ "ShadowRealm",      "Shadow Realm",      Color3.fromRGB(100, 60, 140)  },
		{ "GlitchStorm",      "Glitch Storm",      Color3.fromRGB(0, 255, 255)   },
		{ "LunarTide",        "Lunar Tide",        Color3.fromRGB(200, 220, 255) },
		{ "SolarFlare",       "Solar Flare",       Color3.fromRGB(255, 220, 60)  },
		{ "VoidAbyss",        "Void Abyss",        Color3.fromRGB(80, 40, 120)   },
	}
	for i, t in ipairs(eoTabs) do addTabTo("elemOnetime", eoSidebar, t[1], t[2], t[3], i) end

	contentFrame = Instance.new("ScrollingFrame")
	contentFrame.Name = "Content"
	contentFrame.Size = UDim2.new(1, -sx(22), 1, -sx(148))
	contentFrame.Position = UDim2.new(0, sx(10), 0, sx(142))
	contentFrame.BackgroundTransparency = 1; contentFrame.BorderSizePixel = 0
	contentFrame.ScrollBarThickness = sx(6); contentFrame.ScrollBarImageColor3 = ACCENT
	contentFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	contentFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y; contentFrame.Parent = modalFrame

	local cl = Instance.new("UIListLayout", contentFrame)
	cl.SortOrder = Enum.SortOrder.LayoutOrder; cl.Padding = UDim.new(0, sx(12))
	cl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	Instance.new("UIPadding", contentFrame).PaddingTop = UDim.new(0, sx(8))
	contentFrame:FindFirstChildOfClass("UIPadding").PaddingBottom = UDim.new(0, sx(16))

	OpenSacrificeGui.OnClientEvent:Connect(function()
		local TutorialController = require(script.Parent.TutorialController)
		if TutorialController.IsActive() then return end
		if isOpen then SacrificeController.Close() else SacrificeController.Open() end
	end)

	SacrificeResult.OnClientEvent:Connect(function(result)
		if result.success then
			if result.action then
				if result.action == "queueAutoFill" and result.added then
					if result.added > 0 then
						showToast("Added " .. result.added .. " streamer" .. (result.added > 1 and "s" or "") .. " to queue!", Color3.fromRGB(80, 160, 255), 2)
					else
						showToast("No matching streamers found!", Color3.fromRGB(200, 160, 80), 2)
					end
				end
				if isOpen and activeTabId then buildContent(activeTabId) end
				fireQueueChanged()
				return
			end

			local msg, c = "Sacrifice complete!", Color3.fromRGB(60, 200, 80)
			if result.sacrificeType == "GemTrade" then
				msg = "+" .. formatNumber(result.gems or 0) .. " Gems!"
			elseif result.sacrificeType == "OneTime" then
				msg = "+" .. formatNumber(result.gems or 0) .. " Gems! One-time complete!"
			elseif result.sacrificeType == "Elemental" then
				msg = "Got " .. (result.effect or "Default") .. " " .. (result.streamerId or "") .. "!"
			end
			showToast(msg, c, 3.5)
		else
			if result.action then
				showToast(result.reason or "Failed!", Color3.fromRGB(200, 50, 50), 3)
				return
			end
			showToast(result.reason or "Failed!", Color3.fromRGB(200, 50, 50), 3)
		end
		task.defer(function() task.wait(0.3); if isOpen and activeTabId then buildContent(activeTabId) end end)
		fireQueueChanged()
	end)

	HUDController.OnDataUpdated(function()
		if isOpen and activeTabId and not pickerFrame then buildContent(activeTabId) end
		fireQueueChanged()
	end)

	local InventoryCtrl = require(script.Parent.InventoryController)
	local StorageCtrl = require(script.Parent.StorageController)
	SacrificeController.OnQueueChanged(function()
		if InventoryCtrl and InventoryCtrl.RefreshVisuals then InventoryCtrl.RefreshVisuals() end
		if StorageCtrl and StorageCtrl.Refresh then StorageCtrl.Refresh() end
	end)

	modalFrame.Visible = false
end

function SacrificeController.GetQueuedIndices()
	return {}
end

function SacrificeController.OnQueueChanged(cb)
	table.insert(onQueueChanged, cb)
end

function SacrificeController.OnOpen(cb)
	table.insert(onOpenCallbacks, cb)
end
function SacrificeController.OnClose(cb)
	table.insert(onCloseCallbacks, cb)
end

return SacrificeController
