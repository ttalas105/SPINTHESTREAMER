--[[
	SacrificeController.lua
	Sacrifice UI — GemShop-style sidebar + content.
	Players pick EXACT streamers from their inventory to queue.
	Queues persist across close/reopen. Players can remove any time.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")

local Sacrifice    = require(ReplicatedStorage.Shared.Config.Sacrifice)
local Streamers    = require(ReplicatedStorage.Shared.Config.Streamers)
local Effects      = require(ReplicatedStorage.Shared.Config.Effects)
local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local UIHelper     = require(script.Parent.UIHelper)
local HUDController = require(script.Parent.HUDController)

local SacrificeController = {}

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RemoteEvents     = ReplicatedStorage:WaitForChild("RemoteEvents")
local OpenSacrificeGui = RemoteEvents:WaitForChild("OpenSacrificeGui")
local SacrificeRequest = RemoteEvents:WaitForChild("SacrificeRequest")
local SacrificeResult  = RemoteEvents:WaitForChild("SacrificeResult")

local screenGui, modalFrame
local contentFrame
local isOpen       = false
local sidebarBtns  = {}
local activeTabId  = nil
local confirmFrame = nil
local pickerFrame  = nil

local FONT   = Enum.Font.FredokaOne
local FONT2  = Enum.Font.GothamBold
local BG     = Color3.fromRGB(14, 12, 28)
local ACCENT = Color3.fromRGB(180, 60, 80)

-------------------------------------------------
-- PERSISTENT QUEUES (survive close/reopen)
-- Gem/Elemental: set of inventory indices { [invIdx] = true }
-- OneTime: map of slot keys to inventory indices { ["1_1"] = invIdx }
-------------------------------------------------
local gemTradeQueues = {}      -- { [tradeIndex] = { [invIdx]=true } }
local oneTimeQueues  = {}      -- { [oneTimeId] = { [slotKey]=invIdx } }
local elementalQueues = {}     -- { ["effect_rarity"] = { [invIdx]=true } }
local effectOneTimeQueues = {} -- { [oneTimeId] = { [invIdx]=true } } for effect-based one-time sacrifices

-- Set of ALL indices currently queued across all queues (for exclusion)
local function allQueuedIndices()
	local s = {}
	for _, q in pairs(gemTradeQueues) do
		for idx in pairs(q) do s[idx] = true end
	end
	for _, q in pairs(oneTimeQueues) do
		for _, idx in pairs(q) do if idx then s[idx] = true end end
	end
	for _, q in pairs(elementalQueues) do
		for idx in pairs(q) do s[idx] = true end
	end
	for _, q in pairs(effectOneTimeQueues) do
		for idx in pairs(q) do s[idx] = true end
	end
	return s
end

-- Resolve a virtual index to an item (hotbar < 1000, storage >= 1001)
local function resolveVirtualItem(vi)
	if vi > 1000 then
		local sto = HUDController.Data.storage or {}
		return sto[vi - 1000]
	else
		local inv = HUDController.Data.inventory or {}
		return inv[vi]
	end
end

-- Validate a queue set: remove indices that no longer match the filter
local function validateQueueSet(queueSet, matchFn)
	local bad = {}
	for vi in pairs(queueSet) do
		local item = resolveVirtualItem(vi)
		if not item or not matchFn(item) then bad[vi] = true end
	end
	for vi in pairs(bad) do queueSet[vi] = nil end
end

local function validateOneTimeQueue(queueMap, reqList)
	for key, vi in pairs(queueMap) do
		local item = resolveVirtualItem(vi)
		if not item then queueMap[key] = nil end
	end
end

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

local function formatTime(sec)
	if sec == nil or sec <= 0 then return "Ready" end
	local m = math.ceil(sec / 60)
	if m <= 1 then return "<1 min" end
	return m .. " min"
end

local function getItemInfo(item)
	local id = type(item) == "table" and item.id or item
	local effect = type(item) == "table" and item.effect or nil
	local info = Streamers.ById[id]
	return id, effect, info
end

local function queueSetCount(qs)
	local n = 0
	for _ in pairs(qs) do n = n + 1 end
	return n
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
	box.Size = UDim2.new(0, 440, 0, 220); box.Position = UDim2.new(0.5, 0, 0.5, 0)
	box.AnchorPoint = Vector2.new(0.5, 0.5); box.BackgroundColor3 = Color3.fromRGB(28, 26, 50)
	box.BorderSizePixel = 0; box.ZIndex = 51; box.Parent = dim
	Instance.new("UICorner", box).CornerRadius = UDim.new(0, 20)
	local bs = Instance.new("UIStroke", box); bs.Color = ACCENT; bs.Thickness = 3

	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1, -30, 0, 34); t.Position = UDim2.new(0.5, 0, 0, 16)
	t.AnchorPoint = Vector2.new(0.5, 0); t.BackgroundTransparency = 1
	t.Text = "Are you sure?"; t.TextColor3 = Color3.fromRGB(255, 200, 100)
	t.Font = FONT; t.TextSize = 26; t.ZIndex = 52; t.Parent = box

	local ml = Instance.new("TextLabel")
	ml.Size = UDim2.new(1, -36, 0, 70); ml.Position = UDim2.new(0.5, 0, 0, 56)
	ml.AnchorPoint = Vector2.new(0.5, 0); ml.BackgroundTransparency = 1
	ml.Text = message; ml.TextColor3 = Color3.fromRGB(200, 200, 220)
	ml.Font = FONT2; ml.TextSize = 15; ml.TextWrapped = true; ml.ZIndex = 52; ml.Parent = box

	local function dismiss() if dim.Parent then dim:Destroy() end; confirmFrame = nil end
	dim.MouseButton1Click:Connect(dismiss)

	local yb = Instance.new("TextButton")
	yb.Size = UDim2.new(0, 160, 0, 46); yb.Position = UDim2.new(0.5, -86, 1, -24)
	yb.AnchorPoint = Vector2.new(1, 1); yb.BackgroundColor3 = Color3.fromRGB(60, 180, 80)
	yb.Text = "YES, DO IT"; yb.TextColor3 = Color3.new(1, 1, 1)
	yb.Font = FONT; yb.TextSize = 16; yb.BorderSizePixel = 0; yb.ZIndex = 52; yb.Parent = box
	Instance.new("UICorner", yb).CornerRadius = UDim.new(0, 12)
	yb.MouseButton1Click:Connect(function() dismiss(); if onYes then onYes() end end)

	local nb = Instance.new("TextButton")
	nb.Size = UDim2.new(0, 160, 0, 46); nb.Position = UDim2.new(0.5, 86, 1, -24)
	nb.AnchorPoint = Vector2.new(0, 1); nb.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	nb.Text = "CANCEL"; nb.TextColor3 = Color3.new(1, 1, 1)
	nb.Font = FONT; nb.TextSize = 16; nb.BorderSizePixel = 0; nb.ZIndex = 52; nb.Parent = box
	Instance.new("UICorner", nb).CornerRadius = UDim.new(0, 12)
	nb.MouseButton1Click:Connect(dismiss)

	confirmFrame = dim
	box.Size = UDim2.new(0, 220, 0, 110)
	TweenService:Create(box, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 440, 0, 220),
	}):Play()
end

-------------------------------------------------
-- TOAST
-------------------------------------------------

local function showToast(text, color, dur)
	color = color or Color3.fromRGB(60, 200, 80); dur = dur or 3
	local toast = Instance.new("Frame")
	toast.Size = UDim2.new(0.55, 0, 0, 50); toast.Position = UDim2.new(0.5, 0, 0, -58)
	toast.AnchorPoint = Vector2.new(0.5, 0); toast.BackgroundColor3 = color
	toast.BorderSizePixel = 0; toast.ZIndex = 60; toast.Parent = modalFrame
	Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 14)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -20, 1, 0); lbl.Position = UDim2.new(0.5, 0, 0.5, 0)
	lbl.AnchorPoint = Vector2.new(0.5, 0.5); lbl.BackgroundTransparency = 1
	lbl.Text = text; lbl.TextColor3 = Color3.new(1, 1, 1)
	lbl.Font = FONT; lbl.TextSize = 16; lbl.TextWrapped = true; lbl.ZIndex = 61; lbl.Parent = toast
	TweenService:Create(toast, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 8),
	}):Play()
	task.delay(dur, function()
		if not toast.Parent then return end
		TweenService:Create(toast, TweenInfo.new(0.2), { Position = UDim2.new(0.5, 0, 0, -58) }):Play()
		task.delay(0.25, function() if toast.Parent then toast:Destroy() end end)
	end)
end

-------------------------------------------------
-- PICKER POPUP (for one-time: pick a specific streamer)
-------------------------------------------------

local function closePicker()
	if pickerFrame then pickerFrame:Destroy(); pickerFrame = nil end
end

local STORAGE_OFFSET = 1000

--- Build a combined list of {vi, item, source} from hotbar + storage for sacrifice UI
local function getCombinedItems()
	local inv = HUDController.Data.inventory or {}
	local sto = HUDController.Data.storage or {}
	local combined = {}
	for i, item in ipairs(inv) do
		table.insert(combined, { vi = i, item = item, source = "hotbar" })
	end
	for i, item in ipairs(sto) do
		table.insert(combined, { vi = STORAGE_OFFSET + i, item = item, source = "storage" })
	end
	return combined
end

