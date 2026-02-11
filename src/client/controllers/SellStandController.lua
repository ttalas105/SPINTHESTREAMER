--[[
	SellStandController.lua
	Sell stand UI — walk up to the red Sell stall and press E to open.
	Shows all inventory items in a scrollable list with individual sell buttons
	and a "Sell All" button at the bottom. Sell price = cashPerSecond * effect multiplier.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local Streamers = require(ReplicatedStorage.Shared.Config.Streamers)
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
local overlay
local isOpen = false
local scrollFrame
local sellAllBtn
local totalLabel
local emptyLabel

local CARTOON_FONT = Enum.Font.Cartoon

-- Helper: get item info
local function getItemId(item)
	if type(item) == "table" then return item.id end
	if type(item) == "string" then return item end
	return nil
end
local function getItemEffect(item)
	if type(item) == "table" then return item.effect end
	return nil
end

-- Calculate sell price for display (matches server logic)
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

-- Format number with commas
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

-------------------------------------------------
-- BUILD INVENTORY LIST
-------------------------------------------------

local function clearScrollFrame()
	if not scrollFrame then return end
	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function buildInventoryList()
	if not scrollFrame then return end
	clearScrollFrame()

	local inventory = HUDController.Data.inventory or {}
	local totalValue = 0

	if #inventory == 0 then
		if emptyLabel then
			emptyLabel.Visible = true
		end
		if sellAllBtn then
			sellAllBtn.Visible = false
		end
		if totalLabel then
			totalLabel.Text = "Total: $0"
		end
		return
	end

	if emptyLabel then
		emptyLabel.Visible = false
	end

	for idx, item in ipairs(inventory) do
		local streamerId = getItemId(item)
		local effect = getItemEffect(item)
		local info = Streamers.ById[streamerId]
		if not info then continue end

		local effectInfo = effect and Effects.ByName[effect] or nil
		local sellPrice = calcSellPrice(item)
		totalValue = totalValue + sellPrice

		local rarityColor = DesignConfig.RarityColors[info.rarity] or Color3.fromRGB(170, 170, 170)
		local displayColor = effectInfo and effectInfo.color or rarityColor

		-- Row frame
		local row = Instance.new("Frame")
		row.Name = "Row_" .. idx
		row.Size = UDim2.new(1, -8, 0, 52)
		row.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
		row.BorderSizePixel = 0
		row.Parent = scrollFrame

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 8)
		rowCorner.Parent = row

		-- Left color strip (rarity/effect indicator)
		local strip = Instance.new("Frame")
		strip.Name = "Strip"
		strip.Size = UDim2.new(0, 5, 1, -6)
		strip.Position = UDim2.new(0, 3, 0, 3)
		strip.BackgroundColor3 = displayColor
		strip.BorderSizePixel = 0
		strip.Parent = row
		local stripCorner = Instance.new("UICorner")
		stripCorner.CornerRadius = UDim.new(0, 3)
		stripCorner.Parent = strip

		-- Effect badge (if any)
		local nameXOffset = 14
		if effectInfo then
			local badge = Instance.new("TextLabel")
			badge.Name = "EffectBadge"
			badge.Size = UDim2.new(0, 44, 0, 16)
			badge.Position = UDim2.new(0, 14, 0, 4)
			badge.BackgroundColor3 = effectInfo.color
			badge.BackgroundTransparency = 0.7
			badge.Text = effectInfo.prefix:upper()
			badge.TextColor3 = effectInfo.color
			badge.Font = Enum.Font.GothamBold
			badge.TextSize = 10
			badge.TextScaled = false
			badge.BorderSizePixel = 0
			badge.Parent = row
			local badgeCorner = Instance.new("UICorner")
			badgeCorner.CornerRadius = UDim.new(0, 4)
			badgeCorner.Parent = badge
		end

		-- Streamer name
		local displayName = info.displayName
		if effectInfo then
			displayName = effectInfo.prefix .. " " .. displayName
		end
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "Name"
		nameLabel.Size = UDim2.new(0.5, -nameXOffset, 0, 22)
		nameLabel.Position = UDim2.new(0, nameXOffset, 0, effectInfo and 20 or 6)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = displayName
		nameLabel.TextColor3 = displayColor
		nameLabel.Font = CARTOON_FONT
		nameLabel.TextSize = 15
		nameLabel.TextScaled = false
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Parent = row

		-- Rarity label
		local rarityLabel = Instance.new("TextLabel")
		rarityLabel.Name = "Rarity"
		rarityLabel.Size = UDim2.new(0.5, -nameXOffset, 0, 14)
		rarityLabel.Position = UDim2.new(0, nameXOffset, 0, effectInfo and 38 or 30)
		rarityLabel.BackgroundTransparency = 1
		rarityLabel.Text = info.rarity:upper()
		rarityLabel.TextColor3 = rarityColor
		rarityLabel.Font = Enum.Font.Gotham
		rarityLabel.TextSize = 11
		rarityLabel.TextScaled = false
		rarityLabel.TextXAlignment = Enum.TextXAlignment.Left
		rarityLabel.Parent = row

		-- Price label
		local priceLabel = Instance.new("TextLabel")
		priceLabel.Name = "Price"
		priceLabel.Size = UDim2.new(0, 100, 0, 20)
		priceLabel.Position = UDim2.new(1, -150, 0.5, 0)
		priceLabel.AnchorPoint = Vector2.new(0, 0.5)
		priceLabel.BackgroundTransparency = 1
		priceLabel.Text = "$" .. formatNumber(sellPrice)
		priceLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
		priceLabel.Font = CARTOON_FONT
		priceLabel.TextSize = 14
		priceLabel.TextScaled = false
		priceLabel.TextXAlignment = Enum.TextXAlignment.Right
		priceLabel.Parent = row

		-- Sell button
		local sellBtn = Instance.new("TextButton")
		sellBtn.Name = "SellBtn"
		sellBtn.Size = UDim2.new(0, 54, 0, 30)
		sellBtn.Position = UDim2.new(1, -58, 0.5, 0)
		sellBtn.AnchorPoint = Vector2.new(0, 0.5)
		sellBtn.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
		sellBtn.Text = "SELL"
		sellBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		sellBtn.Font = CARTOON_FONT
		sellBtn.TextSize = 14
		sellBtn.BorderSizePixel = 0
		sellBtn.Parent = row

		local sellBtnCorner = Instance.new("UICorner")
		sellBtnCorner.CornerRadius = UDim.new(0, 8)
		sellBtnCorner.Parent = sellBtn

		-- Capture index for the click
		local capturedIndex = idx
		sellBtn.MouseButton1Click:Connect(function()
			SellByIndexRequest:FireServer(capturedIndex)
		end)
	end

	-- Update total
	if totalLabel then
		totalLabel.Text = "Total Value: $" .. formatNumber(totalValue) .. " (" .. #inventory .. " items)"
	end
	if sellAllBtn then
		sellAllBtn.Visible = #inventory > 0
		sellAllBtn.Text = "SELL ALL — $" .. formatNumber(totalValue)
	end

	-- Update canvas size
	local listLayout = scrollFrame:FindFirstChildOfClass("UIListLayout")
	if listLayout then
		scrollFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 8)
	end
