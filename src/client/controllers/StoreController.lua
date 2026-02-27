--[[
	StoreController.lua
	Robux store: VIP, 2x Luck, Gem packs, and Enhanced Cases.
	All items use MarketplaceService:PromptProductPurchase.
	Tabbed layout: Premium | Gems | Cases
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
local scroll
local isOpen = false

local currentTab = "Premium"

local BUBBLE_FONT = Enum.Font.FredokaOne
local FONT_SUB = Enum.Font.GothamBold
local MODAL_BG = Color3.fromRGB(18, 14, 32)
local CARD_BG = Color3.fromRGB(30, 24, 50)
local MODAL_W = 700
local MODAL_H = 720

local HOTBAR_MAX = 9
local STORAGE_MAX = 200

local TAB_DEFS = {
	{ id = "Premium", label = "Premium",  accent = Color3.fromRGB(255, 220, 80),  activeColor = Color3.fromRGB(200, 160, 40) },
	{ id = "Gems",    label = "Gems",     accent = Color3.fromRGB(100, 220, 255), activeColor = Color3.fromRGB(40, 140, 200) },
	{ id = "Cases",   label = "Cases",    accent = Color3.fromRGB(220, 160, 255), activeColor = Color3.fromRGB(140, 70, 200) },
}

local tabButtons = {}

-------------------------------------------------
-- HELPERS
-------------------------------------------------

local function isInventoryFull()
	local inv = HUDController.Data.inventory or {}
	local sto = HUDController.Data.storage or {}
	return #inv >= HOTBAR_MAX and #sto >= STORAGE_MAX
end

local function showStoreToast(text)
	if not modalFrame then return end
	local existing = modalFrame:FindFirstChild("_StoreToast")
	if existing then existing:Destroy() end

	local toast = Instance.new("Frame")
	toast.Name = "_StoreToast"
	toast.Size = UDim2.new(0.7, 0, 0, 40)
	toast.Position = UDim2.new(0.5, 0, 1, -16)
	toast.AnchorPoint = Vector2.new(0.5, 1)
	toast.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	toast.BorderSizePixel = 0
	toast.ZIndex = 60
	toast.Parent = modalFrame
	Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 10)

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -16, 1, 0)
	lbl.Position = UDim2.new(0.5, 0, 0.5, 0)
	lbl.AnchorPoint = Vector2.new(0.5, 0.5)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = Color3.new(1, 1, 1)
	lbl.Font = BUBBLE_FONT
	lbl.TextSize = 15
	lbl.ZIndex = 61
	lbl.Parent = toast

	task.delay(3, function()
		if toast and toast.Parent then
			TweenService:Create(toast, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(lbl, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			task.wait(0.35)
			if toast and toast.Parent then toast:Destroy() end
		end
	end)
end

local function createStroke(parent, color, thickness, mode)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.fromRGB(0, 0, 0)
	s.Thickness = thickness or 2
	if mode then s.ApplyStrokeMode = mode end
	s.Parent = parent
	return s
end

local function addGlow(parent, color, transparency)
	local glow = Instance.new("Frame")
	glow.Name = "_Glow"
	glow.Size = UDim2.new(1, 20, 1, 20)
	glow.Position = UDim2.new(0.5, 0, 0.5, 0)
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.BackgroundColor3 = color
	glow.BackgroundTransparency = transparency or 0.85
	glow.BorderSizePixel = 0
	glow.ZIndex = parent.ZIndex - 1
	Instance.new("UICorner", glow).CornerRadius = UDim.new(0, 22)
	glow.Parent = parent
	return glow
end

local productIconCache = {}
local productPriceCache = {}

local function fetchProductPriceAsync(productId, btn)
	if not productId or productId == 0 then return end
	if productPriceCache[productId] then
		if btn and btn.Parent then
			btn.Text = "R$ " .. productPriceCache[productId]
		end
		return
	end
	task.spawn(function()
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, productId, Enum.InfoType.Product)
		if ok and info and info.PriceInRobux then
			productPriceCache[productId] = tostring(info.PriceInRobux)
			if btn and btn.Parent then
				btn.Text = "R$ " .. info.PriceInRobux
			end
		end
	end)
end

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

local function createBuyButton(parent, cfg)
	local owned = cfg.owned
	local btn = Instance.new("TextButton")
	btn.Name = "BuyBtn"
	btn.Size = UDim2.new(0, 130, 0, 44)
	btn.Position = UDim2.new(1, -16, 0.5, 0)
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.ZIndex = cfg.zIndex or 53
	btn.Font = BUBBLE_FONT
	btn.TextSize = 18
	btn.Parent = parent
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 12)

	if owned then
		btn.BackgroundColor3 = Color3.fromRGB(40, 130, 55)
		btn.Text = "OWNED"
		btn.TextColor3 = Color3.fromRGB(180, 255, 200)
		createStroke(btn, Color3.fromRGB(25, 90, 35), 2)
	else
		btn.BackgroundColor3 = Color3.fromRGB(50, 210, 80)
		btn.Text = cfg.text or "BUY"
		btn.TextColor3 = Color3.new(1, 1, 1)
		createStroke(btn, Color3.fromRGB(30, 160, 55), 2.5)

		local grad = Instance.new("UIGradient")
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 255, 210)),
		})
		grad.Rotation = 90
		grad.Parent = btn

		local bTI = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		btn.MouseEnter:Connect(function()
			TweenService:Create(btn, bTI, {
				BackgroundColor3 = Color3.fromRGB(80, 255, 120),
				Size = UDim2.new(0, 138, 0, 48),
			}):Play()
		end)
		btn.MouseLeave:Connect(function()
			TweenService:Create(btn, bTI, {
				BackgroundColor3 = Color3.fromRGB(50, 210, 80),
				Size = UDim2.new(0, 130, 0, 44),
			}):Play()
		end)
		btn.MouseButton1Click:Connect(function()
			if cfg.productId and cfg.productId > 0 then
				MarketplaceService:PromptProductPurchase(player, cfg.productId)
			end
		end)
	end

	createStroke(btn, Color3.fromRGB(0, 0, 0), 1.5, Enum.ApplyStrokeMode.Contextual)
	return btn
