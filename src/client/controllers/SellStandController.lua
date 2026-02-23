--[[
	SellStandController.lua
	Sell UI — dark-themed panel matching the Case Shop / Potion Shop style.
	3D streamer model previews with rotating viewports, sorted by sell price.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local Streamers = require(ReplicatedStorage.Shared.Config.Streamers)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Effects = require(ReplicatedStorage.Shared.Config.Effects)
local UIHelper = require(script.Parent.UIHelper)
local HUDController = require(script.Parent.HUDController)

local SellStandController = {}

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

local FONT = Enum.Font.FredokaOne
local FONT_SUB = Enum.Font.GothamBold
local MODAL_BG = Color3.fromRGB(30, 25, 45)
local RED = Color3.fromRGB(220, 55, 55)
local RED_DARK = Color3.fromRGB(160, 30, 30)
local GREEN = Color3.fromRGB(80, 220, 100)
local MODAL_W, MODAL_H = 480, 540

local bounceTween = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local viewportConns = {}
local lastInventorySnapshot = ""

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

local function buildInventorySnapshot(inventory)
	if not inventory or #inventory == 0 then return "" end
	local parts = {}
	for i, item in ipairs(inventory) do
		local id = getItemId(item) or "?"
		local eff = getItemEffect(item) or ""
		parts[i] = id .. ":" .. eff
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

-------------------------------------------------
-- VIEWPORT CLEANUP
-------------------------------------------------

local function cleanViewportConns()
	for _, conn in ipairs(viewportConns) do
		pcall(function() conn:Disconnect() end)
	end
	viewportConns = {}
end

-------------------------------------------------
-- BUILD ITEM CARD
-------------------------------------------------

local function buildItemCard(item, originalIndex, parent)
	local streamerId = getItemId(item)
	local effect = getItemEffect(item)
	local info = Streamers.ById[streamerId]
	if not info then return nil, 0 end

	local effectInfo = effect and Effects.ByName[effect] or nil
	local sellPrice = calcSellPrice(item)
	local rarityInfo = Rarities.ByName[info.rarity]
	local rarityColor = rarityInfo and rarityInfo.color or Color3.fromRGB(170, 170, 170)
	local displayColor = effectInfo and effectInfo.color or rarityColor

	local card = Instance.new("Frame")
	card.Name = "Card_" .. originalIndex
	card.Size = UDim2.new(1, -12, 0, 90)
	card.BackgroundColor3 = Color3.fromRGB(40, 35, 60)
	card.BorderSizePixel = 0
	card.Parent = parent
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = displayColor
	cardStroke.Thickness = 1.5
	cardStroke.Transparency = 0.5
	cardStroke.Parent = card

	-- 3D model viewport (left)
	local vpSize = 70
	local modelsFolder = ReplicatedStorage:FindFirstChild("StreamerModels")
	local modelTemplate = modelsFolder and modelsFolder:FindFirstChild(streamerId)

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "ModelVP"
	viewport.Size = UDim2.new(0, vpSize, 0, vpSize)
	viewport.Position = UDim2.new(0, 10, 0.5, 0)
	viewport.AnchorPoint = Vector2.new(0, 0.5)
	viewport.BackgroundColor3 = Color3.fromRGB(25, 22, 42)
	viewport.BackgroundTransparency = 0.2
	viewport.BorderSizePixel = 0
	viewport.Parent = card
	Instance.new("UICorner", viewport).CornerRadius = UDim.new(0, 10)

	if modelTemplate then
		local vpModel = modelTemplate:Clone()
		vpModel.Parent = viewport
		local vpCamera = Instance.new("Camera")
		vpCamera.Parent = viewport
		viewport.CurrentCamera = vpCamera

		local ok, cf, size = pcall(function() return vpModel:GetBoundingBox() end)
		if ok and cf and size then
			local maxDim = math.max(size.X, size.Y, size.Z)
			local dist = maxDim * 1.8
			local target = cf.Position
			local camYOffset = size.Y * 0.15
			local angle = { value = 0 }

			vpCamera.CFrame = CFrame.new(target + Vector3.new(0, camYOffset, dist), target)

			local alive = true
			local conn
			conn = RunService.Heartbeat:Connect(function(dt)
				if not alive then conn:Disconnect(); return end
				if not viewport.Parent or not vpCamera.Parent then
					alive = false; conn:Disconnect(); return
				end
				angle.value = angle.value + dt * 0.8
				local a = angle.value
				vpCamera.CFrame = CFrame.new(
					target + Vector3.new(math.sin(a) * dist, camYOffset, math.cos(a) * dist),
					target
				)
			end)
			table.insert(viewportConns, conn)
		else
			vpCamera.CFrame = CFrame.new(Vector3.new(0, 2, 5), Vector3.new(0, 1, 0))
		end
	else
		local placeholder = Instance.new("TextLabel")
		placeholder.Size = UDim2.new(1, 0, 1, 0)
		placeholder.BackgroundTransparency = 1
		placeholder.Text = "?"
		placeholder.TextSize = 28
		placeholder.TextColor3 = Color3.fromRGB(100, 100, 120)
		placeholder.Font = FONT
		placeholder.Parent = viewport
	end

	-- Info area (middle)
	local textX = vpSize + 18

	-- Effect badge
	if effectInfo then
		local badge = Instance.new("Frame")
		badge.Size = UDim2.new(0, 56, 0, 16)
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
	local displayName = info.displayName
	if effectInfo then displayName = effectInfo.prefix .. " " .. displayName end
	local nameY = effectInfo and 26 or 12
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(0, 180, 0, 22)
	nameLabel.Position = UDim2.new(0, textX, 0, nameY)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = displayName
	nameLabel.TextColor3 = displayColor
	nameLabel.Font = FONT
	nameLabel.TextSize = 15
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
	rarLine.Size = UDim2.new(0, 180, 0, 14)
	rarLine.Position = UDim2.new(0, textX, 0, nameY + 22)
	rarLine.BackgroundTransparency = 1
	rarLine.Text = info.rarity .. (oddsStr ~= "" and ("  •  " .. oddsStr) or "")
	rarLine.TextColor3 = Color3.fromRGB(140, 135, 160)
	rarLine.Font = FONT_SUB
	rarLine.TextSize = 11
	rarLine.TextXAlignment = Enum.TextXAlignment.Left
	rarLine.Parent = card

	-- $/sec
	local cashLine = Instance.new("TextLabel")
	cashLine.Size = UDim2.new(0, 180, 0, 14)
	cashLine.Position = UDim2.new(0, textX, 0, nameY + 36)
	cashLine.BackgroundTransparency = 1
	cashLine.Text = "$" .. fmtNum(sellPrice)
	cashLine.TextColor3 = Color3.fromRGB(100, 255, 120)
	cashLine.Font = FONT_SUB
	cashLine.TextSize = 11
	cashLine.TextXAlignment = Enum.TextXAlignment.Left
	cashLine.Parent = card

	-- Sell button (right side)
	local sellBtn = Instance.new("TextButton")
	sellBtn.Name = "SellBtn"
	sellBtn.Size = UDim2.new(0, 62, 0, 36)
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
	sellText.TextSize = 14
	sellText.Parent = sellBtn
	addStroke(sellText, Color3.new(0, 0, 0), 1)

	sellBtn.MouseEnter:Connect(function()
		TweenService:Create(sellBtn, bounceTween, {
			Size = UDim2.new(0, 68, 0, 40),
			BackgroundColor3 = Color3.fromRGB(255, 75, 75),
		}):Play()
	end)
	sellBtn.MouseLeave:Connect(function()
		TweenService:Create(sellBtn, bounceTween, {
			Size = UDim2.new(0, 62, 0, 36),
			BackgroundColor3 = RED,
		}):Play()
	end)
	sellBtn.MouseButton1Click:Connect(function()
		SellByIndexRequest:FireServer(originalIndex)
	end)

	return card, sellPrice
end

-------------------------------------------------
-- BUILD INVENTORY LIST
-------------------------------------------------

local function clearScrollFrame()
	if not scrollFrame then return end
	cleanViewportConns()
	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
end

local function buildInventoryList(force)
	if not scrollFrame then return end
	local inventory = HUDController.Data.inventory or {}
	local snapshot = buildInventorySnapshot(inventory)
	if not force and snapshot == lastInventorySnapshot then return end
	lastInventorySnapshot = snapshot

	clearScrollFrame()
	local totalValue = 0

	if #inventory == 0 then
		if emptyLabel then emptyLabel.Visible = true end
		if sellAllBtn then sellAllBtn.Visible = false end
		if totalLabel then totalLabel.Text = "Total: $0" end
		if countLabel then countLabel.Text = "0 streamers" end
		return
	end

	if emptyLabel then emptyLabel.Visible = false end

	local sortedIndices = {}
	for i = 1, #inventory do sortedIndices[i] = i end
	table.sort(sortedIndices, function(a, b)
		return calcSellPrice(inventory[a]) > calcSellPrice(inventory[b])
	end)

	for _, origIdx in ipairs(sortedIndices) do
		local _, price = buildItemCard(inventory[origIdx], origIdx, scrollFrame)
		totalValue = totalValue + (price or 0)
	end

	if totalLabel then totalLabel.Text = "Total: $" .. fmtNum(totalValue) end
	if countLabel then countLabel.Text = #inventory .. " streamer" .. (#inventory ~= 1 and "s" or "") end
	if sellAllBtn then
		sellAllBtn.Visible = #inventory > 0
	end

	local listLayout = scrollFrame:FindFirstChildOfClass("UIListLayout")
	if listLayout then
		scrollFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 10)
	end
end

-------------------------------------------------
-- OPEN / CLOSE
-------------------------------------------------

function SellStandController.Open()
	if isOpen then return end
	isOpen = true
	lastInventorySnapshot = ""
	if modalFrame then
		overlay.Visible = true
		modalFrame.Visible = true
		buildInventoryList(true)
		UIHelper.ScaleIn(modalFrame, 0.25)
	end
end

function SellStandController.Close()
	if not isOpen then return end
	isOpen = false
	lastInventorySnapshot = ""
	cleanViewportConns()
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

	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(0.5, 0, 0, 16)
	subtitle.Position = UDim2.new(0, 22, 0, 42)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "Sell streamers from your inventory"
	subtitle.TextColor3 = Color3.fromRGB(150, 145, 170)
	subtitle.Font = FONT_SUB
	subtitle.TextSize = 11
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.ZIndex = 3
	subtitle.Parent = header

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
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 10)
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
	infoRow.Position = UDim2.new(0.5, 0, 0, 68)
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

	countLabel = Instance.new("TextLabel")
	countLabel.Size = UDim2.new(0.4, 0, 1, 0)
	countLabel.Position = UDim2.new(0.6, 0, 0, 0)
	countLabel.BackgroundTransparency = 1
	countLabel.Text = "0 streamers"
	countLabel.TextColor3 = Color3.fromRGB(150, 145, 170)
	countLabel.Font = FONT_SUB
	countLabel.TextSize = 12
	countLabel.TextXAlignment = Enum.TextXAlignment.Right
	countLabel.ZIndex = 3
	countLabel.Parent = infoRow

	-- ===== SCROLL LIST =====
	scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ItemList"
	scrollFrame.Size = UDim2.new(1, -20, 1, -160)
	scrollFrame.Position = UDim2.new(0.5, 0, 0, 96)
	scrollFrame.AnchorPoint = Vector2.new(0.5, 0)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 5
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 80, 150)
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.None
	scrollFrame.ZIndex = 3
	scrollFrame.Parent = modalFrame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = scrollFrame

	-- Empty state
	emptyLabel = Instance.new("TextLabel")
	emptyLabel.Size = UDim2.new(1, -20, 0, 80)
	emptyLabel.Position = UDim2.new(0.5, 0, 0.3, 0)
	emptyLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.Text = "Your inventory is empty!\nSpin some cases first."
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
		SellAllRequest:FireServer()
	end)

	-------------------------------------------------
	-- EVENTS
	-------------------------------------------------

	HUDController.OnDataUpdated(function()
		if isOpen then buildInventoryList(false) end
	end)

	SellResult.OnClientEvent:Connect(function(data)
		if data.success and isOpen then
			task.wait(0.1)
			lastInventorySnapshot = ""
			buildInventoryList(true)
		end
	end)

	OpenSellStandGui.OnClientEvent:Connect(function()
		if isOpen then
			SellStandController.Close()
		else
			SellStandController.Open()
		end
	end)

	modalFrame.Visible = false
end

return SellStandController