end

-------------------------------------------------
-- OPEN / CLOSE
-------------------------------------------------

function SellStandController.Open()
	if isOpen then return end
	isOpen = true
	if overlay then overlay.Visible = true end
	if modalFrame then
		modalFrame.Visible = true
		buildInventoryList()
	end
end

function SellStandController.Close()
	if not isOpen then return end
	isOpen = false
	if overlay then overlay.Visible = false end
	if modalFrame then modalFrame.Visible = false end
end

-------------------------------------------------
-- INIT
-------------------------------------------------

function SellStandController.Init()
	screenGui = UIHelper.CreateScreenGui("SellStandGui", 8)
	screenGui.Parent = playerGui

	-- Full-screen overlay
	overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.ZIndex = 8
	overlay.Parent = screenGui

	overlay.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			SellStandController.Close()
		end
	end)

	-- Modal
	modalFrame = UIHelper.CreateRoundedFrame({
		Name = "SellModal",
		Size = UDim2.new(0, 440, 0, 480),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Color3.fromRGB(25, 25, 40),
		CornerRadius = UDim.new(0, 20),
		StrokeColor = Color3.fromRGB(220, 60, 60),
		StrokeThickness = 3,
		ZIndex = 9,
		Parent = screenGui,
	})

	-- Title
	UIHelper.CreateLabel({
		Name = "Title",
		Size = UDim2.new(1, -80, 0, 36),
		Position = UDim2.new(0.5, 0, 0, 16),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "Sell Stand",
		TextColor = Color3.fromRGB(255, 255, 255),
		Font = CARTOON_FONT,
		TextSize = 26,
		Parent = modalFrame,
	})

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 40, 0, 40)
	closeBtn.Position = UDim2.new(1, -48, 0, 8)
	closeBtn.AnchorPoint = Vector2.new(0, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = DesignConfig.Colors.White
	closeBtn.Font = CARTOON_FONT
	closeBtn.TextSize = 24
	closeBtn.BorderSizePixel = 0
	closeBtn.ZIndex = 10
	closeBtn.Parent = modalFrame
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(1, 0)
	closeCorner.Parent = closeBtn
	closeBtn.MouseButton1Click:Connect(function()
		SellStandController.Close()
	end)

	-- Total value label
	totalLabel = Instance.new("TextLabel")
	totalLabel.Name = "TotalLabel"
	totalLabel.Size = UDim2.new(1, -32, 0, 22)
	totalLabel.Position = UDim2.new(0.5, 0, 0, 52)
	totalLabel.AnchorPoint = Vector2.new(0.5, 0)
	totalLabel.BackgroundTransparency = 1
	totalLabel.Text = "Total Value: $0"
	totalLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	totalLabel.Font = CARTOON_FONT
	totalLabel.TextSize = 16
	totalLabel.TextScaled = false
	totalLabel.ZIndex = 9
	totalLabel.Parent = modalFrame

	-- Scrolling frame for inventory items
	scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ItemList"
	scrollFrame.Size = UDim2.new(1, -24, 1, -148)
	scrollFrame.Position = UDim2.new(0.5, 0, 0, 78)
	scrollFrame.AnchorPoint = Vector2.new(0.5, 0)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 6
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(180, 180, 200)
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.None
	scrollFrame.ZIndex = 9
	scrollFrame.Parent = modalFrame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = scrollFrame

	-- Empty state label
	emptyLabel = Instance.new("TextLabel")
	emptyLabel.Name = "EmptyLabel"
	emptyLabel.Size = UDim2.new(1, -20, 0, 60)
	emptyLabel.Position = UDim2.new(0.5, 0, 0.3, 0)
	emptyLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.Text = "Your inventory is empty!\nGo spin some cases first."
	emptyLabel.TextColor3 = Color3.fromRGB(120, 120, 140)
	emptyLabel.Font = CARTOON_FONT
	emptyLabel.TextSize = 18
	emptyLabel.TextScaled = false
	emptyLabel.Visible = false
	emptyLabel.ZIndex = 9
	emptyLabel.Parent = modalFrame

	-- Sell All button (bottom of modal)
	sellAllBtn = Instance.new("TextButton")
	sellAllBtn.Name = "SellAllBtn"
	sellAllBtn.Size = UDim2.new(1, -32, 0, 46)
	sellAllBtn.Position = UDim2.new(0.5, 0, 1, -58)
	sellAllBtn.AnchorPoint = Vector2.new(0.5, 0)
	sellAllBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	sellAllBtn.Text = "SELL ALL — $0"
	sellAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	sellAllBtn.Font = CARTOON_FONT
	sellAllBtn.TextSize = 20
	sellAllBtn.BorderSizePixel = 0
	sellAllBtn.Visible = false
	sellAllBtn.ZIndex = 10
	sellAllBtn.Parent = modalFrame

	local sellAllCorner = Instance.new("UICorner")
	sellAllCorner.CornerRadius = UDim.new(0, 12)
	sellAllCorner.Parent = sellAllBtn
	local sellAllStroke = Instance.new("UIStroke")
	sellAllStroke.Color = Color3.fromRGB(160, 30, 30)
	sellAllStroke.Thickness = 2
	sellAllStroke.Parent = sellAllBtn

	sellAllBtn.MouseButton1Click:Connect(function()
		SellAllRequest:FireServer()
	end)

	-- Hover effects for sell all
	sellAllBtn.MouseEnter:Connect(function()
		TweenService:Create(sellAllBtn, TweenInfo.new(0.15), {
			BackgroundColor3 = Color3.fromRGB(240, 70, 70),
		}):Play()
	end)
	sellAllBtn.MouseLeave:Connect(function()
		TweenService:Create(sellAllBtn, TweenInfo.new(0.15), {
			BackgroundColor3 = Color3.fromRGB(200, 50, 50),
		}):Play()
	end)

	-- Wire up data updates — refresh list when inventory changes (while open)
	HUDController.OnDataUpdated(function()
		if isOpen then
			buildInventoryList()
		end
	end)

	-- Wire up sell results — flash feedback
	SellResult.OnClientEvent:Connect(function(data)
		if data.success and isOpen then
			-- Brief delay for data to replicate, then refresh
			task.wait(0.1)
			buildInventoryList()
		end
	end)

	-- Wire up proximity prompt event
	OpenSellStandGui.OnClientEvent:Connect(function()
		SellStandController.Open()
	end)

	-- Start hidden
	modalFrame.Visible = false
	overlay.Visible = false
end

return SellStandController