end

-------------------------------------------------
-- PREMIUM CARD (VIP / X2 Luck)
-------------------------------------------------

local function buildPremiumCard(parent, cfg)
	local owned = cfg.checkOwned()

	local card = Instance.new("Frame")
	card.Name = cfg.key .. "Card"
	card.Size = UDim2.new(1, 0, 0, 100)
	card.BackgroundColor3 = owned and Color3.fromRGB(20, 50, 30) or CARD_BG
	card.BorderSizePixel = 0
	card.LayoutOrder = cfg.order
	card.ZIndex = 52
	card.Parent = parent
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 16)
	createStroke(card, owned and Color3.fromRGB(60, 200, 90) or cfg.accent, 2.5)

	local grad = Instance.new("UIGradient")
	if owned then
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(35, 70, 40)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 40, 22)),
		})
	else
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(55, 40, 85)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(40, 30, 65)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(25, 18, 45)),
		})
	end
	grad.Rotation = 90
	grad.Parent = card

	addGlow(card, cfg.accent, 0.92)

	local iconFrame = Instance.new("Frame")
	iconFrame.Size = UDim2.new(0, 68, 0, 68)
	iconFrame.Position = UDim2.new(0, 16, 0.5, 0)
	iconFrame.AnchorPoint = Vector2.new(0, 0.5)
	iconFrame.BackgroundColor3 = Color3.fromRGB(20, 16, 35)
	iconFrame.ZIndex = 53
	iconFrame.ClipsDescendants = true
	iconFrame.Parent = card
	Instance.new("UICorner", iconFrame).CornerRadius = UDim.new(0, 14)
	createStroke(iconFrame, cfg.accent, 2)

	local iconGlow = Instance.new("UIGradient")
	iconGlow.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(60, 50, 90)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(25, 20, 40)),
	})
	iconGlow.Rotation = 135
	iconGlow.Parent = iconFrame

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(1, -6, 1, -6)
	icon.Position = UDim2.new(0.5, 0, 0.5, 0)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
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
	fallback.TextSize = 34
	fallback.ZIndex = 54
	fallback.Parent = iconFrame

	fetchProductIconAsync(cfg.productId, icon, fallback)

	local nameL = Instance.new("TextLabel")
	nameL.Size = UDim2.new(0.45, 0, 0, 28)
	nameL.Position = UDim2.new(0, 98, 0, 14)
	nameL.BackgroundTransparency = 1
	nameL.Text = cfg.title
	nameL.TextColor3 = Color3.new(1, 1, 1)
	nameL.Font = BUBBLE_FONT
	nameL.TextSize = 22
	nameL.TextXAlignment = Enum.TextXAlignment.Left
	nameL.ZIndex = 53
	nameL.Parent = card
	createStroke(nameL, Color3.fromRGB(0, 0, 0), 2.5, Enum.ApplyStrokeMode.Contextual)

	local descL = Instance.new("TextLabel")
	descL.Size = UDim2.new(0.5, 0, 0, 18)
	descL.Position = UDim2.new(0, 98, 0, 44)
	descL.BackgroundTransparency = 1
	descL.Text = cfg.desc
	descL.TextColor3 = cfg.accent
	descL.Font = FONT_SUB
	descL.TextSize = 13
	descL.TextXAlignment = Enum.TextXAlignment.Left
	descL.ZIndex = 53
	descL.Parent = card

	local permL = Instance.new("TextLabel")
	permL.Size = UDim2.new(0, 120, 0, 16)
	permL.Position = UDim2.new(0, 98, 0, 66)
	permL.BackgroundTransparency = 1
	permL.Text = "PERMANENT"
	permL.TextColor3 = Color3.fromRGB(255, 220, 80)
	permL.Font = BUBBLE_FONT
	permL.TextSize = 12
	permL.TextXAlignment = Enum.TextXAlignment.Left
	permL.ZIndex = 53
	permL.Parent = card
	createStroke(permL, Color3.fromRGB(0, 0, 0), 1.5, Enum.ApplyStrokeMode.Contextual)

	createBuyButton(card, {
		owned = owned,
		productId = cfg.productId,
		zIndex = 53,
	})

	return card