local function showPicker(title, filterFn, excludeSet, onSelect)
	closePicker()
	local combined = getCombinedItems()
	local eligible = {}
	for _, entry in ipairs(combined) do
		if filterFn(entry.item) and not (excludeSet and excludeSet[entry.vi]) then
			table.insert(eligible, entry)
		end
	end

	local dim = Instance.new("TextButton")
	dim.Size = UDim2.new(1, 0, 1, 0); dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.35; dim.Text = ""; dim.ZIndex = 40
	dim.BorderSizePixel = 0; dim.Parent = modalFrame
	dim.MouseButton1Click:Connect(closePicker)

	local popup = Instance.new("Frame")
	popup.Size = UDim2.new(0, 480, 0, 380)
	popup.Position = UDim2.new(0.5, 0, 0.5, 0); popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.BackgroundColor3 = Color3.fromRGB(20, 18, 38); popup.BorderSizePixel = 0; popup.ZIndex = 41
	popup.ClipsDescendants = true; popup.Parent = dim
	Instance.new("UICorner", popup).CornerRadius = UDim.new(0, 18)
	local ps = Instance.new("UIStroke", popup); ps.Color = Color3.fromRGB(255, 200, 60); ps.Thickness = 2.5

	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.new(1, -60, 0, 36); tl.Position = UDim2.new(0.5, 0, 0, 10)
	tl.AnchorPoint = Vector2.new(0.5, 0); tl.BackgroundTransparency = 1
	tl.Text = title; tl.TextColor3 = Color3.fromRGB(255, 220, 100)
	tl.Font = FONT; tl.TextSize = 22; tl.ZIndex = 42; tl.Parent = popup

	local cb = Instance.new("TextButton")
	cb.Size = UDim2.new(0, 36, 0, 36); cb.Position = UDim2.new(1, -10, 0, 8)
	cb.AnchorPoint = Vector2.new(1, 0); cb.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	cb.Text = "X"; cb.TextColor3 = Color3.new(1, 1, 1); cb.Font = FONT; cb.TextSize = 18
	cb.BorderSizePixel = 0; cb.ZIndex = 43; cb.Parent = popup
	Instance.new("UICorner", cb).CornerRadius = UDim.new(1, 0)
	cb.MouseButton1Click:Connect(closePicker)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -12, 1, -56); scroll.Position = UDim2.new(0, 6, 0, 50)
	scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4; scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; scroll.ZIndex = 42; scroll.Parent = popup

	local grid = Instance.new("UIGridLayout", scroll)
	grid.CellSize = UDim2.new(0, 100, 0, 72); grid.CellPadding = UDim2.new(0, 8, 0, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder

	local sp = Instance.new("UIPadding", scroll)
	sp.PaddingLeft = UDim.new(0, 6); sp.PaddingTop = UDim.new(0, 4)

	if #eligible == 0 then
		local nl = Instance.new("TextLabel")
		nl.Size = UDim2.new(1, 0, 0, 60); nl.BackgroundTransparency = 1
		nl.Text = "No eligible streamers!"; nl.TextColor3 = Color3.fromRGB(150, 150, 170)
		nl.Font = FONT; nl.TextSize = 16; nl.ZIndex = 42; nl.Parent = scroll
	end

	for order, entry in ipairs(eligible) do
		local item = entry.item
		local vi = entry.vi
		local id, eff, info = getItemInfo(item)
		local rColor = DesignConfig.RarityColors[info and info.rarity or "Common"] or Color3.new(1, 1, 1)
		local isStorage = vi > STORAGE_OFFSET

		local cell = Instance.new("TextButton")
		cell.Size = UDim2.new(0, 100, 0, 72)
		cell.BackgroundColor3 = Color3.fromRGB(30, 28, 50); cell.BorderSizePixel = 0
		cell.Text = ""; cell.LayoutOrder = order; cell.ZIndex = 42; cell.Parent = scroll
		Instance.new("UICorner", cell).CornerRadius = UDim.new(0, 10)
		local cs = Instance.new("UIStroke", cell); cs.Color = rColor; cs.Thickness = 1.5; cs.Transparency = 0.3

		-- Storage indicator
		if isStorage then
			local si = Instance.new("TextLabel")
			si.Size = UDim2.new(0, 14, 0, 10); si.Position = UDim2.new(1, -2, 0, 2)
			si.AnchorPoint = Vector2.new(1, 0); si.BackgroundTransparency = 1
			si.Text = "S"; si.TextColor3 = Color3.fromRGB(255, 165, 50)
			si.Font = Enum.Font.GothamBold; si.TextSize = 8; si.ZIndex = 43; si.Parent = cell
		end

		local nl2 = Instance.new("TextLabel")
		nl2.Size = UDim2.new(1, -6, 0, 22); nl2.Position = UDim2.new(0.5, 0, 0, 8)
		nl2.AnchorPoint = Vector2.new(0.5, 0); nl2.BackgroundTransparency = 1
		nl2.Text = id; nl2.TextColor3 = rColor
		nl2.Font = FONT; nl2.TextSize = 12; nl2.TextTruncate = Enum.TextTruncate.AtEnd
		nl2.ZIndex = 43; nl2.Parent = cell

		if eff then
			local el = Instance.new("TextLabel")
			el.Size = UDim2.new(1, -6, 0, 16); el.Position = UDim2.new(0.5, 0, 0, 30)
			el.AnchorPoint = Vector2.new(0.5, 0); el.BackgroundTransparency = 1
			el.Text = eff; el.TextColor3 = (Effects.ByName[eff] and Effects.ByName[eff].color) or Color3.fromRGB(180, 180, 180)
			el.Font = FONT2; el.TextSize = 10; el.ZIndex = 43; el.Parent = cell
		end

		local rl = Instance.new("TextLabel")
		rl.Size = UDim2.new(1, 0, 0, 16); rl.Position = UDim2.new(0.5, 0, 1, -20)
		rl.AnchorPoint = Vector2.new(0.5, 0); rl.BackgroundTransparency = 1
		rl.Text = info and info.rarity or "?"; rl.TextColor3 = rColor
		rl.Font = FONT2; rl.TextSize = 10; rl.ZIndex = 43; rl.Parent = cell

		local capturedVI = vi
		cell.MouseButton1Click:Connect(function()
			closePicker()
			if onSelect then onSelect(capturedVI) end
		end)
	end

	pickerFrame = dim
	UIHelper.ScaleIn(popup, 0.15)
end

-------------------------------------------------
-- BINARY SPIN ANIMATION (for 50/50, Feeling Lucky, Don't Do It)
-- Unskippable! Green = good, Red = bad.
-------------------------------------------------

local binarySpinOverlay = nil
local binaryAnimConn = nil

local function easeOutQuint(t)
	local t1 = 1 - t
	return 1 - t1 * t1 * t1 * t1 * t1
end

local function cleanupBinarySpin()
	if binarySpinOverlay then binarySpinOverlay:Destroy(); binarySpinOverlay = nil end
	if binaryAnimConn then binaryAnimConn:Disconnect(); binaryAnimConn = nil end
end

local function showBinarySpin(goodText, badText, isGood, goodEmoji, badEmoji, onComplete)
	cleanupBinarySpin()

	local GOOD_COLOR = Color3.fromRGB(40, 180, 60)
	local BAD_COLOR = Color3.fromRGB(200, 50, 50)
	local CARD_W, CARD_H, CARD_GAP = 150, 100, 6
	local CARD_STEP = CARD_W + CARD_GAP
	local DURATION = 4.5
	local TOTAL = 50

	-- winIdx: odd = good card, even = bad card
	local winIdx = math.floor(TOTAL * 0.72)
	if isGood and winIdx % 2 == 0 then winIdx = winIdx + 1 end
	if not isGood and winIdx % 2 == 1 then winIdx = winIdx + 1 end
	if winIdx > TOTAL then winIdx = TOTAL - 1 end

	-- Fullscreen overlay (high ZIndex, covers everything)
	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.2
	overlay.BorderSizePixel = 0; overlay.ZIndex = 70
	overlay.Parent = screenGui

	-- Title
	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, 0, 0, 50)
	titleLbl.Position = UDim2.new(0.5, 0, 0.18, 0)
	titleLbl.AnchorPoint = Vector2.new(0.5, 0.5)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text = "SPINNING..."
	titleLbl.TextColor3 = Color3.fromRGB(255, 220, 80)
	titleLbl.Font = FONT; titleLbl.TextSize = 36; titleLbl.ZIndex = 71
	titleLbl.Parent = overlay
	local tStk = Instance.new("UIStroke", titleLbl)
	tStk.Color = Color3.new(0, 0, 0); tStk.Thickness = 3
	tStk.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	-- Strip window
	local stripWin = Instance.new("Frame")
	stripWin.Size = UDim2.new(0.75, 0, 0, CARD_H + 24)
	stripWin.Position = UDim2.new(0.5, 0, 0.45, 0)
	stripWin.AnchorPoint = Vector2.new(0.5, 0.5)
	stripWin.BackgroundColor3 = Color3.fromRGB(8, 8, 18)
	stripWin.BorderSizePixel = 0; stripWin.ClipsDescendants = true
	stripWin.ZIndex = 71; stripWin.Parent = overlay
	Instance.new("UICorner", stripWin).CornerRadius = UDim.new(0, 14)
	local wStk = Instance.new("UIStroke", stripWin)
	wStk.Color = Color3.fromRGB(255, 200, 60); wStk.Thickness = 3

	-- Inner strip
	local strip = Instance.new("Frame")
	strip.BackgroundTransparency = 1; strip.BorderSizePixel = 0
	strip.Size = UDim2.new(0, TOTAL * CARD_STEP, 1, 0)
	strip.ZIndex = 72; strip.Parent = stripWin

	-- Build alternating green/red cards
	for i = 1, TOTAL do
		local isGoodCard = (i % 2 == 1)
		local cardColor = isGoodCard and GOOD_COLOR or BAD_COLOR
		local cardText = isGoodCard and goodText or badText
		local cardEmoji = isGoodCard and (goodEmoji or "\u{2714}") or (badEmoji or "\u{2716}")

		local card = Instance.new("Frame")
		card.Name = "C" .. i
		card.Size = UDim2.new(0, CARD_W, 0, CARD_H)
		card.Position = UDim2.new(0, (i - 1) * CARD_STEP, 0.5, 0)
		card.AnchorPoint = Vector2.new(0, 0.5)
		card.BackgroundColor3 = cardColor
		card.BorderSizePixel = 0; card.ZIndex = 72; card.Parent = strip
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

		-- Gradient for depth
		local cg = Instance.new("UIGradient", card)
		cg.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 30, 30)),
		})
		cg.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(1, 0),
		})
		cg.Rotation = 90

		-- Stroke
		local cs = Instance.new("UIStroke", card)
		cs.Color = isGoodCard and Color3.fromRGB(100, 255, 120) or Color3.fromRGB(255, 100, 100)
		cs.Thickness = 2; cs.Transparency = 0.3

		-- Emoji
		local el = Instance.new("TextLabel")
		el.Size = UDim2.new(1, 0, 0, 32)
		el.Position = UDim2.new(0.5, 0, 0, 8)
		el.AnchorPoint = Vector2.new(0.5, 0)
		el.BackgroundTransparency = 1
		el.Text = cardEmoji; el.TextColor3 = Color3.new(1, 1, 1)
		el.Font = Enum.Font.SourceSans; el.TextSize = 30
		el.ZIndex = 73; el.Parent = card

		-- Text
		local tl = Instance.new("TextLabel")
		tl.Size = UDim2.new(1, -10, 0, 42)
		tl.Position = UDim2.new(0.5, 0, 0, 42)
		tl.AnchorPoint = Vector2.new(0.5, 0)
		tl.BackgroundTransparency = 1
		tl.Text = cardText; tl.TextColor3 = Color3.new(1, 1, 1)
		tl.Font = FONT; tl.TextSize = 16; tl.TextWrapped = true
		tl.ZIndex = 73; tl.Parent = card
		local ns = Instance.new("UIStroke", tl)
		ns.Color = Color3.new(0, 0, 0); ns.Thickness = 1.5
		ns.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	end

	-- Center selector (golden)
	local sel = Instance.new("Frame")
	sel.Size = UDim2.new(0, 3, 1, 10)
	sel.Position = UDim2.new(0.5, 0, 0.5, 0)
	sel.AnchorPoint = Vector2.new(0.5, 0.5)
	sel.BackgroundColor3 = Color3.fromRGB(255, 220, 60)
	sel.BorderSizePixel = 0; sel.ZIndex = 75; sel.Parent = stripWin
	Instance.new("UIStroke", sel).Color = Color3.fromRGB(255, 255, 100)

	-- Arrows
	local topArr = Instance.new("TextLabel")
	topArr.Size = UDim2.new(0, 30, 0, 22)
	topArr.Position = UDim2.new(0.5, 0, 0, -2)
	topArr.AnchorPoint = Vector2.new(0.5, 0)
	topArr.BackgroundTransparency = 1; topArr.Text = "\u{25BC}"
	topArr.TextColor3 = Color3.fromRGB(255, 220, 60)
	topArr.Font = Enum.Font.GothamBold; topArr.TextSize = 22
	topArr.ZIndex = 75; topArr.Parent = stripWin

	local botArr = Instance.new("TextLabel")
	botArr.Size = UDim2.new(0, 30, 0, 22)
	botArr.Position = UDim2.new(0.5, 0, 1, 2)
	botArr.AnchorPoint = Vector2.new(0.5, 1)
	botArr.BackgroundTransparency = 1; botArr.Text = "\u{25B2}"
	botArr.TextColor3 = Color3.fromRGB(255, 220, 60)
	botArr.Font = Enum.Font.GothamBold; botArr.TextSize = 22
	botArr.ZIndex = 75; botArr.Parent = stripWin

	-- Dark edge fades
	for _, side in ipairs({"Left", "Right"}) do
		local fade = Instance.new("Frame")
		fade.Size = UDim2.new(0, 80, 1, 0)
		fade.Position = side == "Left" and UDim2.new(0, 0, 0, 0) or UDim2.new(1, -80, 0, 0)
		fade.BackgroundColor3 = Color3.fromRGB(8, 8, 18)
		fade.BorderSizePixel = 0; fade.ZIndex = 74; fade.Parent = stripWin
		local ug = Instance.new("UIGradient", fade)
		ug.Transparency = side == "Left"
			and NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1)})
			or  NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0)})
	end

	binarySpinOverlay = overlay

	-- Calculate animation
	local frameWidth = stripWin.AbsoluteSize.X
	if frameWidth == 0 then frameWidth = 600 end
	local halfFrame = frameWidth / 2
	local targetCenterX = (winIdx - 1) * CARD_STEP + CARD_W / 2
	local endX = halfFrame - targetCenterX + math.random(-10, 10)
	local startX = endX + 20 * CARD_STEP

	strip.Position = UDim2.new(0, startX, 0, 0)

	local totalDist = startX - endX
	local startTime = tick()
	local done = false

	-- NOT skippable — the animation MUST play out
	binaryAnimConn = RunService.RenderStepped:Connect(function()
		local t = (tick() - startTime) / DURATION
		if t >= 1 then t = 1 end
		local eased = easeOutQuint(t)
		strip.Position = UDim2.new(0, startX - totalDist * eased, 0, 0)

		if t >= 1 and not done then
			done = true
			binaryAnimConn:Disconnect(); binaryAnimConn = nil

			-- Full-screen colour flash
			local winColor = isGood and GOOD_COLOR or BAD_COLOR
			local flash = Instance.new("Frame")
			flash.Size = UDim2.new(1, 0, 1, 0)
			flash.BackgroundColor3 = winColor
			flash.BackgroundTransparency = 0.5
			flash.ZIndex = 80; flash.Parent = overlay
			TweenService:Create(flash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
			task.delay(0.5, function() if flash.Parent then flash:Destroy() end end)

			-- Glow on winning card
			local winCard = strip:FindFirstChild("C" .. winIdx)
			if winCard then
				local glow = Instance.new("UIStroke")
				glow.Name = "WinGlow"
				glow.Color = isGood and Color3.fromRGB(100, 255, 120) or Color3.fromRGB(255, 100, 100)
				glow.Thickness = 0; glow.Parent = winCard
				TweenService:Create(glow, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Thickness = 6 }):Play()
			end

			-- Big result text in the title
			titleLbl.Text = isGood and goodText or badText
			titleLbl.TextColor3 = isGood and Color3.fromRGB(100, 255, 120) or Color3.fromRGB(255, 100, 100)
			titleLbl.TextSize = 42

			-- Camera shake on bad outcome
			if not isGood then
				UIHelper.CameraShake(0.6, 0.4)
			end

			-- Clean up after dramatic pause, then callback
			task.delay(2.5, function()
				if overlay and overlay.Parent then
					TweenService:Create(overlay, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
					task.delay(0.45, function() cleanupBinarySpin() end)
				end
				if onComplete then onComplete() end
			end)
		end
	end)
end

-------------------------------------------------
-- STREAMER GRID (for Gem Trades & Elemental — toggle select)
-------------------------------------------------

local function buildStreamerGrid(parent, matchFn, queueSet, onChanged, accentColor)
	local combined = getCombinedItems()
	local queued = allQueuedIndices()

	-- Collect eligible items (matching + not queued in OTHER queues)
	local items = {}
	for _, entry in ipairs(combined) do
		if matchFn(entry.item) then
			local inThisQueue = queueSet[entry.vi]
			local inOtherQueue = not inThisQueue and queued[entry.vi]
			if not inOtherQueue then
				table.insert(items, entry)
			end
		end
	end

	if #items == 0 then
		local nl = Instance.new("TextLabel")
		nl.Size = UDim2.new(1, 0, 0, 50); nl.BackgroundTransparency = 1
		nl.Text = "No eligible streamers in your inventory or storage"; nl.TextColor3 = Color3.fromRGB(120, 120, 140)
		nl.Font = FONT; nl.TextSize = 14; nl.TextWrapped = true; nl.Parent = parent
		return
	end

	-- Grid container (wrapped in a frame so it sizes correctly)
	local gridFrame = Instance.new("Frame")
	gridFrame.Size = UDim2.new(1, 0, 0, 0)
	gridFrame.AutomaticSize = Enum.AutomaticSize.Y
	gridFrame.BackgroundTransparency = 1; gridFrame.Parent = parent

	local grid = Instance.new("UIGridLayout", gridFrame)
	grid.CellSize = UDim2.new(0, 88, 0, 68)
	grid.CellPadding = UDim2.new(0, 6, 0, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder

	for order, entry in ipairs(items) do
		local item = entry.item
		local vi = entry.vi
		local id, eff, info = getItemInfo(item)
		local selected = queueSet[vi] == true
		local rColor = DesignConfig.RarityColors[info and info.rarity or "Common"] or Color3.new(1, 1, 1)
		local isStorage = entry.source == "storage"

		local cell = Instance.new("TextButton")
		cell.Size = UDim2.new(0, 88, 0, 68)
		cell.BackgroundColor3 = selected and Color3.fromRGB(30, 100, 45) or Color3.fromRGB(28, 26, 48)
		cell.BorderSizePixel = 0; cell.Text = ""; cell.LayoutOrder = order
		cell.Parent = gridFrame
		Instance.new("UICorner", cell).CornerRadius = UDim.new(0, 10)
		local cs = Instance.new("UIStroke", cell)
		cs.Color = selected and Color3.fromRGB(60, 220, 80) or rColor
		cs.Thickness = selected and 2.5 or 1.5
		cs.Transparency = selected and 0 or 0.4

		-- Storage indicator
		if isStorage then
			local si = Instance.new("TextLabel")
			si.Size = UDim2.new(0, 14, 0, 10); si.Position = UDim2.new(1, -2, 0, 2)
			si.AnchorPoint = Vector2.new(1, 0); si.BackgroundTransparency = 1
			si.Text = "S"; si.TextColor3 = Color3.fromRGB(255, 165, 50)
			si.Font = Enum.Font.GothamBold; si.TextSize = 8; si.Parent = cell
		end

		-- Name
		local nl2 = Instance.new("TextLabel")
		nl2.Size = UDim2.new(1, -6, 0, 20); nl2.Position = UDim2.new(0.5, 0, 0, 4)
		nl2.AnchorPoint = Vector2.new(0.5, 0); nl2.BackgroundTransparency = 1
		nl2.Text = id; nl2.TextColor3 = selected and Color3.fromRGB(200, 255, 200) or rColor
		nl2.Font = FONT; nl2.TextSize = 11; nl2.TextTruncate = Enum.TextTruncate.AtEnd
		nl2.Parent = cell

		-- Effect
		if eff then
			local el = Instance.new("TextLabel")
			el.Size = UDim2.new(1, -6, 0, 14); el.Position = UDim2.new(0.5, 0, 0, 24)
			el.AnchorPoint = Vector2.new(0.5, 0); el.BackgroundTransparency = 1
			el.Text = eff
			el.TextColor3 = (Effects.ByName[eff] and Effects.ByName[eff].color) or Color3.fromRGB(150, 150, 150)
			el.Font = FONT2; el.TextSize = 9; el.Parent = cell
		end

		-- Checkmark or rarity
		local bl = Instance.new("TextLabel")
		bl.Size = UDim2.new(1, 0, 0, 18); bl.Position = UDim2.new(0.5, 0, 1, -20)
		bl.AnchorPoint = Vector2.new(0.5, 0); bl.BackgroundTransparency = 1
		bl.Text = selected and "QUEUED" or (info and info.rarity or "")
		bl.TextColor3 = selected and Color3.fromRGB(100, 255, 120) or Color3.fromRGB(100, 100, 120)
		bl.Font = FONT; bl.TextSize = 9; bl.Parent = cell

		local capVI = vi
		local capCell = cell
		local capCS = cs
		local capNL = nl2
		local capBL = bl
		local capRColor = rColor
		cell.MouseButton1Click:Connect(function()
			if queueSet[capVI] then
				queueSet[capVI] = nil
			else
				queueSet[capVI] = true
			end
			-- Instant visual update on the cell (no full rebuild)
			local sel = queueSet[capVI] == true
			capCell.BackgroundColor3 = sel and Color3.fromRGB(30, 100, 45) or Color3.fromRGB(28, 26, 48)
			capCS.Color = sel and Color3.fromRGB(60, 220, 80) or capRColor
			capCS.Thickness = sel and 2.5 or 1.5
			capCS.Transparency = sel and 0 or 0.4
			capNL.TextColor3 = sel and Color3.fromRGB(200, 255, 200) or capRColor
			capBL.Text = sel and "QUEUED" or (info and info.rarity or "")
			capBL.TextColor3 = sel and Color3.fromRGB(100, 255, 120) or Color3.fromRGB(100, 100, 120)
			fireQueueChanged()
			-- Defer the heavy content rebuild so the click feels instant
			task.defer(function()
				if onChanged then onChanged() end
			end)
		end)
	end
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

local buildContent -- forward declare

-- =========== GEM TRADE CONTENT ===========
local function buildGemTradeContent(tradeIndex)
	clearContent()
	local trade = Sacrifice.GemTrades[tradeIndex]
	if not trade then return end

	if not gemTradeQueues[tradeIndex] then gemTradeQueues[tradeIndex] = {} end
	local queue = gemTradeQueues[tradeIndex]

	-- Validate queue
	validateQueueSet(queue, function(item)
		local _, _, info = getItemInfo(item)
		return info and info.rarity == trade.rarity
	end)

	local selected = queueSetCount(queue)
	local need = trade.count
	local rc = DesignConfig.RarityColors[trade.rarity] or Color3.new(1, 1, 1)
	local canSacrifice = selected >= need

	-- Header
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, -10, 0, 110)
	header.BackgroundColor3 = Color3.fromRGB(22, 22, 40); header.BorderSizePixel = 0
	header.Parent = contentFrame
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, 18)
	Instance.new("UIStroke", header).Color = rc

	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.new(1, -24, 0, 36); tl.Position = UDim2.new(0.5, 0, 0, 10)
	tl.AnchorPoint = Vector2.new(0.5, 0); tl.BackgroundTransparency = 1
	tl.Text = trade.rarity .. " Gem Sacrifice  —  " .. formatNumber(trade.gems) .. " Gems"
	tl.TextColor3 = rc; tl.Font = FONT; tl.TextSize = 24; tl.Parent = header
	local ts = Instance.new("UIStroke", tl)
	ts.Color = Color3.new(0, 0, 0); ts.Thickness = 2; ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	local sl = Instance.new("TextLabel")
	sl.Size = UDim2.new(1, -24, 0, 24); sl.Position = UDim2.new(0.5, 0, 0, 48)
	sl.AnchorPoint = Vector2.new(0.5, 0); sl.BackgroundTransparency = 1
	sl.Text = "Tap streamers below to queue them. They'll stay here until you sacrifice or remove them."
	sl.TextColor3 = Color3.fromRGB(160, 170, 200); sl.Font = FONT2; sl.TextSize = 13
	sl.TextWrapped = true; sl.Parent = header

	-- Progress bar
	local pct = math.min(1, selected / need)
	local progBg = Instance.new("Frame")
	progBg.Size = UDim2.new(1, -40, 0, 22); progBg.Position = UDim2.new(0.5, 0, 0, 78)
	progBg.AnchorPoint = Vector2.new(0.5, 0)
	progBg.BackgroundColor3 = Color3.fromRGB(30, 30, 50); progBg.BorderSizePixel = 0; progBg.Parent = header
	Instance.new("UICorner", progBg).CornerRadius = UDim.new(0, 6)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(pct, 0, 1, 0)
	fill.BackgroundColor3 = canSacrifice and Color3.fromRGB(60, 200, 80) or rc
	fill.BorderSizePixel = 0; fill.Parent = progBg
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 6)
	local pLbl = Instance.new("TextLabel")
	pLbl.Size = UDim2.new(1, 0, 1, 0); pLbl.BackgroundTransparency = 1
	pLbl.Text = selected .. " / " .. need .. " queued"
	pLbl.TextColor3 = Color3.new(1, 1, 1); pLbl.Font = FONT; pLbl.TextSize = 12; pLbl.ZIndex = 2
	pLbl.Parent = progBg

	-- Button row
	local btnRow = Instance.new("Frame")
	btnRow.Size = UDim2.new(1, -10, 0, 50); btnRow.BackgroundTransparency = 1; btnRow.Parent = contentFrame
	local bl = Instance.new("UIListLayout", btnRow)
	bl.FillDirection = Enum.FillDirection.Horizontal
	bl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	bl.VerticalAlignment = Enum.VerticalAlignment.Center; bl.Padding = UDim.new(0, 10)

	-- Auto Fill
	local afBtn = Instance.new("TextButton")
	afBtn.Size = UDim2.new(0, 120, 0, 40); afBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 90)
	afBtn.Text = "Auto Fill"; afBtn.TextColor3 = Color3.new(1, 1, 1)
	afBtn.Font = FONT; afBtn.TextSize = 14; afBtn.BorderSizePixel = 0; afBtn.Parent = btnRow
	Instance.new("UICorner", afBtn).CornerRadius = UDim.new(0, 10)
	afBtn.MouseButton1Click:Connect(function()
		local inv = HUDController.Data.inventory or {}
		local queued = allQueuedIndices()
		local added = queueSetCount(queue)
		for i, item in ipairs(inv) do
			if added >= need then break end
			if not queue[i] and not queued[i] then
				local _, _, info = getItemInfo(item)
				if info and info.rarity == trade.rarity then
					queue[i] = true; added = added + 1
				end
			end
		end
		buildContent(activeTabId)
	end)

	-- Clear All
	local clBtn = Instance.new("TextButton")
	clBtn.Size = UDim2.new(0, 120, 0, 40); clBtn.BackgroundColor3 = Color3.fromRGB(90, 50, 50)
	clBtn.Text = "Clear All"; clBtn.TextColor3 = Color3.new(1, 1, 1)
	clBtn.Font = FONT; clBtn.TextSize = 14; clBtn.BorderSizePixel = 0; clBtn.Parent = btnRow
	Instance.new("UICorner", clBtn).CornerRadius = UDim.new(0, 10)
	clBtn.MouseButton1Click:Connect(function()
		gemTradeQueues[tradeIndex] = {}
		fireQueueChanged()
		buildContent(activeTabId)
	end)

	-- Sacrifice
	local sacBtn = Instance.new("TextButton")
	sacBtn.Size = UDim2.new(0, 200, 0, 44)
	sacBtn.BackgroundColor3 = canSacrifice and Color3.fromRGB(60, 200, 80) or Color3.fromRGB(50, 50, 70)
	sacBtn.Text = canSacrifice and "SACRIFICE" or "NEED MORE"
	sacBtn.TextColor3 = Color3.new(1, 1, 1); sacBtn.Font = FONT; sacBtn.TextSize = 17
	sacBtn.BorderSizePixel = 0; sacBtn.Parent = btnRow
	Instance.new("UICorner", sacBtn).CornerRadius = UDim.new(0, 12)
	Instance.new("UIStroke", sacBtn).Color = canSacrifice and Color3.fromRGB(40, 140, 55) or Color3.fromRGB(40, 40, 55)
	if canSacrifice then
		sacBtn.MouseButton1Click:Connect(function()
			showConfirmation(
				("Sacrifice %d %s streamers for %s Gems?"):format(need, trade.rarity, formatNumber(trade.gems)),
				function()
					SacrificeRequest:FireServer("GemTrade", tradeIndex)
					gemTradeQueues[tradeIndex] = {}
					fireQueueChanged()
				end
			)
		end)
	end

	-- Streamer grid
	buildStreamerGrid(contentFrame, function(item)
		local _, _, info = getItemInfo(item)
		return info and info.rarity == trade.rarity
	end, queue, function()
		buildContent(activeTabId)
	end, rc)
