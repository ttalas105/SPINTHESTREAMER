--[[
	SellStandController.lua
	Kid-friendly sell UI with 3D streamer model previews, vibrant cards,
	effect badges, and bubbly design. Walk up to the Sell stall and press E.
	Items sorted by sell price (highest first).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local Streamers = require(ReplicatedStorage.Shared.Config.Streamers)
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

local screenGui
local modalFrame
local isOpen = false
local scrollFrame
local sellAllBtn
local totalLabel
local emptyLabel
local countLabel

local FONT = Enum.Font.FredokaOne

-- Active viewport rotation connections (cleaned up on rebuild)
local viewportConns = {}

-- Track inventory snapshot to avoid unnecessary rebuilds that reset viewports
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
	local price = info.cashPerSecond or 0
	if effect then
		local effectInfo = Effects.ByName[effect]
		if effectInfo and effectInfo.cashMultiplier then
			price = price * effectInfo.cashMultiplier
		end
	end
	return math.floor(price)
end

local function formatNumber(n)
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
	return "1/" .. formatNumber(odds)
end

-- Build a fingerprint string of the inventory for change detection
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

-------------------------------------------------
-- CLEANUP VIEWPORT CONNECTIONS
-------------------------------------------------
local function cleanViewportConns()
	for _, conn in ipairs(viewportConns) do
		pcall(function() conn:Disconnect() end)
	end
	viewportConns = {}
end

-------------------------------------------------
-- BUILD CARD FOR ONE ITEM
-- originalIndex = the real index in the server inventory (for sell requests)
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

	-- Card
	local card = Instance.new("Frame")
	card.Name = "Card_" .. originalIndex
	card.Size = UDim2.new(1, -12, 0, 100)
	card.BackgroundColor3 = Color3.fromRGB(22, 22, 38)
	card.BorderSizePixel = 0
	card.Parent = parent

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 14)
	cardCorner.Parent = card

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = displayColor
	cardStroke.Thickness = 2
	cardStroke.Transparency = 0.4
	cardStroke.Parent = card

	-- Left: 3D model viewport
	local modelsFolder = ReplicatedStorage:FindFirstChild("StreamerModels")
	local modelTemplate = modelsFolder and modelsFolder:FindFirstChild(streamerId)

	local vpSize = 80
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "ModelVP"
	viewport.Size = UDim2.new(0, vpSize, 0, vpSize)
	viewport.Position = UDim2.new(0, 10, 0.5, 0)
	viewport.AnchorPoint = Vector2.new(0, 0.5)
	viewport.BackgroundColor3 = Color3.fromRGB(15, 15, 28)
	viewport.BackgroundTransparency = 0.3
	viewport.BorderSizePixel = 0
	viewport.Parent = card
	local vpCorner = Instance.new("UICorner")
	vpCorner.CornerRadius = UDim.new(0, 10)
	vpCorner.Parent = viewport
	local vpStroke = Instance.new("UIStroke")
	vpStroke.Color = displayColor
	vpStroke.Thickness = 1.5
	vpStroke.Transparency = 0.5
	vpStroke.Parent = viewport

	if modelTemplate then
		local vpModel = modelTemplate:Clone()
		vpModel.Parent = viewport

		local vpCamera = Instance.new("Camera")
		vpCamera.Parent = viewport
		viewport.CurrentCamera = vpCamera

		local ok, cf, size = pcall(function()
			return vpModel:GetBoundingBox()
		end)
		if ok and cf and size then
			local maxDim = math.max(size.X, size.Y, size.Z)
			local dist = maxDim * 1.8
			local target = cf.Position
			local camYOffset = size.Y * 0.15
			local angle = { value = 0 }

			vpCamera.CFrame = CFrame.new(
				target + Vector3.new(0, camYOffset, dist),
				target
			)

			-- Continuous rotation using accumulated angle
			local alive = true
			local conn
			conn = RunService.Heartbeat:Connect(function(dt)
				if not alive then
					conn:Disconnect()
					return
				end
				-- Check if viewport still exists in the hierarchy
				if not viewport.Parent or not vpCamera.Parent then
					alive = false
					conn:Disconnect()
					return
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
		placeholder.Text = "\u{1F3AD}"
		placeholder.TextSize = 36
		placeholder.Font = Enum.Font.SourceSans
		placeholder.Parent = viewport
	end

	-- Right side content
	local textX = vpSize + 20

	-- Effect badge
	if effectInfo then
		local badge = Instance.new("Frame")
		badge.Name = "EffectBadge"
		badge.Size = UDim2.new(0, 60, 0, 18)
		badge.Position = UDim2.new(0, textX, 0, 6)
		badge.BackgroundColor3 = effectInfo.color
		badge.BackgroundTransparency = 0.6
		badge.BorderSizePixel = 0
		badge.Parent = card
		local bCorner = Instance.new("UICorner")
		bCorner.CornerRadius = UDim.new(0, 6)
		bCorner.Parent = badge
		local bLabel = Instance.new("TextLabel")
		bLabel.Size = UDim2.new(1, 0, 1, 0)
		bLabel.BackgroundTransparency = 1
		bLabel.Text = effectInfo.prefix:upper()
		bLabel.TextColor3 = effectInfo.color
		bLabel.Font = FONT
		bLabel.TextSize = 11
		bLabel.Parent = badge
		local bStroke = Instance.new("UIStroke")
		bStroke.Color = Color3.fromRGB(0, 0, 0)
		bStroke.Thickness = 1
		bStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		bStroke.Parent = bLabel
	end

	-- Streamer name
	local displayName = info.displayName
	if effectInfo then
		displayName = effectInfo.prefix .. " " .. displayName
	end
	local nameY = effectInfo and 24 or 8
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(0, 200, 0, 24)
	nameLabel.Position = UDim2.new(0, textX, 0, nameY)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = displayName
	nameLabel.TextColor3 = displayColor
	nameLabel.Font = FONT
	nameLabel.TextSize = 16
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = card
	local nStroke = Instance.new("UIStroke")
	nStroke.Color = Color3.fromRGB(0, 0, 0)
	nStroke.Thickness = 1.5
	nStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	nStroke.Parent = nameLabel

	-- Rarity + odds
	local baseOdds = info.odds or 0
	local effectOdds = baseOdds
	if effectInfo then
		effectOdds = math.floor(baseOdds * effectInfo.rarityMult)
	end
	local oddsStr = formatOdds(effectOdds)

	local rarLine = Instance.new("TextLabel")
	rarLine.Name = "RarityLine"
	rarLine.Size = UDim2.new(0, 200, 0, 16)
	rarLine.Position = UDim2.new(0, textX, 0, nameY + 24)
	rarLine.BackgroundTransparency = 1
	rarLine.Text = info.rarity:upper() .. "  \u{2022}  " .. oddsStr
	rarLine.TextColor3 = rarityColor
	rarLine.Font = FONT
	rarLine.TextSize = 12
	rarLine.TextXAlignment = Enum.TextXAlignment.Left
	rarLine.Parent = card

	-- Cash per second
	local cashLine = Instance.new("TextLabel")
	cashLine.Name = "CashLine"
	cashLine.Size = UDim2.new(0, 200, 0, 16)
	cashLine.Position = UDim2.new(0, textX, 0, nameY + 40)
	cashLine.BackgroundTransparency = 1
	cashLine.Text = "\u{1F4B0} $" .. formatNumber(sellPrice) .. "/sec"
	cashLine.TextColor3 = Color3.fromRGB(100, 255, 120)
	cashLine.Font = FONT
	cashLine.TextSize = 12
	cashLine.TextXAlignment = Enum.TextXAlignment.Left
	cashLine.Parent = card

	-- Sell price (big green)
	local priceLabel = Instance.new("TextLabel")
	priceLabel.Name = "Price"
	priceLabel.Size = UDim2.new(0, 90, 0, 22)
	priceLabel.Position = UDim2.new(1, -110, 0, 16)
	priceLabel.BackgroundTransparency = 1
	priceLabel.Text = "$" .. formatNumber(sellPrice)
	priceLabel.TextColor3 = Color3.fromRGB(80, 255, 100)
	priceLabel.Font = FONT
	priceLabel.TextSize = 18
	priceLabel.TextXAlignment = Enum.TextXAlignment.Right
	priceLabel.Parent = card
	local pStroke = Instance.new("UIStroke")
	pStroke.Color = Color3.fromRGB(0, 0, 0)
	pStroke.Thickness = 1.5
	pStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	pStroke.Parent = priceLabel

	-- Sell button
	local sellBtn = Instance.new("TextButton")
	sellBtn.Name = "SellBtn"
	sellBtn.Size = UDim2.new(0, 70, 0, 34)
	sellBtn.Position = UDim2.new(1, -80, 1, -14)
	sellBtn.AnchorPoint = Vector2.new(0.5, 1)
	sellBtn.BackgroundColor3 = Color3.fromRGB(230, 55, 55)
	sellBtn.Text = "SELL"
	sellBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	sellBtn.Font = FONT
	sellBtn.TextSize = 16
	sellBtn.BorderSizePixel = 0
	sellBtn.Parent = card
	local sbCorner = Instance.new("UICorner")
	sbCorner.CornerRadius = UDim.new(0, 10)
	sbCorner.Parent = sellBtn
	local sbStroke = Instance.new("UIStroke")
	sbStroke.Color = Color3.fromRGB(160, 30, 30)
	sbStroke.Thickness = 2
	sbStroke.Parent = sellBtn

	sellBtn.MouseEnter:Connect(function()
		TweenService:Create(sellBtn, TweenInfo.new(0.12), {
			BackgroundColor3 = Color3.fromRGB(255, 80, 80),
		}):Play()
	end)
	sellBtn.MouseLeave:Connect(function()
		TweenService:Create(sellBtn, TweenInfo.new(0.12), {
			BackgroundColor3 = Color3.fromRGB(230, 55, 55),
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
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

-- Force a full rebuild (clears viewport connections and recreates everything)
local function buildInventoryList(force)
	if not scrollFrame then return end

	local inventory = HUDController.Data.inventory or {}
	local snapshot = buildInventorySnapshot(inventory)

	-- Skip rebuild if nothing changed (keeps viewports spinning)
	if not force and snapshot == lastInventorySnapshot then return end
	lastInventorySnapshot = snapshot

	clearScrollFrame()

	local totalValue = 0

	if #inventory == 0 then
		if emptyLabel then emptyLabel.Visible = true end
		if sellAllBtn then sellAllBtn.Visible = false end
		if totalLabel then totalLabel.Text = "\u{1F4B0} Total: $0" end
		if countLabel then countLabel.Text = "0 streamers" end
		return
	end

	if emptyLabel then emptyLabel.Visible = false end

	-- Build sorted index list (by sell price, highest first)
	local sortedIndices = {}
	for i = 1, #inventory do
		sortedIndices[i] = i
	end
	table.sort(sortedIndices, function(a, b)
		return calcSellPrice(inventory[a]) > calcSellPrice(inventory[b])
	end)

	for _, origIdx in ipairs(sortedIndices) do
		local item = inventory[origIdx]
		local _, price = buildItemCard(item, origIdx, scrollFrame)
		totalValue = totalValue + (price or 0)
	end

	if totalLabel then
		totalLabel.Text = "\u{1F4B0} Total: $" .. formatNumber(totalValue)
	end
	if countLabel then
		countLabel.Text = #inventory .. " streamer" .. (#inventory ~= 1 and "s" or "")
	end
	if sellAllBtn then
		sellAllBtn.Visible = #inventory > 0
		sellAllBtn.Text = "\u{1F4A5} SELL ALL \u{2014} $" .. formatNumber(totalValue)
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
	lastInventorySnapshot = "" -- force rebuild on open (resets viewports)
	if modalFrame then
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
	if modalFrame then UIHelper.ScaleOut(modalFrame, 0.2) end
end

-------------------------------------------------
-- INIT
-------------------------------------------------

function SellStandController.Init()
	screenGui = UIHelper.CreateScreenGui("SellStandGui", 8)
	screenGui.Parent = playerGui

	modalFrame = Instance.new("Frame")
	modalFrame.Name = "SellModal"
	modalFrame.Size = UDim2.new(0, 480, 0, 520)
	modalFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	modalFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	modalFrame.BackgroundColor3 = Color3.fromRGB(16, 14, 30)
	modalFrame.BorderSizePixel = 0
	modalFrame.Visible = false
	modalFrame.Parent = screenGui
	local mCorner = Instance.new("UICorner")
	mCorner.CornerRadius = UDim.new(0, 22)
	mCorner.Parent = modalFrame
	local mStroke = Instance.new("UIStroke")
	mStroke.Color = Color3.fromRGB(230, 60, 60)
	mStroke.Thickness = 3
	mStroke.Transparency = 0.15
	mStroke.Parent = modalFrame
	UIHelper.CreateShadow(modalFrame)

	-- Red gradient top bar
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.Size = UDim2.new(1, 0, 0, 5)
	topBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	topBar.BorderSizePixel = 0
	topBar.ZIndex = 5
	topBar.Parent = modalFrame
	local tbGrad = Instance.new("UIGradient")
	tbGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 200, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 80)),
	})
	tbGrad.Parent = topBar

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -80, 0, 44)
	title.Position = UDim2.new(0.5, 0, 0, 10)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.BackgroundTransparency = 1
	title.Text = "\u{1F3EA} SELL STAND \u{1F3EA}"
	title.TextColor3 = Color3.fromRGB(255, 220, 80)
	title.Font = FONT
	title.TextSize = 28
	title.Parent = modalFrame
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.fromRGB(200, 50, 50)
	titleStroke.Thickness = 3
	titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	titleStroke.Parent = title

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 42, 0, 42)
	closeBtn.Position = UDim2.new(1, -12, 0, 10)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
	closeBtn.Text = "\u{2715}"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Font = FONT
	closeBtn.TextSize = 22
	closeBtn.BorderSizePixel = 0
	closeBtn.ZIndex = 10
	closeBtn.Parent = modalFrame
	local ccCorner = Instance.new("UICorner")
	ccCorner.CornerRadius = UDim.new(1, 0)
	ccCorner.Parent = closeBtn
	local ccStroke = Instance.new("UIStroke")
	ccStroke.Color = Color3.fromRGB(120, 30, 30)
	ccStroke.Thickness = 2
	ccStroke.Parent = closeBtn
	closeBtn.MouseButton1Click:Connect(function()
		SellStandController.Close()
	end)

	-- Total value + count row
	local infoRow = Instance.new("Frame")
	infoRow.Name = "InfoRow"
	infoRow.Size = UDim2.new(1, -30, 0, 26)
	infoRow.Position = UDim2.new(0.5, 0, 0, 56)
	infoRow.AnchorPoint = Vector2.new(0.5, 0)
	infoRow.BackgroundTransparency = 1
	infoRow.Parent = modalFrame

	totalLabel = Instance.new("TextLabel")
	totalLabel.Name = "TotalLabel"
	totalLabel.Size = UDim2.new(0.6, 0, 1, 0)
	totalLabel.Position = UDim2.new(0, 0, 0, 0)
	totalLabel.BackgroundTransparency = 1
	totalLabel.Text = "\u{1F4B0} Total: $0"
	totalLabel.TextColor3 = Color3.fromRGB(100, 255, 120)
	totalLabel.Font = FONT
	totalLabel.TextSize = 17
	totalLabel.TextXAlignment = Enum.TextXAlignment.Left
	totalLabel.Parent = infoRow
	local tlStroke = Instance.new("UIStroke")
	tlStroke.Color = Color3.fromRGB(0, 0, 0)
	tlStroke.Thickness = 1.5
	tlStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	tlStroke.Parent = totalLabel

	countLabel = Instance.new("TextLabel")
	countLabel.Name = "CountLabel"
	countLabel.Size = UDim2.new(0.4, 0, 1, 0)
	countLabel.Position = UDim2.new(0.6, 0, 0, 0)
	countLabel.BackgroundTransparency = 1
	countLabel.Text = "0 streamers"
	countLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
	countLabel.Font = FONT
	countLabel.TextSize = 14
	countLabel.TextXAlignment = Enum.TextXAlignment.Right
	countLabel.Parent = infoRow

	-- Scrolling frame
	scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ItemList"
	scrollFrame.Size = UDim2.new(1, -20, 1, -156)
	scrollFrame.Position = UDim2.new(0.5, 0, 0, 86)
	scrollFrame.AnchorPoint = Vector2.new(0.5, 0)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 6
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(200, 100, 100)
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.None
	scrollFrame.ZIndex = 9
	scrollFrame.Parent = modalFrame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = scrollFrame

	-- Empty state
	emptyLabel = Instance.new("TextLabel")
	emptyLabel.Name = "EmptyLabel"
	emptyLabel.Size = UDim2.new(1, -20, 0, 80)
	emptyLabel.Position = UDim2.new(0.5, 0, 0.3, 0)
	emptyLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.Text = "\u{1F3B0} Your inventory is empty!\nSpin some cases first!"
	emptyLabel.TextColor3 = Color3.fromRGB(140, 140, 160)
	emptyLabel.Font = FONT
	emptyLabel.TextSize = 18
	emptyLabel.TextWrapped = true
	emptyLabel.Visible = false
	emptyLabel.ZIndex = 9
	emptyLabel.Parent = modalFrame

	-- Sell All button
	sellAllBtn = Instance.new("TextButton")
	sellAllBtn.Name = "SellAllBtn"
	sellAllBtn.Size = UDim2.new(1, -30, 0, 50)
	sellAllBtn.Position = UDim2.new(0.5, 0, 1, -14)
	sellAllBtn.AnchorPoint = Vector2.new(0.5, 1)
	sellAllBtn.BackgroundColor3 = Color3.fromRGB(210, 45, 45)
	sellAllBtn.Text = "\u{1F4A5} SELL ALL \u{2014} $0"
	sellAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	sellAllBtn.Font = FONT
	sellAllBtn.TextSize = 20
	sellAllBtn.BorderSizePixel = 0
	sellAllBtn.Visible = false
	sellAllBtn.ZIndex = 10
	sellAllBtn.Parent = modalFrame
	local saCorner = Instance.new("UICorner")
	saCorner.CornerRadius = UDim.new(0, 14)
	saCorner.Parent = sellAllBtn
	local saStroke = Instance.new("UIStroke")
	saStroke.Color = Color3.fromRGB(140, 20, 20)
	saStroke.Thickness = 2.5
	saStroke.Parent = sellAllBtn
	local saGrad = Instance.new("UIGradient")
	saGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(240, 70, 70)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 30, 30)),
	})
	saGrad.Rotation = 90
	saGrad.Parent = sellAllBtn

	sellAllBtn.MouseButton1Click:Connect(function()
		SellAllRequest:FireServer()
	end)
	sellAllBtn.MouseEnter:Connect(function()
		TweenService:Create(sellAllBtn, TweenInfo.new(0.12), {
			Size = UDim2.new(1, -24, 0, 52),
		}):Play()
	end)
	sellAllBtn.MouseLeave:Connect(function()
		TweenService:Create(sellAllBtn, TweenInfo.new(0.12), {
			Size = UDim2.new(1, -30, 0, 50),
		}):Play()
	end)

	-------------------------------------------------
	-- EVENTS
	-------------------------------------------------

	-- Only rebuild if inventory actually changed (avoids destroying viewports on cash ticks)
	HUDController.OnDataUpdated(function()
		if isOpen then buildInventoryList(false) end
	end)

	SellResult.OnClientEvent:Connect(function(data)
		if data.success and isOpen then
			task.wait(0.1)
			lastInventorySnapshot = "" -- force rebuild after selling
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
