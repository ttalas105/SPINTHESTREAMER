--[[
	GemShopController.lua
	Gem Shop UI — spend gems on cases.
	Tabs: Gem Case 1, Effect Cases (Acid→Void), All In.
	Each effect case has a "View Drop Rate" popup with spinning models + percentages.
	Walk up to the Gems stall → press E.
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

local GemShopController = {}

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RemoteEvents  = ReplicatedStorage:WaitForChild("RemoteEvents")
local OpenGemShopGui = RemoteEvents:WaitForChild("OpenGemShopGui")
local BuyGemCase     = RemoteEvents:WaitForChild("BuyGemCase")
local GemCaseResult  = RemoteEvents:WaitForChild("GemCaseResult")

local screenGui
local modalFrame
local isOpen      = false
local balanceLabel
local contentFrame         -- right-side content area
local sidebarBtns          = {}
local activeTabId          = nil
local dropRateFrame        = nil -- popup for viewing drop rates
local vpConns              = {}   -- viewport heartbeat data (shared loop)
local heartbeatConn        = nil
local autoOpenEnabled      = false   -- auto-open toggle state
local autoOpenCaseId       = nil     -- which case is being auto-opened

local FONT = Enum.Font.FredokaOne

-------------------------------------------------
-- HELPERS
-------------------------------------------------

local function formatNumber(n)
	local s = tostring(math.floor(n))
	local f = ""
	for i = 1, #s do
		f = f .. s:sub(i,i)
		if (#s - i) % 3 == 0 and i < #s then f = f .. "," end
	end
	return f
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

-- Create a spinning model viewport (infinite)
local function addSpinningViewport(parent, streamerId, width, height, speed)
	local viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.new(0, width, 0, height)
	viewport.BackgroundColor3 = Color3.fromRGB(12, 12, 24)
	viewport.BackgroundTransparency = 0.2
	viewport.BorderSizePixel = 0
	viewport.Parent = parent
	local vpCorner = Instance.new("UICorner")
	vpCorner.CornerRadius = UDim.new(0, 8)
	vpCorner.Parent = viewport

	local modelsFolder = ReplicatedStorage:FindFirstChild("StreamerModels")
	local tpl = modelsFolder and modelsFolder:FindFirstChild(streamerId)
	if tpl then
		local m = tpl:Clone()
		m.Parent = viewport
		local cam = Instance.new("Camera")
		cam.Parent = viewport
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
	else
		local ph = Instance.new("TextLabel")
		ph.Size = UDim2.new(1, 0, 1, 0)
		ph.BackgroundTransparency = 1
		ph.Text = "\u{1F3AD}"; ph.TextSize = 20
		ph.Font = Enum.Font.SourceSans; ph.Parent = viewport
	end
	return viewport
end

-- Create a static model viewport (no spinning)
local function addStaticViewport(parent, streamerId, width, height)
	local viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.new(0, width, 0, height)
	viewport.BackgroundColor3 = Color3.fromRGB(15, 15, 28)
	viewport.BackgroundTransparency = 0.3
	viewport.BorderSizePixel = 0
	viewport.Parent = parent
	local vpCorner = Instance.new("UICorner")
	vpCorner.CornerRadius = UDim.new(0, 8)
	vpCorner.Parent = viewport

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
			cam.CFrame = CFrame.new(cf.Position + Vector3.new(dist*0.3, sz.Y*0.2, dist*0.9), cf.Position)
		end
	else
		local ph = Instance.new("TextLabel")
		ph.Size = UDim2.new(1, 0, 1, 0); ph.BackgroundTransparency = 1
		ph.Text = "\u{1F3AD}"; ph.TextSize = 20; ph.Font = Enum.Font.SourceSans
		ph.Parent = viewport
	end
	return viewport
end

-- Compute effect case percentages client-side (mirrors server logic)
local function computeEffectPercentages(compression)
	local weights, total = {}, 0
	for i, s in ipairs(Streamers.List) do
		local w = (1 / s.odds) ^ compression
		weights[i] = w
		total = total + w
	end
	local result = {}
	for i, s in ipairs(Streamers.List) do
		result[i] = {
			streamerId  = s.id,
			displayName = s.displayName,
			rarity      = s.rarity,
			percent     = (weights[i] / total) * 100,
		}
	end
	return result
end

-------------------------------------------------
-- DROP RATE POPUP (spinning models + percentages)
-------------------------------------------------

local function closeDropRatePopup()
	if dropRateFrame then
		dropRateFrame:Destroy()
		dropRateFrame = nil
	end
end

local function openDropRatePopup(caseData)
	closeDropRatePopup()

	local popup = Instance.new("Frame")
	popup.Name = "DropRatePopup"
	popup.Size = UDim2.new(0, 700, 0, 560)
	popup.Position = UDim2.new(0.5, 0, 0.5, 0)
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.BackgroundColor3 = Color3.fromRGB(12, 10, 25)
	popup.BorderSizePixel = 0
	popup.ZIndex = 30
	popup.ClipsDescendants = true
	popup.Parent = modalFrame
	local pCorner = Instance.new("UICorner")
	pCorner.CornerRadius = UDim.new(0, 20)
	pCorner.Parent = popup
	local pStroke = Instance.new("UIStroke")
	pStroke.Color = caseData.color
	pStroke.Thickness = 3
	pStroke.Parent = popup
	UIHelper.MakeResponsiveModal(popup, 700, 560)

	-- Title
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -80, 0, 44)
	title.Position = UDim2.new(0.5, 0, 0, 12)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.BackgroundTransparency = 1
	title.Text = caseData.name .. " — Drop Rates"
	title.TextColor3 = caseData.color
	title.Font = FONT; title.TextSize = 26
	title.Parent = popup
	local tS = Instance.new("UIStroke")
	tS.Color = Color3.fromRGB(0,0,0); tS.Thickness = 2
	tS.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	tS.Parent = title

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 46, 0, 46)
	closeBtn.Position = UDim2.new(1, -12, 0, 8)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	closeBtn.Text = "X"; closeBtn.TextColor3 = Color3.new(1,1,1)
	closeBtn.Font = FONT; closeBtn.TextSize = 22
	closeBtn.BorderSizePixel = 0; closeBtn.ZIndex = 32
	closeBtn.Parent = popup
	local cbC = Instance.new("UICorner"); cbC.CornerRadius = UDim.new(1,0); cbC.Parent = closeBtn
	closeBtn.MouseButton1Click:Connect(closeDropRatePopup)

	-- Scroll area
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -14, 1, -64)
	scroll.Position = UDim2.new(0, 7, 0, 60)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = caseData.color
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ZIndex = 31
	scroll.Parent = popup

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = scroll

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = scroll

	-- Build items
	local items
	if caseData.compression then
		items = computeEffectPercentages(caseData.compression)
	elseif caseData.items then
		items = {}
		for i, item in ipairs(caseData.items) do
			local sInfo = Streamers.ById[item.streamerId]
			items[i] = {
				streamerId  = item.streamerId,
				displayName = item.displayName or (sInfo and sInfo.displayName) or item.streamerId,
				rarity      = (sInfo and sInfo.rarity) or "Common",
				percent     = item.chance,
			}
		end
	end

	for idx, item in ipairs(items) do
		local rarInfo = Rarities.ByName[item.rarity]
		local rarColor = rarInfo and rarInfo.color or Color3.fromRGB(170,170,170)

		local row = Instance.new("Frame")
		row.Name = "Row_" .. idx
		row.Size = UDim2.new(1, 0, 0, 68)
		row.BackgroundColor3 = Color3.fromRGB(22, 22, 40)
		row.BorderSizePixel = 0
		row.LayoutOrder = idx
		row.ZIndex = 31
		row.Parent = scroll
		local rCorner = Instance.new("UICorner")
		rCorner.CornerRadius = UDim.new(0, 12)
		rCorner.Parent = row

		-- Spinning model
		local vp = addSpinningViewport(row, item.streamerId, 58, 58, 0.8)
		vp.Position = UDim2.new(0, 6, 0.5, 0)
		vp.AnchorPoint = Vector2.new(0, 0.5)
		vp.ZIndex = 32

		-- Name
		local nm = Instance.new("TextLabel")
		nm.Size = UDim2.new(0, 260, 0, 26)
		nm.Position = UDim2.new(0, 72, 0, 8)
		nm.BackgroundTransparency = 1
		nm.Text = item.displayName
		nm.TextColor3 = rarColor
		nm.Font = FONT; nm.TextSize = 16
		nm.TextXAlignment = Enum.TextXAlignment.Left
		nm.TextTruncate = Enum.TextTruncate.AtEnd
		nm.ZIndex = 32
		nm.Parent = row

		-- Rarity
		local rar = Instance.new("TextLabel")
		rar.Size = UDim2.new(0, 260, 0, 20)
		rar.Position = UDim2.new(0, 72, 0, 36)
		rar.BackgroundTransparency = 1
		rar.Text = item.rarity:upper()
		rar.TextColor3 = rarColor
		rar.Font = FONT; rar.TextSize = 12
		rar.TextXAlignment = Enum.TextXAlignment.Left
		rar.ZIndex = 32
		rar.Parent = row

		-- Percentage
		local pctText
		if item.percent >= 1 then
			pctText = string.format("%.1f%%", item.percent)
		elseif item.percent >= 0.01 then
			pctText = string.format("%.2f%%", item.percent)
		else
			pctText = string.format("%.4f%%", item.percent)
		end
		local pct = Instance.new("TextLabel")
		pct.Size = UDim2.new(0, 130, 1, 0)
		pct.Position = UDim2.new(1, -12, 0, 0)
		pct.AnchorPoint = Vector2.new(1, 0)
		pct.BackgroundTransparency = 1
		pct.Text = pctText
		pct.TextColor3 = Color3.fromRGB(255, 255, 100)
		pct.Font = FONT; pct.TextSize = 20
		pct.TextXAlignment = Enum.TextXAlignment.Right
		pct.ZIndex = 32
		pct.Parent = row
		local pStk = Instance.new("UIStroke")
		pStk.Color = Color3.fromRGB(0,0,0); pStk.Thickness = 1.2
		pStk.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		pStk.ZIndex = 32; pStk.Parent = pct
	end

	dropRateFrame = popup
	UIHelper.ScaleIn(popup, 0.2)
