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
local StoreController = require(script.Parent.StoreController)

local SacrificeController = {}

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RemoteEvents     = ReplicatedStorage:WaitForChild("RemoteEvents")
local OpenSacrificeGui = RemoteEvents:WaitForChild("OpenSacrificeGui")
local SacrificeRequest = RemoteEvents:WaitForChild("SacrificeRequest")
local SacrificeResult  = RemoteEvents:WaitForChild("SacrificeResult")

local screenGui, modalFrame
local contentFrame
local rarityBarFrame  -- horizontal rarity buttons (visible only in "Gem Sacrifice" mode)
local topTabBtns = {}
local activeTopTab = "gems"
local activeGemRarity = 1   -- index into Sacrifice.GemTrades
local isOpen       = false

-- Per-tab sidebars and their button lists
local sidebars = {}     -- { onetime = frame, elemOnetime = frame, luck = frame }
local sidebarBtnLists = { onetime = {}, elemOnetime = {}, luck = {} }
local activeTabId  = nil
local confirmFrame = nil
local pickerFrame  = nil
local gemRouletteInputActive = false
local onOpenCallbacks = {}
local onCloseCallbacks = {}
local rarityBtns = {} -- { {btn, idx} } for the horizontal rarity bar

local FONT   = Enum.Font.FredokaOne
local FONT2  = Enum.Font.GothamBold
local BG     = Color3.fromRGB(45, 35, 75)
local ACCENT = Color3.fromRGB(255, 100, 120)

-- Scale helper — UIScale on the ScreenGui now handles responsive sizing,
-- so S = 1 (pixel values stay at their authored 1080p sizes).
local S = 1
local function sx(n) return math.floor(n * S + 0.5) end

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

-- Queue-change callbacks (must be defined before any content builder that calls fireQueueChanged)
local onQueueChanged = {}
local function fireQueueChanged()
	for _, cb in ipairs(onQueueChanged) do
		task.spawn(cb)
	end
end

local function clearAllQueues()
	gemTradeQueues = {}
	oneTimeQueues = {}
	elementalQueues = {}
	effectOneTimeQueues = {}
	fireQueueChanged()
end

-------------------------------------------------
-- AVATAR SLOT HELPER
-------------------------------------------------

local modelsFolder = ReplicatedStorage:FindFirstChild("StreamerModels")

local function buildAvatarSlot(slot, streamerId)
	local modelTemplate = modelsFolder and modelsFolder:FindFirstChild(streamerId)
	if not modelTemplate then
		local fallback = Instance.new("TextLabel")
		fallback.Size = UDim2.new(1, 0, 1, 0); fallback.BackgroundTransparency = 1
		local dn = Streamers.ById[streamerId] and Streamers.ById[streamerId].displayName or streamerId
		fallback.Text = dn:sub(1, 2):upper(); fallback.TextColor3 = Color3.fromRGB(200, 255, 200)
		fallback.Font = FONT; fallback.TextSize = sx(18); fallback.Parent = slot
		return
	end

	slot.ClipsDescendants = true
	local vp = Instance.new("ViewportFrame")
	vp.Size = UDim2.new(1, 0, 1, 0); vp.BackgroundTransparency = 1
	vp.BorderSizePixel = 0; vp.Parent = slot

	local vpModel = modelTemplate:Clone()
	vpModel.Parent = vp
	local vpCam = Instance.new("Camera"); vpCam.Parent = vp; vp.CurrentCamera = vpCam

	local ok, cf, size = pcall(function() return vpModel:GetBoundingBox() end)
	if ok and cf and size then
		local dist = math.max(size.X, size.Y, size.Z) * 1.6
		local target = cf.Position
		local yOff = size.Y * 0.15
		vpCam.CFrame = CFrame.new(target + Vector3.new(0, yOff, dist), target)
	else
		vpCam.CFrame = CFrame.new(Vector3.new(0, 2, 4), Vector3.new(0, 1, 0))
	end
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
-- NOT ENOUGH GEMS POPUP
-------------------------------------------------

local activeGemPopup = nil