end

-- Forward declaration for effect-based one-time content builder (defined later)
local buildEffectOneTimeContent

-- =========== ONE-TIME CONTENT ===========
local function buildOneTimeContent(oneTimeId)
	clearContent()
	local cfg = Sacrifice.OneTime[oneTimeId]
	if not cfg then return end
	local done = (HUDController.Data.sacrificeOneTime or {})[oneTimeId]

	-- Branch to effect-based UI if this is an effect-based requirement
	if cfg.req[1] and cfg.req[1].effectReq then
		buildEffectOneTimeContent(oneTimeId, cfg, done)
		return
	end

	if not oneTimeQueues[oneTimeId] then oneTimeQueues[oneTimeId] = {} end
	local queue = oneTimeQueues[oneTimeId]
	validateOneTimeQueue(queue, cfg.req)

	-- Header
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, -10, 0, 100)
	header.BackgroundColor3 = Color3.fromRGB(22, 22, 40); header.BorderSizePixel = 0; header.Parent = contentFrame
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, 18)
	Instance.new("UIStroke", header).Color = done and Color3.fromRGB(60, 200, 80) or Color3.fromRGB(255, 200, 60)

	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.new(1, -28, 0, 36); tl.Position = UDim2.new(0.5, 0, 0, 12)
	tl.AnchorPoint = Vector2.new(0.5, 0); tl.BackgroundTransparency = 1
	tl.Text = cfg.name .. "  —  " .. formatNumber(cfg.gems) .. " Gems"
	tl.TextColor3 = done and Color3.fromRGB(80, 200, 80) or Color3.fromRGB(255, 220, 100)
	tl.Font = FONT; tl.TextSize = 26; tl.Parent = header
	Instance.new("UIStroke", tl).Color = Color3.new(0, 0, 0)

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, -28, 0, 32); sub.Position = UDim2.new(0.5, 0, 0, 52)
	sub.AnchorPoint = Vector2.new(0.5, 0); sub.BackgroundTransparency = 1
	sub.Text = done and "You've already completed this sacrifice!" or "Tap each slot to pick a streamer. They stay here even if you close the menu."
	sub.TextColor3 = Color3.fromRGB(160, 170, 200); sub.Font = FONT; sub.TextSize = 14
	sub.TextWrapped = true; sub.Parent = header

	if done then return end

	local usedSet = {}
	for _, idx in pairs(queue) do if idx then usedSet[idx] = true end end

	-- Count total slots to decide layout
	local totalSlots = 0
	for _, r in ipairs(cfg.req) do totalSlots = totalSlots + (r.count or 1) end

	local allFilled = true
	local slotGrid = Instance.new("Frame")
	slotGrid.BackgroundTransparency = 1; slotGrid.Parent = contentFrame
	if totalSlots <= 5 then
		slotGrid.Size = UDim2.new(1, -10, 0, 115)
		local sl2 = Instance.new("UIListLayout", slotGrid)
		sl2.FillDirection = Enum.FillDirection.Horizontal; sl2.Padding = UDim.new(0, 12)
		sl2.HorizontalAlignment = Enum.HorizontalAlignment.Center
		sl2.VerticalAlignment = Enum.VerticalAlignment.Center
	else
		local cols = 5
		local rows = math.ceil(totalSlots / cols)
		slotGrid.Size = UDim2.new(1, -10, 0, rows * 115 + (rows - 1) * 10)
		local gl = Instance.new("UIGridLayout", slotGrid)
		gl.CellSize = UDim2.new(0, 110, 0, 105)
		gl.CellPadding = UDim2.new(0, 10, 0, 10)
		gl.FillDirection = Enum.FillDirection.Horizontal
		gl.HorizontalAlignment = Enum.HorizontalAlignment.Center
		gl.SortOrder = Enum.SortOrder.LayoutOrder
	end

	local slotOrder = 0
	for si, r in ipairs(cfg.req) do
		local count = r.count or 1
		for c = 1, count do
			local key = si .. "_" .. c
			local filled = queue[key] ~= nil
			if not filled then allFilled = false end

			-- Build label: show effect + display name or rarity
			local reqLabel
			local displayId = r.streamerId and Streamers.ById[r.streamerId] and Streamers.ById[r.streamerId].displayName or r.streamerId
			if r.effect and r.streamerId then
				reqLabel = r.effect .. " " .. (displayId or "?")
			elseif r.streamerId then
				reqLabel = displayId or "?"
			elseif r.rarity then
				reqLabel = r.rarity
			else
				reqLabel = "?"
			end

			slotOrder = slotOrder + 1
			local slot = Instance.new("TextButton")
			slot.Size = UDim2.new(0, 110, 0, 105)
			slot.BackgroundColor3 = filled and Color3.fromRGB(30, 100, 45) or Color3.fromRGB(28, 26, 48)
			slot.BorderSizePixel = 0; slot.Text = ""; slot.LayoutOrder = slotOrder; slot.Parent = slotGrid
			Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 14)
			local ss = Instance.new("UIStroke", slot)
			ss.Color = filled and Color3.fromRGB(60, 220, 80) or Color3.fromRGB(60, 58, 90); ss.Thickness = 2.5

			-- Required label (top of slot)
			local rl = Instance.new("TextLabel")
			rl.Size = UDim2.new(1, -8, 0, 30); rl.Position = UDim2.new(0.5, 0, 0, 4)
			rl.AnchorPoint = Vector2.new(0.5, 0); rl.BackgroundTransparency = 1
			rl.Text = reqLabel; rl.TextColor3 = Color3.new(1, 1, 1)
			rl.Font = FONT; rl.TextSize = 11; rl.TextWrapped = true; rl.Parent = slot

			if filled then
				local resolvedItem = resolveVirtualItem(queue[key])
				local name = type(resolvedItem) == "table" and resolvedItem.id or resolvedItem or "?"
				local eff = type(resolvedItem) == "table" and resolvedItem.effect or nil
				local nl = Instance.new("TextLabel")
				nl.Size = UDim2.new(1, -8, 0, 20); nl.Position = UDim2.new(0.5, 0, 0, 36)
				nl.AnchorPoint = Vector2.new(0.5, 0); nl.BackgroundTransparency = 1
				nl.Text = name .. (eff and (" (" .. eff .. ")") or "")
				nl.TextColor3 = Color3.fromRGB(180, 255, 180)
				nl.Font = FONT2; nl.TextSize = 11; nl.TextTruncate = Enum.TextTruncate.AtEnd; nl.Parent = slot

				local rl2 = Instance.new("TextLabel")
				rl2.Size = UDim2.new(1, 0, 0, 22); rl2.Position = UDim2.new(0.5, 0, 1, -26)
				rl2.AnchorPoint = Vector2.new(0.5, 0); rl2.BackgroundTransparency = 1
				rl2.Text = "Tap to remove"; rl2.TextColor3 = Color3.fromRGB(255, 130, 130)
				rl2.Font = FONT2; rl2.TextSize = 11; rl2.Parent = slot

				local capKey, capId = key, oneTimeId
				slot.MouseButton1Click:Connect(function()
					oneTimeQueues[capId][capKey] = nil
					fireQueueChanged()
					buildContent(activeTabId)
				end)
			else
				local pl = Instance.new("TextLabel")
				pl.Size = UDim2.new(1, 0, 0, 34); pl.Position = UDim2.new(0.5, 0, 0.5, -2)
				pl.AnchorPoint = Vector2.new(0.5, 0.5); pl.BackgroundTransparency = 1
				pl.Text = "+"; pl.TextColor3 = Color3.fromRGB(90, 90, 120)
				pl.Font = FONT; pl.TextSize = 32; pl.Parent = slot

				local hl = Instance.new("TextLabel")
				hl.Size = UDim2.new(1, 0, 0, 18); hl.Position = UDim2.new(0.5, 0, 1, -22)
				hl.AnchorPoint = Vector2.new(0.5, 0); hl.BackgroundTransparency = 1
				hl.Text = "Tap to pick"; hl.TextColor3 = Color3.fromRGB(90, 90, 120)
				hl.Font = FONT2; hl.TextSize = 10; hl.Parent = slot

				local capKey, capId, capR = key, oneTimeId, r
				slot.MouseButton1Click:Connect(function()
					local excludeSet = allQueuedIndices()
					local filterFn
					if capR.streamerId then
						filterFn = function(item)
							local id = type(item) == "table" and item.id or item
							if id ~= capR.streamerId then return false end
							if capR.effect ~= nil then
								local e = type(item) == "table" and item.effect or nil
								if e ~= capR.effect then return false end
							end
							return true
						end
					elseif capR.rarity then
						filterFn = function(item)
							local id = type(item) == "table" and item.id or item
							local info = Streamers.ById[id]
							return info and info.rarity == capR.rarity
						end
					end
					local pickerTitle = "Pick a "
					if capR.effect and capR.streamerId then
						local dn = Streamers.ById[capR.streamerId] and Streamers.ById[capR.streamerId].displayName or capR.streamerId
						pickerTitle = pickerTitle .. capR.effect .. " " .. dn
					else
						pickerTitle = pickerTitle .. (capR.streamerId or capR.rarity)
					end
					if filterFn then
						showPicker(pickerTitle, filterFn, excludeSet, function(invIdx)
							oneTimeQueues[capId][capKey] = invIdx
							fireQueueChanged()
							buildContent(activeTabId)
						end)
					end
				end)
			end
		end
	end

	-- Sacrifice button
	local sacBtn = Instance.new("TextButton")
	sacBtn.Size = UDim2.new(0, 300, 0, 50)
	sacBtn.BackgroundColor3 = allFilled and Color3.fromRGB(60, 200, 80) or Color3.fromRGB(50, 50, 70)
	sacBtn.Text = allFilled and ("SACRIFICE FOR " .. formatNumber(cfg.gems) .. " GEMS") or "Fill all slots to sacrifice"
	sacBtn.TextColor3 = allFilled and Color3.new(1, 1, 1) or Color3.fromRGB(110, 110, 130)
	sacBtn.Font = FONT; sacBtn.TextSize = 18; sacBtn.BorderSizePixel = 0; sacBtn.Parent = contentFrame
	Instance.new("UICorner", sacBtn).CornerRadius = UDim.new(0, 14)
	Instance.new("UIStroke", sacBtn).Color = allFilled and Color3.fromRGB(40, 140, 55) or Color3.fromRGB(40, 40, 55)

	if allFilled then
		local capId = oneTimeId
		sacBtn.MouseButton1Click:Connect(function()
			showConfirmation("Sacrifice these streamers for " .. formatNumber(cfg.gems) .. " Gems?", function()
				SacrificeRequest:FireServer("OneTime", capId)
				oneTimeQueues[capId] = {}
				fireQueueChanged()
			end)
		end)
	end