end

-------------------------------------------------
-- BUILD CONTENT FOR A GIVEN CASE TAB
-------------------------------------------------

local function clearContent()
	if not contentFrame then return end
	for _, child in ipairs(contentFrame:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function buildCaseContent(caseData)
	clearContent()
	closeDropRatePopup()

	local isEffect = caseData.compression ~= nil
	local isAllIn  = caseData.id == "AllInCase"

	-- Case header
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, -10, 0, 110)
	header.BackgroundColor3 = Color3.fromRGB(22, 22, 40)
	header.BorderSizePixel = 0
	header.Parent = contentFrame
	local hCorner = Instance.new("UICorner")
	hCorner.CornerRadius = UDim.new(0, 18)
	hCorner.Parent = header
	local hStroke = Instance.new("UIStroke")
	hStroke.Color = caseData.color; hStroke.Thickness = 2.5
	hStroke.Parent = header

	-- Title
	local titleEmoji = isAllIn and "\u{1F3B0}" or "\u{1F48E}"
	local caseTitle = Instance.new("TextLabel")
	caseTitle.Size = UDim2.new(1, -24, 0, 40)
	caseTitle.Position = UDim2.new(0.5, 0, 0, 14)
	caseTitle.AnchorPoint = Vector2.new(0.5, 0)
	caseTitle.BackgroundTransparency = 1
	caseTitle.Text = titleEmoji .. " " .. caseData.name .. " " .. titleEmoji
	caseTitle.TextColor3 = caseData.color
	caseTitle.Font = FONT; caseTitle.TextSize = 28
	caseTitle.Parent = header
	local ctS = Instance.new("UIStroke")
	ctS.Color = Color3.fromRGB(0,0,0); ctS.Thickness = 2
	ctS.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	ctS.Parent = caseTitle

	-- Cost + effect info
	local subtitle = ""
	if isEffect then
		local effInfo = Effects.ByName[caseData.effect]
		local mult = effInfo and effInfo.cashMultiplier or 1
		subtitle = "Cost: " .. formatNumber(caseData.cost) .. " Gems  •  All streamers with " .. caseData.effect .. " (x" .. mult .. " cash)"
	elseif isAllIn then
		subtitle = "Cost: " .. formatNumber(caseData.cost) .. " Gems  •  99.9% Rakai  |  0.1% Void xQc"
	else
		subtitle = "Cost: " .. formatNumber(caseData.cost) .. " Gems"
	end
	local costLabel = Instance.new("TextLabel")
	costLabel.Size = UDim2.new(1, -24, 0, 28)
	costLabel.Position = UDim2.new(0.5, 0, 0, 58)
	costLabel.AnchorPoint = Vector2.new(0.5, 0)
	costLabel.BackgroundTransparency = 1
	costLabel.Text = subtitle
	costLabel.TextColor3 = Color3.fromRGB(180, 200, 230)
	costLabel.Font = FONT; costLabel.TextSize = 15
	costLabel.TextWrapped = true
	costLabel.Parent = header

	-- Items preview (for regular cases or All In — static models)
	if caseData.items and not isEffect then
		local itemsRow = Instance.new("Frame")
		itemsRow.Name = "ItemsRow"
		itemsRow.Size = UDim2.new(1, -10, 0, 165)
		itemsRow.BackgroundTransparency = 1
		itemsRow.Parent = contentFrame

		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.Padding = UDim.new(0, 10)
		rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		rowLayout.Parent = itemsRow

		local itemCount = #caseData.items
		local itemW = math.min(120, math.floor(520 / itemCount) - 12)

		for _, item in ipairs(caseData.items) do
			local sInfo = Streamers.ById[item.streamerId]
			local rInfo = sInfo and Rarities.ByName[sInfo.rarity]
			local rColor = rInfo and rInfo.color or Color3.fromRGB(170,170,170)

			local card = Instance.new("Frame")
			card.Size = UDim2.new(0, itemW, 1, 0)
			card.BackgroundColor3 = Color3.fromRGB(22, 22, 40)
			card.BorderSizePixel = 0
			card.Parent = itemsRow
			local cC = Instance.new("UICorner"); cC.CornerRadius = UDim.new(0, 8); cC.Parent = card
			local cS = Instance.new("UIStroke"); cS.Color = rColor; cS.Thickness = 1.5; cS.Transparency = 0.4; cS.Parent = card

			local vp = addSpinningViewport(card, item.streamerId, itemW - 10, 78, 0.6)
			vp.Position = UDim2.new(0.5, 0, 0, 6); vp.AnchorPoint = Vector2.new(0.5, 0)

			local nm = Instance.new("TextLabel")
			nm.Size = UDim2.new(1, -6, 0, 20)
			nm.Position = UDim2.new(0.5, 0, 0, 86); nm.AnchorPoint = Vector2.new(0.5, 0)
			nm.BackgroundTransparency = 1
			nm.Text = item.displayName or item.streamerId
			nm.TextColor3 = rColor
			nm.Font = FONT; nm.TextSize = 12; nm.TextTruncate = Enum.TextTruncate.AtEnd
			nm.Parent = card

			local chanceText = item.chance >= 1 and string.format("%.0f%%", item.chance) or string.format("%.1f%%", item.chance)
			local ch = Instance.new("TextLabel")
			ch.Size = UDim2.new(1, -6, 0, 22)
			ch.Position = UDim2.new(0.5, 0, 0, 106); ch.AnchorPoint = Vector2.new(0.5, 0)
			ch.BackgroundTransparency = 1
			ch.Text = chanceText
			ch.TextColor3 = Color3.fromRGB(255, 255, 100)
			ch.Font = FONT; ch.TextSize = 16
			ch.Parent = card

			if sInfo then
				local rr = Instance.new("TextLabel")
				rr.Size = UDim2.new(1, 0, 0, 16)
				rr.Position = UDim2.new(0.5, 0, 0, 130); rr.AnchorPoint = Vector2.new(0.5, 0)
				rr.BackgroundTransparency = 1
				rr.Text = sInfo.rarity:upper()
				rr.TextColor3 = rColor
				rr.Font = FONT; rr.TextSize = 10
				rr.Parent = card
			end
		end
	end

	-- Buttons row
	local btnRow = Instance.new("Frame")
	btnRow.Name = "Buttons"
	btnRow.Size = UDim2.new(1, -10, 0, 50)
	btnRow.BackgroundTransparency = 1
	btnRow.Parent = contentFrame

	local btnLayout = Instance.new("UIListLayout")
	btnLayout.FillDirection = Enum.FillDirection.Horizontal
	btnLayout.Padding = UDim.new(0, 10)
	btnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	btnLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	btnLayout.Parent = btnRow

	-- BUY BUTTON
	local buyBtn = Instance.new("TextButton")
	buyBtn.Name = "BuyBtn"
	buyBtn.Size = UDim2.new(0, 180, 0, 44)
	buyBtn.BackgroundColor3 = Color3.fromRGB(80, 180, 255)
	buyBtn.Text = "\u{1F48E} OPEN — " .. formatNumber(caseData.cost) .. " Gems"
	buyBtn.TextColor3 = Color3.new(1,1,1)
	buyBtn.Font = FONT; buyBtn.TextSize = 16
	buyBtn.BorderSizePixel = 0
	buyBtn.Parent = btnRow
	local bbCorner = Instance.new("UICorner"); bbCorner.CornerRadius = UDim.new(0, 14); bbCorner.Parent = buyBtn
	local bbStroke = Instance.new("UIStroke"); bbStroke.Color = Color3.fromRGB(40, 120, 200); bbStroke.Thickness = 2.5; bbStroke.Transparency = 0.15; bbStroke.Parent = buyBtn
	UIHelper.AddPuffyGradient(buyBtn)

	buyBtn.MouseEnter:Connect(function()
		TweenService:Create(buyBtn, TweenInfo.new(0.1), { Size = UDim2.new(0, 188, 0, 46) }):Play()
	end)
	buyBtn.MouseLeave:Connect(function()
		TweenService:Create(buyBtn, TweenInfo.new(0.1), { Size = UDim2.new(0, 180, 0, 44) }):Play()
	end)
	buyBtn.MouseButton1Click:Connect(function()
		local gems = HUDController.Data.gems or 0
		if gems < caseData.cost then
			buyBtn.Text = "Not enough gems!"
			buyBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
			task.delay(1.5, function()
				if buyBtn.Parent then
					buyBtn.Text = "\u{1F48E} OPEN \u{2014} " .. formatNumber(caseData.cost) .. " Gems"
					buyBtn.BackgroundColor3 = Color3.fromRGB(80, 180, 255)
				end
			end)
			return
		end
		BuyGemCase:FireServer(caseData.id)
	end)

	-- AUTO TOGGLE BUTTON
	local autoBtn = Instance.new("TextButton")
	autoBtn.Name = "AutoBtn"
	autoBtn.Size = UDim2.new(0, 80, 0, 44)
	local isAutoForThis = autoOpenEnabled and autoOpenCaseId == caseData.id
	autoBtn.BackgroundColor3 = isAutoForThis and Color3.fromRGB(60, 200, 80) or Color3.fromRGB(50, 50, 70)
	autoBtn.Text = isAutoForThis and "AUTO: ON" or "AUTO"
	autoBtn.TextColor3 = isAutoForThis and Color3.new(1, 1, 1) or Color3.fromRGB(180, 180, 200)
	autoBtn.Font = FONT; autoBtn.TextSize = 14
	autoBtn.BorderSizePixel = 0
	autoBtn.Parent = btnRow
	local abCorner = Instance.new("UICorner"); abCorner.CornerRadius = UDim.new(0, 12); abCorner.Parent = autoBtn
	local abStroke = Instance.new("UIStroke")
	abStroke.Color = isAutoForThis and Color3.fromRGB(40, 160, 60) or Color3.fromRGB(60, 60, 80)
	abStroke.Thickness = 2; abStroke.Parent = autoBtn

	autoBtn.MouseButton1Click:Connect(function()
		if autoOpenEnabled and autoOpenCaseId == caseData.id then
			autoOpenEnabled = false
			autoOpenCaseId = nil
			autoBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
			autoBtn.Text = "AUTO"
			autoBtn.TextColor3 = Color3.fromRGB(180, 180, 200)
			abStroke.Color = Color3.fromRGB(60, 60, 80)
		else
			autoOpenEnabled = true
			autoOpenCaseId = caseData.id
			autoBtn.BackgroundColor3 = Color3.fromRGB(60, 200, 80)
			autoBtn.Text = "AUTO: ON"
			autoBtn.TextColor3 = Color3.new(1, 1, 1)
			abStroke.Color = Color3.fromRGB(40, 160, 60)
		end
	end)

	-- VIEW DROP RATE BUTTON
	local drBtn = Instance.new("TextButton")
	drBtn.Name = "DropRateBtn"
	drBtn.Size = UDim2.new(0, 220, 0, 54)
	drBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 80)
	drBtn.Text = "\u{1F4CA} View Drop Rate"
	drBtn.TextColor3 = Color3.fromRGB(200, 200, 230)
	drBtn.Font = FONT; drBtn.TextSize = 16
	drBtn.BorderSizePixel = 0
	drBtn.Parent = btnRow
	local drCorner = Instance.new("UICorner"); drCorner.CornerRadius = UDim.new(0, 14); drCorner.Parent = drBtn
	local drStroke = Instance.new("UIStroke"); drStroke.Color = Color3.fromRGB(80, 80, 120); drStroke.Thickness = 2; drStroke.Parent = drBtn
	drBtn.MouseButton1Click:Connect(function()
		openDropRatePopup(caseData)
	end)
