--[[
	StoreController.lua
	Robux store: VIP, 2x Luck, Gem packs, and Enhanced Cases.
	All items use MarketplaceService:PromptProductPurchase.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local EnhancedCases = require(ReplicatedStorage.Shared.Config.EnhancedCases)
local Effects = require(ReplicatedStorage.Shared.Config.Effects)
local Streamers = require(ReplicatedStorage.Shared.Config.Streamers)
local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local UIHelper = require(script.Parent.UIHelper)
local HUDController = require(script.Parent.HUDController)

local StoreController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui
local modalFrame
local overlay
local isOpen = false

local BUBBLE_FONT = Enum.Font.FredokaOne
local FONT_SUB = Enum.Font.GothamBold
local MODAL_BG = Color3.fromRGB(28, 26, 34)
local CARD_BG = Color3.fromRGB(42, 38, 50)
local MODAL_W = 540
local MODAL_H = 650

-------------------------------------------------
-- HELPERS
-------------------------------------------------

local function createStroke(parent, color, thickness, mode)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.fromRGB(0, 0, 0)
	s.Thickness = thickness or 2
	if mode then s.ApplyStrokeMode = mode end
	s.Parent = parent
	return s
end

local productIconCache = {}

local function fetchProductIconAsync(productId, imageLabel, fallbackLabel)
	if not productId or productId == 0 then return end
	if productIconCache[productId] then
		imageLabel.Image = productIconCache[productId]
		imageLabel.Visible = true
		if fallbackLabel then fallbackLabel.Visible = false end
		return
	end
	task.spawn(function()
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, productId, Enum.InfoType.Product)
		if ok and info and info.IconImageAssetId and info.IconImageAssetId > 0 then
			local url = "rbxassetid://" .. info.IconImageAssetId
			productIconCache[productId] = url
			if imageLabel and imageLabel.Parent then
				imageLabel.Image = url
				imageLabel.Visible = true
				if fallbackLabel and fallbackLabel.Parent then
					fallbackLabel.Visible = false
				end
			end
		end
	end)
end

-------------------------------------------------
-- PREMIUM CARD (VIP / X2 Luck)
-------------------------------------------------

local function buildPremiumCard(parent, cfg)
	local owned = cfg.checkOwned()
	local card = Instance.new("Frame")
	card.Name = cfg.key .. "Card"
	card.Size = UDim2.new(1, 0, 0, 80)
	card.BackgroundColor3 = owned and Color3.fromRGB(30, 50, 35) or CARD_BG
	card.BorderSizePixel = 0
	card.LayoutOrder = cfg.order
	card.ZIndex = 52
	card.Parent = parent
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)
	createStroke(card, owned and Color3.fromRGB(60, 200, 90) or cfg.accent, 2)

	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, owned and Color3.fromRGB(40, 60, 45) or Color3.fromRGB(50, 44, 65)),
		ColorSequenceKeypoint.new(1, owned and Color3.fromRGB(25, 40, 28) or Color3.fromRGB(32, 28, 42)),
	})
	grad.Rotation = 90
	grad.Parent = card

	local iconFrame = Instance.new("Frame")
	iconFrame.Size = UDim2.new(0, 50, 0, 50)
	iconFrame.Position = UDim2.new(0, 16, 0.5, 0)
	iconFrame.AnchorPoint = Vector2.new(0, 0.5)
	iconFrame.BackgroundColor3 = Color3.fromRGB(25, 22, 35)
	iconFrame.ZIndex = 53
	iconFrame.ClipsDescendants = true
	iconFrame.Parent = card
	Instance.new("UICorner", iconFrame).CornerRadius = UDim.new(0, 12)
	createStroke(iconFrame, cfg.accent, 1.5)

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(1, 0, 1, 0)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 54
	icon.Visible = false
	icon.Parent = iconFrame

	local fallback = Instance.new("TextLabel")
	fallback.Size = UDim2.new(1, 0, 1, 0)
	fallback.BackgroundTransparency = 1
	fallback.Text = cfg.icon
	fallback.TextColor3 = cfg.accent
	fallback.Font = BUBBLE_FONT
	fallback.TextSize = 28
	fallback.ZIndex = 54
	fallback.Parent = iconFrame

	fetchProductIconAsync(cfg.productId, icon, fallback)

	local nameL = Instance.new("TextLabel")
	nameL.Size = UDim2.new(0.5, 0, 0, 24)
	nameL.Position = UDim2.new(0, 78, 0, 14)
	nameL.BackgroundTransparency = 1
	nameL.Text = cfg.title
	nameL.TextColor3 = Color3.new(1, 1, 1)
	nameL.Font = BUBBLE_FONT
	nameL.TextSize = 18
	nameL.TextXAlignment = Enum.TextXAlignment.Left
	nameL.ZIndex = 53
	nameL.Parent = card
	createStroke(nameL, Color3.fromRGB(0, 0, 0), 2, Enum.ApplyStrokeMode.Contextual)

	local descL = Instance.new("TextLabel")
	descL.Size = UDim2.new(0.55, 0, 0, 16)
	descL.Position = UDim2.new(0, 78, 0, 40)
	descL.BackgroundTransparency = 1
	descL.Text = cfg.desc
	descL.TextColor3 = cfg.accent
	descL.Font = FONT_SUB
	descL.TextSize = 11
	descL.TextXAlignment = Enum.TextXAlignment.Left
	descL.ZIndex = 53
	descL.Parent = card

	local permL = Instance.new("TextLabel")
	permL.Size = UDim2.new(0, 90, 0, 14)
	permL.Position = UDim2.new(0, 78, 0, 56)
	permL.BackgroundTransparency = 1
	permL.Text = "PERMANENT"
	permL.TextColor3 = Color3.fromRGB(255, 215, 80)
	permL.Font = BUBBLE_FONT
	permL.TextSize = 10
	permL.TextXAlignment = Enum.TextXAlignment.Left
	permL.ZIndex = 53
	permL.Parent = card

	local btn = Instance.new("TextButton")
	btn.Name = "BuyBtn"
	btn.Size = UDim2.new(0, 100, 0, 36)
	btn.Position = UDim2.new(1, -14, 0.5, 0)
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.BackgroundColor3 = owned and Color3.fromRGB(50, 160, 70) or Color3.fromRGB(60, 200, 90)
	btn.Text = owned and "OWNED" or "BUY"
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Font = BUBBLE_FONT
	btn.TextSize = 16
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.ZIndex = 53
	btn.Parent = card
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)
	createStroke(btn, owned and Color3.fromRGB(30, 120, 45) or Color3.fromRGB(30, 140, 50), 2)
	createStroke(btn, Color3.fromRGB(0, 0, 0), 1.5, Enum.ApplyStrokeMode.Contextual)

	if not owned then
		local bTI = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		btn.MouseEnter:Connect(function()
			TweenService:Create(btn, bTI, { BackgroundColor3 = Color3.fromRGB(80, 235, 115) }):Play()
		end)
		btn.MouseLeave:Connect(function()
			TweenService:Create(btn, bTI, { BackgroundColor3 = Color3.fromRGB(60, 200, 90) }):Play()
		end)
		btn.MouseButton1Click:Connect(function()
			if cfg.productId and cfg.productId > 0 then
				MarketplaceService:PromptProductPurchase(player, cfg.productId)
			end
		end)
	end

	return card