end

-------------------------------------------------
-- GEM PACK CARD
-------------------------------------------------

local function buildGemCard(parent, cfg)
	local card = Instance.new("Frame")
	card.Name = "GemPack_" .. cfg.key
	card.Size = UDim2.new(1, 0, 0, 100)
	card.BackgroundColor3 = CARD_BG
	card.BorderSizePixel = 0
	card.LayoutOrder = cfg.order
	card.ZIndex = 52
	card.Parent = parent
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 16)
	createStroke(card, Color3.fromRGB(60, 160, 255), 2)

	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 45, 80)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(25, 30, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 20, 45)),
	})
	grad.Rotation = 90
	grad.Parent = card

	addGlow(card, Color3.fromRGB(80, 180, 255), 0.92)

	local gemIconFrame = Instance.new("Frame")
	gemIconFrame.Size = UDim2.new(0, 68, 0, 68)
	gemIconFrame.Position = UDim2.new(0, 16, 0.5, 0)
	gemIconFrame.AnchorPoint = Vector2.new(0, 0.5)
	gemIconFrame.BackgroundColor3 = Color3.fromRGB(15, 20, 45)
	gemIconFrame.ZIndex = 53
	gemIconFrame.ClipsDescendants = true
	gemIconFrame.Parent = card
	Instance.new("UICorner", gemIconFrame).CornerRadius = UDim.new(0, 14)
	createStroke(gemIconFrame, Color3.fromRGB(80, 180, 255), 2)

	local iconGlow = Instance.new("UIGradient")
	iconGlow.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 60, 110)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 20, 45)),
	})
	iconGlow.Rotation = 135
	iconGlow.Parent = gemIconFrame

	local gemIcon = Instance.new("ImageLabel")
	gemIcon.Size = UDim2.new(1, -6, 1, -6)
	gemIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
	gemIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	gemIcon.BackgroundTransparency = 1
	gemIcon.ScaleType = Enum.ScaleType.Fit
	gemIcon.ZIndex = 54
	gemIcon.Visible = false
	gemIcon.Parent = gemIconFrame

	local fallbackGem = Instance.new("TextLabel")
	fallbackGem.Size = UDim2.new(1, 0, 1, 0)
	fallbackGem.BackgroundTransparency = 1
	fallbackGem.Text = "\u{1F48E}"
	fallbackGem.TextSize = 34
	fallbackGem.ZIndex = 54
	fallbackGem.Parent = gemIconFrame

	fetchProductIconAsync(cfg.productId, gemIcon, fallbackGem)

	local nameL = Instance.new("TextLabel")
	nameL.Size = UDim2.new(0.45, 0, 0, 28)
	nameL.Position = UDim2.new(0, 98, 0, 18)
	nameL.BackgroundTransparency = 1
	nameL.Text = cfg.label
	nameL.TextColor3 = Color3.fromRGB(120, 220, 255)
	nameL.Font = BUBBLE_FONT
	nameL.TextSize = 22
	nameL.TextXAlignment = Enum.TextXAlignment.Left
	nameL.ZIndex = 53
	nameL.Parent = card
	createStroke(nameL, Color3.fromRGB(0, 0, 0), 2.5, Enum.ApplyStrokeMode.Contextual)

	local descL = Instance.new("TextLabel")
	descL.Size = UDim2.new(0.5, 0, 0, 18)
	descL.Position = UDim2.new(0, 98, 0, 50)
	descL.BackgroundTransparency = 1
	descL.Text = "Instant delivery"
	descL.TextColor3 = Color3.fromRGB(160, 200, 230)
	descL.Font = FONT_SUB
	descL.TextSize = 13
	descL.TextXAlignment = Enum.TextXAlignment.Left
	descL.ZIndex = 53
	descL.Parent = card

	createBuyButton(card, {
		owned = false,
		productId = cfg.productId,
		zIndex = 53,
	})

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
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 16)

	local outerStroke = createStroke(card, accent, 3)
	outerStroke.Transparency = 0.15

	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 38, 80)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(35, 26, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 16, 40)),
	})
	grad.Rotation = 90
	grad.Parent = card

	local cardLayout = Instance.new("UIListLayout")
	cardLayout.FillDirection = Enum.FillDirection.Vertical
	cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
	cardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	cardLayout.Padding = UDim.new(0, 8)
	cardLayout.Parent = card

	local cardPad = Instance.new("UIPadding")
	cardPad.PaddingTop = UDim.new(0, 14)
	cardPad.PaddingBottom = UDim.new(0, 14)
	cardPad.PaddingLeft = UDim.new(0, 14)
	cardPad.PaddingRight = UDim.new(0, 14)
	cardPad.Parent = card

	local topRow = Instance.new("Frame")
	topRow.Size = UDim2.new(1, 0, 0, 68)
	topRow.BackgroundTransparency = 1
	topRow.LayoutOrder = 0
	topRow.ZIndex = 53
	topRow.Parent = card

	local imgFrame = Instance.new("Frame")
	imgFrame.Size = UDim2.new(0, 60, 0, 60)
	imgFrame.Position = UDim2.new(0, 0, 0.5, 0)
	imgFrame.AnchorPoint = Vector2.new(0, 0.5)
	imgFrame.BackgroundColor3 = Color3.fromRGB(18, 14, 30)
	imgFrame.ClipsDescendants = true
	imgFrame.ZIndex = 54
	imgFrame.Parent = topRow
	Instance.new("UICorner", imgFrame).CornerRadius = UDim.new(0, 14)
	createStroke(imgFrame, accent, 2)

	local imgGlow = Instance.new("UIGradient")
	imgGlow.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 40, 80)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 14, 30)),
	})
	imgGlow.Rotation = 135
	imgGlow.Parent = imgFrame

	local img = Instance.new("ImageLabel")
	img.Size = UDim2.new(1, -6, 1, -6)
	img.Position = UDim2.new(0.5, 0, 0.5, 0)
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.BackgroundTransparency = 1
	img.ScaleType = Enum.ScaleType.Fit
	img.ZIndex = 55
	img.Visible = false
	img.Parent = imgFrame

	fetchProductIconAsync(productId, img, nil)

	local titleL = Instance.new("TextLabel")
	titleL.Size = UDim2.new(1, -76, 0, 28)
	titleL.Position = UDim2.new(0, 72, 0, 8)
	titleL.BackgroundTransparency = 1
	titleL.Text = caseData.name
	titleL.TextColor3 = Color3.new(1, 1, 1)
	titleL.Font = BUBBLE_FONT
	titleL.TextSize = 20
	titleL.TextXAlignment = Enum.TextXAlignment.Left
	titleL.ZIndex = 54
	titleL.Parent = topRow
	createStroke(titleL, Color3.fromRGB(0, 0, 0), 2.5, Enum.ApplyStrokeMode.Contextual)

	local subtitleL = Instance.new("TextLabel")
	subtitleL.Size = UDim2.new(1, -76, 0, 16)
	subtitleL.Position = UDim2.new(0, 72, 0, 36)
	subtitleL.BackgroundTransparency = 1
	subtitleL.Text = "Exclusive Robux Case \u{2022} 1 Spin"
	subtitleL.TextColor3 = accent
	subtitleL.Font = FONT_SUB
	subtitleL.TextSize = 12
	subtitleL.TextXAlignment = Enum.TextXAlignment.Left
	subtitleL.ZIndex = 54
	subtitleL.Parent = topRow

	for i, entry in ipairs(caseData.pool) do
		local effectInfo = Effects.ByName[entry.effect]
		local streamerInfo = Streamers.ById[entry.streamerId]
		local rarityText = streamerInfo and streamerInfo.rarity or "?"
		local effectColor = effectInfo and effectInfo.color or Color3.fromRGB(200, 200, 200)

		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 28)
		row.BackgroundColor3 = (i % 2 == 0) and Color3.fromRGB(40, 32, 60) or Color3.fromRGB(32, 24, 50)
		row.BackgroundTransparency = 0.15
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.ZIndex = 53
		row.Parent = card
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

		local nameL2 = Instance.new("TextLabel")
		nameL2.Size = UDim2.new(0.5, 0, 1, 0)
		nameL2.Position = UDim2.new(0, 12, 0, 0)
		nameL2.BackgroundTransparency = 1
		nameL2.Text = entry.label
		nameL2.TextColor3 = effectColor
		nameL2.Font = BUBBLE_FONT
		nameL2.TextSize = 14
		nameL2.TextXAlignment = Enum.TextXAlignment.Left
		nameL2.ZIndex = 54
		nameL2.Parent = row
		createStroke(nameL2, Color3.fromRGB(0, 0, 0), 1.5, Enum.ApplyStrokeMode.Contextual)

		local rarityL = Instance.new("TextLabel")
		rarityL.Size = UDim2.new(0.22, 0, 1, 0)
		rarityL.Position = UDim2.new(0.5, 0, 0, 0)
		rarityL.BackgroundTransparency = 1
		rarityL.Text = rarityText
		rarityL.TextColor3 = Color3.fromRGB(200, 195, 220)
		rarityL.Font = FONT_SUB
		rarityL.TextSize = 12
		rarityL.TextXAlignment = Enum.TextXAlignment.Center
		rarityL.ZIndex = 54
		rarityL.Parent = row

		local oddsL = Instance.new("TextLabel")
		oddsL.Size = UDim2.new(0.28, -12, 1, 0)
		oddsL.Position = UDim2.new(0.72, 0, 0, 0)
		oddsL.BackgroundTransparency = 1
		oddsL.Text = entry.weight .. "%"
		oddsL.TextColor3 = Color3.fromRGB(255, 255, 100)
		oddsL.Font = BUBBLE_FONT
		oddsL.TextSize = 15
		oddsL.TextXAlignment = Enum.TextXAlignment.Right
		oddsL.ZIndex = 54
		oddsL.Parent = row
		createStroke(oddsL, Color3.fromRGB(0, 0, 0), 1.5, Enum.ApplyStrokeMode.Contextual)
	end

	local btnWrap = Instance.new("Frame")
	btnWrap.Size = UDim2.new(1, 0, 0, 50)
	btnWrap.BackgroundTransparency = 1
	btnWrap.LayoutOrder = 100
	btnWrap.ZIndex = 53
	btnWrap.Parent = card

	local btn = Instance.new("TextButton")
	btn.Name = "BuyBtn"
	btn.Size = UDim2.new(0.55, 0, 0, 42)
	btn.Position = UDim2.new(0.5, 0, 0.5, 0)
	btn.AnchorPoint = Vector2.new(0.5, 0.5)
	btn.BackgroundColor3 = Color3.fromRGB(50, 210, 80)
	btn.Text = "R$ ..."
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Font = BUBBLE_FONT
	btn.TextSize = 18
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.ZIndex = 54
	btn.Parent = btnWrap
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 12)
	createStroke(btn, Color3.fromRGB(30, 160, 55), 2.5)
	createStroke(btn, Color3.fromRGB(0, 0, 0), 1.5, Enum.ApplyStrokeMode.Contextual)

	fetchProductPriceAsync(productId, btn)

	local btnGrad = Instance.new("UIGradient")
	btnGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 255, 210)),
	})
	btnGrad.Rotation = 90
	btnGrad.Parent = btn

	local bTI = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, bTI, {
			BackgroundColor3 = Color3.fromRGB(80, 255, 120),
			Size = UDim2.new(0.58, 0, 0, 46),
		}):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, bTI, {
			BackgroundColor3 = Color3.fromRGB(50, 210, 80),
			Size = UDim2.new(0.55, 0, 0, 42),
		}):Play()
	end)
	btn.MouseButton1Click:Connect(function()
		if isInventoryFull() then
			showStoreToast("Inventory & storage are full!")
			return
		end
		if productId and productId > 0 then
			MarketplaceService:PromptProductPurchase(player, productId)
		end
	end)

	return card
