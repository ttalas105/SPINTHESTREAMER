--[[
	GemShopController.lua
	Gem Shop UI — single scrollable page of elemental cases.
	Each case shows: logo image, case picture, gem price, and buy button.
	Colorful, bubbly, kid-friendly design.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")

local GemCases    = require(ReplicatedStorage.Shared.Config.GemCases)
local Streamers   = require(ReplicatedStorage.Shared.Config.Streamers)
local Effects     = require(ReplicatedStorage.Shared.Config.Effects)
local Rarities    = require(ReplicatedStorage.Shared.Config.Rarities)
local UIHelper    = require(script.Parent.UIHelper)
local HUDController = require(script.Parent.HUDController)
local StoreController = require(script.Parent.StoreController)
local SpinController = require(script.Parent.SpinController)

local GemShopController = {}

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RemoteEvents  = ReplicatedStorage:WaitForChild("RemoteEvents")
local OpenGemShopGui = RemoteEvents:WaitForChild("OpenGemShopGui")
local BuyGemCase     = RemoteEvents:WaitForChild("BuyGemCase")
local GemCaseResult  = RemoteEvents:WaitForChild("GemCaseResult")

local screenGui, overlay, modalFrame
local isOpen      = false
local balanceLabel
local autoOpenEnabled  = false
local autoOpenCaseId   = nil
local pendingGemSpin = false

local FONT = Enum.Font.FredokaOne
local FONT_SUB = Enum.Font.GothamBold
local MODAL_BG = Color3.fromRGB(30, 25, 45)
local MODAL_W, MODAL_H = 920, 680
local RED = Color3.fromRGB(220, 55, 55)
local RED_DARK = Color3.fromRGB(160, 30, 30)

local bounceTween = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- Viewport rotation data
local vpConns = {}
local heartbeatConn = nil

-------------------------------------------------
-- HELPERS
-------------------------------------------------

local function fmtNum(n)
	local s = tostring(math.floor(n))
	local f = ""
	for i = 1, #s do
		f = f .. s:sub(i, i)
		if (#s - i) % 3 == 0 and i < #s then f = f .. "," end
	end
	return f
end

local function addStroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.new(0, 0, 0)
	s.Thickness = thickness or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = parent
	return s
end

local activeGemPopup = nil
local activeErrorToast = nil

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
	box.Size = UDim2.new(0, 400, 0, 240)
	box.Position = UDim2.new(0.5, 0, 0.5, 0)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.BackgroundColor3 = Color3.fromRGB(28, 22, 48)
	box.BorderSizePixel = 0
	box.ZIndex = 81
	box.Parent = dim
	Instance.new("UICorner", box).CornerRadius = UDim.new(0, 22)

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
	gemIcon.Size = UDim2.new(0, 56, 0, 56)
	gemIcon.Position = UDim2.new(0.5, 0, 0, 22)
	gemIcon.AnchorPoint = Vector2.new(0.5, 0)
	gemIcon.BackgroundTransparency = 1
	gemIcon.Text = "\u{1F48E}"
	gemIcon.TextScaled = true
	gemIcon.Font = FONT
	gemIcon.ZIndex = 83
	gemIcon.Parent = box

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -40, 0, 30)
	title.Position = UDim2.new(0.5, 0, 0, 84)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.BackgroundTransparency = 1
	title.Text = "Not Enough Gems!"
	title.TextColor3 = Color3.fromRGB(255, 90, 90)
	title.Font = FONT
	title.TextSize = 26
	title.ZIndex = 82
	title.Parent = box
	addStroke(title, Color3.fromRGB(0, 0, 0), 2.5)

	local desc = Instance.new("TextLabel")
	desc.Size = UDim2.new(1, -50, 0, 20)
	desc.Position = UDim2.new(0.5, 0, 0, 120)
	desc.AnchorPoint = Vector2.new(0.5, 0)
	desc.BackgroundTransparency = 1
	desc.Text = "Would you like to buy more gems?"
	desc.TextColor3 = Color3.fromRGB(190, 185, 210)
	desc.Font = FONT_SUB
	desc.TextSize = 14
	desc.ZIndex = 82
	desc.Parent = box

	local function dismiss()
		TweenService:Create(dim, TweenInfo.new(0.15), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(box, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Size = UDim2.new(0, 200, 0, 120),
		}):Play()
		task.delay(0.16, function()
			if dim.Parent then dim:Destroy() end
			activeGemPopup = nil
		end)
	end

	local btnRow = Instance.new("Frame")
	btnRow.Size = UDim2.new(1, -60, 0, 44)
	btnRow.Position = UDim2.new(0.5, 0, 1, -32)
	btnRow.AnchorPoint = Vector2.new(0.5, 1)
	btnRow.BackgroundTransparency = 1
	btnRow.ZIndex = 82
	btnRow.Parent = box

	local btnLayout = Instance.new("UIListLayout")
	btnLayout.FillDirection = Enum.FillDirection.Horizontal
	btnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	btnLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	btnLayout.Padding = UDim.new(0, 16)
	btnLayout.Parent = btnRow

	local yesBtn = Instance.new("TextButton")
	yesBtn.Name = "YesBtn"
	yesBtn.Size = UDim2.new(0, 150, 0, 44)
	yesBtn.BackgroundColor3 = Color3.fromRGB(50, 190, 80)
	yesBtn.Text = "Yes, Buy Gems!"
	yesBtn.TextColor3 = Color3.new(1, 1, 1)
	yesBtn.Font = FONT
	yesBtn.TextSize = 16
	yesBtn.BorderSizePixel = 0
	yesBtn.AutoButtonColor = false
	yesBtn.ZIndex = 83
	yesBtn.Parent = btnRow
	Instance.new("UICorner", yesBtn).CornerRadius = UDim.new(0, 12)

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
	noBtn.Size = UDim2.new(0, 120, 0, 44)
	noBtn.BackgroundColor3 = Color3.fromRGB(65, 55, 85)
	noBtn.Text = "No Thanks"
	noBtn.TextColor3 = Color3.fromRGB(180, 170, 200)
	noBtn.Font = FONT
	noBtn.TextSize = 16
	noBtn.BorderSizePixel = 0
	noBtn.AutoButtonColor = false
	noBtn.ZIndex = 83
	noBtn.Parent = btnRow
	Instance.new("UICorner", noBtn).CornerRadius = UDim.new(0, 12)

	local noStroke = Instance.new("UIStroke")
	noStroke.Color = Color3.fromRGB(90, 75, 120)
	noStroke.Thickness = 2
	noStroke.Parent = noBtn

	local hoverTI = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	yesBtn.MouseEnter:Connect(function()
		TweenService:Create(yesBtn, hoverTI, { Size = UDim2.new(0, 156, 0, 46) }):Play()
		TweenService:Create(yesStroke, hoverTI, { Color = Color3.fromRGB(50, 200, 80) }):Play()
	end)
	yesBtn.MouseLeave:Connect(function()
		TweenService:Create(yesBtn, hoverTI, { Size = UDim2.new(0, 150, 0, 44) }):Play()
		TweenService:Create(yesStroke, hoverTI, { Color = Color3.fromRGB(30, 140, 50) }):Play()
	end)
	noBtn.MouseEnter:Connect(function()
		TweenService:Create(noBtn, hoverTI, { Size = UDim2.new(0, 126, 0, 46) }):Play()
		TweenService:Create(noBtn, hoverTI, { BackgroundColor3 = Color3.fromRGB(85, 70, 110) }):Play()
	end)
	noBtn.MouseLeave:Connect(function()
		TweenService:Create(noBtn, hoverTI, { Size = UDim2.new(0, 120, 0, 44) }):Play()
		TweenService:Create(noBtn, hoverTI, { BackgroundColor3 = Color3.fromRGB(65, 55, 85) }):Play()
	end)

	yesBtn.MouseButton1Click:Connect(function()
		dismiss()
		GemShopController.Close()
		StoreController.Open("Gems")
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

	box.Size = UDim2.new(0, 200, 0, 120)
	TweenService:Create(box, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 400, 0, 240),
	}):Play()
end

local function showGemCaseErrorToast(message)
	if not screenGui then return end
	if activeErrorToast and activeErrorToast.Parent then
		activeErrorToast:Destroy()
	end

	local toast = Instance.new("Frame")
	toast.Name = "GemCaseErrorToast"
	toast.Size = UDim2.new(0, 430, 0, 46)
	toast.Position = UDim2.new(0.5, 0, 0.92, 0)
	toast.AnchorPoint = Vector2.new(0.5, 0.5)
	toast.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	toast.BorderSizePixel = 0
	toast.ZIndex = 95
	toast.Parent = screenGui
	activeErrorToast = toast
	Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 10)

	local tL = Instance.new("TextLabel")
	tL.Size = UDim2.new(1, -12, 1, 0)
	tL.Position = UDim2.new(0.5, 0, 0.5, 0)
	tL.AnchorPoint = Vector2.new(0.5, 0.5)
	tL.BackgroundTransparency = 1
	tL.Text = tostring(message or "Error!")
	tL.TextColor3 = Color3.new(1, 1, 1)
	tL.Font = FONT
	tL.TextSize = 14
	tL.TextWrapped = true
	tL.ZIndex = 96
	tL.Parent = toast

	task.delay(2.2, function()
		if not toast.Parent then return end
		TweenService:Create(toast, TweenInfo.new(0.22), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(tL, TweenInfo.new(0.22), { TextTransparency = 1 }):Play()
		task.delay(0.26, function()
			if toast.Parent then toast:Destroy() end
			if activeErrorToast == toast then
				activeErrorToast = nil
			end
		end)
	end)
end

local function stopViewports()
	vpConns = {}
	if heartbeatConn then heartbeatConn:Disconnect(); heartbeatConn = nil end
end

local function startViewportLoop()
	if heartbeatConn then return end
	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		for i = #vpConns, 1, -1 do
			local d = vpConns[i]
			if not d.camera or not d.camera.Parent then
				table.remove(vpConns, i)
			else
				d.angle = d.angle + dt * d.speed
				d.camera.CFrame = CFrame.new(
					d.target + Vector3.new(math.sin(d.angle) * d.dist, d.camY, math.cos(d.angle) * d.dist),
					d.target
				)
			end
		end
		if #vpConns == 0 and heartbeatConn then
			heartbeatConn:Disconnect(); heartbeatConn = nil
		end
	end)