local function showNotEnoughGemsPopup()
	if activeGemPopup and activeGemPopup.Parent then activeGemPopup:Destroy() end

	local dim = Instance.new("Frame")
	dim.Name = "GemPopupDim"
	dim.Size = UDim2.new(1, 0, 1, 0)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.ZIndex = 80
	dim.Parent = screenGui
	activeGemPopup = dim

	TweenService:Create(dim, TweenInfo.new(0.2), { BackgroundTransparency = 0.4 }):Play()

	local box = Instance.new("Frame")
	box.Name = "GemPopupBox"
	box.Size = UDim2.new(0, sx(400), 0, sx(240))
	box.Position = UDim2.new(0.5, 0, 0.5, 0)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.BackgroundColor3 = Color3.fromRGB(28, 22, 48)
	box.BorderSizePixel = 0
	box.ZIndex = 81
	box.Parent = dim
	Instance.new("UICorner", box).CornerRadius = UDim.new(0, sx(22))

	local boxStroke = Instance.new("UIStroke")
	boxStroke.Color = Color3.fromRGB(120, 90, 200)
	boxStroke.Thickness = 2.5
	boxStroke.Parent = box

	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(45, 35, 75)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(32, 26, 55)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 18, 38)),
	})
	grad.Rotation = 90
	grad.Parent = box

	UIHelper.CreateShadow(box)

	local gemIcon = Instance.new("TextLabel")
	gemIcon.Size = UDim2.new(0, sx(56), 0, sx(56))
	gemIcon.Position = UDim2.new(0.5, 0, 0, sx(22))
	gemIcon.AnchorPoint = Vector2.new(0.5, 0)
	gemIcon.BackgroundTransparency = 1
	gemIcon.Text = "\u{1F48E}"
	gemIcon.TextScaled = true
	gemIcon.Font = FONT
	gemIcon.ZIndex = 83
	gemIcon.Parent = box

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -40, 0, sx(30))
	title.Position = UDim2.new(0.5, 0, 0, sx(84))
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.BackgroundTransparency = 1
	title.Text = "Not Enough Gems!"
	title.TextColor3 = Color3.fromRGB(255, 90, 90)
	title.Font = FONT
	title.TextSize = sx(26)
	title.ZIndex = 82
	title.Parent = box

	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.fromRGB(0, 0, 0)
	titleStroke.Thickness = 2.5
	titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	titleStroke.Parent = title

	local descLbl = Instance.new("TextLabel")
	descLbl.Size = UDim2.new(1, -50, 0, sx(20))
	descLbl.Position = UDim2.new(0.5, 0, 0, sx(120))
	descLbl.AnchorPoint = Vector2.new(0.5, 0)
	descLbl.BackgroundTransparency = 1
	descLbl.Text = "Would you like to buy more gems?"
	descLbl.TextColor3 = Color3.fromRGB(190, 185, 210)
	descLbl.Font = FONT2
	descLbl.TextSize = sx(14)
	descLbl.ZIndex = 82
	descLbl.Parent = box

	local function dismiss()
		TweenService:Create(dim, TweenInfo.new(0.15), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(box, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Size = UDim2.new(0, sx(200), 0, sx(120)),
		}):Play()
		task.delay(0.16, function()
			if dim.Parent then dim:Destroy() end
			activeGemPopup = nil
		end)
	end

	local btnRow = Instance.new("Frame")
	btnRow.Size = UDim2.new(1, -60, 0, sx(44))
	btnRow.Position = UDim2.new(0.5, 0, 1, -sx(32))
	btnRow.AnchorPoint = Vector2.new(0.5, 1)
	btnRow.BackgroundTransparency = 1
	btnRow.ZIndex = 82
	btnRow.Parent = box

	local btnLayout = Instance.new("UIListLayout")
	btnLayout.FillDirection = Enum.FillDirection.Horizontal
	btnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	btnLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	btnLayout.Padding = UDim.new(0, sx(16))
	btnLayout.Parent = btnRow

	local yesBtn = Instance.new("TextButton")
	yesBtn.Name = "YesBtn"
	yesBtn.Size = UDim2.new(0, sx(150), 0, sx(44))
	yesBtn.BackgroundColor3 = Color3.fromRGB(50, 190, 80)
	yesBtn.Text = "Yes, Buy Gems!"
	yesBtn.TextColor3 = Color3.new(1, 1, 1)
	yesBtn.Font = FONT
	yesBtn.TextSize = sx(16)
	yesBtn.BorderSizePixel = 0
	yesBtn.AutoButtonColor = false
	yesBtn.ZIndex = 83
	yesBtn.Parent = btnRow
	Instance.new("UICorner", yesBtn).CornerRadius = UDim.new(0, sx(12))

	local yesStroke = Instance.new("UIStroke")
	yesStroke.Color = Color3.fromRGB(30, 140, 50)
	yesStroke.Thickness = 2
	yesStroke.Parent = yesBtn

	local yesGrad = Instance.new("UIGradient")
	yesGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 220, 100)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 170, 65)),
	})
	yesGrad.Rotation = 90
	yesGrad.Parent = yesBtn

	local noBtn = Instance.new("TextButton")
	noBtn.Name = "NoBtn"
	noBtn.Size = UDim2.new(0, sx(120), 0, sx(44))
	noBtn.BackgroundColor3 = Color3.fromRGB(65, 55, 85)
	noBtn.Text = "No Thanks"
	noBtn.TextColor3 = Color3.fromRGB(180, 170, 200)
	noBtn.Font = FONT
	noBtn.TextSize = sx(16)
	noBtn.BorderSizePixel = 0
	noBtn.AutoButtonColor = false
	noBtn.ZIndex = 83
	noBtn.Parent = btnRow
	Instance.new("UICorner", noBtn).CornerRadius = UDim.new(0, sx(12))

	local noStroke = Instance.new("UIStroke")
	noStroke.Color = Color3.fromRGB(90, 75, 120)
	noStroke.Thickness = 2
	noStroke.Parent = noBtn

	local hoverTI = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	yesBtn.MouseEnter:Connect(function()
		TweenService:Create(yesBtn, hoverTI, { Size = UDim2.new(0, sx(156), 0, sx(46)) }):Play()
		TweenService:Create(yesStroke, hoverTI, { Color = Color3.fromRGB(50, 200, 80) }):Play()
	end)
	yesBtn.MouseLeave:Connect(function()
		TweenService:Create(yesBtn, hoverTI, { Size = UDim2.new(0, sx(150), 0, sx(44)) }):Play()
		TweenService:Create(yesStroke, hoverTI, { Color = Color3.fromRGB(30, 140, 50) }):Play()
	end)
	noBtn.MouseEnter:Connect(function()
		TweenService:Create(noBtn, hoverTI, { Size = UDim2.new(0, sx(126), 0, sx(46)) }):Play()
		TweenService:Create(noBtn, hoverTI, { BackgroundColor3 = Color3.fromRGB(85, 70, 110) }):Play()
	end)
	noBtn.MouseLeave:Connect(function()
		TweenService:Create(noBtn, hoverTI, { Size = UDim2.new(0, sx(120), 0, sx(44)) }):Play()
		TweenService:Create(noBtn, hoverTI, { BackgroundColor3 = Color3.fromRGB(65, 55, 85) }):Play()
	end)

	yesBtn.MouseButton1Click:Connect(function()
		dismiss()
		SacrificeController.Close()
		StoreController.Open()
	end)

	noBtn.MouseButton1Click:Connect(function()
		dismiss()
	end)

	dim.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if input.Position then
				local absPos = box.AbsolutePosition
				local absSize = box.AbsoluteSize
				local px, py = input.Position.X, input.Position.Y
				if px < absPos.X or px > absPos.X + absSize.X or py < absPos.Y or py > absPos.Y + absSize.Y then
					dismiss()
				end
			end
		end
	end)

	box.Size = UDim2.new(0, sx(200), 0, sx(120))
	TweenService:Create(box, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, sx(400), 0, sx(240)),
	}):Play()
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
		local vi = entry.vi
		local id, eff, info = getItemInfo(item)
		local rColor = DesignConfig.RarityColors[info and info.rarity or "Common"] or Color3.new(1, 1, 1)
		local isStorage = vi > STORAGE_OFFSET

		local cell = Instance.new("TextButton")
		cell.Size = UDim2.new(0, sx(100), 0, sx(120))
		cell.BackgroundColor3 = Color3.fromRGB(50, 42, 80); cell.BorderSizePixel = 0
		cell.Text = ""; cell.LayoutOrder = order; cell.ZIndex = 42; cell.Parent = scroll
		Instance.new("UICorner", cell).CornerRadius = UDim.new(0, sx(12))
		local cs = Instance.new("UIStroke", cell); cs.Color = rColor; cs.Thickness = 2; cs.Transparency = 0.2

		-- Avatar viewport (centered top)
		local pvpS = sx(48)
		local pvp = Instance.new("ViewportFrame")
		pvp.Size = UDim2.new(0, pvpS, 0, pvpS)
		pvp.Position = UDim2.new(0.5, 0, 0, sx(8))
		pvp.AnchorPoint = Vector2.new(0.5, 0)
		pvp.BackgroundColor3 = Color3.fromRGB(30, 26, 50); pvp.BackgroundTransparency = 0.3
		pvp.BorderSizePixel = 0; pvp.ZIndex = 43; pvp.Parent = cell
		pvp.ClipsDescendants = true
		Instance.new("UICorner", pvp).CornerRadius = UDim.new(1, 0)

		local pStreamerId = type(item) == "table" and item.id or item
		local pTmpl = modelsFolder and modelsFolder:FindFirstChild(pStreamerId)
		if pTmpl then
			local pm = pTmpl:Clone(); pm.Parent = pvp
			local pCam = Instance.new("Camera"); pCam.Parent = pvp; pvp.CurrentCamera = pCam
			local pOk, pCf, pSz = pcall(function() return pm:GetBoundingBox() end)
			if pOk and pCf and pSz then
				local pDist = math.max(pSz.X, pSz.Y, pSz.Z) * 1.6
				pCam.CFrame = CFrame.new(pCf.Position + Vector3.new(0, pSz.Y * 0.15, pDist), pCf.Position)
			else
				pCam.CFrame = CFrame.new(Vector3.new(0, 2, 4), Vector3.new(0, 1, 0))
			end
		end

		-- Storage badge (top-right corner)
		if isStorage then
			local si = Instance.new("TextLabel")
			si.Size = UDim2.new(0, sx(16), 0, sx(16)); si.Position = UDim2.new(1, -sx(6), 0, sx(4))
			si.AnchorPoint = Vector2.new(1, 0); si.BackgroundColor3 = Color3.fromRGB(200, 120, 30)
			si.Text = "S"; si.TextColor3 = Color3.new(1, 1, 1)
			si.Font = Enum.Font.GothamBold; si.TextSize = sx(9); si.ZIndex = 44; si.Parent = cell
			Instance.new("UICorner", si).CornerRadius = UDim.new(1, 0)
		end

		-- Name (centered, below avatar)
		local nameY = sx(8) + pvpS + sx(4)
		local nl2 = Instance.new("TextLabel")
		nl2.Size = UDim2.new(1, -sx(8), 0, sx(18)); nl2.Position = UDim2.new(0.5, 0, 0, nameY)
		nl2.AnchorPoint = Vector2.new(0.5, 0); nl2.BackgroundTransparency = 1
		nl2.Text = id; nl2.TextColor3 = rColor
		nl2.Font = FONT; nl2.TextSize = sx(12); nl2.TextTruncate = Enum.TextTruncate.AtEnd
		nl2.ZIndex = 43; nl2.Parent = cell

		-- Effect (if any, below name)
		if eff then
			local el = Instance.new("TextLabel")
			el.Size = UDim2.new(1, -sx(8), 0, sx(14)); el.Position = UDim2.new(0.5, 0, 0, nameY + sx(16))
			el.AnchorPoint = Vector2.new(0.5, 0); el.BackgroundTransparency = 1
			el.Text = eff; el.TextColor3 = (Effects.ByName[eff] and Effects.ByName[eff].color) or Color3.fromRGB(180, 180, 180)
			el.Font = FONT2; el.TextSize = sx(10); el.ZIndex = 43; el.Parent = cell
		end

		-- Rarity (bottom center)
		local rl = Instance.new("TextLabel")
		rl.Size = UDim2.new(1, 0, 0, sx(16)); rl.Position = UDim2.new(0.5, 0, 1, -sx(18))
		rl.AnchorPoint = Vector2.new(0.5, 0); rl.BackgroundTransparency = 1
		rl.Text = info and info.rarity or "?"; rl.TextColor3 = rColor
		rl.Font = FONT2; rl.TextSize = sx(11); rl.ZIndex = 43; rl.Parent = cell

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
		local emptyFrame = Instance.new("Frame")
		emptyFrame.Size = UDim2.new(1, 0, 0, sx(90)); emptyFrame.BackgroundTransparency = 1; emptyFrame.Parent = parent

		local nl = Instance.new("TextLabel")
		nl.Size = UDim2.new(1, 0, 0, sx(30)); nl.Position = UDim2.new(0.5, 0, 0, sx(8))
		nl.AnchorPoint = Vector2.new(0.5, 0); nl.BackgroundTransparency = 1
		nl.Text = "No eligible streamers yet!"; nl.TextColor3 = Color3.fromRGB(180, 160, 210)
		nl.Font = FONT; nl.TextSize = sx(18); nl.TextWrapped = true; nl.Parent = emptyFrame
		return
	end

	-- Grid container (wrapped in a frame so it sizes correctly)
	local gridFrame = Instance.new("Frame")
	gridFrame.Size = UDim2.new(1, 0, 0, 0)
	gridFrame.AutomaticSize = Enum.AutomaticSize.Y
	gridFrame.BackgroundTransparency = 1; gridFrame.Parent = parent

	local grid = Instance.new("UIGridLayout", gridFrame)
	grid.CellSize = UDim2.new(0, sx(130), 0, sx(110))
	grid.CellPadding = UDim2.new(0, sx(8), 0, sx(8))
	grid.SortOrder = Enum.SortOrder.LayoutOrder

	for order, entry in ipairs(items) do
		local item = entry.item
		local vi = entry.vi
		local id, eff, info = getItemInfo(item)
		local selected = queueSet[vi] == true
		local rColor = DesignConfig.RarityColors[info and info.rarity or "Common"] or Color3.new(1, 1, 1)
		local isStorage = entry.source == "storage"

		local cell = Instance.new("TextButton")
		cell.Size = UDim2.new(0, sx(130), 0, sx(110))
		cell.BackgroundColor3 = selected and Color3.fromRGB(40, 120, 60) or Color3.fromRGB(50, 42, 80)
		cell.BorderSizePixel = 0; cell.Text = ""; cell.LayoutOrder = order
		cell.Parent = gridFrame
		Instance.new("UICorner", cell).CornerRadius = UDim.new(0, sx(14))
		local cs = Instance.new("UIStroke", cell)
		cs.Color = selected and Color3.fromRGB(80, 240, 100) or rColor
		cs.Thickness = selected and 2.5 or 1.5
		cs.Transparency = selected and 0 or 0.3

		-- Avatar viewport (top-left)
		local vpS = sx(44)
		local vp = Instance.new("ViewportFrame")
		vp.Size = UDim2.new(0, vpS, 0, vpS)
		vp.Position = UDim2.new(0, sx(6), 0, sx(6))
		vp.BackgroundColor3 = Color3.fromRGB(30, 26, 50); vp.BackgroundTransparency = 0.3
		vp.BorderSizePixel = 0; vp.Parent = cell
		vp.ClipsDescendants = true
		Instance.new("UICorner", vp).CornerRadius = UDim.new(1, 0)

		local streamerId = type(item) == "table" and item.id or item
		local tmpl = modelsFolder and modelsFolder:FindFirstChild(streamerId)
		if tmpl then
			local m = tmpl:Clone(); m.Parent = vp
			local cam = Instance.new("Camera"); cam.Parent = vp; vp.CurrentCamera = cam
			local okk, cf2, sz2 = pcall(function() return m:GetBoundingBox() end)
			if okk and cf2 and sz2 then
				local d = math.max(sz2.X, sz2.Y, sz2.Z) * 1.6
				cam.CFrame = CFrame.new(cf2.Position + Vector3.new(0, sz2.Y * 0.15, d), cf2.Position)
			else
				cam.CFrame = CFrame.new(Vector3.new(0, 2, 4), Vector3.new(0, 1, 0))
			end
		end

		-- Storage indicator
		if isStorage then
			local si = Instance.new("TextLabel")
			si.Size = UDim2.new(0, sx(18), 0, sx(12)); si.Position = UDim2.new(1, -sx(4), 0, sx(2))
			si.AnchorPoint = Vector2.new(1, 0); si.BackgroundTransparency = 1
			si.Text = "S"; si.TextColor3 = Color3.fromRGB(255, 165, 50)
			si.Font = Enum.Font.GothamBold; si.TextSize = sx(10); si.Parent = cell
		end

		local textX = vpS + sx(10)
		local textW = sx(130) - textX - sx(4)

		-- Name
		local nl2 = Instance.new("TextLabel")
		nl2.Size = UDim2.new(0, textW, 0, sx(22)); nl2.Position = UDim2.new(0, textX, 0, sx(6))
		nl2.BackgroundTransparency = 1; nl2.TextXAlignment = Enum.TextXAlignment.Left
		nl2.Text = id; nl2.TextColor3 = selected and Color3.fromRGB(200, 255, 200) or rColor
		nl2.Font = FONT; nl2.TextSize = sx(13); nl2.TextTruncate = Enum.TextTruncate.AtEnd
		nl2.Parent = cell

		-- Effect
		if eff then
			local el = Instance.new("TextLabel")
			el.Size = UDim2.new(0, textW, 0, sx(16)); el.Position = UDim2.new(0, textX, 0, sx(26))
			el.BackgroundTransparency = 1; el.TextXAlignment = Enum.TextXAlignment.Left
			el.Text = eff
			el.TextColor3 = (Effects.ByName[eff] and Effects.ByName[eff].color) or Color3.fromRGB(180, 180, 180)
			el.Font = FONT2; el.TextSize = sx(11); el.Parent = cell
		end

		-- Checkmark or rarity (bottom)
		local bl = Instance.new("TextLabel")
		bl.Size = UDim2.new(1, 0, 0, sx(20)); bl.Position = UDim2.new(0.5, 0, 1, -sx(22))
		bl.AnchorPoint = Vector2.new(0.5, 0); bl.BackgroundTransparency = 1
		bl.Text = selected and "\u{2705} QUEUED" or (info and info.rarity or "")
		bl.TextColor3 = selected and Color3.fromRGB(100, 255, 120) or Color3.fromRGB(140, 130, 170)
		bl.Font = FONT; bl.TextSize = sx(12); bl.Parent = cell

		local capVI = vi
		cell.MouseButton1Click:Connect(function()
			if queueSet[capVI] then
				queueSet[capVI] = nil
			else
				queueSet[capVI] = true
			end
			fireQueueChanged()
			if onChanged then onChanged() end
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

	validateQueueSet(queue, function(item)
		local _, _, info = getItemInfo(item)
		return info and info.rarity == trade.rarity
	end)

	local selected = queueSetCount(queue)
	local need = trade.count
	local rc = DesignConfig.RarityColors[trade.rarity] or Color3.new(1, 1, 1)
	local canSacrifice = selected >= need

	-- Visual queue: horizontal row of circular slots
	local slotRowH = math.min(need, 10) > 5 and sx(160) or sx(80)
	local slotsPerRow = math.min(need, 10)
	local slotSize = sx(60)
	local slotGap = sx(8)
	local totalRows = math.ceil(need / slotsPerRow)
	slotRowH = totalRows * (slotSize + slotGap) + sx(12)

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

	-- Build the filled indices list in order
	local filledList = {}
	for vi in pairs(queue) do table.insert(filledList, vi) end
	table.sort(filledList)

	for i = 1, need do
		local vi = filledList[i]
		local isFilled = vi ~= nil
		local slot = Instance.new("Frame")
		slot.Size = UDim2.new(0, slotSize, 0, slotSize)
		slot.BackgroundColor3 = isFilled and Color3.fromRGB(40, 120, 60) or Color3.fromRGB(50, 42, 80)
		slot.BorderSizePixel = 0; slot.LayoutOrder = i; slot.Parent = slotGrid
		Instance.new("UICorner", slot).CornerRadius = UDim.new(1, 0)
		local slotStroke = Instance.new("UIStroke", slot)
		slotStroke.Color = isFilled and Color3.fromRGB(80, 240, 100) or rc
		slotStroke.Thickness = isFilled and 2.5 or 1.5
		slotStroke.Transparency = isFilled and 0 or 0.5

		if isFilled then
			local item = resolveVirtualItem(vi)
			local id = type(item) == "table" and item.id or (item or "?")
			buildAvatarSlot(slot, id)
		end
	end

	-- Counter text
	local counterLbl = Instance.new("TextLabel")
	counterLbl.Size = UDim2.new(1, -sx(12), 0, sx(28))
	counterLbl.BackgroundTransparency = 1
	counterLbl.Text = selected .. " / " .. need .. " queued  —  " .. formatNumber(trade.gems) .. " Gems"
	counterLbl.TextColor3 = canSacrifice and Color3.fromRGB(100, 255, 120) or rc
	counterLbl.Font = FONT; counterLbl.TextSize = sx(20); counterLbl.Parent = contentFrame
	local cntStroke = Instance.new("UIStroke", counterLbl)
	cntStroke.Color = Color3.fromRGB(15, 10, 30); cntStroke.Thickness = 1.5
	cntStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	-- Action row: primary "Auto Fill & Sacrifice" + secondary "Clear" link
	local actionRow = Instance.new("Frame")
	actionRow.Size = UDim2.new(1, -sx(12), 0, sx(64)); actionRow.BackgroundTransparency = 1; actionRow.Parent = contentFrame
	local arl = Instance.new("UIListLayout", actionRow)
	arl.FillDirection = Enum.FillDirection.Horizontal
	arl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	arl.VerticalAlignment = Enum.VerticalAlignment.Center; arl.Padding = UDim.new(0, sx(16))

	local mainBtn = Instance.new("TextButton")
	mainBtn.Size = UDim2.new(0, sx(320), 0, sx(56))
	mainBtn.BorderSizePixel = 0; mainBtn.Parent = actionRow
	Instance.new("UICorner", mainBtn).CornerRadius = UDim.new(0, sx(16))

	if canSacrifice then
		mainBtn.BackgroundColor3 = rc
		mainBtn.Text = "SACRIFICE " .. formatNumber(trade.gems) .. " Gems"
		mainBtn.TextColor3 = Color3.new(1, 1, 1); mainBtn.Font = FONT; mainBtn.TextSize = sx(20)
		local mbStroke = Instance.new("UIStroke", mainBtn); mbStroke.Color = Color3.fromRGB(0, 0, 0); mbStroke.Thickness = 2; mbStroke.Transparency = 0.5
		UIHelper.AddPuffyGradient(mainBtn)
		mainBtn.MouseButton1Click:Connect(function()
			showConfirmation(
				("Sacrifice %d %s streamers for %s Gems?"):format(need, trade.rarity, formatNumber(trade.gems)),
				function()
					SacrificeRequest:FireServer("GemTrade", tradeIndex)
					gemTradeQueues[tradeIndex] = {}
					fireQueueChanged()
				end
			)
		end)
	else
		mainBtn.BackgroundColor3 = rc
		mainBtn.Text = "Auto Fill & Sacrifice"
		mainBtn.TextColor3 = Color3.new(1, 1, 1); mainBtn.Font = FONT; mainBtn.TextSize = sx(20)
		local mbStroke = Instance.new("UIStroke", mainBtn); mbStroke.Color = Color3.fromRGB(0, 0, 0); mbStroke.Thickness = 2; mbStroke.Transparency = 0.5
		UIHelper.AddPuffyGradient(mainBtn)
		mainBtn.MouseButton1Click:Connect(function()
			local inv = HUDController.Data.inventory or {}
			local sto = HUDController.Data.storage or {}
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
			for i, item in ipairs(sto) do
				if added >= need then break end
				local vi = STORAGE_OFFSET + i
				if not queue[vi] and not queued[vi] then
					local _, _, info = getItemInfo(item)
					if info and info.rarity == trade.rarity then
						queue[vi] = true; added = added + 1
					end
				end
			end
			fireQueueChanged()
			if queueSetCount(queue) >= need then
				showConfirmation(
					("Sacrifice %d %s streamers for %s Gems?"):format(need, trade.rarity, formatNumber(trade.gems)),
					function()
						SacrificeRequest:FireServer("GemTrade", tradeIndex)
						gemTradeQueues[tradeIndex] = {}
						fireQueueChanged()
					end
				)
			end
			buildContent(activeTabId)
		end)
	end

	-- Clear link (secondary)
	if selected > 0 then
		local clrLink = Instance.new("TextButton")
		clrLink.Size = UDim2.new(0, sx(80), 0, sx(30))
		clrLink.BackgroundTransparency = 1; clrLink.Text = "Clear All"
		clrLink.TextColor3 = Color3.fromRGB(200, 160, 180); clrLink.Font = FONT; clrLink.TextSize = sx(15)
		clrLink.BorderSizePixel = 0; clrLink.Parent = actionRow
		clrLink.MouseButton1Click:Connect(function()
			gemTradeQueues[tradeIndex] = {}
			fireQueueChanged()
			buildContent(activeTabId)
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

	local accentColor = done and Color3.fromRGB(80, 220, 100) or Color3.fromRGB(255, 200, 60)

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, -sx(12), 0, sx(90))
	header.BackgroundColor3 = Color3.fromRGB(55, 45, 90); header.BorderSizePixel = 0; header.Parent = contentFrame
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, sx(18))
	Instance.new("UIStroke", header).Color = accentColor; Instance.new("UIStroke", header).Thickness = 2

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

	local usedSet = {}
	for _, idx in pairs(queue) do if idx then usedSet[idx] = true end end

	local totalSlots = 0
	for _, r in ipairs(cfg.req) do totalSlots = totalSlots + (r.count or 1) end

	local allFilled = true
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
	local scStroke = Instance.new("UIStroke", slotContainer)
	scStroke.Color = Color3.fromRGB(255, 200, 60); scStroke.Thickness = 2; scStroke.Transparency = 0.3

	local slotGrid = Instance.new("Frame")
	slotGrid.Size = UDim2.new(1, 0, 1, 0); slotGrid.BackgroundTransparency = 1; slotGrid.Parent = slotContainer
	local sgLayout = Instance.new("UIGridLayout", slotGrid)
	sgLayout.CellSize = UDim2.new(0, slotSize, 0, slotSize)
	sgLayout.CellPadding = UDim2.new(0, slotGap, 0, slotGap)
	sgLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sgLayout.SortOrder = Enum.SortOrder.LayoutOrder
	local sgPad = Instance.new("UIPadding", slotGrid)
	sgPad.PaddingTop = UDim.new(0, sx(8)); sgPad.PaddingBottom = UDim.new(0, sx(4))

	local slotOrder = 0
	for si, r in ipairs(cfg.req) do
		local count = r.count or 1
		for c = 1, count do
			local key = si .. "_" .. c
			local filled = queue[key] ~= nil
			if not filled then allFilled = false end

			slotOrder = slotOrder + 1
			local slot = Instance.new("TextButton")
			slot.Size = UDim2.new(0, slotSize, 0, slotSize)
			slot.BackgroundColor3 = filled and Color3.fromRGB(40, 120, 60) or Color3.fromRGB(50, 42, 80)
			slot.BorderSizePixel = 0; slot.Text = ""; slot.LayoutOrder = slotOrder; slot.Parent = slotGrid
			Instance.new("UICorner", slot).CornerRadius = UDim.new(1, 0)
			local ss = Instance.new("UIStroke", slot)
			ss.Color = filled and Color3.fromRGB(80, 240, 100) or Color3.fromRGB(80, 70, 120)
			ss.Thickness = filled and 2.5 or 1.5
			ss.Transparency = filled and 0 or 0.5

			if filled then
				local resolvedItem = resolveVirtualItem(queue[key])
				local sid = type(resolvedItem) == "table" and resolvedItem.id or resolvedItem or "?"
				buildAvatarSlot(slot, sid)
				local capKey, capId = key, oneTimeId
				slot.MouseButton1Click:Connect(function()
					oneTimeQueues[capId][capKey] = nil
					fireQueueChanged()
					buildContent(activeTabId)
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

	-- Action row: combined button + clear link (matching gem style)
	local actionRow = Instance.new("Frame")
	actionRow.Size = UDim2.new(1, -sx(12), 0, sx(50)); actionRow.BackgroundTransparency = 1; actionRow.Parent = contentFrame

	local mainBtn = Instance.new("TextButton")
	mainBtn.Size = UDim2.new(0, sx(320), 0, sx(46)); mainBtn.Position = UDim2.new(0.5, 0, 0.5, 0)
	mainBtn.AnchorPoint = Vector2.new(0.5, 0.5); mainBtn.BorderSizePixel = 0; mainBtn.Parent = actionRow
	Instance.new("UICorner", mainBtn).CornerRadius = UDim.new(0, sx(14))
	mainBtn.BackgroundColor3 = allFilled and Color3.fromRGB(80, 220, 100) or Color3.fromRGB(60, 55, 80)
	mainBtn.Text = allFilled and ("SACRIFICE FOR " .. formatNumber(cfg.gems) .. " GEMS") or "Fill all slots to sacrifice"
	mainBtn.TextColor3 = allFilled and Color3.new(1, 1, 1) or Color3.fromRGB(140, 130, 170)
	mainBtn.Font = FONT; mainBtn.TextSize = sx(18)
	Instance.new("UIStroke", mainBtn).Color = allFilled and Color3.fromRGB(50, 160, 65) or Color3.fromRGB(50, 45, 65)
	UIHelper.AddPuffyGradient(mainBtn)

	if allFilled then
		local capId = oneTimeId
		mainBtn.MouseButton1Click:Connect(function()
			showConfirmation("Sacrifice these streamers for " .. formatNumber(cfg.gems) .. " Gems?", function()
				SacrificeRequest:FireServer("OneTime", capId)
				oneTimeQueues[capId] = {}
				fireQueueChanged()
			end)
		end)
	end

	local clrLink = Instance.new("TextButton")
	clrLink.Size = UDim2.new(0, sx(80), 0, sx(24)); clrLink.Position = UDim2.new(1, -sx(6), 0.5, 0)
	clrLink.AnchorPoint = Vector2.new(1, 0.5); clrLink.BackgroundTransparency = 1
	clrLink.Text = "Clear"; clrLink.TextColor3 = Color3.fromRGB(200, 100, 100)
	clrLink.Font = FONT2; clrLink.TextSize = sx(14); clrLink.Parent = actionRow
	local capId2 = oneTimeId
	clrLink.MouseButton1Click:Connect(function()
		oneTimeQueues[capId2] = {}
		fireQueueChanged()
		buildContent(activeTabId)
	end)
end

-- =========== LUCK CONTENT ===========
local function buildLuckContent(luckType)
	clearContent()

	local warnFrame = Instance.new("Frame")
	warnFrame.Size = UDim2.new(1, -sx(12), 0, sx(44))
	warnFrame.BackgroundColor3 = Color3.fromRGB(80, 35, 35); warnFrame.BorderSizePixel = 0
	warnFrame.Parent = contentFrame
	Instance.new("UICorner", warnFrame).CornerRadius = UDim.new(0, sx(12))
	Instance.new("UIStroke", warnFrame).Color = Color3.fromRGB(200, 80, 60)
	local wl = Instance.new("TextLabel")
	wl.Size = UDim2.new(1, -sx(20), 1, -sx(6)); wl.Position = UDim2.new(0.5, 0, 0.5, 0)
	wl.AnchorPoint = Vector2.new(0.5, 0.5); wl.BackgroundTransparency = 1
	wl.Text = Sacrifice.LuckWarning; wl.TextColor3 = Color3.fromRGB(255, 210, 170)
	wl.Font = FONT; wl.TextSize = sx(13); wl.TextWrapped = true; wl.Parent = warnFrame

	if luckType == "FiftyFifty" then
		local cfg = Sacrifice.FiftyFifty
		local cs = (HUDController.Data.sacrificeChargeState or {}).FiftyFifty or { count = 0, nextAt = nil }
		local nextIn = cs.nextAt and (cs.nextAt - os.clock()) or 0
		local rp = {}; for _, r in ipairs(cfg.req) do table.insert(rp, r.count .. " " .. r.rarity) end
		local accentColor = Color3.fromRGB(255, 220, 80)

		local header = Instance.new("Frame")
		header.Size = UDim2.new(1, -sx(12), 0, sx(90))
		header.BackgroundColor3 = Color3.fromRGB(55, 45, 90); header.BorderSizePixel = 0; header.Parent = contentFrame
		Instance.new("UICorner", header).CornerRadius = UDim.new(0, sx(18))
		Instance.new("UIStroke", header).Color = accentColor; Instance.new("UIStroke", header).Thickness = 2

		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, -sx(24), 0, sx(32)); t.Position = UDim2.new(0.5, 0, 0, sx(10))
		t.AnchorPoint = Vector2.new(0.5, 0); t.BackgroundTransparency = 1
		t.Text = cfg.name; t.TextColor3 = accentColor
		t.Font = FONT; t.TextSize = sx(24); t.Parent = header
		local ts = Instance.new("UIStroke", t)
		ts.Color = Color3.new(0, 0, 0); ts.Thickness = 2; ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

		local d = Instance.new("TextLabel")
		d.Size = UDim2.new(1, -sx(24), 0, sx(40)); d.Position = UDim2.new(0.5, 0, 0, sx(44))
		d.AnchorPoint = Vector2.new(0.5, 0); d.BackgroundTransparency = 1
		d.Text = cfg.desc .. "  •  Cost: " .. table.concat(rp, ", ")
		d.TextColor3 = Color3.fromRGB(200, 190, 230); d.Font = FONT; d.TextSize = sx(14); d.TextWrapped = true; d.Parent = header

		local chargeRow = Instance.new("Frame")
		chargeRow.Size = UDim2.new(1, -sx(12), 0, sx(36)); chargeRow.BackgroundTransparency = 1; chargeRow.Parent = contentFrame
		local cl = Instance.new("TextLabel")
		cl.Size = UDim2.new(1, 0, 1, 0); cl.BackgroundTransparency = 1
		cl.Text = "Charges: " .. cs.count .. " / " .. cfg.maxCharges .. (cs.count < cfg.maxCharges and nextIn > 0 and ("  •  Next: " .. formatTime(nextIn)) or "")
		cl.TextColor3 = accentColor; cl.Font = FONT; cl.TextSize = sx(16); cl.Parent = chargeRow

		local actionRow = Instance.new("Frame")
		actionRow.Size = UDim2.new(1, -sx(12), 0, sx(50)); actionRow.BackgroundTransparency = 1; actionRow.Parent = contentFrame

		local sb = Instance.new("TextButton")
		sb.Size = UDim2.new(0, sx(320), 0, sx(46)); sb.Position = UDim2.new(0.5, 0, 0.5, 0)
		sb.AnchorPoint = Vector2.new(0.5, 0.5); sb.BorderSizePixel = 0; sb.Parent = actionRow
		Instance.new("UICorner", sb).CornerRadius = UDim.new(0, sx(14))
		sb.BackgroundColor3 = cs.count > 0 and accentColor or Color3.fromRGB(60, 55, 80)
		sb.Text = cs.count > 0 and "SACRIFICE" or "NO CHARGES"
		sb.TextColor3 = cs.count > 0 and Color3.fromRGB(30, 20, 10) or Color3.fromRGB(140, 130, 170)
		sb.Font = FONT; sb.TextSize = sx(18)
		Instance.new("UIStroke", sb).Color = cs.count > 0 and Color3.fromRGB(200, 170, 30) or Color3.fromRGB(50, 45, 65)
		UIHelper.AddPuffyGradient(sb)
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
		local accentColor = Color3.fromRGB(100, 200, 255)

		local header = Instance.new("Frame")
		header.Size = UDim2.new(1, -sx(12), 0, sx(90))
		header.BackgroundColor3 = Color3.fromRGB(55, 45, 90); header.BorderSizePixel = 0; header.Parent = contentFrame
		Instance.new("UICorner", header).CornerRadius = UDim.new(0, sx(18))
		Instance.new("UIStroke", header).Color = accentColor; Instance.new("UIStroke", header).Thickness = 2

		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, -sx(24), 0, sx(32)); t.Position = UDim2.new(0.5, 0, 0, sx(10))
		t.AnchorPoint = Vector2.new(0.5, 0); t.BackgroundTransparency = 1
		t.Text = cfg.name; t.TextColor3 = accentColor
		t.Font = FONT; t.TextSize = sx(24); t.Parent = header
		local ts = Instance.new("UIStroke", t)
		ts.Color = Color3.new(0, 0, 0); ts.Thickness = 2; ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

		local d = Instance.new("TextLabel")
		d.Size = UDim2.new(1, -sx(24), 0, sx(40)); d.Position = UDim2.new(0.5, 0, 0, sx(44))
		d.AnchorPoint = Vector2.new(0.5, 0); d.BackgroundTransparency = 1
		d.Text = cfg.desc .. "  •  Cost: " .. table.concat(rp, ", ")
		d.TextColor3 = Color3.fromRGB(200, 190, 230); d.Font = FONT; d.TextSize = sx(14); d.TextWrapped = true; d.Parent = header

		local chargeRow = Instance.new("Frame")
		chargeRow.Size = UDim2.new(1, -sx(12), 0, sx(36)); chargeRow.BackgroundTransparency = 1; chargeRow.Parent = contentFrame
		local cl = Instance.new("TextLabel")
		cl.Size = UDim2.new(1, 0, 1, 0); cl.BackgroundTransparency = 1
		cl.Text = "Charges: " .. cs.count .. " / " .. cfg.maxCharges .. (cs.count < cfg.maxCharges and nextIn > 0 and ("  •  Recharge: " .. formatTime(nextIn)) or "")
		cl.TextColor3 = accentColor; cl.Font = FONT; cl.TextSize = sx(16); cl.Parent = chargeRow

		local actionRow = Instance.new("Frame")
		actionRow.Size = UDim2.new(1, -sx(12), 0, sx(50)); actionRow.BackgroundTransparency = 1; actionRow.Parent = contentFrame

		local sb = Instance.new("TextButton")
		sb.Size = UDim2.new(0, sx(320), 0, sx(46)); sb.Position = UDim2.new(0.5, 0, 0.5, 0)
		sb.AnchorPoint = Vector2.new(0.5, 0.5); sb.BorderSizePixel = 0; sb.Parent = actionRow
		Instance.new("UICorner", sb).CornerRadius = UDim.new(0, sx(14))
		sb.BackgroundColor3 = cs.count > 0 and accentColor or Color3.fromRGB(60, 55, 80)
		sb.Text = cs.count > 0 and "SACRIFICE" or "NO CHARGES"
		sb.TextColor3 = cs.count > 0 and Color3.fromRGB(10, 30, 50) or Color3.fromRGB(140, 130, 170)
		sb.Font = FONT; sb.TextSize = sx(18)
		Instance.new("UIStroke", sb).Color = cs.count > 0 and Color3.fromRGB(60, 150, 200) or Color3.fromRGB(50, 45, 65)
		UIHelper.AddPuffyGradient(sb)
		if cs.count > 0 then
			sb.MouseButton1Click:Connect(function()
				showConfirmation("Feeling Lucky: +100% or -100% luck for 10 min!\nCost: " .. table.concat(rp, ", "), function()
					SacrificeRequest:FireServer("FeelingLucky")
				end)
			end)
		end

	elseif luckType == "DontDoIt" then
		local cfg = Sacrifice.DontDoIt
		local accentColor = Color3.fromRGB(255, 110, 110)

		local header = Instance.new("Frame")
		header.Size = UDim2.new(1, -sx(12), 0, sx(90))
		header.BackgroundColor3 = Color3.fromRGB(55, 45, 90); header.BorderSizePixel = 0; header.Parent = contentFrame
		Instance.new("UICorner", header).CornerRadius = UDim.new(0, sx(18))
		Instance.new("UIStroke", header).Color = accentColor; Instance.new("UIStroke", header).Thickness = 2

		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, -sx(24), 0, sx(32)); t.Position = UDim2.new(0.5, 0, 0, sx(10))
		t.AnchorPoint = Vector2.new(0.5, 0); t.BackgroundTransparency = 1
		t.Text = cfg.name; t.TextColor3 = accentColor
		t.Font = FONT; t.TextSize = sx(24); t.Parent = header
		local ts = Instance.new("UIStroke", t)
		ts.Color = Color3.new(0, 0, 0); ts.Thickness = 2; ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

		local d = Instance.new("TextLabel")
		d.Size = UDim2.new(1, -sx(24), 0, sx(40)); d.Position = UDim2.new(0.5, 0, 0, sx(44))
		d.AnchorPoint = Vector2.new(0.5, 0); d.BackgroundTransparency = 1
		d.Text = cfg.desc .. "\nCommon>Rare 50% | Rare>Epic 30% | Epic>Leg 10% | Leg>Mythic 4%"
		d.TextColor3 = Color3.fromRGB(200, 190, 230); d.Font = FONT; d.TextSize = sx(13); d.TextWrapped = true; d.Parent = header

		local allItems = getCombinedItems()
		local excludeSet = allQueuedIndices()
		local filtered = {}
		for _, entry in ipairs(allItems) do
			if not excludeSet[entry.vi] then table.insert(filtered, entry) end
		end

		if #filtered == 0 then
			local noItems = Instance.new("TextLabel")
			noItems.Size = UDim2.new(1, -sx(20), 0, sx(60)); noItems.BackgroundTransparency = 1
			noItems.Text = "No eligible streamers!"
			noItems.TextColor3 = Color3.fromRGB(180, 160, 210)
			noItems.Font = FONT; noItems.TextSize = sx(18); noItems.Parent = contentFrame
		else
			local pickScroll = Instance.new("ScrollingFrame")
			pickScroll.Size = UDim2.new(1, -sx(12), 0, sx(320))
			pickScroll.BackgroundTransparency = 1; pickScroll.BorderSizePixel = 0
			pickScroll.ScrollBarThickness = sx(5); pickScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
			pickScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; pickScroll.Parent = contentFrame

			local grid = Instance.new("UIGridLayout", pickScroll)
			grid.CellSize = UDim2.new(0, sx(130), 0, sx(110))
			grid.CellPadding = UDim2.new(0, sx(8), 0, sx(8))
			grid.SortOrder = Enum.SortOrder.LayoutOrder
			grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
			Instance.new("UIPadding", pickScroll).PaddingTop = UDim.new(0, sx(4))

			for order, entry in ipairs(filtered) do
				local item = entry.item
				local vi = entry.vi
				local id, eff, info = getItemInfo(item)
				if info then
					local rColor = DesignConfig.RarityColors[info.rarity] or Color3.new(1, 1, 1)
					local effInfo = eff and Effects.ByName[eff] or nil
					local displayColor = effInfo and effInfo.color or rColor
					local displayName = info.displayName or id
					if effInfo then displayName = effInfo.prefix .. " " .. displayName end
					local isStorage = vi > STORAGE_OFFSET

					local cell = Instance.new("TextButton")
					cell.Size = UDim2.new(0, sx(130), 0, sx(110))
					cell.BackgroundColor3 = Color3.fromRGB(40, 34, 70); cell.BorderSizePixel = 0
					cell.Text = ""; cell.LayoutOrder = order; cell.Parent = pickScroll
					Instance.new("UICorner", cell).CornerRadius = UDim.new(0, sx(14))
					local cStroke = Instance.new("UIStroke", cell)
					cStroke.Color = displayColor; cStroke.Thickness = 2; cStroke.Transparency = 0.2

					local avSize = sx(44)
					local avFrame = Instance.new("Frame")
					avFrame.Size = UDim2.new(0, avSize, 0, avSize)
					avFrame.Position = UDim2.new(0, sx(6), 0, sx(6))
					avFrame.BackgroundColor3 = Color3.fromRGB(30, 25, 55); avFrame.BorderSizePixel = 0; avFrame.Parent = cell
					Instance.new("UICorner", avFrame).CornerRadius = UDim.new(1, 0)
					buildAvatarSlot(avFrame, id)

					local nl = Instance.new("TextLabel")
					nl.Size = UDim2.new(1, -sx(56), 0, sx(20)); nl.Position = UDim2.new(0, sx(54), 0, sx(8))
					nl.BackgroundTransparency = 1; nl.Text = displayName; nl.TextColor3 = displayColor
					nl.Font = FONT; nl.TextSize = sx(13); nl.TextTruncate = Enum.TextTruncate.AtEnd
					nl.TextXAlignment = Enum.TextXAlignment.Left; nl.Parent = cell

					local rl = Instance.new("TextLabel")
					rl.Size = UDim2.new(1, -sx(56), 0, sx(16)); rl.Position = UDim2.new(0, sx(54), 0, sx(28))
					rl.BackgroundTransparency = 1; rl.Text = info.rarity; rl.TextColor3 = rColor
					rl.Font = FONT2; rl.TextSize = sx(12)
					rl.TextXAlignment = Enum.TextXAlignment.Left; rl.Parent = cell

					if isStorage then
						local sl = Instance.new("TextLabel")
						sl.Size = UDim2.new(0, sx(14), 0, sx(14)); sl.Position = UDim2.new(1, -sx(6), 0, sx(6))
						sl.AnchorPoint = Vector2.new(1, 0); sl.BackgroundColor3 = Color3.fromRGB(60, 130, 200)
						sl.Text = "S"; sl.TextColor3 = Color3.new(1, 1, 1)
						sl.Font = FONT; sl.TextSize = sx(9); sl.Parent = cell
						Instance.new("UICorner", sl).CornerRadius = UDim.new(0, sx(3))
					end

					local bl = Instance.new("TextLabel")
					bl.Size = UDim2.new(1, -sx(8), 0, sx(22)); bl.Position = UDim2.new(0.5, 0, 1, -sx(4))
					bl.AnchorPoint = Vector2.new(0.5, 1); bl.BackgroundTransparency = 1
					bl.Text = "Tap to sacrifice"; bl.TextColor3 = accentColor
					bl.Font = FONT2; bl.TextSize = sx(11); bl.Parent = cell

					cell.MouseButton1Click:Connect(function()
						showConfirmation("Sacrifice " .. displayName .. " (" .. info.rarity .. ")?\nChance to upgrade to next rarity!", function()
							SacrificeRequest:FireServer("DontDoIt", vi)
						end)
					end)
				end
			end
		end
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
	local elStroke = Instance.new("UIStroke", header); elStroke.Color = effectColor; elStroke.Thickness = 2

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

		local capQKey = qKey
		local capRarity = rarity
		local capEffect = effectName

		-- Visual queue: circular slots
		local slotSize = sx(50)
		local slotGap = sx(6)
		local slotsPerRow = math.min(need, 10)
		local totalRows = math.ceil(need / slotsPerRow)
		local slotRowH = totalRows * (slotSize + slotGap) + sx(10)

		local slotContainer = Instance.new("Frame")
		slotContainer.Size = UDim2.new(1, -sx(12), 0, slotRowH + sx(34))
		slotContainer.BackgroundColor3 = Color3.fromRGB(35, 30, 60); slotContainer.BorderSizePixel = 0
		slotContainer.LayoutOrder = ri * 100; slotContainer.Parent = contentFrame
		Instance.new("UICorner", slotContainer).CornerRadius = UDim.new(0, sx(14))
		local scStk = Instance.new("UIStroke", slotContainer); scStk.Color = rarColor; scStk.Thickness = 2; scStk.Transparency = 0.3

		-- Rarity label inside the slot container
		local rarLbl = Instance.new("TextLabel")
		rarLbl.Size = UDim2.new(1, -sx(16), 0, sx(26)); rarLbl.Position = UDim2.new(0.5, 0, 0, sx(4))
		rarLbl.AnchorPoint = Vector2.new(0.5, 0); rarLbl.BackgroundTransparency = 1
		rarLbl.Text = rarity .. "  —  " .. selected .. "/" .. need
		rarLbl.TextColor3 = canSacrifice and Color3.fromRGB(100, 255, 120) or rarColor
		rarLbl.Font = FONT; rarLbl.TextSize = sx(16); rarLbl.Parent = slotContainer
		local rlStk = Instance.new("UIStroke", rarLbl)
		rlStk.Color = Color3.fromRGB(15, 10, 30); rlStk.Thickness = 1
		rlStk.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

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

		local filledList = {}
		for vi in pairs(queue) do table.insert(filledList, vi) end
		table.sort(filledList)

		for i = 1, need do
			local vi = filledList[i]
			local isFilled = vi ~= nil
			local slot = Instance.new("Frame")
			slot.Size = UDim2.new(0, slotSize, 0, slotSize)
			slot.BackgroundColor3 = isFilled and Color3.fromRGB(40, 120, 60) or Color3.fromRGB(50, 42, 80)
			slot.BorderSizePixel = 0; slot.LayoutOrder = i; slot.Parent = slotGrid
			Instance.new("UICorner", slot).CornerRadius = UDim.new(1, 0)
			local slotStk = Instance.new("UIStroke", slot)
			slotStk.Color = isFilled and Color3.fromRGB(80, 240, 100) or rarColor
			slotStk.Thickness = isFilled and 2 or 1.5
			slotStk.Transparency = isFilled and 0 or 0.5

			if isFilled then
				local item = resolveVirtualItem(vi)
				local id = type(item) == "table" and item.id or (item or "?")
				buildAvatarSlot(slot, id)
			end
		end

		-- Action row: combined button + clear link
		local actionRow = Instance.new("Frame")
		actionRow.Size = UDim2.new(1, -sx(12), 0, sx(50)); actionRow.BackgroundTransparency = 1
		actionRow.LayoutOrder = ri * 100 + 1; actionRow.Parent = contentFrame
		local arl = Instance.new("UIListLayout", actionRow)
		arl.FillDirection = Enum.FillDirection.Horizontal
		arl.HorizontalAlignment = Enum.HorizontalAlignment.Center
		arl.VerticalAlignment = Enum.VerticalAlignment.Center; arl.Padding = UDim.new(0, sx(14))

		local mainBtn = Instance.new("TextButton")
		mainBtn.Size = UDim2.new(0, sx(280), 0, sx(44))
		mainBtn.BorderSizePixel = 0; mainBtn.Parent = actionRow
		Instance.new("UICorner", mainBtn).CornerRadius = UDim.new(0, sx(14))

		if canSacrifice then
			mainBtn.BackgroundColor3 = rarColor
			mainBtn.Text = "CONVERT " .. rarity
			mainBtn.TextColor3 = Color3.new(1, 1, 1); mainBtn.Font = FONT; mainBtn.TextSize = sx(18)
			UIHelper.AddPuffyGradient(mainBtn)
			mainBtn.MouseButton1Click:Connect(function()
				showConfirmation(("Combine %d %s %s into 1?"):format(need, displayName, capRarity), function()
					SacrificeRequest:FireServer("Elemental", capEffect, capRarity)
					elementalQueues[capQKey] = {}
					fireQueueChanged()
				end)
			end)
		else
			mainBtn.BackgroundColor3 = rarColor
			mainBtn.Text = "Auto Fill & Convert"
			mainBtn.TextColor3 = Color3.new(1, 1, 1); mainBtn.Font = FONT; mainBtn.TextSize = sx(18)
			UIHelper.AddPuffyGradient(mainBtn)
			mainBtn.MouseButton1Click:Connect(function()
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
				if queueSetCount(q) >= need then
					showConfirmation(("Combine %d %s %s into 1?"):format(need, displayName, capRarity), function()
						SacrificeRequest:FireServer("Elemental", capEffect, capRarity)
						elementalQueues[capQKey] = {}
						fireQueueChanged()
					end)
				end
				buildContent(activeTabId)
			end)
		end

		if selected > 0 then
			local clrLink = Instance.new("TextButton")
			clrLink.Size = UDim2.new(0, sx(70), 0, sx(28))
			clrLink.BackgroundTransparency = 1; clrLink.Text = "Clear"
			clrLink.TextColor3 = Color3.fromRGB(200, 160, 180); clrLink.Font = FONT; clrLink.TextSize = sx(14)
			clrLink.BorderSizePixel = 0; clrLink.Parent = actionRow
			clrLink.MouseButton1Click:Connect(function()
				elementalQueues[capQKey] = {}
				fireQueueChanged()
				buildContent(activeTabId)
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

		if ri < #rarities then
			local div = Instance.new("Frame")
			div.Size = UDim2.new(0.85, 0, 0, sx(1))
			div.BackgroundColor3 = Color3.fromRGB(60, 55, 85); div.BorderSizePixel = 0
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
	local accentColor = done and Color3.fromRGB(80, 220, 100) or effectColor

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, -sx(12), 0, sx(90))
	header.BackgroundColor3 = Color3.fromRGB(55, 45, 90); header.BorderSizePixel = 0; header.Parent = contentFrame
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, sx(18))
	Instance.new("UIStroke", header).Color = accentColor; Instance.new("UIStroke", header).Thickness = 2

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

	-- Visual queue: circular slots (matching gem style)
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
	local scStk = Instance.new("UIStroke", slotContainer); scStk.Color = effectColor; scStk.Thickness = 2; scStk.Transparency = 0.3

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

	local filledList = {}
	for vi in pairs(queue) do table.insert(filledList, vi) end
	table.sort(filledList)

	for i = 1, need do
		local vi = filledList[i]
		local isFilled = vi ~= nil
		local slot = Instance.new("Frame")
		slot.Size = UDim2.new(0, slotSize, 0, slotSize)
		slot.BackgroundColor3 = isFilled and Color3.fromRGB(40, 120, 60) or Color3.fromRGB(50, 42, 80)
		slot.BorderSizePixel = 0; slot.LayoutOrder = i; slot.Parent = slotGrid
		Instance.new("UICorner", slot).CornerRadius = UDim.new(1, 0)
		local slotStk = Instance.new("UIStroke", slot)
		slotStk.Color = isFilled and Color3.fromRGB(80, 240, 100) or effectColor
		slotStk.Thickness = isFilled and 2 or 1.5
		slotStk.Transparency = isFilled and 0 or 0.5

		if isFilled then
			local item = resolveVirtualItem(vi)
			local id = type(item) == "table" and item.id or (item or "?")
			buildAvatarSlot(slot, id)
		end
	end

	-- Action row: combined button + clear link (matching gem style)
	local capOneTimeId = oneTimeId
	local canSac = queued >= need
	local actionRow = Instance.new("Frame")
	actionRow.Size = UDim2.new(1, -sx(12), 0, sx(50)); actionRow.BackgroundTransparency = 1; actionRow.Parent = contentFrame

	local mainBtn = Instance.new("TextButton")
	mainBtn.Size = UDim2.new(0, sx(320), 0, sx(46)); mainBtn.Position = UDim2.new(0.5, 0, 0.5, 0)
	mainBtn.AnchorPoint = Vector2.new(0.5, 0.5); mainBtn.BorderSizePixel = 0; mainBtn.Parent = actionRow
	Instance.new("UICorner", mainBtn).CornerRadius = UDim.new(0, sx(14))

	if canSac then
		mainBtn.BackgroundColor3 = Color3.fromRGB(80, 220, 100)
		mainBtn.Text = "SACRIFICE FOR " .. formatNumber(cfg.gems) .. " GEMS"
		mainBtn.TextColor3 = Color3.new(1, 1, 1); mainBtn.Font = FONT; mainBtn.TextSize = sx(18)
		Instance.new("UIStroke", mainBtn).Color = Color3.fromRGB(50, 160, 65)
		UIHelper.AddPuffyGradient(mainBtn)
		mainBtn.MouseButton1Click:Connect(function()
			showConfirmation("Sacrifice " .. need .. " " .. effectName .. " cards for " .. formatNumber(cfg.gems) .. " Gems?", function()
				SacrificeRequest:FireServer("OneTime", capOneTimeId)
				effectOneTimeQueues[capOneTimeId] = {}
				fireQueueChanged()
			end)
		end)
	else
		mainBtn.BackgroundColor3 = effectColor
		mainBtn.Text = "Auto Fill & Sacrifice"
		mainBtn.TextColor3 = Color3.new(1, 1, 1); mainBtn.Font = FONT; mainBtn.TextSize = sx(18)
		Instance.new("UIStroke", mainBtn).Color = effectColor
		UIHelper.AddPuffyGradient(mainBtn)
		mainBtn.MouseButton1Click:Connect(function()
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
			if queueSetCount(effectOneTimeQueues[capOneTimeId] or {}) >= need then
				showConfirmation("Sacrifice " .. need .. " " .. effectName .. " cards for " .. formatNumber(cfg.gems) .. " Gems?", function()
					SacrificeRequest:FireServer("OneTime", capOneTimeId)
					effectOneTimeQueues[capOneTimeId] = {}
					fireQueueChanged()
				end)
			end
			buildContent(activeTabId)
		end)
	end

	if queued > 0 then
		local clrLink = Instance.new("TextButton")
		clrLink.Size = UDim2.new(0, sx(80), 0, sx(24)); clrLink.Position = UDim2.new(1, -sx(6), 0.5, 0)
		clrLink.AnchorPoint = Vector2.new(1, 0.5); clrLink.BackgroundTransparency = 1
		clrLink.Text = "Clear"; clrLink.TextColor3 = Color3.fromRGB(200, 100, 100)
		clrLink.Font = FONT2; clrLink.TextSize = sx(14); clrLink.Parent = actionRow
		clrLink.MouseButton1Click:Connect(function()
			effectOneTimeQueues[capOneTimeId] = {}
			fireQueueChanged()
			buildContent(activeTabId)
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
	gemRouletteInputActive = true
	local cfg = Sacrifice.GemRoulette

	local accentColor = Color3.fromRGB(255, 200, 60)

	local warnFrame = Instance.new("Frame")
	warnFrame.Size = UDim2.new(1, -sx(12), 0, sx(44))
	warnFrame.BackgroundColor3 = Color3.fromRGB(80, 35, 35); warnFrame.BorderSizePixel = 0
	warnFrame.Parent = contentFrame
	Instance.new("UICorner", warnFrame).CornerRadius = UDim.new(0, sx(12))
	Instance.new("UIStroke", warnFrame).Color = Color3.fromRGB(200, 80, 60)
	local wl = Instance.new("TextLabel")
	wl.Size = UDim2.new(1, -sx(20), 1, -sx(6)); wl.Position = UDim2.new(0.5, 0, 0.5, 0)
	wl.AnchorPoint = Vector2.new(0.5, 0.5); wl.BackgroundTransparency = 1
	wl.Text = Sacrifice.LuckWarning; wl.TextColor3 = Color3.fromRGB(255, 210, 170)
	wl.Font = FONT; wl.TextSize = sx(13); wl.TextWrapped = true; wl.Parent = warnFrame

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, -sx(12), 0, sx(90))
	header.BackgroundColor3 = Color3.fromRGB(55, 45, 90); header.BorderSizePixel = 0; header.Parent = contentFrame
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, sx(18))
	Instance.new("UIStroke", header).Color = accentColor; Instance.new("UIStroke", header).Thickness = 2

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -sx(24), 0, sx(32)); title.Position = UDim2.new(0.5, 0, 0, sx(10))
	title.AnchorPoint = Vector2.new(0.5, 0); title.BackgroundTransparency = 1
	title.Text = "Gem Roulette"; title.TextColor3 = accentColor
	title.Font = FONT; title.TextSize = sx(24); title.Parent = header
	local tStk = Instance.new("UIStroke", title)
	tStk.Color = Color3.new(0, 0, 0); tStk.Thickness = 2; tStk.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	local desc = Instance.new("TextLabel")
	desc.Size = UDim2.new(1, -sx(24), 0, sx(40)); desc.Position = UDim2.new(0.5, 0, 0, sx(44))
	desc.AnchorPoint = Vector2.new(0.5, 0); desc.BackgroundTransparency = 1
	desc.Text = cfg.desc; desc.TextColor3 = Color3.fromRGB(200, 190, 230)
	desc.Font = FONT; desc.TextSize = sx(14); desc.TextWrapped = true; desc.Parent = header

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

	local infoRow = Instance.new("Frame")
	infoRow.Size = UDim2.new(1, -sx(12), 0, sx(36)); infoRow.BackgroundTransparency = 1; infoRow.Parent = contentFrame
	local gems = HUDController.Data.gems or 0
	local il = Instance.new("TextLabel")
	il.Size = UDim2.new(1, 0, 1, 0); il.BackgroundTransparency = 1
	il.Text = "Charges: " .. charges .. "/" .. cfg.maxCharges .. "  •  Your Gems: " .. formatNumber(gems)
	il.TextColor3 = accentColor; il.Font = FONT; il.TextSize = sx(15); il.Parent = infoRow

	local inputRow = Instance.new("Frame")
	inputRow.Size = UDim2.new(1, -sx(12), 0, sx(54))
	inputRow.BackgroundTransparency = 1; inputRow.Parent = contentFrame

	local inputBox = Instance.new("TextBox")
	inputBox.Name = "GemWagerInput"
	inputBox.Size = UDim2.new(0, sx(320), 0, sx(46))
	inputBox.Position = UDim2.new(0.5, 0, 0.5, 0); inputBox.AnchorPoint = Vector2.new(0.5, 0.5)
	inputBox.BackgroundColor3 = Color3.fromRGB(30, 28, 50)
	inputBox.Text = ""; inputBox.PlaceholderText = "Enter gem amount..."
	inputBox.PlaceholderColor3 = Color3.fromRGB(100, 100, 130)
	inputBox.TextColor3 = accentColor
	inputBox.Font = FONT; inputBox.TextSize = sx(20)
	inputBox.ClearTextOnFocus = true; inputBox.TextEditable = true
	inputBox.BorderSizePixel = 0; inputBox.ZIndex = 5; inputBox.Parent = inputRow
	Instance.new("UICorner", inputBox).CornerRadius = UDim.new(0, sx(14))
	Instance.new("UIStroke", inputBox).Color = Color3.fromRGB(255, 180, 50)
	local ibPad = Instance.new("UIPadding", inputBox)
	ibPad.PaddingLeft = UDim.new(0, sx(12)); ibPad.PaddingRight = UDim.new(0, sx(12))

	local actionRow = Instance.new("Frame")
	actionRow.Size = UDim2.new(1, -sx(12), 0, sx(50)); actionRow.BackgroundTransparency = 1; actionRow.Parent = contentFrame
	local canSpin = charges > 0
	local spinBtn = Instance.new("TextButton")
	spinBtn.Size = UDim2.new(0, sx(320), 0, sx(46)); spinBtn.Position = UDim2.new(0.5, 0, 0.5, 0)
	spinBtn.AnchorPoint = Vector2.new(0.5, 0.5); spinBtn.BorderSizePixel = 0; spinBtn.Parent = actionRow
	Instance.new("UICorner", spinBtn).CornerRadius = UDim.new(0, sx(14))
	spinBtn.BackgroundColor3 = canSpin and accentColor or Color3.fromRGB(60, 55, 80)
	spinBtn.Text = canSpin and "SPIN THE ROULETTE" or "NO CHARGES"
	spinBtn.TextColor3 = canSpin and Color3.fromRGB(20, 10, 0) or Color3.fromRGB(140, 130, 170)
	spinBtn.Font = FONT; spinBtn.TextSize = sx(18)
	Instance.new("UIStroke", spinBtn).Color = canSpin and Color3.fromRGB(200, 140, 30) or Color3.fromRGB(50, 45, 65)
	UIHelper.AddPuffyGradient(spinBtn)

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
				showNotEnoughGemsPopup()
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