end

-- =========== LUCK CONTENT ===========
local function buildLuckContent(luckType)
	clearContent()

	local warnFrame = Instance.new("Frame")
	warnFrame.Size = UDim2.new(1, -10, 0, 50)
	warnFrame.BackgroundColor3 = Color3.fromRGB(80, 28, 28); warnFrame.BorderSizePixel = 0
	warnFrame.Parent = contentFrame
	Instance.new("UICorner", warnFrame).CornerRadius = UDim.new(0, 12)
	Instance.new("UIStroke", warnFrame).Color = Color3.fromRGB(200, 70, 50)
	local wl = Instance.new("TextLabel")
	wl.Size = UDim2.new(1, -20, 1, -8); wl.Position = UDim2.new(0.5, 0, 0.5, 0)
	wl.AnchorPoint = Vector2.new(0.5, 0.5); wl.BackgroundTransparency = 1
	wl.Text = Sacrifice.LuckWarning; wl.TextColor3 = Color3.fromRGB(255, 200, 160)
	wl.Font = FONT; wl.TextSize = 13; wl.TextWrapped = true; wl.Parent = warnFrame

	if luckType == "FiftyFifty" then
		local cfg = Sacrifice.FiftyFifty
		local cs = (HUDController.Data.sacrificeChargeState or {}).FiftyFifty or { count = 0, nextAt = nil }
		local nextIn = cs.nextAt and (cs.nextAt - os.clock()) or 0
		local rp = {}; for _, r in ipairs(cfg.req) do table.insert(rp, r.count .. " " .. r.rarity) end

		local header = Instance.new("Frame")
		header.Size = UDim2.new(1, -10, 0, 130)
		header.BackgroundColor3 = Color3.fromRGB(22, 22, 40); header.BorderSizePixel = 0; header.Parent = contentFrame
		Instance.new("UICorner", header).CornerRadius = UDim.new(0, 18)
		Instance.new("UIStroke", header).Color = Color3.fromRGB(255, 200, 60)
		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, -24, 0, 34); t.Position = UDim2.new(0.5, 0, 0, 12)
		t.AnchorPoint = Vector2.new(0.5, 0); t.BackgroundTransparency = 1
		t.Text = cfg.name; t.TextColor3 = Color3.fromRGB(255, 220, 80)
		t.Font = FONT; t.TextSize = 28; t.Parent = header
		local d = Instance.new("TextLabel")
		d.Size = UDim2.new(1, -24, 0, 70); d.Position = UDim2.new(0.5, 0, 0, 50)
		d.AnchorPoint = Vector2.new(0.5, 0); d.BackgroundTransparency = 1
		d.Text = cfg.desc .. "\n\nCost: " .. table.concat(rp, ", ") .. "\nCharges: " .. cs.count .. "/" .. cfg.maxCharges .. (cs.count < cfg.maxCharges and nextIn > 0 and ("  •  Next: " .. formatTime(nextIn)) or "")
		d.TextColor3 = Color3.fromRGB(160, 170, 200); d.Font = FONT; d.TextSize = 14; d.TextWrapped = true; d.Parent = header

		local sb = Instance.new("TextButton")
		sb.Size = UDim2.new(0, 200, 0, 48)
		sb.BackgroundColor3 = cs.count > 0 and Color3.fromRGB(220, 180, 40) or Color3.fromRGB(50, 50, 70)
		sb.Text = cs.count > 0 and "SACRIFICE" or "NO CHARGES"
		sb.TextColor3 = Color3.new(1, 1, 1); sb.Font = FONT; sb.TextSize = 18
		sb.BorderSizePixel = 0; sb.Parent = contentFrame
		Instance.new("UICorner", sb).CornerRadius = UDim.new(0, 12)
		if cs.count > 0 then
			sb.MouseButton1Click:Connect(function()
				showConfirmation("50/50: DOUBLE your cash or LOSE HALF!\nCost: " .. table.concat(rp, ", "), function()
					SacrificeRequest:FireServer("FiftyFifty")
				end)
			end)
		end

	elseif luckType == "FeelingLucky" then
		local cfg = Sacrifice.FeelingLucky
		local cs = (HUDController.Data.sacrificeChargeState or {}).FeelingLucky or { count = 0, nextAt = nil }
		local nextIn = cs.nextAt and (cs.nextAt - os.clock()) or 0
		local rp = {}; for _, r in ipairs(cfg.req) do table.insert(rp, r.count .. " " .. r.rarity) end

		local header = Instance.new("Frame")
		header.Size = UDim2.new(1, -10, 0, 130)
		header.BackgroundColor3 = Color3.fromRGB(22, 22, 40); header.BorderSizePixel = 0; header.Parent = contentFrame
		Instance.new("UICorner", header).CornerRadius = UDim.new(0, 18)
		Instance.new("UIStroke", header).Color = Color3.fromRGB(100, 200, 255)
		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, -24, 0, 34); t.Position = UDim2.new(0.5, 0, 0, 12)
		t.AnchorPoint = Vector2.new(0.5, 0); t.BackgroundTransparency = 1
		t.Text = cfg.name; t.TextColor3 = Color3.fromRGB(130, 220, 255)
		t.Font = FONT; t.TextSize = 28; t.Parent = header
		local d = Instance.new("TextLabel")
		d.Size = UDim2.new(1, -24, 0, 70); d.Position = UDim2.new(0.5, 0, 0, 50)
		d.AnchorPoint = Vector2.new(0.5, 0); d.BackgroundTransparency = 1
		d.Text = cfg.desc .. "\n\nCost: " .. table.concat(rp, ", ") .. "\nCharges: " .. cs.count .. "/" .. cfg.maxCharges .. (cs.count < cfg.maxCharges and nextIn > 0 and ("  •  Recharge: " .. formatTime(nextIn)) or "")
		d.TextColor3 = Color3.fromRGB(160, 170, 200); d.Font = FONT; d.TextSize = 14; d.TextWrapped = true; d.Parent = header

		local sb = Instance.new("TextButton")
		sb.Size = UDim2.new(0, 200, 0, 48)
		sb.BackgroundColor3 = cs.count > 0 and Color3.fromRGB(70, 170, 220) or Color3.fromRGB(50, 50, 70)
		sb.Text = cs.count > 0 and "SACRIFICE" or "NO CHARGES"
		sb.TextColor3 = Color3.new(1, 1, 1); sb.Font = FONT; sb.TextSize = 18
		sb.BorderSizePixel = 0; sb.Parent = contentFrame
		Instance.new("UICorner", sb).CornerRadius = UDim.new(0, 12)
		if cs.count > 0 then
			sb.MouseButton1Click:Connect(function()
				showConfirmation("Feeling Lucky: +100% or -100% luck for 10 min!\nCost: " .. table.concat(rp, ", "), function()
					SacrificeRequest:FireServer("FeelingLucky")
				end)
			end)
		end

	elseif luckType == "DontDoIt" then
		local cfg = Sacrifice.DontDoIt
		local header = Instance.new("Frame")
		header.Size = UDim2.new(1, -10, 0, 170)
		header.BackgroundColor3 = Color3.fromRGB(22, 22, 40); header.BorderSizePixel = 0; header.Parent = contentFrame
		Instance.new("UICorner", header).CornerRadius = UDim.new(0, 18)
		Instance.new("UIStroke", header).Color = Color3.fromRGB(220, 60, 60)
		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, -24, 0, 34); t.Position = UDim2.new(0.5, 0, 0, 12)
		t.AnchorPoint = Vector2.new(0.5, 0); t.BackgroundTransparency = 1
		t.Text = cfg.name; t.TextColor3 = Color3.fromRGB(255, 100, 100)
		t.Font = FONT; t.TextSize = 28; t.Parent = header
		local d = Instance.new("TextLabel")
		d.Size = UDim2.new(1, -24, 0, 100); d.Position = UDim2.new(0.5, 0, 0, 52)
		d.AnchorPoint = Vector2.new(0.5, 0); d.BackgroundTransparency = 1
		d.Text = cfg.desc .. "\n\nUpgrade Chances:\nCommon->Rare: 50%  |  Rare->Epic: 30%\nEpic->Legendary: 10%  |  Legendary->Mythic: 4%\n\nInfinite charges — no cooldown!"
		d.TextColor3 = Color3.fromRGB(160, 170, 200); d.Font = FONT; d.TextSize = 14; d.TextWrapped = true; d.Parent = header

		local sb = Instance.new("TextButton")
		sb.Size = UDim2.new(0, 220, 0, 48); sb.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
		sb.Text = "SACRIFICE"; sb.TextColor3 = Color3.new(1, 1, 1)
		sb.Font = FONT; sb.TextSize = 18; sb.BorderSizePixel = 0; sb.Parent = contentFrame
		Instance.new("UICorner", sb).CornerRadius = UDim.new(0, 12)
		sb.MouseButton1Click:Connect(function()
			-- Find the highest earner across hotbar + storage
			local allItems = getCombinedItems()
			local bestName, bestEffect = "???", nil
			local bestPrice = -1
			for _, entry in ipairs(allItems) do
				local id = type(entry.item) == "table" and entry.item.id or entry.item
				local eff = type(entry.item) == "table" and entry.item.effect or nil
				local info = Streamers.ById[id]
				if info then
					local p = info.cashPerSecond or 0
					if eff then
						local ei = Effects.ByName[eff]
						if ei and ei.cashMultiplier then p = p * ei.cashMultiplier end
					end
					if p > bestPrice then
						bestPrice = p
						bestName = info.displayName or id
						bestEffect = eff
					end
				end
			end
			local streamerLabel = bestEffect and (bestEffect .. " " .. bestName) or bestName
			showConfirmation("This will PERMANENTLY sacrifice your " .. streamerLabel .. " (highest earner)!", function()
				SacrificeRequest:FireServer("DontDoIt")
			end)
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
	header.Size = UDim2.new(1, -10, 0, 90)
	header.BackgroundColor3 = Color3.fromRGB(22, 22, 40); header.BorderSizePixel = 0; header.Parent = contentFrame
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, 18)
	Instance.new("UIStroke", header).Color = effectColor

	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.new(1, -24, 0, 34); tl.Position = UDim2.new(0.5, 0, 0, 12)
	tl.AnchorPoint = Vector2.new(0.5, 0); tl.BackgroundTransparency = 1
	tl.Text = displayName .. " Elemental Sacrifice"
	tl.TextColor3 = effectColor; tl.Font = FONT; tl.TextSize = 24; tl.Parent = header
	local ts = Instance.new("UIStroke", tl)
	ts.Color = Color3.new(0, 0, 0); ts.Thickness = 2; ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, -24, 0, 24); sub.Position = UDim2.new(0.5, 0, 0, 50)
	sub.AnchorPoint = Vector2.new(0.5, 0); sub.BackgroundTransparency = 1
	sub.Text = "Tap streamers to queue them. Combine into one " .. displayName .. " streamer!"
	sub.TextColor3 = Color3.fromRGB(160, 170, 200); sub.Font = FONT; sub.TextSize = 13
	sub.TextWrapped = true; sub.Parent = header

	for ri, rarity in ipairs(rarities) do
		local need = Sacrifice.ElementalRates[rarity]
		if not need then return end
		local rarColor = rc[rarity] or Color3.new(1, 1, 1)

		local qKey = (effectName or "") .. "_" .. rarity
		if not elementalQueues[qKey] then elementalQueues[qKey] = {} end
		local queue = elementalQueues[qKey]

		validateQueueSet(queue, function(item)
			local id, eff, info = getItemInfo(item)
			return info and info.rarity == rarity and (effectName == nil and eff == nil or eff == effectName)
		end)

		local selected = queueSetCount(queue)
		local canSacrifice = selected >= need
		local pct = math.min(1, selected / need)

		-- Section label for this rarity
		local secLabel = Instance.new("TextLabel")
		secLabel.Size = UDim2.new(1, 0, 0, 30); secLabel.BackgroundTransparency = 1
		secLabel.Text = rarity .. "  —  " .. selected .. "/" .. need .. " queued"
		secLabel.TextColor3 = rarColor; secLabel.Font = FONT; secLabel.TextSize = 18
		secLabel.TextXAlignment = Enum.TextXAlignment.Left; secLabel.LayoutOrder = ri * 100
		secLabel.Parent = contentFrame

		-- Progress + buttons row
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 36); row.BackgroundTransparency = 1
		row.LayoutOrder = ri * 100 + 1; row.Parent = contentFrame

		local progBg = Instance.new("Frame")
		progBg.Size = UDim2.new(0.45, 0, 0, 20); progBg.Position = UDim2.new(0, 0, 0.5, 0)
		progBg.AnchorPoint = Vector2.new(0, 0.5)
		progBg.BackgroundColor3 = Color3.fromRGB(30, 30, 50); progBg.BorderSizePixel = 0; progBg.Parent = row
		Instance.new("UICorner", progBg).CornerRadius = UDim.new(0, 6)
		local fillBar = Instance.new("Frame")
		fillBar.Size = UDim2.new(pct, 0, 1, 0)
		fillBar.BackgroundColor3 = canSacrifice and Color3.fromRGB(60, 200, 80) or rarColor
		fillBar.BorderSizePixel = 0; fillBar.Parent = progBg
		Instance.new("UICorner", fillBar).CornerRadius = UDim.new(0, 6)
		local pLbl = Instance.new("TextLabel")
		pLbl.Size = UDim2.new(1, 0, 1, 0); pLbl.BackgroundTransparency = 1
		pLbl.Text = selected .. "/" .. need; pLbl.TextColor3 = Color3.new(1, 1, 1)
		pLbl.Font = FONT; pLbl.TextSize = 10; pLbl.ZIndex = 2; pLbl.Parent = progBg

		-- Auto fill for this rarity
		local afb = Instance.new("TextButton")
		afb.Size = UDim2.new(0, 80, 0, 28); afb.Position = UDim2.new(0.48, 0, 0.5, 0)
		afb.AnchorPoint = Vector2.new(0, 0.5); afb.BackgroundColor3 = Color3.fromRGB(50, 50, 80)
		afb.Text = "Auto Fill"; afb.TextColor3 = Color3.new(1, 1, 1)
		afb.Font = FONT; afb.TextSize = 11; afb.BorderSizePixel = 0; afb.Parent = row
		Instance.new("UICorner", afb).CornerRadius = UDim.new(0, 8)
		local capQKey = qKey
		local capRarity = rarity
		local capEffect = effectName
		afb.MouseButton1Click:Connect(function()
			local allItems = getCombinedItems()
			local queued = allQueuedIndices()
			local q = elementalQueues[capQKey]
			local added = queueSetCount(q)
			for _, entry in ipairs(allItems) do
				if added >= need then break end
				if not q[entry.vi] and not queued[entry.vi] then
					local id, eff, info = getItemInfo(entry.item)
					if info and info.rarity == capRarity and (capEffect == nil and eff == nil or eff == capEffect) then
						q[entry.vi] = true; added = added + 1
					end
				end
			end
			fireQueueChanged()
			buildContent(activeTabId)
		end)

		-- Clear
		local clb = Instance.new("TextButton")
		clb.Size = UDim2.new(0, 60, 0, 28); clb.Position = UDim2.new(0.48, 88, 0.5, 0)
		clb.AnchorPoint = Vector2.new(0, 0.5); clb.BackgroundColor3 = Color3.fromRGB(80, 40, 40)
		clb.Text = "Clear"; clb.TextColor3 = Color3.new(1, 1, 1)
		clb.Font = FONT; clb.TextSize = 11; clb.BorderSizePixel = 0; clb.Parent = row
		Instance.new("UICorner", clb).CornerRadius = UDim.new(0, 8)
		clb.MouseButton1Click:Connect(function()
			elementalQueues[capQKey] = {}
			fireQueueChanged()
			buildContent(activeTabId)
		end)

		-- Convert button
		local cvb = Instance.new("TextButton")
		cvb.Size = UDim2.new(0, 100, 0, 32); cvb.Position = UDim2.new(1, 0, 0.5, 0)
		cvb.AnchorPoint = Vector2.new(1, 0.5)
		cvb.BackgroundColor3 = canSacrifice and Color3.fromRGB(120, 80, 200) or Color3.fromRGB(50, 50, 70)
		cvb.Text = canSacrifice and "CONVERT" or "NEED MORE"
		cvb.TextColor3 = Color3.new(1, 1, 1); cvb.Font = FONT; cvb.TextSize = 13
		cvb.BorderSizePixel = 0; cvb.Parent = row
		Instance.new("UICorner", cvb).CornerRadius = UDim.new(0, 10)
		if canSacrifice then
			cvb.MouseButton1Click:Connect(function()
				showConfirmation(("Combine %d %s %s into 1?"):format(need, displayName, capRarity), function()
					SacrificeRequest:FireServer("Elemental", capEffect, capRarity)
					elementalQueues[capQKey] = {}
					fireQueueChanged()
				end)
			end)
		end

		-- Streamer grid for this rarity
		local gridWrapper = Instance.new("Frame")
		gridWrapper.Size = UDim2.new(1, 0, 0, 0)
		gridWrapper.AutomaticSize = Enum.AutomaticSize.Y
		gridWrapper.BackgroundTransparency = 1; gridWrapper.LayoutOrder = ri * 100 + 2
		gridWrapper.Parent = contentFrame

		buildStreamerGrid(gridWrapper, function(item)
			local id, eff, info = getItemInfo(item)
			return info and info.rarity == rarity and (effectName == nil and eff == nil or eff == effectName)
		end, queue, function()
			buildContent(activeTabId)
		end, rarColor)

		-- Divider
		if ri < #rarities then
			local div = Instance.new("Frame")
			div.Size = UDim2.new(0.8, 0, 0, 1)
			div.BackgroundColor3 = Color3.fromRGB(50, 48, 70); div.BorderSizePixel = 0
			div.LayoutOrder = ri * 100 + 3; div.Parent = contentFrame
		end
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

	if not effectOneTimeQueues[oneTimeId] then effectOneTimeQueues[oneTimeId] = {} end
	local queue = effectOneTimeQueues[oneTimeId]

	-- Validate queue: remove virtual indices that are no longer valid or no longer match effect
	local inv = HUDController.Data.inventory or {}
	local sto = HUDController.Data.storage or {}
	local toRemove = {}
	for vi in pairs(queue) do
		local item
		if vi > STORAGE_OFFSET then
			item = sto[vi - STORAGE_OFFSET]
		else
			item = inv[vi]
		end
		if not item then
			toRemove[vi] = true
		else
			local eff = type(item) == "table" and item.effect or nil
			if eff ~= effectName then toRemove[vi] = true end
		end
	end
	for vi in pairs(toRemove) do queue[vi] = nil end

	local queued = queueSetCount(queue)

	-- Header
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, -10, 0, 100)
	header.BackgroundColor3 = Color3.fromRGB(22, 22, 40); header.BorderSizePixel = 0; header.Parent = contentFrame
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, 18)
	Instance.new("UIStroke", header).Color = done and Color3.fromRGB(60, 200, 80) or effectColor

	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.new(1, -28, 0, 36); tl.Position = UDim2.new(0.5, 0, 0, 12)
	tl.AnchorPoint = Vector2.new(0.5, 0); tl.BackgroundTransparency = 1
	tl.Text = cfg.name .. "  —  " .. formatNumber(cfg.gems) .. " Gems"
	tl.TextColor3 = done and Color3.fromRGB(80, 200, 80) or effectColor
	tl.Font = FONT; tl.TextSize = 26; tl.Parent = header
	Instance.new("UIStroke", tl).Color = Color3.new(0, 0, 0)

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, -28, 0, 32); sub.Position = UDim2.new(0.5, 0, 0, 52)
	sub.AnchorPoint = Vector2.new(0.5, 0); sub.BackgroundTransparency = 1
	sub.Text = done and "You've already completed this sacrifice!" or ("Sacrifice " .. need .. " " .. effectName .. " cards (any rarity) for " .. formatNumber(cfg.gems) .. " Gems!")
	sub.TextColor3 = Color3.fromRGB(160, 170, 200); sub.Font = FONT; sub.TextSize = 14
	sub.TextWrapped = true; sub.Parent = header

	if done then return end

	-- Progress bar
	local barFrame = Instance.new("Frame")
	barFrame.Size = UDim2.new(1, -10, 0, 38)
	barFrame.BackgroundTransparency = 1; barFrame.Parent = contentFrame

	local barBG = Instance.new("Frame")
	barBG.Size = UDim2.new(1, -60, 0, 22); barBG.Position = UDim2.new(0, 0, 0.5, 0)
	barBG.AnchorPoint = Vector2.new(0, 0.5)
	barBG.BackgroundColor3 = Color3.fromRGB(30, 30, 50); barBG.BorderSizePixel = 0; barBG.Parent = barFrame
	Instance.new("UICorner", barBG).CornerRadius = UDim.new(0, 8)

	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.new(math.clamp(queued / need, 0, 1), 0, 1, 0)
	barFill.BackgroundColor3 = effectColor; barFill.BorderSizePixel = 0; barFill.Parent = barBG
	Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 8)

	local barLabel = Instance.new("TextLabel")
	barLabel.Size = UDim2.new(0, 50, 0, 22); barLabel.Position = UDim2.new(1, 4, 0.5, 0)
	barLabel.AnchorPoint = Vector2.new(0, 0.5); barLabel.BackgroundTransparency = 1
	barLabel.Text = queued .. "/" .. need; barLabel.TextColor3 = effectColor
	barLabel.Font = FONT; barLabel.TextSize = 16; barLabel.Parent = barBG

	-- Buttons row: Auto Fill | Clear | Sacrifice
	local btnRow = Instance.new("Frame")
	btnRow.Size = UDim2.new(1, -10, 0, 42)
	btnRow.BackgroundTransparency = 1; btnRow.Parent = contentFrame
	local brl = Instance.new("UIListLayout", btnRow)
	brl.FillDirection = Enum.FillDirection.Horizontal; brl.Padding = UDim.new(0, 10)
	brl.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local capOneTimeId = oneTimeId

	-- Auto Fill
	local afBtn = Instance.new("TextButton")
	afBtn.Size = UDim2.new(0, 130, 0, 36); afBtn.BackgroundColor3 = Color3.fromRGB(40, 100, 180)
	afBtn.Text = "AUTO FILL"; afBtn.TextColor3 = Color3.new(1, 1, 1)
	afBtn.Font = FONT; afBtn.TextSize = 14; afBtn.BorderSizePixel = 0; afBtn.Parent = btnRow
	Instance.new("UICorner", afBtn).CornerRadius = UDim.new(0, 10)
	afBtn.MouseButton1Click:Connect(function()
		local excluded = allQueuedIndices()
		local allItems = getCombinedItems()
		for _, entry in ipairs(allItems) do
			if queueSetCount(effectOneTimeQueues[capOneTimeId] or {}) >= need then break end
			if not excluded[entry.vi] then
				local eff = type(entry.item) == "table" and entry.item.effect or nil
				if eff == effectName then
					if not effectOneTimeQueues[capOneTimeId] then effectOneTimeQueues[capOneTimeId] = {} end
					effectOneTimeQueues[capOneTimeId][entry.vi] = true
					excluded[entry.vi] = true
				end
			end
		end
		fireQueueChanged()
		buildContent(activeTabId)
	end)

	-- Clear
	local clrBtn = Instance.new("TextButton")
	clrBtn.Size = UDim2.new(0, 100, 0, 36); clrBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 50)
	clrBtn.Text = "CLEAR"; clrBtn.TextColor3 = Color3.new(1, 1, 1)
	clrBtn.Font = FONT; clrBtn.TextSize = 14; clrBtn.BorderSizePixel = 0; clrBtn.Parent = btnRow
	Instance.new("UICorner", clrBtn).CornerRadius = UDim.new(0, 10)
	clrBtn.MouseButton1Click:Connect(function()
		effectOneTimeQueues[capOneTimeId] = {}
		fireQueueChanged()
		buildContent(activeTabId)
	end)

	-- Sacrifice
	local canSac = queued >= need
	local sacBtn = Instance.new("TextButton")
	sacBtn.Size = UDim2.new(0, 200, 0, 36)
	sacBtn.BackgroundColor3 = canSac and Color3.fromRGB(60, 200, 80) or Color3.fromRGB(50, 50, 70)
	sacBtn.Text = canSac and ("SACRIFICE FOR " .. formatNumber(cfg.gems) .. " GEMS") or ("NEED " .. (need - queued) .. " MORE")
	sacBtn.TextColor3 = canSac and Color3.new(1, 1, 1) or Color3.fromRGB(110, 110, 130)
	sacBtn.Font = FONT; sacBtn.TextSize = 14; sacBtn.BorderSizePixel = 0; sacBtn.Parent = btnRow
	Instance.new("UICorner", sacBtn).CornerRadius = UDim.new(0, 10)
	if canSac then
		sacBtn.MouseButton1Click:Connect(function()
			showConfirmation("Sacrifice " .. need .. " " .. effectName .. " cards for " .. formatNumber(cfg.gems) .. " Gems?", function()
				SacrificeRequest:FireServer("OneTime", capOneTimeId)
				effectOneTimeQueues[capOneTimeId] = {}
				fireQueueChanged()
			end)
		end)
	end

	-- Streamer grid (filtered by effect)
	local gridWrapper = Instance.new("Frame")
	gridWrapper.Size = UDim2.new(1, 0, 0, 0)
	gridWrapper.AutomaticSize = Enum.AutomaticSize.Y
	gridWrapper.BackgroundTransparency = 1; gridWrapper.Parent = contentFrame

	buildStreamerGrid(gridWrapper, function(item)
		local _, eff = getItemInfo(item)
		return eff == effectName
	end, queue, function()
		buildContent(activeTabId)
	end, effectColor)