end

local function addSpinningViewport(parent, streamerId, width, height, speed)
	local viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.new(0, width, 0, height)
	viewport.BackgroundColor3 = Color3.fromRGB(12, 12, 24)
	viewport.BackgroundTransparency = 0.2
	viewport.BorderSizePixel = 0
	viewport.Parent = parent
	Instance.new("UICorner", viewport).CornerRadius = UDim.new(0, 8)

	local modelsFolder = ReplicatedStorage:FindFirstChild("StreamerModels")
	local tpl = modelsFolder and modelsFolder:FindFirstChild(streamerId)
	if tpl then
		local m = tpl:Clone(); m.Parent = viewport
		local cam = Instance.new("Camera"); cam.Parent = viewport
		viewport.CurrentCamera = cam
		local ok, cf, sz = pcall(function() return m:GetBoundingBox() end)
		if ok and cf and sz then
			local maxD = math.max(sz.X, sz.Y, sz.Z)
			local dist = maxD * 1.8
			local target = cf.Position
			local camY = sz.Y * 0.15
			cam.CFrame = CFrame.new(target + Vector3.new(0, camY, dist), target)
			table.insert(vpConns, {
				camera = cam, target = target, dist = dist,
				camY = camY, angle = math.random() * math.pi * 2, speed = speed or 0.8,
			})
			startViewportLoop()
		end
	end
	return viewport