end

-------------------------------------------------
-- TAB CONTENT BUILDERS
-------------------------------------------------

local function clearScroll()
	if not scroll then return end
	for _, child in ipairs(scroll:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	scroll.CanvasPosition = Vector2.new(0, 0)
end

local function buildPremiumTab()
	buildPremiumCard(scroll, {
		key = "VIP",
		title = "VIP Pass",
		desc = "1.5x Luck + 1.5x Money Earned",
		icon = "\u{1F451}",
		accent = Color3.fromRGB(255, 200, 60),
		productId = Economy.Products.VIP,
		checkOwned = function() return HUDController.Data.hasVIP == true end,
		order = 1,
	})

	buildPremiumCard(scroll, {
		key = "X2Luck",
		title = "2x Luck",
		desc = "Permanently double your luck",
		icon = "\u{1F340}",
		accent = Color3.fromRGB(80, 220, 255),
		productId = Economy.Products.X2Luck,
		checkOwned = function() return HUDController.Data.hasX2Luck == true end,
		order = 2,
	})
end

local function buildGemsTab()
	for i, pack in ipairs(Economy.GemPacks) do
		buildGemCard(scroll, {
			key = pack.key,
			label = pack.label,
			productId = Economy.Products[pack.key],
			order = i,
		})
	end
end

local function buildCasesTab()
	for i, caseData in ipairs(EnhancedCases.List) do
		buildEnhancedCaseCard(scroll, caseData, i)
	end
end

local TAB_BUILDERS = {
	Premium = buildPremiumTab,
	Gems    = buildGemsTab,
	Cases   = buildCasesTab,
}

-------------------------------------------------
-- TAB STYLING
-------------------------------------------------

local INACTIVE_BG    = Color3.fromRGB(40, 32, 60)
local INACTIVE_TEXT  = Color3.fromRGB(160, 150, 190)
local INACTIVE_STROKE = Color3.fromRGB(60, 50, 85)

local function updateTabStyles()
	for _, def in ipairs(TAB_DEFS) do
		local btn = tabButtons[def.id]
		if not btn then continue end
		local active = (currentTab == def.id)
		local stroke = btn:FindFirstChildOfClass("UIStroke")

		if active then
			btn.BackgroundColor3 = def.activeColor
			btn.TextColor3 = Color3.new(1, 1, 1)
			if stroke then stroke.Color = def.accent end
		else
			btn.BackgroundColor3 = INACTIVE_BG
			btn.TextColor3 = INACTIVE_TEXT
			if stroke then stroke.Color = INACTIVE_STROKE end
		end
	end
end

local function switchTab(tabId)
	if currentTab == tabId then return end
	currentTab = tabId
	updateTabStyles()
	clearScroll()
	local builder = TAB_BUILDERS[tabId]
	if builder then builder() end
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
	Instance.new("UICorner", modalFrame).CornerRadius = UDim.new(0, 22)
	UIHelper.SinkInput(modalFrame)

	local modalGrad = Instance.new("UIGradient")
	modalGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 22, 55)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(18, 14, 32)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 8, 22)),
	})
	modalGrad.Rotation = 170
	modalGrad.Parent = modalFrame

	createStroke(modalFrame, Color3.fromRGB(120, 80, 200), 3)
	UIHelper.CreateShadow(modalFrame)
	UIHelper.MakeResponsiveModal(modalFrame, MODAL_W, MODAL_H)

	-- Top bar background
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.Size = UDim2.new(1, 0, 0, 70)
	topBar.BackgroundColor3 = Color3.fromRGB(25, 18, 50)
	topBar.BackgroundTransparency = 0.3
	topBar.BorderSizePixel = 0
	topBar.ZIndex = 52
	topBar.Parent = modalFrame

	local topBarGrad = Instance.new("UIGradient")
	topBarGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 30, 90)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 14, 40)),
	})
	topBarGrad.Rotation = 90
	topBarGrad.Parent = topBar

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(0.5, 0, 0, 38)
	title.Position = UDim2.new(0, 24, 0, 8)
	title.BackgroundTransparency = 1
	title.Text = "STORE"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = BUBBLE_FONT
	title.TextSize = 34
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 53
	title.Parent = modalFrame
	createStroke(title, Color3.fromRGB(80, 40, 160), 3, Enum.ApplyStrokeMode.Contextual)

	-- Subtitle
	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(0.5, 0, 0, 16)
	sub.Position = UDim2.new(0, 26, 0, 46)
	sub.BackgroundTransparency = 1
	sub.Text = "Premium upgrades, gem packs & exclusive cases"
	sub.TextColor3 = Color3.fromRGB(180, 160, 220)
	sub.Font = FONT_SUB
	sub.TextSize = 12
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.ZIndex = 53
	sub.Parent = modalFrame

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 44, 0, 44)
	closeBtn.Position = UDim2.new(1, -16, 0, 13)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = BUBBLE_FONT
	closeBtn.TextSize = 24
	closeBtn.BorderSizePixel = 0
	closeBtn.AutoButtonColor = false
	closeBtn.ZIndex = 55
	closeBtn.Parent = modalFrame
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1, 0)
	createStroke(closeBtn, Color3.fromRGB(180, 30, 30), 2.5)
	createStroke(closeBtn, Color3.fromRGB(100, 0, 0), 1.5, Enum.ApplyStrokeMode.Contextual)

	local closeBounce = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	closeBtn.MouseEnter:Connect(function()
		TweenService:Create(closeBtn, closeBounce, { Size = UDim2.new(0, 50, 0, 50), BackgroundColor3 = Color3.fromRGB(255, 75, 75) }):Play()
	end)
	closeBtn.MouseLeave:Connect(function()
		TweenService:Create(closeBtn, closeBounce, { Size = UDim2.new(0, 44, 0, 44), BackgroundColor3 = Color3.fromRGB(220, 50, 50) }):Play()
	end)
	closeBtn.MouseButton1Click:Connect(function()
		StoreController.Close()
	end)

	-- Divider below header
	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(1, -30, 0, 2)
	divider.Position = UDim2.new(0.5, 0, 0, 70)
	divider.AnchorPoint = Vector2.new(0.5, 0)
	divider.BackgroundColor3 = Color3.fromRGB(120, 80, 200)
	divider.BackgroundTransparency = 0.4
	divider.BorderSizePixel = 0
	divider.ZIndex = 52
	divider.Parent = modalFrame
	Instance.new("UICorner", divider).CornerRadius = UDim.new(1, 0)

	local divGrad = Instance.new("UIGradient")
	divGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 0.9),
	})
	divGrad.Parent = divider

	-------------------------------------------------
	-- TAB ROW
	-------------------------------------------------
	local tabRow = Instance.new("Frame")
	tabRow.Name = "TabRow"
	tabRow.Size = UDim2.new(1, -24, 0, 38)
	tabRow.Position = UDim2.new(0.5, 0, 0, 78)
	tabRow.AnchorPoint = Vector2.new(0.5, 0)
	tabRow.BackgroundTransparency = 1
	tabRow.ZIndex = 52
	tabRow.Parent = modalFrame

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	tabLayout.Padding = UDim.new(0, 10)
	tabLayout.Parent = tabRow

	local hoverTI = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	for _, def in ipairs(TAB_DEFS) do
		local btn = Instance.new("TextButton")
		btn.Name = "Tab_" .. def.id
		btn.Size = UDim2.new(0, 160, 0, 34)
		btn.BackgroundColor3 = INACTIVE_BG
		btn.Text = def.label
		btn.TextColor3 = INACTIVE_TEXT
		btn.Font = BUBBLE_FONT
		btn.TextSize = 17
		btn.BorderSizePixel = 0
		btn.AutoButtonColor = false
		btn.ZIndex = 53
		btn.Parent = tabRow
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)
		createStroke(btn, INACTIVE_STROKE, 1.5)

		btn.MouseEnter:Connect(function()
			if currentTab == def.id then return end
			TweenService:Create(btn, hoverTI, { BackgroundColor3 = Color3.fromRGB(55, 45, 80) }):Play()
		end)
		btn.MouseLeave:Connect(function()
			if currentTab == def.id then return end
			TweenService:Create(btn, hoverTI, { BackgroundColor3 = INACTIVE_BG }):Play()
		end)
		btn.MouseButton1Click:Connect(function()
			switchTab(def.id)
		end)

		tabButtons[def.id] = btn
	end

	-------------------------------------------------
	-- SCROLL CONTENT AREA
	-------------------------------------------------
	scroll = Instance.new("ScrollingFrame")
	scroll.Name = "StoreScroll"
	scroll.Size = UDim2.new(1, -20, 1, -128)
	scroll.Position = UDim2.new(0.5, 0, 0, 122)
	scroll.AnchorPoint = Vector2.new(0.5, 0)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = Color3.fromRGB(120, 80, 200)
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ZIndex = 51
	scroll.Parent = modalFrame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.Parent = scroll

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 16)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = scroll

	-- Build initial tab
	updateTabStyles()
	buildPremiumTab()
end

-------------------------------------------------
-- OPEN / CLOSE
-------------------------------------------------

function StoreController.Open(tabId)
	if isOpen then return end
	if tabId and TAB_BUILDERS[tabId] then
		currentTab = tabId
	end
	isOpen = true
	overlay.Visible = true
	modalFrame.Visible = true

	clearScroll()
	local builder = TAB_BUILDERS[currentTab]
	if builder then builder() end
	updateTabStyles()

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