end

-------------------------------------------------
-- GEM ROULETTE (wager gems, 50/50 double or gone)
-------------------------------------------------

local function buildGemRouletteContent()
	clearContent()
	local cfg = Sacrifice.GemRoulette

	-- Big warning (same style as the other luck sacrifices)
	local warnFrame = Instance.new("Frame")
	warnFrame.Size = UDim2.new(1, -10, 0, 50)
	warnFrame.BackgroundColor3 = Color3.fromRGB(80, 28, 28); warnFrame.BorderSizePixel = 0
	warnFrame.Parent = contentFrame
	Instance.new("UICorner", warnFrame).CornerRadius = UDim.new(0, 12)
	Instance.new("UIStroke", warnFrame).Color = Color3.fromRGB(200, 70, 50)
	local wl = Instance.new("TextLabel")
	wl.Size = UDim2.new(1, -20, 1, -8); wl.Position = UDim2.new(0.5, 0, 0.5, 0)
	wl.AnchorPoint = Vector2.new(0.5, 0.5); wl.BackgroundTransparency = 1
	wl.Text = Sacrifice.LuckWarning; wl.TextColor3 = Color3.fromRGB(255, 200, 160)
	wl.Font = FONT; wl.TextSize = 13; wl.TextWrapped = true; wl.Parent = warnFrame

	-- Header
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, -10, 0, 130)
	header.BackgroundColor3 = Color3.fromRGB(22, 22, 40)
	header.BorderSizePixel = 0; header.Parent = contentFrame
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, 18)
	local hs = Instance.new("UIStroke", header)
	hs.Color = Color3.fromRGB(255, 180, 50); hs.Thickness = 2.5

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -24, 0, 38)
	title.Position = UDim2.new(0.5, 0, 0, 10); title.AnchorPoint = Vector2.new(0.5, 0)
	title.BackgroundTransparency = 1
	title.Text = "\u{1F3B0} GEM ROULETTE \u{1F3B0}"
	title.TextColor3 = Color3.fromRGB(255, 200, 60)
	title.Font = FONT; title.TextSize = 26; title.Parent = header
	local tStk = Instance.new("UIStroke", title)
	tStk.Color = Color3.fromRGB(0, 0, 0); tStk.Thickness = 2
	tStk.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	local desc = Instance.new("TextLabel")
	desc.Size = UDim2.new(1, -24, 0, 22)
	desc.Position = UDim2.new(0.5, 0, 0, 50); desc.AnchorPoint = Vector2.new(0.5, 0)
	desc.BackgroundTransparency = 1
	desc.Text = cfg.desc
	desc.TextColor3 = Color3.fromRGB(200, 180, 200)
	desc.Font = FONT; desc.TextSize = 14; desc.TextWrapped = true; desc.Parent = header

	-- Charge info
	local sacState = HUDController.Data.sacrificeState or {}
	local chargeData = sacState["GemRoulette"]
	local rechargeSec = cfg.rechargeMinutes * 60
	local charges = cfg.maxCharges
	if chargeData then
		local now = os.time()
		local elapsed = now - (chargeData.lastUsed or 0)
		local recharged = math.floor(elapsed / rechargeSec)
		charges = math.min(cfg.maxCharges, (chargeData.charges or 0) + recharged)
	end

	local chargeLabel = Instance.new("TextLabel")
	chargeLabel.Size = UDim2.new(1, -24, 0, 20)
	chargeLabel.Position = UDim2.new(0.5, 0, 0, 74); chargeLabel.AnchorPoint = Vector2.new(0.5, 0)
	chargeLabel.BackgroundTransparency = 1
	chargeLabel.Text = "Charges: " .. charges .. " / " .. cfg.maxCharges .. "  (1 every " .. cfg.rechargeMinutes .. " min)"
	chargeLabel.TextColor3 = charges > 0 and Color3.fromRGB(100, 255, 120) or Color3.fromRGB(255, 100, 100)
	chargeLabel.Font = FONT; chargeLabel.TextSize = 13; chargeLabel.Parent = header

	-- Gem balance
	local gems = HUDController.Data.gems or 0
	local balLabel = Instance.new("TextLabel")
	balLabel.Size = UDim2.new(1, -24, 0, 20)
	balLabel.Position = UDim2.new(0.5, 0, 0, 100); balLabel.AnchorPoint = Vector2.new(0.5, 0)
	balLabel.BackgroundTransparency = 1
	balLabel.Text = "\u{1F48E} Your Gems: " .. formatNumber(gems)
	balLabel.TextColor3 = Color3.fromRGB(150, 210, 255)
	balLabel.Font = FONT; balLabel.TextSize = 16; balLabel.Parent = header

	-- Wager input area
	local inputRow = Instance.new("Frame")
	inputRow.Size = UDim2.new(1, -10, 0, 50)
	inputRow.BackgroundTransparency = 1; inputRow.Parent = contentFrame
	local irl = Instance.new("UIListLayout", inputRow)
	irl.FillDirection = Enum.FillDirection.Horizontal; irl.Padding = UDim.new(0, 10)
	irl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	irl.VerticalAlignment = Enum.VerticalAlignment.Center

	local inputLabel = Instance.new("TextLabel")
	inputLabel.Size = UDim2.new(0, 100, 0, 44)
	inputLabel.BackgroundTransparency = 1
	inputLabel.Text = "Wager:"
	inputLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
	inputLabel.Font = FONT; inputLabel.TextSize = 20; inputLabel.Parent = inputRow

	local inputBox = Instance.new("TextBox")
	inputBox.Name = "GemWagerInput"
	inputBox.Size = UDim2.new(0, 220, 0, 44)
	inputBox.BackgroundColor3 = Color3.fromRGB(30, 28, 50)
	inputBox.Text = ""; inputBox.PlaceholderText = "Enter gem amount..."
	inputBox.PlaceholderColor3 = Color3.fromRGB(100, 100, 130)
	inputBox.TextColor3 = Color3.fromRGB(255, 220, 80)
	inputBox.Font = FONT; inputBox.TextSize = 20
	inputBox.ClearTextOnFocus = true
	inputBox.TextEditable = true
	inputBox.BorderSizePixel = 0
	inputBox.ZIndex = 5
	inputBox.Parent = inputRow
	Instance.new("UICorner", inputBox).CornerRadius = UDim.new(0, 12)
	local ibStk = Instance.new("UIStroke", inputBox)
	ibStk.Color = Color3.fromRGB(255, 180, 50); ibStk.Thickness = 2
	local ibPad = Instance.new("UIPadding", inputBox)
	ibPad.PaddingLeft = UDim.new(0, 10); ibPad.PaddingRight = UDim.new(0, 10)

	-- SPIN button
	local canSpin = charges > 0
	local spinBtn = Instance.new("TextButton")
	spinBtn.Size = UDim2.new(0, 300, 0, 56)
	spinBtn.BackgroundColor3 = canSpin and Color3.fromRGB(255, 180, 50) or Color3.fromRGB(50, 50, 70)
	spinBtn.Text = canSpin and "\u{1F3B0} SPIN THE ROULETTE" or "NO CHARGES"
	spinBtn.TextColor3 = canSpin and Color3.fromRGB(20, 10, 0) or Color3.fromRGB(110, 110, 130)
	spinBtn.Font = FONT; spinBtn.TextSize = 20; spinBtn.BorderSizePixel = 0; spinBtn.Parent = contentFrame
	Instance.new("UICorner", spinBtn).CornerRadius = UDim.new(0, 14)
	local sbStk = Instance.new("UIStroke", spinBtn)
	sbStk.Color = canSpin and Color3.fromRGB(200, 140, 30) or Color3.fromRGB(40, 40, 55)
	sbStk.Thickness = 2.5

	if canSpin then
		spinBtn.MouseButton1Click:Connect(function()
			local raw = inputBox.Text:gsub(",", ""):gsub("%s+", "")
			local amount = tonumber(raw)
			if not amount or amount <= 0 or amount ~= math.floor(amount) then
				showToast("Enter a valid whole number!", Color3.fromRGB(200, 50, 50), 2)
				return
			end
			local g = HUDController.Data.gems or 0
			if amount > g then
				showToast("Not enough gems! You have " .. formatNumber(g), Color3.fromRGB(200, 50, 50), 2)
				return
			end
			showConfirmation("Wager " .. formatNumber(amount) .. " Gems? 50/50 to DOUBLE or LOSE them all!", function()
				SacrificeRequest:FireServer("GemRoulette", amount)
			end)
		end)
	end