end

local function computeEffectPercentages(compression)
	local weights, total = {}, 0
	for i, s in ipairs(Streamers.List) do
		local w = (1 / s.odds) ^ compression
		weights[i] = w; total = total + w
	end
	local result = {}
	for i, s in ipairs(Streamers.List) do
		result[i] = {
			streamerId = s.id, displayName = s.displayName,
			rarity = s.rarity, percent = (weights[i] / total) * 100,
		}
	end
	return result
end

-------------------------------------------------
-- DROP RATE POPUP
-------------------------------------------------

local dropRateFrame = nil

local function closeDropRatePopup()
	if dropRateFrame then dropRateFrame:Destroy(); dropRateFrame = nil end
end

local function openDropRatePopup(caseData)
	closeDropRatePopup()

	local popup = Instance.new("Frame")
	popup.Name = "DropRatePopup"
	popup.Size = UDim2.new(0, 700, 0, 580)
	popup.Position = UDim2.new(0.5, 0, 0.5, 0)
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.BackgroundColor3 = MODAL_BG
	popup.BorderSizePixel = 0; popup.ZIndex = 30
	popup.ClipsDescendants = true
	popup.Parent = screenGui
	Instance.new("UICorner", popup).CornerRadius = UDim.new(0, 20)
	local pStroke = Instance.new("UIStroke")
	pStroke.Color = caseData.color; pStroke.Thickness = 2; pStroke.Parent = popup
	UIHelper.MakeResponsiveModal(popup, 700, 580)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0.7, 0, 0, 32)
	title.Position = UDim2.new(0, 18, 0, 10)
	title.BackgroundTransparency = 1
	title.Text = caseData.name .. " — Drops"
	title.TextColor3 = caseData.color
	title.Font = FONT; title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 31; title.Parent = popup
	addStroke(title, Color3.new(0, 0, 0), 1.5)

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 36, 0, 36)
	closeBtn.Position = UDim2.new(1, -12, 0, 8)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = RED; closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = FONT; closeBtn.TextSize = 18
	closeBtn.BorderSizePixel = 0; closeBtn.AutoButtonColor = false
	closeBtn.ZIndex = 32; closeBtn.Parent = popup
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1, 0)
	closeBtn.MouseButton1Click:Connect(closeDropRatePopup)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -14, 1, -52)
	scroll.Position = UDim2.new(0, 7, 0, 48)
	scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5; scroll.ScrollBarImageColor3 = caseData.color
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ZIndex = 31; scroll.Parent = popup

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 5); layout.Parent = scroll

	Instance.new("UIPadding", scroll).PaddingTop = UDim.new(0, 4)

	local items = computeEffectPercentages(caseData.compression)
	for idx, item in ipairs(items) do
		local rarInfo = Rarities.ByName[item.rarity]
		local rarColor = rarInfo and rarInfo.color or Color3.fromRGB(170, 170, 170)

		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 50)
		row.BackgroundColor3 = Color3.fromRGB(40, 35, 60)
		row.BorderSizePixel = 0; row.LayoutOrder = idx; row.ZIndex = 31
		row.Parent = scroll
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)

		local vp = addSpinningViewport(row, item.streamerId, 42, 42, 0.8)
		vp.Position = UDim2.new(0, 6, 0.5, 0)
		vp.AnchorPoint = Vector2.new(0, 0.5); vp.ZIndex = 32

		local nm = Instance.new("TextLabel")
		nm.Size = UDim2.new(0, 200, 0, 20)
		nm.Position = UDim2.new(0, 54, 0, 6)
		nm.BackgroundTransparency = 1
		nm.Text = item.displayName; nm.TextColor3 = rarColor
		nm.Font = FONT; nm.TextSize = 13
		nm.TextXAlignment = Enum.TextXAlignment.Left
		nm.TextTruncate = Enum.TextTruncate.AtEnd
		nm.ZIndex = 32; nm.Parent = row

		local rar = Instance.new("TextLabel")
		rar.Size = UDim2.new(0, 200, 0, 14)
		rar.Position = UDim2.new(0, 54, 0, 28)
		rar.BackgroundTransparency = 1
		rar.Text = item.rarity:upper(); rar.TextColor3 = Color3.fromRGB(120, 115, 140)
		rar.Font = FONT_SUB; rar.TextSize = 10
		rar.TextXAlignment = Enum.TextXAlignment.Left
		rar.ZIndex = 32; rar.Parent = row

		local pctText = item.percent >= 1 and string.format("%.1f%%", item.percent)
			or item.percent >= 0.01 and string.format("%.2f%%", item.percent)
			or string.format("%.4f%%", item.percent)
		local pct = Instance.new("TextLabel")
		pct.Size = UDim2.new(0, 80, 1, 0)
		pct.Position = UDim2.new(1, -8, 0, 0)
		pct.AnchorPoint = Vector2.new(1, 0)
		pct.BackgroundTransparency = 1
		pct.Text = pctText; pct.TextColor3 = Color3.fromRGB(255, 255, 100)
		pct.Font = FONT; pct.TextSize = 16
		pct.TextXAlignment = Enum.TextXAlignment.Right
		pct.ZIndex = 32; pct.Parent = row
		addStroke(pct, Color3.new(0, 0, 0), 1)
	end

	dropRateFrame = popup
	UIHelper.ScaleIn(popup, 0.2)
end