end

-------------------------------------------------
-- GEM PACK CARD
-------------------------------------------------

local function buildGemCard(parent, cfg)
	local card = Instance.new("Frame")
	card.Name = "GemPack_" .. cfg.key
	card.Size = UDim2.new(1, 0, 0, 80)
	card.BackgroundColor3 = CARD_BG
	card.BorderSizePixel = 0
	card.LayoutOrder = cfg.order
	card.ZIndex = 52
	card.Parent = parent
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)
	createStroke(card, Color3.fromRGB(60, 55, 75), 1.5)

	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(45, 38, 65)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 26, 42)),
	})
	grad.Rotation = 90
	grad.Parent = card

	local gemIconFrame = Instance.new("Frame")
	gemIconFrame.Size = UDim2.new(0, 50, 0, 50)
	gemIconFrame.Position = UDim2.new(0, 16, 0.5, 0)
	gemIconFrame.AnchorPoint = Vector2.new(0, 0.5)
	gemIconFrame.BackgroundColor3 = Color3.fromRGB(25, 22, 40)
	gemIconFrame.ZIndex = 53
	gemIconFrame.ClipsDescendants = true
	gemIconFrame.Parent = card
	Instance.new("UICorner", gemIconFrame).CornerRadius = UDim.new(0, 12)
	createStroke(gemIconFrame, Color3.fromRGB(100, 180, 255), 1.5)

	local gemIcon = Instance.new("ImageLabel")
	gemIcon.Size = UDim2.new(1, 0, 1, 0)
	gemIcon.BackgroundTransparency = 1
	gemIcon.ScaleType = Enum.ScaleType.Fit
	gemIcon.ZIndex = 54
	gemIcon.Visible = false
	gemIcon.Parent = gemIconFrame

	local fallbackGem = Instance.new("TextLabel")
	fallbackGem.Size = UDim2.new(1, 0, 1, 0)
	fallbackGem.BackgroundTransparency = 1
	fallbackGem.Text = "\u{1F48E}"
	fallbackGem.TextSize = 28
	fallbackGem.ZIndex = 54
	fallbackGem.Parent = gemIconFrame

	fetchProductIconAsync(cfg.productId, gemIcon, fallbackGem)

	local nameL = Instance.new("TextLabel")
	nameL.Size = UDim2.new(0.5, 0, 0, 26)
	nameL.Position = UDim2.new(0, 78, 0, 14)
	nameL.BackgroundTransparency = 1
	nameL.Text = cfg.label
	nameL.TextColor3 = Color3.fromRGB(100, 220, 255)
	nameL.Font = BUBBLE_FONT
	nameL.TextSize = 20
	nameL.TextXAlignment = Enum.TextXAlignment.Left
	nameL.ZIndex = 53
	nameL.Parent = card
	createStroke(nameL, Color3.fromRGB(0, 0, 0), 2, Enum.ApplyStrokeMode.Contextual)

	local descL = Instance.new("TextLabel")
	descL.Size = UDim2.new(0.5, 0, 0, 16)
	descL.Position = UDim2.new(0, 78, 0, 42)
	descL.BackgroundTransparency = 1
	descL.Text = "Instant delivery"
	descL.TextColor3 = Color3.fromRGB(140, 135, 160)
	descL.Font = FONT_SUB
	descL.TextSize = 11
	descL.TextXAlignment = Enum.TextXAlignment.Left
	descL.ZIndex = 53
	descL.Parent = card

	local btn = Instance.new("TextButton")
	btn.Name = "BuyBtn"
	btn.Size = UDim2.new(0, 100, 0, 36)
	btn.Position = UDim2.new(1, -14, 0.5, 0)
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.BackgroundColor3 = Color3.fromRGB(60, 200, 90)
	btn.Text = "BUY"
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Font = BUBBLE_FONT
	btn.TextSize = 16
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.ZIndex = 53
	btn.Parent = card
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)
	createStroke(btn, Color3.fromRGB(30, 140, 50), 2)
	createStroke(btn, Color3.fromRGB(0, 0, 0), 1.5, Enum.ApplyStrokeMode.Contextual)

	local bTI = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, bTI, { BackgroundColor3 = Color3.fromRGB(80, 235, 115) }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, bTI, { BackgroundColor3 = Color3.fromRGB(60, 200, 90) }):Play()
	end)
	btn.MouseButton1Click:Connect(function()
		if cfg.productId and cfg.productId > 0 then
			MarketplaceService:PromptProductPurchase(player, cfg.productId)
		end
	end)

	return card