end

-------------------------------------------------
-- SIDEBAR + TAB DISPATCH
-------------------------------------------------

local function highlightSidebar(tabId)
	activeTabId = tabId
	for _, info in ipairs(sidebarBtns) do
		local isActive = info.id == tabId
		info.btn.BackgroundColor3 = isActive and Color3.fromRGB(50, 50, 80) or Color3.fromRGB(22, 22, 38)
		local lbl = info.btn:FindFirstChild("TabLabel")
		if lbl then lbl.TextSize = isActive and 15 or 13 end
	end
end

buildContent = function(tabId)
	local tabChanged = tabId ~= activeTabId
	highlightSidebar(tabId)
	if tabChanged then closePicker() end
	if tabId:sub(1, 8) == "GemTrade" then
		buildGemTradeContent(tonumber(tabId:sub(10)))
	elseif Sacrifice.OneTime[tabId] then
		buildOneTimeContent(tabId)
	elseif tabId == "FiftyFifty" or tabId == "FeelingLucky" or tabId == "DontDoIt" then
		buildLuckContent(tabId)
	elseif tabId == "GemRoulette" then
		buildGemRouletteContent()
	elseif tabId:sub(1, 4) == "Elem" then
		local en = tabId:sub(6); if en == "" then en = nil end
		buildElementalContent(en)
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
		if sidebarBtns[1] then buildContent(sidebarBtns[1].id) end
		UIHelper.ScaleIn(modalFrame, 0.2)
	end