local function highlightRarityBtn(idx)
	activeGemRarity = idx
	for _, rb in ipairs(rarityBtns) do
		local isActive = rb.idx == idx
		local trade = Sacrifice.GemTrades[rb.idx]
		local rc = trade and DesignConfig.RarityColors[trade.rarity] or Color3.new(1, 1, 1)
		rb.btn.BackgroundColor3 = isActive and rc or Color3.fromRGB(40, 35, 65)
		local lbl = rb.btn:FindFirstChild("RarLbl")
		if lbl then lbl.TextColor3 = isActive and Color3.new(1, 1, 1) or rc end
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
	luck        = Color3.fromRGB(255, 200, 60),
}

local function switchTopTab(tab)
	activeTopTab = tab

	for key, btn in pairs(topTabBtns) do
		local isActive = key == tab
		btn.BackgroundColor3 = isActive and (TAB_COLORS[key] or Color3.new(1,1,1)) or Color3.fromRGB(50, 42, 80)
		btn.TextColor3 = isActive and Color3.new(1, 1, 1) or Color3.fromRGB(180, 160, 210)
	end

	-- Show/hide sidebars
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

	closePicker(); gemRouletteInputActive = false

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
	local tabChanged = tabId ~= activeTabId
	highlightSidebar(tabId)
	if tabChanged then closePicker(); gemRouletteInputActive = false end
	if tabId:sub(1, 8) == "GemTrade" then
		buildGemTradeContent(tonumber(tabId:sub(10)))
	elseif Sacrifice.OneTime[tabId] then
		buildOneTimeContent(tabId)
	elseif tabId == "FiftyFifty" or tabId == "FeelingLucky" or tabId == "DontDoIt" then
		buildLuckContent(tabId)
	elseif tabId == "GemRoulette" then
		buildGemRouletteContent()
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
	gemRouletteInputActive = false
	closePicker()
	cleanupBinarySpin()
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

	-- Title row (compact — just the title + close)
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

	-- Top tab bar: 5 tabs
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
		{ key = "luck",        label = "Test Your Luck", order = 4 },
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

	-- Horizontal rarity bar (visible in "Gem Sacrifice" mode)
	rarityBarFrame = Instance.new("Frame")
	rarityBarFrame.Size = UDim2.new(1, -sx(24), 0, sx(42)); rarityBarFrame.Position = UDim2.new(0.5, 0, 0, sx(94))
	rarityBarFrame.AnchorPoint = Vector2.new(0.5, 0); rarityBarFrame.BackgroundTransparency = 1
	rarityBarFrame.BorderSizePixel = 0; rarityBarFrame.Parent = modalFrame
	local rbLayout = Instance.new("UIListLayout", rarityBarFrame)
	rbLayout.FillDirection = Enum.FillDirection.Horizontal; rbLayout.Padding = UDim.new(0, sx(8))
	rbLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center; rbLayout.VerticalAlignment = Enum.VerticalAlignment.Center

	rarityBtns = {}
	for i, trade in ipairs(Sacrifice.GemTrades) do
		local rc = DesignConfig.RarityColors[trade.rarity] or Color3.new(1, 1, 1)
		local rbtn = Instance.new("TextButton")
		rbtn.Size = UDim2.new(0, sx(170), 0, sx(40)); rbtn.BackgroundColor3 = Color3.fromRGB(40, 35, 65)
		rbtn.BorderSizePixel = 0; rbtn.Text = ""; rbtn.Parent = rarityBarFrame
		Instance.new("UICorner", rbtn).CornerRadius = UDim.new(0, sx(12))
		local rbStroke = Instance.new("UIStroke", rbtn); rbStroke.Color = rc; rbStroke.Thickness = 1.5; rbStroke.Transparency = 0.4

		local rlbl = Instance.new("TextLabel")
		rlbl.Name = "RarLbl"; rlbl.Size = UDim2.new(0.55, 0, 1, 0); rlbl.Position = UDim2.new(0, sx(10), 0, 0)
		rlbl.BackgroundTransparency = 1; rlbl.Text = trade.rarity
		rlbl.TextColor3 = rc; rlbl.Font = FONT; rlbl.TextSize = sx(15)
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

	-- Helper: create a sidebar frame
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

	-- Helper: add a tab button to a sidebar
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
		local ts = Instance.new("UIStroke", lbl)
		ts.Color = Color3.fromRGB(15, 10, 30); ts.Thickness = 1; ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		btn.MouseButton1Click:Connect(function() buildContent(id) end)
		table.insert(sidebarBtnLists[sidebarKey], { id = id, btn = btn })
	end

	-- ONE-TIME sidebar
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

	-- ELEMENTAL ONE-TIME sidebar
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

	-- TEST YOUR LUCK sidebar
	local lkSidebar = makeSidebar("LuckSidebar")
	sidebars.luck = lkSidebar
	local lkTabs = {
		{ "FiftyFifty",   "50 / 50",           Color3.fromRGB(255, 220, 60)  },
		{ "FeelingLucky",  "Feeling Lucky?",    Color3.fromRGB(100, 200, 255) },
		{ "DontDoIt",      "Streamer Sacrifice", Color3.fromRGB(255, 80, 80) },
		{ "GemRoulette",   "Gem Roulette",      Color3.fromRGB(255, 180, 50) },
	}
	for i, t in ipairs(lkTabs) do addTabTo("luck", lkSidebar, t[1], t[2], t[3], i) end

	-- Content area (position/size managed by switchTopTab)
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

	-- Events
	OpenSacrificeGui.OnClientEvent:Connect(function()
		local TutorialController = require(script.Parent.TutorialController)
		if TutorialController.IsActive() then return end
		if isOpen then SacrificeController.Close() else SacrificeController.Open() end
	end)

	SacrificeResult.OnClientEvent:Connect(function(result)
		if result.success then
			clearAllQueues()
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
		-- Don't rebuild while picker, binary spin, or gem roulette input is active
		if isOpen and activeTabId and not pickerFrame and not binarySpinOverlay and not gemRouletteInputActive then buildContent(activeTabId) end
	end)

	-- Refresh inventory/storage/sell when queues change
	local InventoryCtrl = require(script.Parent.InventoryController)
	local StorageCtrl = require(script.Parent.StorageController)
	local SellCtrl = require(script.Parent.SellStandController)
	SacrificeController.OnQueueChanged(function()
		if InventoryCtrl and InventoryCtrl.RefreshVisuals then InventoryCtrl.RefreshVisuals() end
		if StorageCtrl and StorageCtrl.Refresh then StorageCtrl.Refresh() end
		if SellCtrl and SellCtrl.RefreshList then SellCtrl.RefreshList() end
	end)

	modalFrame.Visible = false
end

--- Public: get the full set of queued virtual indices (for hiding from inventory/storage)
function SacrificeController.GetQueuedIndices()
	return allQueuedIndices()
end

function SacrificeController.OnQueueChanged(cb)
	table.insert(onQueueChanged, cb)
end

-- Callbacks for open/close (music, etc.)
function SacrificeController.OnOpen(cb)
	table.insert(onOpenCallbacks, cb)
end
function SacrificeController.OnClose(cb)
	table.insert(onCloseCallbacks, cb)
end

return SacrificeController