end

-------------------------------------------------
-- ENHANCED CASE CARD (with odds display)
-------------------------------------------------

local function buildEnhancedCaseCard(parent, caseData, order)
	local productId = Economy.Products[caseData.key]
	local accent = caseData.accent

	local card = Instance.new("Frame")
	card.Name = "EnhancedCase_" .. caseData.key
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = CARD_BG
	card.BorderSizePixel = 0
	card.LayoutOrder = order
	card.ZIndex = 52
	card.Parent = parent
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)
	createStroke(card, accent, 2)

	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 44, 65)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 26, 38)),
	})
	grad.Rotation = 90
	grad.Parent = card

	local cardLayout = Instance.new("UIListLayout")
	cardLayout.FillDirection = Enum.FillDirection.Vertical
	cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
	cardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	cardLayout.Padding = UDim.new(0, 6)
	cardLayout.Parent = card

	local cardPad = Instance.new("UIPadding")
	cardPad.PaddingTop = UDim.new(0, 10)
	cardPad.PaddingBottom = UDim.new(0, 12)
	cardPad.PaddingLeft = UDim.new(0, 12)
	cardPad.PaddingRight = UDim.new(0, 12)
	cardPad.Parent = card

	-- Top row: image + title
	local topRow = Instance.new("Frame")
	topRow.Size = UDim2.new(1, 0, 0, 60)
	topRow.BackgroundTransparency = 1
	topRow.LayoutOrder = 0
	topRow.ZIndex = 53
	topRow.Parent = card

	local imgFrame = Instance.new("Frame")
	imgFrame.Size = UDim2.new(0, 56, 0, 56)
	imgFrame.Position = UDim2.new(0, 0, 0.5, 0)
	imgFrame.AnchorPoint = Vector2.new(0, 0.5)
	imgFrame.BackgroundColor3 = Color3.fromRGB(20, 18, 28)
	imgFrame.ClipsDescendants = true
	imgFrame.ZIndex = 54
	imgFrame.Parent = topRow
	Instance.new("UICorner", imgFrame).CornerRadius = UDim.new(0, 12)
	createStroke(imgFrame, accent, 1.5)

	local img = Instance.new("ImageLabel")
	img.Size = UDim2.new(1, 0, 1, 0)
	img.BackgroundTransparency = 1
	img.ScaleType = Enum.ScaleType.Fit
	img.ZIndex = 55
	img.Visible = false
	img.Parent = imgFrame

	fetchProductIconAsync(productId, img, nil)

	local titleL = Instance.new("TextLabel")
	titleL.Size = UDim2.new(1, -68, 0, 24)
	titleL.Position = UDim2.new(0, 66, 0, 6)
	titleL.BackgroundTransparency = 1
	titleL.Text = caseData.name
	titleL.TextColor3 = Color3.new(1, 1, 1)
	titleL.Font = BUBBLE_FONT
	titleL.TextSize = 17
	titleL.TextXAlignment = Enum.TextXAlignment.Left
	titleL.ZIndex = 54
	titleL.Parent = topRow
	createStroke(titleL, Color3.fromRGB(0, 0, 0), 2, Enum.ApplyStrokeMode.Contextual)

	local subtitleL = Instance.new("TextLabel")
	subtitleL.Size = UDim2.new(1, -68, 0, 14)
	subtitleL.Position = UDim2.new(0, 66, 0, 30)
	subtitleL.BackgroundTransparency = 1
	subtitleL.Text = "Exclusive Robux Case • 1 Spin"
	subtitleL.TextColor3 = accent
	subtitleL.Font = FONT_SUB
	subtitleL.TextSize = 10
	subtitleL.TextXAlignment = Enum.TextXAlignment.Left
	subtitleL.ZIndex = 54
	subtitleL.Parent = topRow

	-- Odds list
	for i, entry in ipairs(caseData.pool) do
		local effectInfo = Effects.ByName[entry.effect]
		local streamerInfo = Streamers.ById[entry.streamerId]
		local rarityText = streamerInfo and streamerInfo.rarity or "?"
		local effectColor = effectInfo and effectInfo.color or Color3.fromRGB(200, 200, 200)

		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 22)
		row.BackgroundColor3 = (i % 2 == 0) and Color3.fromRGB(38, 34, 48) or Color3.fromRGB(32, 28, 42)
		row.BackgroundTransparency = 0.3
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.ZIndex = 53
		row.Parent = card
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

		local nameL = Instance.new("TextLabel")
		nameL.Size = UDim2.new(0.55, 0, 1, 0)
		nameL.Position = UDim2.new(0, 10, 0, 0)
		nameL.BackgroundTransparency = 1
		nameL.Text = entry.label
		nameL.TextColor3 = effectColor
		nameL.Font = BUBBLE_FONT
		nameL.TextSize = 12
		nameL.TextXAlignment = Enum.TextXAlignment.Left
		nameL.ZIndex = 54
		nameL.Parent = row
		createStroke(nameL, Color3.fromRGB(0, 0, 0), 1, Enum.ApplyStrokeMode.Contextual)

		local rarityL = Instance.new("TextLabel")
		rarityL.Size = UDim2.new(0.2, 0, 1, 0)
		rarityL.Position = UDim2.new(0.55, 0, 0, 0)
		rarityL.BackgroundTransparency = 1
		rarityL.Text = rarityText
		rarityL.TextColor3 = Color3.fromRGB(180, 175, 200)
		rarityL.Font = FONT_SUB
		rarityL.TextSize = 10
		rarityL.TextXAlignment = Enum.TextXAlignment.Center
		rarityL.ZIndex = 54
		rarityL.Parent = row

		local oddsL = Instance.new("TextLabel")
		oddsL.Size = UDim2.new(0.25, -10, 1, 0)
		oddsL.Position = UDim2.new(0.75, 0, 0, 0)
		oddsL.BackgroundTransparency = 1
		oddsL.Text = entry.weight .. "%"
		oddsL.TextColor3 = Color3.fromRGB(255, 255, 100)
		oddsL.Font = BUBBLE_FONT
		oddsL.TextSize = 13
		oddsL.TextXAlignment = Enum.TextXAlignment.Right
		oddsL.ZIndex = 54
		oddsL.Parent = row
		createStroke(oddsL, Color3.fromRGB(0, 0, 0), 1, Enum.ApplyStrokeMode.Contextual)
	end

	-- Buy button
	local btnWrap = Instance.new("Frame")
	btnWrap.Size = UDim2.new(1, 0, 0, 40)
	btnWrap.BackgroundTransparency = 1
	btnWrap.LayoutOrder = 100
	btnWrap.ZIndex = 53
	btnWrap.Parent = card

	local btn = Instance.new("TextButton")
	btn.Name = "BuyBtn"
	btn.Size = UDim2.new(0.6, 0, 0, 34)
	btn.Position = UDim2.new(0.5, 0, 0.5, 0)
	btn.AnchorPoint = Vector2.new(0.5, 0.5)
	btn.BackgroundColor3 = Color3.fromRGB(60, 200, 90)
	btn.Text = "OPEN (R$)"
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Font = BUBBLE_FONT
	btn.TextSize = 16
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.ZIndex = 54
	btn.Parent = btnWrap
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)
	createStroke(btn, Color3.fromRGB(30, 140, 50), 2)
	createStroke(btn, Color3.fromRGB(0, 0, 0), 1.5, Enum.ApplyStrokeMode.Contextual)

	local bTI = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, bTI, { BackgroundColor3 = Color3.fromRGB(80, 235, 115) }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, bTI, { BackgroundColor3 = Color3.fromRGB(60, 200, 90) }):Play()
	end)
	btn.MouseButton1Click:Connect(function()
		if productId and productId > 0 then
			MarketplaceService:PromptProductPurchase(player, productId)
		end
	end)

	return card
