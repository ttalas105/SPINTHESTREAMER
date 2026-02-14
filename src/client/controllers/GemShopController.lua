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
	popup.Size = UDim2.new(0, 500, 0, 420)
	popup.Position = UDim2.new(0.5, 0, 0.5, 0)
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.BackgroundColor3 = Color3.fromRGB(12, 10, 25)
	popup.BorderSizePixel = 0
	popup.ZIndex = 30
	popup.ClipsDescendants = true
	popup.Parent = modalFrame
	local pCorner = Instance.new("UICorner")
	pCorner.CornerRadius = UDim.new(0, 16)
	pCorner.Parent = popup
	local pStroke = Instance.new("UIStroke")
	pStroke.Color = caseData.color
	pStroke.Thickness = 3
	pStroke.Parent = popup

	-- Title
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -60, 0, 32)
	title.Position = UDim2.new(0.5, 0, 0, 8)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.BackgroundTransparency = 1
	title.Text = caseData.name .. " — Drop Rates"
	title.TextColor3 = caseData.color
	title.Font = FONT; title.TextSize = 20
	title.Parent = popup
	local tS = Instance.new("UIStroke")
	tS.Color = Color3.fromRGB(0,0,0); tS.Thickness = 2
	tS.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	tS.Parent = title

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 34, 0, 34)
	closeBtn.Position = UDim2.new(1, -8, 0, 6)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	closeBtn.Text = "\u{2715}"; closeBtn.TextColor3 = Color3.new(1,1,1)
	closeBtn.Font = FONT; closeBtn.TextSize = 16
	closeBtn.BorderSizePixel = 0; closeBtn.ZIndex = 32
	closeBtn.Parent = popup
	local cbC = Instance.new("UICorner"); cbC.CornerRadius = UDim.new(1,0); cbC.Parent = closeBtn
	closeBtn.MouseButton1Click:Connect(closeDropRatePopup)

	-- Scroll area
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -10, 1, -48)
	scroll.Position = UDim2.new(0, 5, 0, 44)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = caseData.color
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ZIndex = 31
	scroll.Parent = popup

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = scroll

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingLeft = UDim.new(0, 4)
	pad.PaddingRight = UDim.new(0, 4)
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
		row.Size = UDim2.new(1, 0, 0, 52)
		row.BackgroundColor3 = Color3.fromRGB(22, 22, 40)
		row.BorderSizePixel = 0
		row.LayoutOrder = idx
		row.ZIndex = 31
		row.Parent = scroll
		local rCorner = Instance.new("UICorner")
		rCorner.CornerRadius = UDim.new(0, 8)
		rCorner.Parent = row

		-- Spinning model
		local vp = addSpinningViewport(row, item.streamerId, 44, 44, 0.8)
		vp.Position = UDim2.new(0, 4, 0.5, 0)
		vp.AnchorPoint = Vector2.new(0, 0.5)
		vp.ZIndex = 32

		-- Name
		local nm = Instance.new("TextLabel")
		nm.Size = UDim2.new(0, 180, 0, 20)
		nm.Position = UDim2.new(0, 54, 0, 6)
		nm.BackgroundTransparency = 1
		nm.Text = item.displayName
		nm.TextColor3 = rarColor
		nm.Font = FONT; nm.TextSize = 12
		nm.TextXAlignment = Enum.TextXAlignment.Left
		nm.TextTruncate = Enum.TextTruncate.AtEnd
		nm.ZIndex = 32
		nm.Parent = row

		-- Rarity
		local rar = Instance.new("TextLabel")
		rar.Size = UDim2.new(0, 180, 0, 14)
		rar.Position = UDim2.new(0, 54, 0, 28)
		rar.BackgroundTransparency = 1
		rar.Text = item.rarity:upper()
		rar.TextColor3 = rarColor
		rar.Font = FONT; rar.TextSize = 9
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
		pct.Size = UDim2.new(0, 100, 1, 0)
		pct.Position = UDim2.new(1, -8, 0, 0)
		pct.AnchorPoint = Vector2.new(1, 0)
		pct.BackgroundTransparency = 1
		pct.Text = pctText
		pct.TextColor3 = Color3.fromRGB(255, 255, 100)
		pct.Font = FONT; pct.TextSize = 16
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
	header.Size = UDim2.new(1, -10, 0, 80)
	header.BackgroundColor3 = Color3.fromRGB(22, 22, 40)
	header.BorderSizePixel = 0
	header.Parent = contentFrame
	local hCorner = Instance.new("UICorner")
	hCorner.CornerRadius = UDim.new(0, 14)
	hCorner.Parent = header
	local hStroke = Instance.new("UIStroke")
	hStroke.Color = caseData.color; hStroke.Thickness = 2.5
	hStroke.Parent = header

	-- Title
	local titleEmoji = isAllIn and "\u{1F3B0}" or "\u{1F48E}"
	local caseTitle = Instance.new("TextLabel")
	caseTitle.Size = UDim2.new(1, -20, 0, 30)
	caseTitle.Position = UDim2.new(0.5, 0, 0, 10)
	caseTitle.AnchorPoint = Vector2.new(0.5, 0)
	caseTitle.BackgroundTransparency = 1
	caseTitle.Text = titleEmoji .. " " .. caseData.name .. " " .. titleEmoji
	caseTitle.TextColor3 = caseData.color
	caseTitle.Font = FONT; caseTitle.TextSize = 22
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
	costLabel.Size = UDim2.new(1, -20, 0, 20)
	costLabel.Position = UDim2.new(0.5, 0, 0, 42)
	costLabel.AnchorPoint = Vector2.new(0.5, 0)
	costLabel.BackgroundTransparency = 1
	costLabel.Text = subtitle
	costLabel.TextColor3 = Color3.fromRGB(180, 200, 230)
	costLabel.Font = FONT; costLabel.TextSize = 11
	costLabel.TextWrapped = true
	costLabel.Parent = header

	-- Items preview (for regular cases or All In — static models)
	if caseData.items and not isEffect then
		local itemsRow = Instance.new("Frame")
		itemsRow.Name = "ItemsRow"
		itemsRow.Size = UDim2.new(1, -10, 0, 120)
		itemsRow.BackgroundTransparency = 1
		itemsRow.Parent = contentFrame

		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.Padding = UDim.new(0, 6)
		rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		rowLayout.Parent = itemsRow

		local itemCount = #caseData.items
		local itemW = math.min(90, math.floor(380 / itemCount) - 8)

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

			local vp = addStaticViewport(card, item.streamerId, itemW - 8, 56)
			vp.Position = UDim2.new(0.5, 0, 0, 4); vp.AnchorPoint = Vector2.new(0.5, 0)

			local nm = Instance.new("TextLabel")
			nm.Size = UDim2.new(1, -4, 0, 14)
			nm.Position = UDim2.new(0.5, 0, 0, 62); nm.AnchorPoint = Vector2.new(0.5, 0)
			nm.BackgroundTransparency = 1
			nm.Text = item.displayName or item.streamerId
			nm.TextColor3 = rColor
			nm.Font = FONT; nm.TextSize = 9; nm.TextTruncate = Enum.TextTruncate.AtEnd
			nm.Parent = card

			local chanceText = item.chance >= 1 and string.format("%.0f%%", item.chance) or string.format("%.1f%%", item.chance)
			local ch = Instance.new("TextLabel")
			ch.Size = UDim2.new(1, -4, 0, 18)
			ch.Position = UDim2.new(0.5, 0, 0, 76); ch.AnchorPoint = Vector2.new(0.5, 0)
			ch.BackgroundTransparency = 1
			ch.Text = chanceText
			ch.TextColor3 = Color3.fromRGB(255, 255, 100)
			ch.Font = FONT; ch.TextSize = 13
			ch.Parent = card

			if sInfo then
				local rr = Instance.new("TextLabel")
				rr.Size = UDim2.new(1, 0, 0, 12)
				rr.Position = UDim2.new(0.5, 0, 0, 96); rr.AnchorPoint = Vector2.new(0.5, 0)
				rr.BackgroundTransparency = 1
				rr.Text = sInfo.rarity:upper()
				rr.TextColor3 = rColor
				rr.Font = FONT; rr.TextSize = 8
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
	local bbCorner = Instance.new("UICorner"); bbCorner.CornerRadius = UDim.new(0, 12); bbCorner.Parent = buyBtn
	local bbStroke = Instance.new("UIStroke"); bbStroke.Color = Color3.fromRGB(40, 120, 200); bbStroke.Thickness = 2.5; bbStroke.Parent = buyBtn

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

	-- VIEW DROP RATE BUTTON
	local drBtn = Instance.new("TextButton")
	drBtn.Name = "DropRateBtn"
	drBtn.Size = UDim2.new(0, 150, 0, 44)
	drBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 80)
	drBtn.Text = "\u{1F4CA} View Drop Rate"
	drBtn.TextColor3 = Color3.fromRGB(200, 200, 230)
	drBtn.Font = FONT; drBtn.TextSize = 13
	drBtn.BorderSizePixel = 0
	drBtn.Parent = btnRow
	local drCorner = Instance.new("UICorner"); drCorner.CornerRadius = UDim.new(0, 12); drCorner.Parent = drBtn
	local drStroke = Instance.new("UIStroke"); drStroke.Color = Color3.fromRGB(80, 80, 120); drStroke.Thickness = 2; drStroke.Parent = drBtn
	drBtn.MouseButton1Click:Connect(function()
		openDropRatePopup(caseData)
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
		if lbl then lbl.TextSize = isActive and 12 or 10 end
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
	closeDropRatePopup()
	stopViewports()
	if modalFrame then modalFrame.Visible = false end
end

-------------------------------------------------
-- INIT
-------------------------------------------------

function GemShopController.Init()
	screenGui = UIHelper.CreateScreenGui("GemShopGui", 10)
	screenGui.Parent = playerGui

	modalFrame = Instance.new("Frame")
	modalFrame.Name = "GemShopModal"
	modalFrame.Size = UDim2.new(0, 600, 0, 440)
	modalFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	modalFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	modalFrame.BackgroundColor3 = Color3.fromRGB(14, 12, 28)
	modalFrame.BorderSizePixel = 0
	modalFrame.Visible = false
	modalFrame.ClipsDescendants = true
	modalFrame.Parent = screenGui
	local mCorner = Instance.new("UICorner"); mCorner.CornerRadius = UDim.new(0, 20); mCorner.Parent = modalFrame
	local mStroke = Instance.new("UIStroke"); mStroke.Color = Color3.fromRGB(100, 200, 255); mStroke.Thickness = 3; mStroke.Parent = modalFrame

	-- Top bar gradient
	local topBar = Instance.new("Frame")
	topBar.Size = UDim2.new(1, 0, 0, 5)
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
	title.Size = UDim2.new(1, -80, 0, 36)
	title.Position = UDim2.new(0.5, 0, 0, 8)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.BackgroundTransparency = 1
	title.Text = "\u{1F48E} GEM SHOP \u{1F48E}"
	title.TextColor3 = Color3.fromRGB(100, 200, 255)
	title.Font = FONT; title.TextSize = 24
	title.Parent = modalFrame
	local tStroke = Instance.new("UIStroke")
	tStroke.Color = Color3.fromRGB(0,0,80); tStroke.Thickness = 2.5
	tStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	tStroke.Parent = title

	-- Gem balance
	balanceLabel = Instance.new("TextLabel")
	balanceLabel.Name = "Balance"
	balanceLabel.Size = UDim2.new(1, -20, 0, 18)
	balanceLabel.Position = UDim2.new(0.5, 0, 0, 42)
	balanceLabel.AnchorPoint = Vector2.new(0.5, 0)
	balanceLabel.BackgroundTransparency = 1
	balanceLabel.Text = "\u{1F48E} " .. formatNumber(HUDController.Data.gems or 0) .. " Gems"
	balanceLabel.TextColor3 = Color3.fromRGB(150, 210, 255)
	balanceLabel.Font = FONT; balanceLabel.TextSize = 13
	balanceLabel.Parent = modalFrame

	-- Close
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 36, 0, 36)
	closeBtn.Position = UDim2.new(1, -10, 0, 8)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
	closeBtn.Text = "\u{2715}"; closeBtn.TextColor3 = Color3.new(1,1,1)
	closeBtn.Font = FONT; closeBtn.TextSize = 18
	closeBtn.BorderSizePixel = 0; closeBtn.ZIndex = 10
	closeBtn.Parent = modalFrame
	local ccC = Instance.new("UICorner"); ccC.CornerRadius = UDim.new(1,0); ccC.Parent = closeBtn
	closeBtn.MouseButton1Click:Connect(function() GemShopController.Close() end)

	-------------------------------------------------
	-- SIDEBAR (left, scrollable list of all cases)
	-------------------------------------------------
	local sidebarWidth = 130
	local sidebar = Instance.new("ScrollingFrame")
	sidebar.Name = "Sidebar"
	sidebar.Size = UDim2.new(0, sidebarWidth, 1, -64)
	sidebar.Position = UDim2.new(0, 0, 0, 64)
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
	sbLayout.Padding = UDim.new(0, 3)
	sbLayout.Parent = sidebar

	local sbPad = Instance.new("UIPadding")
	sbPad.PaddingTop = UDim.new(0, 4)
	sbPad.PaddingLeft = UDim.new(0, 4)
	sbPad.PaddingRight = UDim.new(0, 4)
	sbPad.Parent = sidebar

	-- Build sidebar tabs
	local tabOrder = 0
	local function addSidebarTab(caseData, emoji)
		tabOrder = tabOrder + 1
		local btn = Instance.new("TextButton")
		btn.Name = "Tab_" .. caseData.id
		btn.Size = UDim2.new(1, 0, 0, 32)
		btn.BackgroundColor3 = Color3.fromRGB(22, 22, 38)
		btn.BorderSizePixel = 0
		btn.LayoutOrder = tabOrder
		btn.Text = "" -- no default "Button" text
		btn.Parent = sidebar
		local bCorner = Instance.new("UICorner"); bCorner.CornerRadius = UDim.new(0, 8); bCorner.Parent = btn

		-- Color strip
		local strip = Instance.new("Frame")
		strip.Size = UDim2.new(0, 4, 0.7, 0)
		strip.Position = UDim2.new(0, 3, 0.15, 0)
		strip.BackgroundColor3 = caseData.color
		strip.BorderSizePixel = 0
		strip.Parent = btn
		local sC = Instance.new("UICorner"); sC.CornerRadius = UDim.new(0, 2); sC.Parent = strip

		local lbl = Instance.new("TextLabel")
		lbl.Name = "TabLabel"
		lbl.Size = UDim2.new(1, -14, 1, 0)
		lbl.Position = UDim2.new(0, 12, 0, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = (emoji or "") .. " " .. caseData.name
		lbl.TextColor3 = caseData.color
		lbl.Font = FONT; lbl.TextSize = 10
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
		lbl.Size = UDim2.new(1, 0, 0, 20)
		lbl.BackgroundTransparency = 1
		lbl.Text = text
		lbl.TextColor3 = Color3.fromRGB(100, 100, 130)
		lbl.Font = FONT; lbl.TextSize = 9
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

	-- Add All In
	addSectionLabel("— SPECIAL —")
	addSidebarTab(GemCases.AllInCase, "\u{1F3B0}")

	-------------------------------------------------
	-- CONTENT AREA (right side)
	-------------------------------------------------
	contentFrame = Instance.new("ScrollingFrame")
	contentFrame.Name = "Content"
	contentFrame.Size = UDim2.new(1, -sidebarWidth - 10, 1, -64)
	contentFrame.Position = UDim2.new(0, sidebarWidth + 6, 0, 64)
	contentFrame.BackgroundTransparency = 1
	contentFrame.BorderSizePixel = 0
	contentFrame.ScrollBarThickness = 4
	contentFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 180, 255)
	contentFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	contentFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	contentFrame.Parent = modalFrame

	local cLayout = Instance.new("UIListLayout")
	cLayout.SortOrder = Enum.SortOrder.LayoutOrder
	cLayout.Padding = UDim.new(0, 8)
	cLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	cLayout.Parent = contentFrame

	local cPad = Instance.new("UIPadding")
	cPad.PaddingTop = UDim.new(0, 6)
	cPad.PaddingBottom = UDim.new(0, 6)
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
			local rInfo = Rarities.ByName[result.rarity]
			local rColor = rInfo and rInfo.color or Color3.new(1,1,1)

			local popup = Instance.new("Frame")
			popup.Size = UDim2.new(0.75, 0, 0, 70)
			popup.Position = UDim2.new(0.5, 0, 0.5, 0)
			popup.AnchorPoint = Vector2.new(0.5, 0.5)
			popup.BackgroundColor3 = Color3.fromRGB(25, 25, 45)
			popup.BorderSizePixel = 0; popup.ZIndex = 25
			popup.Parent = modalFrame
			local ppC = Instance.new("UICorner"); ppC.CornerRadius = UDim.new(0, 14); ppC.Parent = popup
			local ppS = Instance.new("UIStroke"); ppS.Color = rColor; ppS.Thickness = 3; ppS.Parent = popup

			local ppL = Instance.new("TextLabel")
			ppL.Size = UDim2.new(1, -20, 1, 0)
			ppL.Position = UDim2.new(0.5, 0, 0.5, 0)
			ppL.AnchorPoint = Vector2.new(0.5, 0.5)
			ppL.BackgroundTransparency = 1
			ppL.Text = "\u{2728} You got: " .. (result.displayName or "???") .. "! \u{2728}\n" .. (result.rarity or ""):upper()
			ppL.TextColor3 = rColor
			ppL.Font = FONT; ppL.TextSize = 17; ppL.TextWrapped = true
			ppL.ZIndex = 26; ppL.Parent = popup

			task.delay(2.5, function()
				if popup.Parent then
					TweenService:Create(popup, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
					TweenService:Create(ppL, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
					TweenService:Create(ppS, TweenInfo.new(0.3), { Transparency = 1 }):Play()
					task.delay(0.3, function() popup:Destroy() end)
				end
			end)
		else
			local toast = Instance.new("Frame")
			toast.Size = UDim2.new(0.6, 0, 0, 32)
			toast.Position = UDim2.new(0.5, 0, 0.9, 0)
			toast.AnchorPoint = Vector2.new(0.5, 0.5)
			toast.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
			toast.BorderSizePixel = 0; toast.ZIndex = 25
			toast.Parent = modalFrame
			local tC = Instance.new("UICorner"); tC.CornerRadius = UDim.new(0, 8); tC.Parent = toast
			local tL = Instance.new("TextLabel")
			tL.Size = UDim2.new(1, -10, 1, 0)
			tL.Position = UDim2.new(0.5, 0, 0.5, 0)
			tL.AnchorPoint = Vector2.new(0.5, 0.5)
			tL.BackgroundTransparency = 1
			tL.Text = result.reason or "Error!"
			tL.TextColor3 = Color3.new(1,1,1)
			tL.Font = FONT; tL.TextSize = 12; tL.ZIndex = 26
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