-------------------------------------------------
-- CASE OPENING ANIMATION (CS:GO style strip)
-------------------------------------------------

local caseAnimOverlay = nil
local caseAnimConn = nil
local caseSkipRequested = false

local function easeOutQuint(t)
	local t1 = 1 - t
	return 1 - t1 * t1 * t1 * t1 * t1
end

local function cleanupCaseAnim()
	if caseAnimOverlay then caseAnimOverlay:Destroy(); caseAnimOverlay = nil end
	if caseAnimConn then caseAnimConn:Disconnect(); caseAnimConn = nil end
end

local function showCaseOpenAnimation(caseData, resultData)
	cleanupCaseAnim()

	local pool = {}
	if caseData.items then
		for _, item in ipairs(caseData.items) do
			local sInfo = Streamers.ById[item.streamerId]
			table.insert(pool, {
				streamerId = item.streamerId,
				displayName = item.displayName or (sInfo and sInfo.displayName) or item.streamerId,
				rarity = sInfo and sInfo.rarity or "Common",
				effect = item.effect,
			})
		end
	elseif caseData.compression then
		for _, s in ipairs(Streamers.List) do
			table.insert(pool, {
				streamerId = s.id,
				displayName = caseData.effect .. " " .. s.displayName,
				rarity = s.rarity,
				effect = caseData.effect,
			})
		end
	end
	if #pool == 0 then return end

	local CARD_W, CARD_H, CARD_GAP = 120, 140, 6
	local CARD_STEP = CARD_W + CARD_GAP
	local DURATION = 5.0

	local totalCards = math.max(60, #pool * 6)
	local cards = {}
	for i = 1, totalCards do cards[i] = pool[((i - 1) % #pool) + 1] end
	for i = #cards, 2, -1 do
		local j = math.random(1, i)
		cards[i], cards[j] = cards[j], cards[i]
	end

	local winIdx = math.floor(totalCards * 0.72)
	local winItem
	for _, p in ipairs(pool) do
		if p.streamerId == resultData.streamerId and (p.effect or "") == (resultData.effect or "") then
			winItem = p; break
		end
	end
	if not winItem then
		winItem = {
			streamerId = resultData.streamerId, displayName = resultData.displayName,
			rarity = resultData.rarity, effect = resultData.effect,
		}
	end
	cards[winIdx] = winItem

	local nearMissOffsets = { -2, -1, 1, 2 }
	for _, off in ipairs(nearMissOffsets) do
		local adj = winIdx + off
		if adj >= 1 and adj <= totalCards and math.random() < 0.35 then
			local rareItems = {}
			for _, p in ipairs(pool) do
				if p.rarity == "Epic" or p.rarity == "Legendary" or p.rarity == "Mythic" then
					table.insert(rareItems, p)
				end
			end
			if #rareItems > 0 then cards[adj] = rareItems[math.random(1, #rareItems)] end
		end
	end

	local aOverlay = Instance.new("Frame")
	aOverlay.Size = UDim2.new(1, 0, 1, 0)
	aOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
	aOverlay.BackgroundTransparency = 0.3
	aOverlay.BorderSizePixel = 0; aOverlay.ZIndex = 20
	aOverlay.Parent = modalFrame

	local stripWin = Instance.new("Frame")
	stripWin.Size = UDim2.new(0.94, 0, 0, CARD_H + 24)
	stripWin.Position = UDim2.new(0.5, 0, 0.42, 0)
	stripWin.AnchorPoint = Vector2.new(0.5, 0.5)
	stripWin.BackgroundColor3 = Color3.fromRGB(10, 10, 22)
	stripWin.BorderSizePixel = 0; stripWin.ClipsDescendants = true
	stripWin.ZIndex = 21; stripWin.Parent = aOverlay
	Instance.new("UICorner", stripWin).CornerRadius = UDim.new(0, 14)
	local wStroke = Instance.new("UIStroke", stripWin)
	wStroke.Color = caseData.color; wStroke.Thickness = 2

	local strip = Instance.new("Frame")
	strip.BackgroundTransparency = 1; strip.BorderSizePixel = 0
	strip.Size = UDim2.new(0, totalCards * CARD_STEP, 1, 0)
	strip.ZIndex = 22; strip.Parent = stripWin

	for i, item in ipairs(cards) do
		local rInfo = Rarities.ByName[item.rarity]
		local rColor = rInfo and rInfo.color or Color3.fromRGB(170, 170, 170)
		local effInfo = item.effect and Effects.ByName[item.effect]
		local bgColor = rColor
		if effInfo then
			bgColor = Color3.fromRGB(
				math.floor(rColor.R * 255 * 0.5 + effInfo.color.R * 255 * 0.5),
				math.floor(rColor.G * 255 * 0.5 + effInfo.color.G * 255 * 0.5),
				math.floor(rColor.B * 255 * 0.5 + effInfo.color.B * 255 * 0.5))
		end

		local card = Instance.new("Frame")
		card.Name = "C" .. i
		card.Size = UDim2.new(0, CARD_W, 0, CARD_H)
		card.Position = UDim2.new(0, (i - 1) * CARD_STEP, 0.5, 0)
		card.AnchorPoint = Vector2.new(0, 0.5)
		card.BackgroundColor3 = bgColor
		card.BorderSizePixel = 0; card.ZIndex = 22; card.Parent = strip
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

		local cg = Instance.new("UIGradient", card)
		cg.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 60, 80)),
		})
		cg.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0),
		})
		cg.Rotation = 90

		Instance.new("UIStroke", card).Color = rColor

		if effInfo then
			local badge = Instance.new("TextLabel")
			badge.Size = UDim2.new(1, -6, 0, 16)
			badge.Position = UDim2.new(0.5, 0, 0, 4)
			badge.AnchorPoint = Vector2.new(0.5, 0)
			badge.BackgroundTransparency = 1
			badge.Text = effInfo.prefix:upper()
			badge.TextColor3 = effInfo.color
			badge.Font = FONT; badge.TextSize = 11; badge.ZIndex = 23
			badge.Parent = card
			addStroke(badge, Color3.new(0, 0, 0), 1)
		end

		local nm = Instance.new("TextLabel")
		nm.Size = UDim2.new(1, -8, 0, 44)
		nm.Position = UDim2.new(0.5, 0, effInfo and 0.16 or 0.06, 0)
		nm.AnchorPoint = Vector2.new(0.5, 0)
		nm.BackgroundTransparency = 1
		nm.Text = item.displayName
		nm.TextColor3 = effInfo and effInfo.color or Color3.new(1, 1, 1)
		nm.Font = FONT; nm.TextSize = 14; nm.TextWrapped = true
		nm.ZIndex = 23; nm.Parent = card
		addStroke(nm, Color3.new(0, 0, 0), 1)

		local rl = Instance.new("TextLabel")
		rl.Size = UDim2.new(1, -6, 0, 18)
		rl.Position = UDim2.new(0.5, 0, 1, -28)
		rl.AnchorPoint = Vector2.new(0.5, 0)
		rl.BackgroundTransparency = 1
		rl.Text = item.rarity:upper(); rl.TextColor3 = rColor
		rl.Font = FONT; rl.TextSize = 11; rl.ZIndex = 23
		rl.Parent = card
	end

	local sel = Instance.new("Frame")
	sel.Size = UDim2.new(0, 3, 1, 10)
	sel.Position = UDim2.new(0.5, 0, 0.5, 0)
	sel.AnchorPoint = Vector2.new(0.5, 0.5)
	sel.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
	sel.BorderSizePixel = 0; sel.ZIndex = 25; sel.Parent = stripWin

	for _, side in ipairs({"Left", "Right"}) do
		local fade = Instance.new("Frame")
		fade.Size = UDim2.new(0, 70, 1, 0)
		fade.Position = side == "Left" and UDim2.new(0, 0, 0, 0) or UDim2.new(1, -70, 0, 0)
		fade.BackgroundColor3 = Color3.fromRGB(10, 10, 22)
		fade.BorderSizePixel = 0; fade.ZIndex = 24; fade.Parent = stripWin
		local ug = Instance.new("UIGradient", fade)
		ug.Transparency = side == "Left"
			and NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1)})
			or  NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0)})
	end

	caseSkipRequested = false
	local skipBtn = Instance.new("TextButton")
	skipBtn.Size = UDim2.new(0, 90, 0, 30)
	skipBtn.Position = UDim2.new(0.5, 0, 0.42, (CARD_H + 24) / 2 + 18)
	skipBtn.AnchorPoint = Vector2.new(0.5, 0)
	skipBtn.BackgroundColor3 = Color3.fromRGB(60, 55, 80)
	skipBtn.Text = "SKIP"; skipBtn.TextColor3 = Color3.fromRGB(180, 180, 200)
	skipBtn.Font = FONT; skipBtn.TextSize = 13
	skipBtn.BorderSizePixel = 0; skipBtn.ZIndex = 25; skipBtn.Parent = aOverlay
	Instance.new("UICorner", skipBtn).CornerRadius = UDim.new(0, 8)
	skipBtn.MouseButton1Click:Connect(function() caseSkipRequested = true end)

	caseAnimOverlay = aOverlay

	local frameWidth = stripWin.AbsoluteSize.X
	if frameWidth == 0 then frameWidth = 480 end
	local halfFrame = frameWidth / 2
	local targetCenterX = (winIdx - 1) * CARD_STEP + CARD_W / 2
	local endX = halfFrame - targetCenterX + math.random(-15, 15)
	local startX = endX + #pool * CARD_STEP * 3

	strip.Position = UDim2.new(0, startX, 0, 0)
	local totalDist = startX - endX
	local startTime = tick()
	local done = false

	local function finishAnim()
		strip.Position = UDim2.new(0, endX, 0, 0)
		if skipBtn and skipBtn.Parent then skipBtn:Destroy() end

		local winCard = strip:FindFirstChild("C" .. winIdx)
		if winCard then
			local rInfo = Rarities.ByName[winItem.rarity]
			local glow = Instance.new("UIStroke")
			glow.Color = rInfo and rInfo.color or Color3.new(1, 1, 1)
			glow.Thickness = 0; glow.Parent = winCard
			TweenService:Create(glow, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Thickness = 5 }):Play()
		end

		local rarityRank = ({ Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5 })[resultData.rarity or "Common"] or 1
		if rarityRank >= 3 then
			local flash = Instance.new("Frame")
			flash.Size = UDim2.new(1, 0, 1, 0)
			flash.BackgroundColor3 = Rarities.ByName[resultData.rarity] and Rarities.ByName[resultData.rarity].color or Color3.new(1, 1, 1)
			flash.BackgroundTransparency = 0.5; flash.ZIndex = 28; flash.Parent = aOverlay
			TweenService:Create(flash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
			task.delay(0.5, function() if flash.Parent then flash:Destroy() end end)
		end
		if rarityRank >= 4 then UIHelper.CameraShake(rarityRank * 0.15, 0.4) end

		task.wait(0.6)

		local rInfo2 = Rarities.ByName[resultData.rarity or "Common"]
		local rColor2 = rInfo2 and rInfo2.color or Color3.new(1, 1, 1)
		local effInfo2 = resultData.effect and Effects.ByName[resultData.effect]
		local displayColor = effInfo2 and effInfo2.color or rColor2

		local popup = Instance.new("Frame")
		popup.Size = UDim2.new(0.7, 0, 0, 100)
		popup.Position = UDim2.new(0.5, 0, 0.75, 0)
		popup.AnchorPoint = Vector2.new(0.5, 0.5)
		popup.BackgroundColor3 = Color3.fromRGB(40, 35, 60)
		popup.BorderSizePixel = 0; popup.ZIndex = 26; popup.Parent = aOverlay
		Instance.new("UICorner", popup).CornerRadius = UDim.new(0, 16)
		Instance.new("UIStroke", popup).Color = displayColor

		local displayName = resultData.displayName or "???"
		local fullText = "You got: " .. displayName .. "!\n" .. (resultData.rarity or ""):upper()
		if effInfo2 then
			fullText = fullText .. "\n" .. effInfo2.prefix:upper() .. " (x" .. effInfo2.cashMultiplier .. " cash)"
		end

		local ppL = Instance.new("TextLabel")
		ppL.Size = UDim2.new(1, -20, 1, 0)
		ppL.Position = UDim2.new(0.5, 0, 0.5, 0)
		ppL.AnchorPoint = Vector2.new(0.5, 0.5)
		ppL.BackgroundTransparency = 1
		ppL.Text = fullText; ppL.TextColor3 = displayColor
		ppL.Font = FONT; ppL.TextSize = 18; ppL.TextWrapped = true
		ppL.ZIndex = 27; ppL.Parent = popup
		addStroke(ppL, Color3.new(0, 0, 0), 1.5)

		UIHelper.ScaleIn(popup, 0.3)

		local dismissDelay = autoOpenEnabled and 1.5 or 3
		task.delay(dismissDelay, function()
			if aOverlay and aOverlay.Parent then
				TweenService:Create(aOverlay, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
				task.delay(0.3, function()
					cleanupCaseAnim()
					if autoOpenEnabled and autoOpenCaseId and isOpen then
						local autoCaseData = GemCases.ById[autoOpenCaseId]
						if autoCaseData then
							local gems = HUDController.Data.gems or 0
							if gems >= autoCaseData.cost then
								BuyGemCase:FireServer(autoOpenCaseId)
							else
								autoOpenEnabled = false; autoOpenCaseId = nil
							end
						end
					end
				end)
			end
		end)
	end

	caseAnimConn = RunService.RenderStepped:Connect(function()
		if caseSkipRequested and not done then
			done = true; caseAnimConn:Disconnect(); caseAnimConn = nil
			local tw = TweenService:Create(strip, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(0, endX, 0, 0)
			})
			tw:Play(); tw.Completed:Connect(function() task.spawn(finishAnim) end)
			return
		end
		local t = math.min((tick() - startTime) / DURATION, 1)
		strip.Position = UDim2.new(0, startX - totalDist * easeOutQuint(t), 0, 0)
		if t >= 1 and not done then
			done = true; caseAnimConn:Disconnect(); caseAnimConn = nil
			task.spawn(finishAnim)
		end
	end)
end

-------------------------------------------------
-- BUILD CASE CARD (single card in the scroll)
-------------------------------------------------

local function buildCaseCard(caseData, parent, order)
	local card = Instance.new("Frame")
	card.Name = "Case_" .. caseData.id
	card.Size = UDim2.new(0, 280, 0, 370)
	card.BackgroundColor3 = Color3.fromRGB(40, 35, 60)
	card.BorderSizePixel = 0
	card.LayoutOrder = order
	card.ZIndex = 3; card.ClipsDescendants = true
	card.Parent = parent
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 18)

	-- Subtle colored border
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = caseData.color
	cardStroke.Thickness = 2.5
	cardStroke.Transparency = 0.2
	cardStroke.Parent = card

	-- Logo image (case name) -- BIG
	local logoImage = Instance.new("ImageLabel")
	logoImage.Name = "Logo"
	logoImage.Size = UDim2.new(1, -16, 0, 75)
	logoImage.Position = UDim2.new(0.5, 0, 0, 10)
	logoImage.AnchorPoint = Vector2.new(0.5, 0)
	logoImage.BackgroundTransparency = 1
	logoImage.ScaleType = Enum.ScaleType.Fit
	logoImage.ZIndex = 4
	logoImage.Parent = card
	if caseData.logoImageId and caseData.logoImageId ~= "" then
		logoImage.Image = caseData.logoImageId
	end

	-- Case picture (center image)
	local casePic = Instance.new("ImageLabel")
	casePic.Name = "CasePicture"
	casePic.Size = UDim2.new(0, 160, 0, 160)
	casePic.Position = UDim2.new(0.5, 0, 0, 88)
	casePic.AnchorPoint = Vector2.new(0.5, 0)
	casePic.BackgroundTransparency = 1
	casePic.ScaleType = Enum.ScaleType.Fit
	casePic.ZIndex = 4
	casePic.Parent = card
	if caseData.pictureImageId and caseData.pictureImageId ~= "" then
		casePic.Image = caseData.pictureImageId
	end

	local isLocked = false

	-- Price label
	local priceLabel = Instance.new("TextLabel")
	priceLabel.Size = UDim2.new(1, 0, 0, 26)
	priceLabel.Position = UDim2.new(0.5, 0, 0, 252)
	priceLabel.AnchorPoint = Vector2.new(0.5, 0)
	priceLabel.BackgroundTransparency = 1
	priceLabel.Text = fmtNum(caseData.cost) .. " Gems"
	priceLabel.TextColor3 = Color3.fromRGB(120, 200, 255)
	priceLabel.Font = FONT; priceLabel.TextSize = 20
	priceLabel.ZIndex = 4; priceLabel.Parent = card
	addStroke(priceLabel, Color3.new(0, 0, 0), 1.2)

	-- OPEN button (wide, element-colored)
	local buyBtn = Instance.new("TextButton")
	buyBtn.Name = "BuyBtn"
	buyBtn.Size = UDim2.new(1, -24, 0, 34)
	buyBtn.Position = UDim2.new(0.5, 0, 0, 284)
	buyBtn.AnchorPoint = Vector2.new(0.5, 0)
	buyBtn.BackgroundColor3 = isLocked and Color3.fromRGB(70, 65, 80) or caseData.color
	buyBtn.Text = ""; buyBtn.BorderSizePixel = 0
	buyBtn.AutoButtonColor = false; buyBtn.ZIndex = 5
	buyBtn.Parent = card
	Instance.new("UICorner", buyBtn).CornerRadius = UDim.new(0, 10)
	local buyStroke = Instance.new("UIStroke")
	buyStroke.Color = Color3.fromRGB(
		math.max(math.floor(caseData.color.R * 255 * 0.6), 0),
		math.max(math.floor(caseData.color.G * 255 * 0.6), 0),
		math.max(math.floor(caseData.color.B * 255 * 0.6), 0))
	buyStroke.Thickness = 1.5; buyStroke.Parent = buyBtn

	local buyText = Instance.new("TextLabel")
	buyText.Size = UDim2.new(1, 0, 1, 0)
	buyText.BackgroundTransparency = 1
	buyText.Text = isLocked and "LOCKED" or "OPEN"
	buyText.TextColor3 = isLocked and Color3.fromRGB(120, 115, 130) or Color3.new(1, 1, 1)
	buyText.Font = FONT; buyText.TextSize = 17; buyText.ZIndex = 6
	buyText.Parent = buyBtn
	addStroke(buyText, Color3.new(0, 0, 0), 1.2)

	if not isLocked then
		buyBtn.MouseEnter:Connect(function()
			TweenService:Create(buyBtn, bounceTween, { Size = UDim2.new(1, -18, 0, 38) }):Play()
		end)
		buyBtn.MouseLeave:Connect(function()
			TweenService:Create(buyBtn, bounceTween, { Size = UDim2.new(1, -24, 0, 34) }):Play()
		end)
		buyBtn.MouseButton1Click:Connect(function()
			local gems = HUDController.Data.gems or 0
			if gems < caseData.cost then
				showNotEnoughGemsPopup()
				return
			end
			-- Route gem case openings through SpinController so animation/flow
			-- exactly matches regular case openings.
			pendingGemSpin = true
			GemShopController.Close()
			SpinController.SetCurrentCost(0)
			SpinController.SetCurrentCrateId(nil)
			SpinController.SetOwnedCrateMode(false)
			SpinController.SetGemCaseVisual(caseData.id)
			SpinController.Show()
			SpinController.WaitForResult()
			BuyGemCase:FireServer(caseData.id)
		end)
	end

	-- Drop Rate button (below OPEN)
	local drBtn = Instance.new("TextButton")
	drBtn.Size = UDim2.new(1, -24, 0, 28)
	drBtn.Position = UDim2.new(0.5, 0, 0, 324)
	drBtn.AnchorPoint = Vector2.new(0.5, 0)
	drBtn.BackgroundColor3 = Color3.fromRGB(55, 50, 75)
	drBtn.Text = ""; drBtn.BorderSizePixel = 0
	drBtn.AutoButtonColor = false; drBtn.ZIndex = 5
	drBtn.Parent = card
	Instance.new("UICorner", drBtn).CornerRadius = UDim.new(0, 8)

	local drText = Instance.new("TextLabel")
	drText.Size = UDim2.new(1, 0, 1, 0)
	drText.BackgroundTransparency = 1
	drText.Text = "View Drop Rates"; drText.TextColor3 = Color3.fromRGB(160, 155, 185)
	drText.Font = FONT_SUB; drText.TextSize = 11; drText.ZIndex = 6
	drText.Parent = drBtn

	drBtn.MouseEnter:Connect(function()
		TweenService:Create(drBtn, bounceTween, { Size = UDim2.new(1, -18, 0, 32) }):Play()
		drText.TextColor3 = Color3.new(1, 1, 1)
	end)
	drBtn.MouseLeave:Connect(function()
		TweenService:Create(drBtn, bounceTween, { Size = UDim2.new(1, -24, 0, 28) }):Play()
		drText.TextColor3 = Color3.fromRGB(160, 155, 185)
	end)
	drBtn.MouseButton1Click:Connect(function()
		openDropRatePopup(caseData)
	end)

	return card