end

-------------------------------------------------
-- BUILD MODAL
-------------------------------------------------

function StoreController.Init()
	screenGui = UIHelper.CreateScreenGui("StoreGui", 20)
	screenGui.Parent = playerGui

	overlay = UIHelper.CreateModalOverlay(screenGui, function()
		StoreController.Close()
	end)
	overlay.Visible = false

	modalFrame = Instance.new("Frame")
	modalFrame.Name = "StoreModal"
	modalFrame.Size = UDim2.new(0, MODAL_W, 0, MODAL_H)
	modalFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	modalFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	modalFrame.BackgroundColor3 = MODAL_BG
	modalFrame.BorderSizePixel = 0
	modalFrame.Visible = false
	modalFrame.ZIndex = 50
	modalFrame.ClipsDescendants = true
	modalFrame.Parent = screenGui
	Instance.new("UICorner", modalFrame).CornerRadius = UDim.new(0, 20)
	createStroke(modalFrame, Color3.fromRGB(70, 60, 100), 2.5)
	UIHelper.CreateShadow(modalFrame)
	UIHelper.MakeResponsiveModal(modalFrame, MODAL_W, MODAL_H)

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(0.6, 0, 0, 36)
	title.Position = UDim2.new(0, 20, 0, 12)
	title.BackgroundTransparency = 1
	title.Text = "Store"
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Font = BUBBLE_FONT
	title.TextSize = 30
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 52
	title.Parent = modalFrame
	createStroke(title, Color3.fromRGB(0, 0, 0), 2.5, Enum.ApplyStrokeMode.Contextual)

	-- Subtitle
	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(0.5, 0, 0, 16)
	sub.Position = UDim2.new(0, 22, 0, 46)
	sub.BackgroundTransparency = 1
	sub.Text = "Premium upgrades & gem packs"
	sub.TextColor3 = Color3.fromRGB(140, 135, 160)
	sub.Font = FONT_SUB
	sub.TextSize = 11
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.ZIndex = 52
	sub.Parent = modalFrame

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 42, 0, 42)
	closeBtn.Position = UDim2.new(1, -14, 0, 10)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(220, 55, 55)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = BUBBLE_FONT
	closeBtn.TextSize = 22
	closeBtn.BorderSizePixel = 0
	closeBtn.AutoButtonColor = false
	closeBtn.ZIndex = 55
	closeBtn.Parent = modalFrame
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1, 0)
	createStroke(closeBtn, Color3.fromRGB(160, 30, 30), 2)
	createStroke(closeBtn, Color3.fromRGB(80, 0, 0), 1.5, Enum.ApplyStrokeMode.Contextual)

	local closeBounce = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	closeBtn.MouseEnter:Connect(function()
		TweenService:Create(closeBtn, closeBounce, { Size = UDim2.new(0, 48, 0, 48), BackgroundColor3 = Color3.fromRGB(255, 75, 75) }):Play()
	end)
	closeBtn.MouseLeave:Connect(function()
		TweenService:Create(closeBtn, closeBounce, { Size = UDim2.new(0, 42, 0, 42), BackgroundColor3 = Color3.fromRGB(220, 55, 55) }):Play()
	end)
	closeBtn.MouseButton1Click:Connect(function()
		StoreController.Close()
	end)

	-- Divider
	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(1, -30, 0, 1)
	divider.Position = UDim2.new(0.5, 0, 0, 66)
	divider.AnchorPoint = Vector2.new(0.5, 0)
	divider.BackgroundColor3 = Color3.fromRGB(65, 60, 80)
	divider.BorderSizePixel = 0
	divider.ZIndex = 52
	divider.Parent = modalFrame

	-- Scrollable content
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "StoreScroll"
	scroll.Size = UDim2.new(1, -24, 1, -86)
	scroll.Position = UDim2.new(0.5, 0, 0, 78)
	scroll.AnchorPoint = Vector2.new(0.5, 0)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Color3.fromRGB(100, 90, 140)
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ZIndex = 51
	scroll.Parent = modalFrame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.Parent = scroll

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = scroll

	-------------------------------------------------
	-- PREMIUM SECTION HEADER
	-------------------------------------------------
	local premHeader = Instance.new("TextLabel")
	premHeader.Size = UDim2.new(1, 0, 0, 22)
	premHeader.BackgroundTransparency = 1
	premHeader.Text = "PREMIUM PASSES"
	premHeader.TextColor3 = Color3.fromRGB(255, 215, 80)
	premHeader.Font = BUBBLE_FONT
	premHeader.TextSize = 15
	premHeader.TextXAlignment = Enum.TextXAlignment.Left
	premHeader.LayoutOrder = 0
	premHeader.ZIndex = 52
	premHeader.Parent = scroll
	createStroke(premHeader, Color3.fromRGB(0, 0, 0), 1.5, Enum.ApplyStrokeMode.Contextual)

	buildPremiumCard(scroll, {
		key = "VIP",
		title = "VIP Pass",
		desc = "1.5x Luck + 1.5x Money Earned",
		icon = "V",
		accent = Color3.fromRGB(255, 200, 60),
		productId = Economy.Products.VIP,
		checkOwned = function() return HUDController.Data.hasVIP == true end,
		order = 1,
	})

	buildPremiumCard(scroll, {
		key = "X2Luck",
		title = "2x Luck",
		desc = "Permanently double your luck",
		icon = "L",
		accent = Color3.fromRGB(80, 200, 255),
		productId = Economy.Products.X2Luck,
		checkOwned = function() return HUDController.Data.hasX2Luck == true end,
		order = 2,
	})

	-------------------------------------------------
	-- GEM PACKS SECTION
	-------------------------------------------------
	local gemDivider = Instance.new("Frame")
	gemDivider.Size = UDim2.new(0.9, 0, 0, 3)
	gemDivider.BackgroundColor3 = Color3.fromRGB(100, 180, 255)
	gemDivider.BorderSizePixel = 0
	gemDivider.LayoutOrder = 5
	gemDivider.ZIndex = 52
	gemDivider.Parent = scroll
	Instance.new("UICorner", gemDivider).CornerRadius = UDim.new(1, 0)

	local gemHeader = Instance.new("TextLabel")
	gemHeader.Size = UDim2.new(1, 0, 0, 22)
	gemHeader.BackgroundTransparency = 1
	gemHeader.Text = "GEM PACKS"
	gemHeader.TextColor3 = Color3.fromRGB(100, 220, 255)
	gemHeader.Font = BUBBLE_FONT
	gemHeader.TextSize = 15
	gemHeader.TextXAlignment = Enum.TextXAlignment.Left
	gemHeader.LayoutOrder = 6
	gemHeader.ZIndex = 52
	gemHeader.Parent = scroll
	createStroke(gemHeader, Color3.fromRGB(0, 0, 0), 1.5, Enum.ApplyStrokeMode.Contextual)

	for i, pack in ipairs(Economy.GemPacks) do
		buildGemCard(scroll, {
			key = pack.key,
			label = pack.label,
			productId = Economy.Products[pack.key],
			order = 6 + i,
		})
	end

	-------------------------------------------------
	-- ENHANCED CASES SECTION
	-------------------------------------------------
	local caseDivider = Instance.new("Frame")
	caseDivider.Size = UDim2.new(0.9, 0, 0, 3)
	caseDivider.BackgroundColor3 = Color3.fromRGB(200, 120, 255)
	caseDivider.BorderSizePixel = 0
	caseDivider.LayoutOrder = 20
	caseDivider.ZIndex = 52
	caseDivider.Parent = scroll
	Instance.new("UICorner", caseDivider).CornerRadius = UDim.new(1, 0)

	local caseHeader = Instance.new("TextLabel")
	caseHeader.Size = UDim2.new(1, 0, 0, 22)
	caseHeader.BackgroundTransparency = 1
	caseHeader.Text = "ENHANCED CASES"
	caseHeader.TextColor3 = Color3.fromRGB(220, 160, 255)
	caseHeader.Font = BUBBLE_FONT
	caseHeader.TextSize = 15
	caseHeader.TextXAlignment = Enum.TextXAlignment.Left
	caseHeader.LayoutOrder = 21
	caseHeader.ZIndex = 52
	caseHeader.Parent = scroll
	createStroke(caseHeader, Color3.fromRGB(0, 0, 0), 1.5, Enum.ApplyStrokeMode.Contextual)

	for i, caseData in ipairs(EnhancedCases.List) do
		buildEnhancedCaseCard(scroll, caseData, 21 + i)
	end
end

-------------------------------------------------
-- OPEN / CLOSE
-------------------------------------------------

function StoreController.Open()
	if isOpen then return end
	isOpen = true
	overlay.Visible = true
	modalFrame.Visible = true
	UIHelper.ScaleIn(modalFrame, 0.25)
end

function StoreController.Close()
	if not isOpen then return end
	isOpen = false
	modalFrame.Visible = false
	overlay.Visible = false
end

function StoreController.IsOpen(): boolean
	return isOpen
end

return StoreController