end

-------------------------------------------------
-- CASE OPENING ANIMATION (CS:GO style horizontal strip)
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

	-- Build item pool from case data
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

	-- Build strip: repeat & shuffle
	local totalCards = math.max(60, #pool * 6)
	local cards = {}
	for i = 1, totalCards do
		cards[i] = pool[((i - 1) % #pool) + 1]
	end
	for i = #cards, 2, -1 do
		local j = math.random(1, i)
		cards[i], cards[j] = cards[j], cards[i]
	end

	-- Place winning item at ~72%
	local winIdx = math.floor(totalCards * 0.72)
	local winItem
	for _, p in ipairs(pool) do
		if p.streamerId == resultData.streamerId and (p.effect or "") == (resultData.effect or "") then
			winItem = p; break
		end
	end
	if not winItem then
		winItem = {
			streamerId = resultData.streamerId,
			displayName = resultData.displayName,
			rarity = resultData.rarity,
			effect = resultData.effect,
		}
	end
	cards[winIdx] = winItem

	-- Near-miss: place flashy items next to winner
	local nearMissOffsets = { -2, -1, 1, 2 }
	for _, off in ipairs(nearMissOffsets) do
		local adj = winIdx + off
		if adj >= 1 and adj <= totalCards then
			if math.random() < 0.35 then
				-- Place a rare/legendary item from pool
				local rareItems = {}
				for _, p in ipairs(pool) do
					local rI = Rarities.ByName[p.rarity]
					if rI and (p.rarity == "Epic" or p.rarity == "Legendary" or p.rarity == "Mythic") then
						table.insert(rareItems, p)
					end
				end
				if #rareItems > 0 then
					cards[adj] = rareItems[math.random(1, #rareItems)]
				end
			end
		end
	end

	-- Dark overlay
	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.3
	overlay.BorderSizePixel = 0; overlay.ZIndex = 20
	overlay.Parent = modalFrame

	-- Strip window (clips the scrolling cards)
	local stripWin = Instance.new("Frame")
	stripWin.Size = UDim2.new(0.92, 0, 0, CARD_H + 24)
	stripWin.Position = UDim2.new(0.5, 0, 0.42, 0)
	stripWin.AnchorPoint = Vector2.new(0.5, 0.5)
	stripWin.BackgroundColor3 = Color3.fromRGB(10, 10, 22)
	stripWin.BorderSizePixel = 0; stripWin.ClipsDescendants = true
	stripWin.ZIndex = 21; stripWin.Parent = overlay
	Instance.new("UICorner", stripWin).CornerRadius = UDim.new(0, 14)
	local wStroke = Instance.new("UIStroke", stripWin)
	wStroke.Color = caseData.color; wStroke.Thickness = 3

	-- Rainbow top line
	local topLine = Instance.new("Frame")
	topLine.Size = UDim2.new(1, 0, 0, 4)
	topLine.BackgroundColor3 = Color3.new(1, 1, 1)
	topLine.BorderSizePixel = 0; topLine.ZIndex = 26; topLine.Parent = stripWin
	local tlg = Instance.new("UIGradient", topLine)
	tlg.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 120)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 200, 50)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 255, 150)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 150, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 80, 255)),
	})

	-- Inner strip container
	local strip = Instance.new("Frame")
	strip.BackgroundTransparency = 1; strip.BorderSizePixel = 0
	strip.Size = UDim2.new(0, totalCards * CARD_STEP, 1, 0)
	strip.ZIndex = 22; strip.Parent = stripWin

	-- Build card frames
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
			NumberSequenceKeypoint.new(0, 0.7),
			NumberSequenceKeypoint.new(1, 0),
		})
		cg.Rotation = 90

		local cStk = Instance.new("UIStroke", card)
		cStk.Color = rColor; cStk.Thickness = 2; cStk.Transparency = 0.5

		-- Bottom colour strip
		local bs = Instance.new("Frame")
		bs.Size = UDim2.new(1, 0, 0, 5)
		bs.Position = UDim2.new(0, 0, 1, -5)
		bs.BackgroundColor3 = rColor; bs.BorderSizePixel = 0; bs.ZIndex = 23
		bs.Parent = card

		-- Effect badge
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
			local eStk = Instance.new("UIStroke", badge)
			eStk.Color = Color3.new(0, 0, 0); eStk.Thickness = 1
			eStk.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		end

		-- Streamer name
		local nm = Instance.new("TextLabel")
		nm.Size = UDim2.new(1, -8, 0, 44)
		nm.Position = UDim2.new(0.5, 0, effInfo and 0.16 or 0.06, 0)
		nm.AnchorPoint = Vector2.new(0.5, 0)
		nm.BackgroundTransparency = 1
		nm.Text = item.displayName
		nm.TextColor3 = effInfo and effInfo.color or Color3.new(1, 1, 1)
		nm.Font = FONT; nm.TextSize = 14; nm.TextWrapped = true
		nm.ZIndex = 23; nm.Parent = card
		local nStk = Instance.new("UIStroke", nm)
		nStk.Color = Color3.new(0, 0, 0); nStk.Thickness = 1.2
		nStk.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

		-- Rarity label
		local rl = Instance.new("TextLabel")
		rl.Size = UDim2.new(1, -6, 0, 18)
		rl.Position = UDim2.new(0.5, 0, 1, -28)
		rl.AnchorPoint = Vector2.new(0.5, 0)
		rl.BackgroundTransparency = 1
		rl.Text = item.rarity:upper()
		rl.TextColor3 = rColor
		rl.Font = FONT; rl.TextSize = 11; rl.ZIndex = 23
		rl.Parent = card
	end

	-- Center selector line
	local sel = Instance.new("Frame")
	sel.Size = UDim2.new(0, 3, 1, 10)
	sel.Position = UDim2.new(0.5, 0, 0.5, 0)
	sel.AnchorPoint = Vector2.new(0.5, 0.5)
	sel.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
	sel.BorderSizePixel = 0; sel.ZIndex = 25; sel.Parent = stripWin
	Instance.new("UIStroke", sel).Color = Color3.fromRGB(255, 100, 100)

	-- Top arrow
	local topArrow = Instance.new("TextLabel")
	topArrow.Size = UDim2.new(0, 30, 0, 22)
	topArrow.Position = UDim2.new(0.5, 0, 0, 0)
	topArrow.AnchorPoint = Vector2.new(0.5, 0)
	topArrow.BackgroundTransparency = 1; topArrow.Text = "\u{25BC}"
	topArrow.TextColor3 = Color3.fromRGB(255, 60, 60)
	topArrow.Font = Enum.Font.GothamBold; topArrow.TextSize = 20
	topArrow.ZIndex = 25; topArrow.Parent = stripWin

	-- Bottom arrow
	local botArrow = Instance.new("TextLabel")
	botArrow.Size = UDim2.new(0, 30, 0, 22)
	botArrow.Position = UDim2.new(0.5, 0, 1, 0)
	botArrow.AnchorPoint = Vector2.new(0.5, 1)
	botArrow.BackgroundTransparency = 1; botArrow.Text = "\u{25B2}"
	botArrow.TextColor3 = Color3.fromRGB(255, 60, 60)
	botArrow.Font = Enum.Font.GothamBold; botArrow.TextSize = 20
	botArrow.ZIndex = 25; botArrow.Parent = stripWin

	-- Dark edge fades (cinematic)
	for _, side in ipairs({"Left", "Right"}) do
		local fade = Instance.new("Frame")
		fade.Size = UDim2.new(0, 90, 1, 0)
		fade.Position = side == "Left" and UDim2.new(0, 0, 0, 0) or UDim2.new(1, -90, 0, 0)
		fade.BackgroundColor3 = Color3.fromRGB(10, 10, 22)
		fade.BorderSizePixel = 0; fade.ZIndex = 24; fade.Parent = stripWin
		local ug = Instance.new("UIGradient", fade)
		ug.Transparency = side == "Left"
			and NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1)})
			or  NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0)})
	end

	-- Skip button
	caseSkipRequested = false
	local skipBtn = Instance.new("TextButton")
	skipBtn.Size = UDim2.new(0, 100, 0, 34)
	skipBtn.Position = UDim2.new(0.5, 0, 0.42, (CARD_H + 24) / 2 + 22)
	skipBtn.AnchorPoint = Vector2.new(0.5, 0)
	skipBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
	skipBtn.Text = "SKIP"; skipBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
	skipBtn.Font = FONT; skipBtn.TextSize = 15
	skipBtn.BorderSizePixel = 0; skipBtn.ZIndex = 25
	skipBtn.Parent = overlay
	Instance.new("UICorner", skipBtn).CornerRadius = UDim.new(0, 10)
	skipBtn.MouseButton1Click:Connect(function() caseSkipRequested = true end)

	caseAnimOverlay = overlay

	-- Animation positions
	local frameWidth = stripWin.AbsoluteSize.X
	if frameWidth == 0 then frameWidth = 700 end
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

		-- Glow on winning card
		local winCard = strip:FindFirstChild("C" .. winIdx)
		if winCard then
			local rInfo = Rarities.ByName[winItem.rarity]
			local glowC = rInfo and rInfo.color or Color3.new(1, 1, 1)
			local glow = Instance.new("UIStroke")
			glow.Name = "WinGlow"
			glow.Color = glowC; glow.Thickness = 0; glow.Parent = winCard
			TweenService:Create(glow, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Thickness = 5 }):Play()
		end

		-- Flash for Epic+ items
		local rarityRank = ({ Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5 })[resultData.rarity or "Common"] or 1
		if rarityRank >= 3 then
			local flash = Instance.new("Frame")
			flash.Size = UDim2.new(1, 0, 1, 0)
			flash.BackgroundColor3 = Rarities.ByName[resultData.rarity] and Rarities.ByName[resultData.rarity].color or Color3.new(1, 1, 1)
			flash.BackgroundTransparency = 0.5; flash.ZIndex = 28; flash.Parent = overlay
			TweenService:Create(flash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
			task.delay(0.5, function() if flash.Parent then flash:Destroy() end end)
		end

		-- Camera shake for Legendary/Mythic
		if rarityRank >= 4 then
			UIHelper.CameraShake(rarityRank * 0.15, 0.4)
		end

		task.wait(0.6)

		-- Result popup
		local rInfo2 = Rarities.ByName[resultData.rarity or "Common"]
		local rColor2 = rInfo2 and rInfo2.color or Color3.new(1, 1, 1)
		local effInfo2 = resultData.effect and Effects.ByName[resultData.effect]
		local displayColor = effInfo2 and effInfo2.color or rColor2

		local popup = Instance.new("Frame")
		popup.Size = UDim2.new(0.65, 0, 0, 120)
		popup.Position = UDim2.new(0.5, 0, 0.73, 0)
		popup.AnchorPoint = Vector2.new(0.5, 0.5)
		popup.BackgroundColor3 = Color3.fromRGB(20, 20, 38)
		popup.BorderSizePixel = 0; popup.ZIndex = 26; popup.Parent = overlay
		Instance.new("UICorner", popup).CornerRadius = UDim.new(0, 18)
		local pStk = Instance.new("UIStroke", popup)
		pStk.Color = displayColor; pStk.Thickness = 3

		local displayName = resultData.displayName or "???"
		local fullText = "\u{2728} You got: " .. displayName .. "! \u{2728}\n" .. (resultData.rarity or ""):upper()
		if effInfo2 then
			fullText = fullText .. "\n" .. effInfo2.prefix:upper() .. " EFFECT (x" .. effInfo2.cashMultiplier .. " cash)"
		end

		local ppL = Instance.new("TextLabel")
		ppL.Size = UDim2.new(1, -28, 1, 0)
		ppL.Position = UDim2.new(0.5, 0, 0.5, 0)
		ppL.AnchorPoint = Vector2.new(0.5, 0.5)
		ppL.BackgroundTransparency = 1
		ppL.Text = fullText
		ppL.TextColor3 = displayColor
		ppL.Font = FONT; ppL.TextSize = 22; ppL.TextWrapped = true
		ppL.ZIndex = 27; ppL.Parent = popup
		local ppStk = Instance.new("UIStroke", ppL)
		ppStk.Color = Color3.new(0, 0, 0); ppStk.Thickness = 2
		ppStk.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

		UIHelper.ScaleIn(popup, 0.3)

		-- Auto-dismiss after delay (shorter if auto-open is active)
		local dismissDelay = autoOpenEnabled and 1.5 or 3
		task.delay(dismissDelay, function()
			if overlay and overlay.Parent then
				TweenService:Create(overlay, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
				task.delay(0.3, function()
					cleanupCaseAnim()
					-- Auto-open: fire next case if toggle is on and player can afford it
					if autoOpenEnabled and autoOpenCaseId and isOpen then
						local autoCaseData = GemCases.ById[autoOpenCaseId]
						if autoCaseData then
							local gems = HUDController.Data.gems or 0
							if gems >= autoCaseData.cost then
								BuyGemCase:FireServer(autoOpenCaseId)
							else
								autoOpenEnabled = false
								autoOpenCaseId = nil
								if activeTabId then
									local cd = GemCases.ById[activeTabId]
									if cd then buildCaseContent(cd) end
								end
							end
						end
					end
				end)
			end
		end)
	end

	-- Animate!
	caseAnimConn = RunService.RenderStepped:Connect(function()
		if caseSkipRequested and not done then
			done = true
			caseAnimConn:Disconnect(); caseAnimConn = nil
			local tw = TweenService:Create(strip, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(0, endX, 0, 0)
			})
			tw:Play()
			tw.Completed:Connect(function() task.spawn(finishAnim) end)
			return
		end

		local t = (tick() - startTime) / DURATION
		if t >= 1 then t = 1 end
		local eased = easeOutQuint(t)
		strip.Position = UDim2.new(0, startX - totalDist * eased, 0, 0)

		if t >= 1 and not done then
			done = true
			caseAnimConn:Disconnect(); caseAnimConn = nil
			task.spawn(finishAnim)
		end
	end)
end

-------------------------------------------------
-- SIDEBAR HIGHLIGHT
-------------------------------------------------
local function highlightSidebar(tabId)
	activeTabId = tabId
	for _, info in ipairs(sidebarBtns) do
		local isActive = info.id == tabId
		info.btn.BackgroundColor3 = isActive and Color3.fromRGB(50, 50, 80) or Color3.fromRGB(22, 22, 38)
		local lbl = info.btn:FindFirstChild("TabLabel")
		if lbl then lbl.TextSize = isActive and 16 or 14 end
	end
end

-------------------------------------------------
-- OPEN / CLOSE
-------------------------------------------------

function GemShopController.Open()
	if isOpen then GemShopController.Close(); return end
	isOpen = true
	if modalFrame then
		modalFrame.Visible = true
		-- default to first tab
		if sidebarBtns[1] then
			highlightSidebar(sidebarBtns[1].id)
			buildCaseContent(GemCases.ById[sidebarBtns[1].id])
		end
		UIHelper.ScaleIn(modalFrame, 0.25)
	end
end

function GemShopController.Close()
	if not isOpen then return end
	isOpen = false
	autoOpenEnabled = false
	autoOpenCaseId = nil
	closeDropRatePopup()
	cleanupCaseAnim()
	stopViewports()
	if modalFrame then UIHelper.ScaleOut(modalFrame, 0.2) end
end

-------------------------------------------------
-- INIT
-------------------------------------------------

function GemShopController.Init()
	screenGui = UIHelper.CreateScreenGui("GemShopGui", 10)
	screenGui.Parent = playerGui

	modalFrame = Instance.new("Frame")
	modalFrame.Name = "GemShopModal"
	modalFrame.Size = UDim2.new(0, 880, 0, 640)
	modalFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	modalFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	modalFrame.BackgroundColor3 = Color3.fromRGB(14, 12, 28)
	modalFrame.BorderSizePixel = 0
	modalFrame.Visible = false
	modalFrame.ClipsDescendants = true
	modalFrame.Parent = screenGui
	local mCorner = Instance.new("UICorner"); mCorner.CornerRadius = UDim.new(0, 24); mCorner.Parent = modalFrame
	local mStroke = Instance.new("UIStroke"); mStroke.Color = Color3.fromRGB(100, 200, 255); mStroke.Thickness = 3; mStroke.Transparency = 0.15; mStroke.Parent = modalFrame
	UIHelper.CreateShadow(modalFrame)
	UIHelper.MakeResponsiveModal(modalFrame, 880, 640)

	-- Top bar gradient
	local topBar = Instance.new("Frame")
	topBar.Size = UDim2.new(1, 0, 0, 8)
	topBar.BackgroundColor3 = Color3.new(1,1,1)
	topBar.BorderSizePixel = 0; topBar.ZIndex = 5
	topBar.Parent = modalFrame
	local tbG = Instance.new("UIGradient")
	tbG.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 180, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(200, 230, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 180, 255)),
	}); tbG.Parent = topBar

	-- Title
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -100, 0, 48)
	title.Position = UDim2.new(0.5, 0, 0, 10)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.BackgroundTransparency = 1
	title.Text = "\u{1F48E} GEM SHOP \u{1F48E}"
	title.TextColor3 = Color3.fromRGB(100, 200, 255)
	title.Font = FONT; title.TextSize = 32
	title.Parent = modalFrame
	local tStroke = Instance.new("UIStroke")
	tStroke.Color = Color3.fromRGB(0,0,80); tStroke.Thickness = 2.5
	tStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	tStroke.Parent = title

	-- Gem balance
	balanceLabel = Instance.new("TextLabel")
	balanceLabel.Name = "Balance"
	balanceLabel.Size = UDim2.new(1, -20, 0, 24)
	balanceLabel.Position = UDim2.new(0.5, 0, 0, 58)
	balanceLabel.AnchorPoint = Vector2.new(0.5, 0)
	balanceLabel.BackgroundTransparency = 1
	balanceLabel.Text = "\u{1F48E} " .. formatNumber(HUDController.Data.gems or 0) .. " Gems"
	balanceLabel.TextColor3 = Color3.fromRGB(150, 210, 255)
	balanceLabel.Font = FONT; balanceLabel.TextSize = 18
	balanceLabel.Parent = modalFrame

	-- Close
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 48, 0, 48)
	closeBtn.Position = UDim2.new(1, -14, 0, 10)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
	closeBtn.Text = "X"; closeBtn.TextColor3 = Color3.new(1,1,1)
	closeBtn.Font = FONT; closeBtn.TextSize = 24
	closeBtn.BorderSizePixel = 0; closeBtn.ZIndex = 10
	closeBtn.Parent = modalFrame
	local ccC = Instance.new("UICorner"); ccC.CornerRadius = UDim.new(1,0); ccC.Parent = closeBtn
	closeBtn.MouseButton1Click:Connect(function() GemShopController.Close() end)

	-------------------------------------------------
	-- SIDEBAR (left, scrollable list of all cases)
	-------------------------------------------------
	local sidebarWidth = 200
	local sidebar = Instance.new("ScrollingFrame")
	sidebar.Name = "Sidebar"
	sidebar.Size = UDim2.new(0, sidebarWidth, 1, -88)
	sidebar.Position = UDim2.new(0, 0, 0, 88)
	sidebar.BackgroundColor3 = Color3.fromRGB(16, 14, 30)
	sidebar.BackgroundTransparency = 0.3
	sidebar.BorderSizePixel = 0
	sidebar.ScrollBarThickness = 3
	sidebar.ScrollBarImageColor3 = Color3.fromRGB(100, 180, 255)
	sidebar.CanvasSize = UDim2.new(0, 0, 0, 0)
	sidebar.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sidebar.Parent = modalFrame

	local sbLayout = Instance.new("UIListLayout")
	sbLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sbLayout.Padding = UDim.new(0, 5)
	sbLayout.Parent = sidebar

	local sbPad = Instance.new("UIPadding")
	sbPad.PaddingTop = UDim.new(0, 6)
	sbPad.PaddingLeft = UDim.new(0, 6)
	sbPad.PaddingRight = UDim.new(0, 6)
	sbPad.Parent = sidebar

	-- Build sidebar tabs
	local tabOrder = 0
	local function addSidebarTab(caseData, emoji)
		tabOrder = tabOrder + 1
		local btn = Instance.new("TextButton")
		btn.Name = "Tab_" .. caseData.id
		btn.Size = UDim2.new(1, 0, 0, 44)
		btn.BackgroundColor3 = Color3.fromRGB(22, 22, 38)
		btn.BorderSizePixel = 0
		btn.LayoutOrder = tabOrder
		btn.Text = "" -- no default "Button" text
		btn.Parent = sidebar
		local bCorner = Instance.new("UICorner"); bCorner.CornerRadius = UDim.new(0, 10); bCorner.Parent = btn

		-- Color strip
		local strip = Instance.new("Frame")
		strip.Size = UDim2.new(0, 6, 0.7, 0)
		strip.Position = UDim2.new(0, 4, 0.15, 0)
		strip.BackgroundColor3 = caseData.color
		strip.BorderSizePixel = 0
		strip.Parent = btn
		local sC = Instance.new("UICorner"); sC.CornerRadius = UDim.new(0, 2); sC.Parent = strip

		local lbl = Instance.new("TextLabel")
		lbl.Name = "TabLabel"
		lbl.Size = UDim2.new(1, -18, 1, 0)
		lbl.Position = UDim2.new(0, 16, 0, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = (emoji or "") .. " " .. caseData.name
		lbl.TextColor3 = caseData.color
		lbl.Font = FONT; lbl.TextSize = 14
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.TextTruncate = Enum.TextTruncate.AtEnd
		lbl.Parent = btn

		btn.MouseButton1Click:Connect(function()
			stopViewports()
			highlightSidebar(caseData.id)
			buildCaseContent(caseData)
		end)

		table.insert(sidebarBtns, { id = caseData.id, btn = btn })
	end

	-- Section label helper
	local function addSectionLabel(text, order)
		tabOrder = tabOrder + 1
		local lbl = Instance.new("TextLabel")
		lbl.Name = "Section_" .. text
		lbl.Size = UDim2.new(1, 0, 0, 28)
		lbl.BackgroundTransparency = 1
		lbl.Text = text
		lbl.TextColor3 = Color3.fromRGB(100, 100, 130)
		lbl.Font = FONT; lbl.TextSize = 12
		lbl.LayoutOrder = tabOrder
		lbl.Parent = sidebar
	end

	-- Add regular cases
	addSectionLabel("— CASES —")
	for _, rc in ipairs(GemCases.RegularCases) do
		addSidebarTab(rc, "\u{1F4E6}")
	end

	-- Add effect cases
	addSectionLabel("— EFFECT CASES —")
	for _, ec in ipairs(GemCases.EffectCases) do
		addSidebarTab(ec, "\u{2728}")
	end

	-- Add special cases
	addSectionLabel("— SPECIAL —")
	for _, sc in ipairs(GemCases.SpecialCases) do
		local emoji = "\u{1F3B0}"
		if sc.id == "QueensCase" then emoji = "\u{1F451}"
		elseif sc.id == "LuckySevenCase" then emoji = "\u{1F340}"
		elseif sc.id == "FiftyFiftyCase" then emoji = "\u{1F3B2}"
		elseif sc.id == "MythicOrBustCase" then emoji = "\u{1F525}"
		elseif sc.id == "WRizzCase" then emoji = "\u{1F60E}"
		elseif sc.id == "OGCase" then emoji = "\u{1F3AE}"
		end
		addSidebarTab(sc, emoji)
	end

	-------------------------------------------------
	-- CONTENT AREA (right side)
	-------------------------------------------------
	contentFrame = Instance.new("ScrollingFrame")
	contentFrame.Name = "Content"
	contentFrame.Size = UDim2.new(1, -sidebarWidth - 14, 1, -88)
	contentFrame.Position = UDim2.new(0, sidebarWidth + 8, 0, 88)
	contentFrame.BackgroundTransparency = 1
	contentFrame.BorderSizePixel = 0
	contentFrame.ScrollBarThickness = 6
	contentFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 180, 255)
	contentFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	contentFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	contentFrame.Parent = modalFrame

	local cLayout = Instance.new("UIListLayout")
	cLayout.SortOrder = Enum.SortOrder.LayoutOrder
	cLayout.Padding = UDim.new(0, 12)
	cLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	cLayout.Parent = contentFrame

	local cPad = Instance.new("UIPadding")
	cPad.PaddingTop = UDim.new(0, 10)
	cPad.PaddingBottom = UDim.new(0, 10)
	cPad.Parent = contentFrame

	-------------------------------------------------
	-- EVENTS
	-------------------------------------------------
	HUDController.OnDataUpdated(function()
		if balanceLabel then
			balanceLabel.Text = "\u{1F48E} " .. formatNumber(HUDController.Data.gems or 0) .. " Gems"
		end
	end)

	GemCaseResult.OnClientEvent:Connect(function(result)
		if not isOpen then return end
		if result.success then
			-- Play case opening animation!
			local caseData2 = result.caseId and GemCases.ById[result.caseId]
			if caseData2 then
				showCaseOpenAnimation(caseData2, result)
			end
		else
			-- Disable auto-open on failure
			if autoOpenEnabled then
				autoOpenEnabled = false
				autoOpenCaseId = nil
				if activeTabId then
					local cd = GemCases.ById[activeTabId]
					if cd then buildCaseContent(cd) end
				end
			end
			local toast = Instance.new("Frame")
			toast.Size = UDim2.new(0.6, 0, 0, 48)
			toast.Position = UDim2.new(0.5, 0, 0.9, 0)
			toast.AnchorPoint = Vector2.new(0.5, 0.5)
			toast.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
			toast.BorderSizePixel = 0; toast.ZIndex = 25
			toast.Parent = modalFrame
			local tC = Instance.new("UICorner"); tC.CornerRadius = UDim.new(0, 12); tC.Parent = toast
			local tL = Instance.new("TextLabel")
			tL.Size = UDim2.new(1, -16, 1, 0)
			tL.Position = UDim2.new(0.5, 0, 0.5, 0)
			tL.AnchorPoint = Vector2.new(0.5, 0.5)
			tL.BackgroundTransparency = 1
			tL.Text = result.reason or "Error!"
			tL.TextColor3 = Color3.new(1,1,1)
			tL.Font = FONT; tL.TextSize = 16; tL.ZIndex = 26
			tL.Parent = toast
			task.delay(2, function() if toast.Parent then toast:Destroy() end end)
		end
	end)

	OpenGemShopGui.OnClientEvent:Connect(function()
		if isOpen then GemShopController.Close() else GemShopController.Open() end
	end)

	modalFrame.Visible = false
end

return GemShopController