end

-------------------------------------------------
-- OPEN / CLOSE
-------------------------------------------------

function GemShopController.Open()
	if isOpen then GemShopController.Close(); return end
	isOpen = true
	if modalFrame then
		overlay.Visible = true
		modalFrame.Visible = true
		UIHelper.ScaleIn(modalFrame, 0.25)
	end
end

function GemShopController.Close()
	if not isOpen then return end
	isOpen = false
	autoOpenEnabled = false; autoOpenCaseId = nil
	closeDropRatePopup()
	cleanupCaseAnim()
	stopViewports()
	if overlay then overlay.Visible = false end
	if modalFrame then UIHelper.ScaleOut(modalFrame, 0.2) end
end

function GemShopController.IsOpen()
	return isOpen
end

-------------------------------------------------
-- INIT
-------------------------------------------------

function GemShopController.Init()
	screenGui = UIHelper.CreateScreenGui("GemShopGui", 10)
	screenGui.Parent = playerGui

	-- Overlay
	overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.45
	overlay.BorderSizePixel = 0; overlay.Visible = false
	overlay.ZIndex = 1; overlay.Parent = screenGui

	-- Modal
	modalFrame = Instance.new("Frame")
	modalFrame.Name = "GemShopModal"
	modalFrame.Size = UDim2.new(0, MODAL_W, 0, MODAL_H)
	modalFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	modalFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	modalFrame.BackgroundColor3 = MODAL_BG
	modalFrame.BorderSizePixel = 0; modalFrame.Visible = false
	modalFrame.ZIndex = 2; modalFrame.ClipsDescendants = true
	modalFrame.Parent = screenGui
	Instance.new("UICorner", modalFrame).CornerRadius = UDim.new(0, 20)
	local mStroke = Instance.new("UIStroke")
	mStroke.Color = Color3.fromRGB(70, 60, 100)
	mStroke.Thickness = 1.5; mStroke.Transparency = 0.3
	mStroke.Parent = modalFrame
	UIHelper.CreateShadow(modalFrame)
	UIHelper.MakeResponsiveModal(modalFrame, MODAL_W, MODAL_H)

	-- ===== HEADER =====
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 60)
	header.BackgroundTransparency = 1; header.ZIndex = 3
	header.Parent = modalFrame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0.6, 0, 0, 32)
	title.Position = UDim2.new(0.5, 0, 0, 14)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.BackgroundTransparency = 1
	title.Text = "Gem Shop"
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Font = FONT; title.TextSize = 28
	title.ZIndex = 3; title.Parent = header
	addStroke(title, Color3.new(0, 0, 0), 1.5)

	balanceLabel = Instance.new("TextLabel")
	balanceLabel.Size = UDim2.new(0.5, 0, 0, 30)
	balanceLabel.Position = UDim2.new(0, 20, 0, 14)
	balanceLabel.TextXAlignment = Enum.TextXAlignment.Left
	balanceLabel.BackgroundTransparency = 1
	balanceLabel.Text = "\u{1F48E} " .. fmtNum(HUDController.Data.gems or 0) .. " Gems"
	balanceLabel.TextColor3 = Color3.fromRGB(120, 210, 255)
	balanceLabel.Font = FONT; balanceLabel.TextSize = 22
	balanceLabel.ZIndex = 3; balanceLabel.Parent = header
	addStroke(balanceLabel, Color3.new(0, 0, 0), 1.5)

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 40, 0, 40)
	closeBtn.Position = UDim2.new(1, -14, 0, 10)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = RED; closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = FONT; closeBtn.TextSize = 20
	closeBtn.BorderSizePixel = 0; closeBtn.AutoButtonColor = false
	closeBtn.ZIndex = 5; closeBtn.Parent = modalFrame
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1, 0)
	local cStroke = Instance.new("UIStroke")
	cStroke.Color = RED_DARK; cStroke.Thickness = 1.5; cStroke.Parent = closeBtn

	closeBtn.MouseEnter:Connect(function()
		TweenService:Create(closeBtn, bounceTween, { Size = UDim2.new(0, 46, 0, 46), BackgroundColor3 = Color3.fromRGB(255, 75, 75) }):Play()
	end)
	closeBtn.MouseLeave:Connect(function()
		TweenService:Create(closeBtn, bounceTween, { Size = UDim2.new(0, 40, 0, 40), BackgroundColor3 = RED }):Play()
	end)
	closeBtn.MouseButton1Click:Connect(function() GemShopController.Close() end)

	-- Divider
	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(1, -30, 0, 1)
	divider.Position = UDim2.new(0.5, 0, 0, 62)
	divider.AnchorPoint = Vector2.new(0.5, 0)
	divider.BackgroundColor3 = Color3.fromRGB(60, 55, 80)
	divider.BorderSizePixel = 0; divider.ZIndex = 3
	divider.Parent = modalFrame

	-- ===== SCROLLABLE CASE GRID (3 columns) =====
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "CaseList"
	scrollFrame.Size = UDim2.new(1, -16, 1, -72)
	scrollFrame.Position = UDim2.new(0.5, 0, 0, 68)
	scrollFrame.AnchorPoint = Vector2.new(0.5, 0)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 5
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 80, 150)
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.ZIndex = 3; scrollFrame.Parent = modalFrame

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.CellSize = UDim2.new(0, 280, 0, 370)
	gridLayout.CellPadding = UDim2.new(0, 12, 0, 14)
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gridLayout.Parent = scrollFrame

	local listPad = Instance.new("UIPadding")
	listPad.PaddingTop = UDim.new(0, 8)
	listPad.PaddingBottom = UDim.new(0, 10)
	listPad.PaddingLeft = UDim.new(0, 6)
	listPad.PaddingRight = UDim.new(0, 6)
	listPad.Parent = scrollFrame

	-- Build all effect case cards (cheapest to most expensive)
	for i, ec in ipairs(GemCases.EffectCases) do
		buildCaseCard(ec, scrollFrame, i)
	end

	-------------------------------------------------
	-- EVENTS
	-------------------------------------------------
	HUDController.OnDataUpdated(function()
		if balanceLabel then
			balanceLabel.Text = "\u{1F48E} " .. fmtNum(HUDController.Data.gems or 0) .. " Gems"
		end
	end)

	GemCaseResult.OnClientEvent:Connect(function(result)
		if result.success then
			pendingGemSpin = false
			SpinController._startSpin(result)
		else
			if pendingGemSpin then
				pendingGemSpin = false
				SpinController.Hide()
			end
			if autoOpenEnabled then
				autoOpenEnabled = false; autoOpenCaseId = nil
			end
			local isGemError = result.reason and string.find(result.reason, "gem", 1, true)
			if isGemError then
				showNotEnoughGemsPopup()
			else
				showGemCaseErrorToast(result.reason or "Error!")
			end
		end
	end)

	OpenGemShopGui.OnClientEvent:Connect(function()
		local TutorialController = require(script.Parent.TutorialController)
		if TutorialController.IsActive() then return end
		if isOpen then GemShopController.Close() else GemShopController.Open() end
	end)

	modalFrame.Visible = false
end

return GemShopController