end

function SacrificeController.Close()
	if not isOpen then return end
	isOpen = false
	closePicker()
	cleanupBinarySpin()
	if confirmFrame then confirmFrame:Destroy(); confirmFrame = nil end
	if modalFrame then modalFrame.Visible = false end
	-- NOTE: queues are NOT cleared — they persist for next open
end

-------------------------------------------------
-- INIT
-------------------------------------------------

function SacrificeController.Init()
	screenGui = UIHelper.CreateScreenGui("SacrificeGui", 8)
	screenGui.Parent = playerGui

	modalFrame = Instance.new("Frame")
	modalFrame.Name = "SacrificeModal"
	modalFrame.Size = UDim2.new(0, 880, 0, 640)
	modalFrame.Position = UDim2.new(0.5, 0, 0.5, 0); modalFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	modalFrame.BackgroundColor3 = BG; modalFrame.BorderSizePixel = 0
	modalFrame.Visible = false; modalFrame.ClipsDescendants = true; modalFrame.Parent = screenGui
	Instance.new("UICorner", modalFrame).CornerRadius = UDim.new(0, 24)
	Instance.new("UIStroke", modalFrame).Color = ACCENT

	local topBar = Instance.new("Frame")
	topBar.Size = UDim2.new(1, 0, 0, 8); topBar.BackgroundColor3 = Color3.new(1, 1, 1)
	topBar.BorderSizePixel = 0; topBar.ZIndex = 5; topBar.Parent = modalFrame
	local g = Instance.new("UIGradient", topBar)
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 60, 80)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 130, 130)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 60, 80)),
	})

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, -100, 0, 48); titleLbl.Position = UDim2.new(0.5, 0, 0, 10)
	titleLbl.AnchorPoint = Vector2.new(0.5, 0); titleLbl.BackgroundTransparency = 1
	titleLbl.Text = "SACRIFICE"; titleLbl.TextColor3 = Color3.fromRGB(255, 160, 160)
	titleLbl.Font = FONT; titleLbl.TextSize = 32; titleLbl.Parent = modalFrame
	local tts = Instance.new("UIStroke", titleLbl)
	tts.Color = Color3.fromRGB(60, 0, 20); tts.Thickness = 2.5; tts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	local subLbl = Instance.new("TextLabel")
	subLbl.Size = UDim2.new(1, -20, 0, 20); subLbl.Position = UDim2.new(0.5, 0, 0, 58)
	subLbl.AnchorPoint = Vector2.new(0.5, 0); subLbl.BackgroundTransparency = 1
	subLbl.Text = "Pick streamers to sacrifice — queues save even if you close!"
	subLbl.TextColor3 = Color3.fromRGB(160, 140, 160); subLbl.Font = FONT; subLbl.TextSize = 13
	subLbl.Parent = modalFrame

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 48, 0, 48); closeBtn.Position = UDim2.new(1, -14, 0, 10)
	closeBtn.AnchorPoint = Vector2.new(1, 0); closeBtn.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
	closeBtn.Text = "X"; closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = FONT; closeBtn.TextSize = 24; closeBtn.BorderSizePixel = 0; closeBtn.ZIndex = 10
	closeBtn.Parent = modalFrame
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1, 0)
	closeBtn.MouseButton1Click:Connect(function() SacrificeController.Close() end)

	-- Sidebar
	local sidebarWidth = 200
	local sidebar = Instance.new("ScrollingFrame")
	sidebar.Name = "Sidebar"; sidebar.Size = UDim2.new(0, sidebarWidth, 1, -88)
	sidebar.Position = UDim2.new(0, 0, 0, 88)
	sidebar.BackgroundColor3 = Color3.fromRGB(16, 14, 30); sidebar.BackgroundTransparency = 0.3
	sidebar.BorderSizePixel = 0; sidebar.ScrollBarThickness = 3; sidebar.ScrollBarImageColor3 = ACCENT
	sidebar.CanvasSize = UDim2.new(0, 0, 0, 0); sidebar.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sidebar.Parent = modalFrame

	Instance.new("UIListLayout", sidebar).SortOrder = Enum.SortOrder.LayoutOrder
	sidebar:FindFirstChildOfClass("UIListLayout").Padding = UDim.new(0, 5)
	local sp = Instance.new("UIPadding", sidebar)
	sp.PaddingTop = UDim.new(0, 6); sp.PaddingLeft = UDim.new(0, 6)
	sp.PaddingRight = UDim.new(0, 6); sp.PaddingBottom = UDim.new(0, 10)

	local tabOrder = 0
	local function addSection(text)
		tabOrder = tabOrder + 1
		local l = Instance.new("TextLabel"); l.Size = UDim2.new(1, 0, 0, 24)
		l.BackgroundTransparency = 1; l.Text = text
		l.TextColor3 = Color3.fromRGB(100, 100, 130); l.Font = FONT; l.TextSize = 11
		l.LayoutOrder = tabOrder; l.Parent = sidebar
	end
	local function addTab(id, name, color)
		tabOrder = tabOrder + 1
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 0, 40); btn.BackgroundColor3 = Color3.fromRGB(22, 22, 38)
		btn.BorderSizePixel = 0; btn.LayoutOrder = tabOrder; btn.Text = ""; btn.Parent = sidebar
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)
		local strip = Instance.new("Frame")
		strip.Size = UDim2.new(0, 5, 0.65, 0); strip.Position = UDim2.new(0, 4, 0.175, 0)
		strip.BackgroundColor3 = color; strip.BorderSizePixel = 0; strip.Parent = btn
		Instance.new("UICorner", strip).CornerRadius = UDim.new(0, 2)
		local lbl = Instance.new("TextLabel")
		lbl.Name = "TabLabel"; lbl.Size = UDim2.new(1, -16, 1, 0); lbl.Position = UDim2.new(0, 14, 0, 0)
		lbl.BackgroundTransparency = 1; lbl.Text = name; lbl.TextColor3 = color
		lbl.Font = FONT; lbl.TextSize = 13; lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.TextTruncate = Enum.TextTruncate.AtEnd; lbl.Parent = btn
		btn.MouseButton1Click:Connect(function() buildContent(id) end)
		table.insert(sidebarBtns, { id = id, btn = btn })
	end

	addSection("— GEM TRADES —")
	for i, tr in ipairs(Sacrifice.GemTrades) do
		addTab("GemTrade_" .. i, tr.rarity .. " -> " .. formatNumber(tr.gems), DesignConfig.RarityColors[tr.rarity] or Color3.new(1, 1, 1))
	end
	addSection("— ONE-TIME —")
	addTab("CommonArmy", "Common Army", Color3.fromRGB(160, 160, 190))
	addTab("FatPeople", "Fat People", Color3.fromRGB(255, 200, 60))
	addTab("GirlPower", "Girl Power", Color3.fromRGB(255, 130, 200))
	addTab("RareRoundup", "Rare Roundup", Color3.fromRGB(80, 180, 255))
	addTab("ContentHouse", "Content House", Color3.fromRGB(255, 150, 80))
	addTab("EpicEnsemble", "Epic Ensemble", Color3.fromRGB(200, 80, 220))
	addTab("GamblingAddicts", "Gambling Addicts", Color3.fromRGB(60, 220, 60))
	addTab("TheOGs", "The OGs", Color3.fromRGB(180, 180, 180))
	addTab("FPSLegends", "FPS Legends", Color3.fromRGB(255, 80, 80))
	addTab("TwitchRoyalty", "Twitch Royalty", Color3.fromRGB(180, 120, 255))
	addTab("TheUntouchables", "The Untouchables", Color3.fromRGB(255, 50, 50))
	addTab("Rainbow", "Rainbow", Color3.fromRGB(120, 255, 200))
	addTab("MythicRoyale", "Mythic Royale", Color3.fromRGB(255, 215, 0))
	addSection("— ELEMENTAL ONE-TIME —")
	addTab("AcidReflex", "Acid Reflex", Color3.fromRGB(50, 255, 50))
	addTab("SnowyAvalanche", "Snowy Avalanche", Color3.fromRGB(180, 220, 255))
	addTab("LavaEruption", "Lava Eruption", Color3.fromRGB(255, 100, 20))
	addTab("LightningStrike", "Lightning Strike", Color3.fromRGB(255, 255, 80))
	addTab("ShadowRealm", "Shadow Realm", Color3.fromRGB(100, 60, 140))
	addTab("GlitchStorm", "Glitch Storm", Color3.fromRGB(0, 255, 255))
	addTab("LunarTide", "Lunar Tide", Color3.fromRGB(200, 220, 255))
	addTab("SolarFlare", "Solar Flare", Color3.fromRGB(255, 220, 60))
	addTab("VoidAbyss", "Void Abyss", Color3.fromRGB(80, 40, 120))
	addSection("— TEST YOUR LUCK —")
	addTab("FiftyFifty", "50 / 50", Color3.fromRGB(255, 220, 60))
	addTab("FeelingLucky", "Feeling Lucky?", Color3.fromRGB(100, 200, 255))
	addTab("DontDoIt", "Don't do it", Color3.fromRGB(255, 80, 80))
	addTab("GemRoulette", "Gem Roulette", Color3.fromRGB(255, 180, 50))
	addSection("— ELEMENTAL —")
	addTab("Elem_", "Default", Color3.fromRGB(170, 170, 170))
	for _, eff in ipairs(Effects.List) do
		addTab("Elem_" .. eff.name, eff.name, eff.color)
	end

	-- Content area
	contentFrame = Instance.new("ScrollingFrame")
	contentFrame.Name = "Content"
	contentFrame.Size = UDim2.new(1, -sidebarWidth - 14, 1, -88)
	contentFrame.Position = UDim2.new(0, sidebarWidth + 8, 0, 88)
	contentFrame.BackgroundTransparency = 1; contentFrame.BorderSizePixel = 0
	contentFrame.ScrollBarThickness = 6; contentFrame.ScrollBarImageColor3 = ACCENT
	contentFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	contentFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y; contentFrame.Parent = modalFrame

	local cl = Instance.new("UIListLayout", contentFrame)
	cl.SortOrder = Enum.SortOrder.LayoutOrder; cl.Padding = UDim.new(0, 12)
	cl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	Instance.new("UIPadding", contentFrame).PaddingTop = UDim.new(0, 10)
	contentFrame:FindFirstChildOfClass("UIPadding").PaddingBottom = UDim.new(0, 14)

	-- Events
	OpenSacrificeGui.OnClientEvent:Connect(function()
		if isOpen then SacrificeController.Close() else SacrificeController.Open() end
	end)

	SacrificeResult.OnClientEvent:Connect(function(result)
		if result.success then
			-----------------------------------------------------------
			-- BINARY SPIN ANIMATIONS (unskippable, dramatic!)
			-----------------------------------------------------------
			if result.sacrificeType == "FiftyFifty" then
				local isGood = result.outcome == "double"
				showBinarySpin("2X CASH!", "HALF CASH", isGood, "\u{1F4B0}", "\u{1F4B8}", function()
					local msg, c
					if isGood then
						msg = "JACKPOT! Cash doubled to $" .. formatNumber(result.newCash or 0) .. "!"
						c = Color3.fromRGB(255, 220, 60)
					else
						msg = "Cash halved to $" .. formatNumber(result.newCash or 0)
						c = Color3.fromRGB(200, 80, 60)
					end
					showToast(msg, c, 3.5)
					task.defer(function() task.wait(0.3); if isOpen and activeTabId then buildContent(activeTabId) end end)
				end)
				return

			elseif result.sacrificeType == "FeelingLucky" then
				local isGood = result.outcome == "buff"
				showBinarySpin("+100% LUCK!", "-100% LUCK", isGood, "\u{1F340}", "\u{1F480}", function()
					local msg, c
					if isGood then
						msg = "+100% Luck for 10 min!"
						c = Color3.fromRGB(80, 220, 255)
					else
						msg = "-100% Luck for 10 min..."
						c = Color3.fromRGB(200, 80, 60)
					end
					showToast(msg, c, 3.5)
					task.defer(function() task.wait(0.3); if isOpen and activeTabId then buildContent(activeTabId) end end)
				end)
				return

			elseif result.sacrificeType == "DontDoIt" then
				local isGood = result.upgraded == true
				showBinarySpin("UPGRADE!", "GONE...", isGood, "\u{2B06}", "\u{274C}", function()
					local msg, c
					if isGood then
						local displayName = result.streamerId or "?"
						if result.effect then displayName = result.effect .. " " .. displayName end
						msg = "UPGRADED! " .. (result.rarity or "") .. " " .. displayName .. "!"
						c = Color3.fromRGB(255, 220, 60)
					else
						msg = "No upgrade... streamers gone."
						c = Color3.fromRGB(200, 80, 60)
					end
					showToast(msg, c, 3.5)
					task.defer(function() task.wait(0.3); if isOpen and activeTabId then buildContent(activeTabId) end end)
				end)
				return

			elseif result.sacrificeType == "GemRoulette" then
				local isGood = result.outcome == "double"
				showBinarySpin("DOUBLE!", "GONE!", isGood, "\u{1F48E}", "\u{1F4A8}", function()
					local msg, c
					if isGood then
						msg = "DOUBLED! +" .. formatNumber(result.wager or 0) .. " Gems! Now: " .. formatNumber(result.newGems or 0)
						c = Color3.fromRGB(255, 220, 60)
					else
						msg = "GONE! Lost " .. formatNumber(result.wager or 0) .. " Gems... Now: " .. formatNumber(result.newGems or 0)
						c = Color3.fromRGB(200, 80, 60)
					end
					showToast(msg, c, 3.5)
					task.defer(function() task.wait(0.3); if isOpen and activeTabId then buildContent(activeTabId) end end)
				end)
				return
			end

			-----------------------------------------------------------
			-- STANDARD TOASTS (gem trades, one-time, elemental)
			-----------------------------------------------------------
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
			showToast(result.reason or "Failed!", Color3.fromRGB(200, 50, 50), 3)
		end
		task.defer(function() task.wait(0.3); if isOpen and activeTabId then buildContent(activeTabId) end end)
	end)

	HUDController.OnDataUpdated(function()
		-- Don't rebuild while picker or binary spin is open — data updates (cash ticks etc.)
		-- would destroy the picker before the player can select a streamer
		if isOpen and activeTabId and not pickerFrame and not binarySpinOverlay then buildContent(activeTabId) end
	end)

	modalFrame.Visible = false
end

--- Public: get the full set of queued virtual indices (for hiding from inventory/storage)
function SacrificeController.GetQueuedIndices()
	return allQueuedIndices()
end

-- Callbacks for when queues change (so inventory/storage can refresh visuals)
local onQueueChanged = {}
function SacrificeController.OnQueueChanged(cb)
	table.insert(onQueueChanged, cb)
end
local function fireQueueChanged()
	for _, cb in ipairs(onQueueChanged) do
		task.spawn(cb)
	end
end

return SacrificeController
