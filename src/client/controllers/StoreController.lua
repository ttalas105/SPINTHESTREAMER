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

local BUBBLE_FONT = Enum.Font.FredokaOne
local FONT_SUB = Enum.Font.GothamBold
local MODAL_BG = Color3.fromRGB(71, 136, 218)
local CARD_BG = Color3.fromRGB(19, 55, 104)
local CARD_BORDER = Color3.fromRGB(76, 243, 255)
local MODAL_W = 920
local MODAL_H = 760

local HOTBAR_MAX = 9
local STORAGE_MAX = 200

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

local function formatWithCommas(value)
	local n = tonumber(value) or 0
	local rounded = math.floor(n + 0.5)
	local s = tostring(rounded)
	local out = s
	while true do
		local nextOut, count = out:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		out = nextOut
		if count == 0 then break end
	end
	return out
end

local function setBuyText(btn, prefix, amountText)
	if not btn or not btn.Parent then return end
	btn.Text = (prefix or "BUY FOR") .. "\nR$ " .. tostring(amountText or "...")
end

local function fetchProductPriceAsync(productId, btn, applyPrice)
	if not productId or productId == 0 then return end
	if productPriceCache[productId] then
		if btn and btn.Parent then
			if applyPrice then
				applyPrice(btn, productPriceCache[productId])
			else
				btn.Text = "R$ " .. productPriceCache[productId]
			end
		end
		return
	end
	task.spawn(function()
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, productId, Enum.InfoType.Product)
		if ok and info and info.PriceInRobux then
			productPriceCache[productId] = tostring(info.PriceInRobux)
			if btn and btn.Parent then
				if applyPrice then
					applyPrice(btn, info.PriceInRobux)
				else
					btn.Text = "R$ " .. info.PriceInRobux
				end
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
-- SHOP CARD (mockup style for robux products)
-------------------------------------------------

local function buildRobuxShopCard(parent, cfg)
	local card = Instance.new("Frame")
	card.Name = cfg.key .. "Card"
	card.Size = UDim2.new(0, 268, 0, 252)
	card.BackgroundColor3 = cfg.cardColor or CARD_BG
	card.BorderSizePixel = 0
	card.LayoutOrder = cfg.order
	card.ZIndex = 52
	card.Parent = parent
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 18)
	createStroke(card, cfg.borderColor or CARD_BORDER, 3)
	createStroke(card, Color3.fromRGB(18, 26, 50), 1.2, Enum.ApplyStrokeMode.Contextual)

	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, cfg.gradTop or Color3.fromRGB(31, 80, 151)),
		ColorSequenceKeypoint.new(1, cfg.gradBottom or Color3.fromRGB(18, 51, 100)),
	})
	grad.Rotation = 90
	grad.Parent = card

	local iconFrame = Instance.new("Frame")
	iconFrame.Name = "IconFrame"
	iconFrame.Size = UDim2.new(0, 108, 0, 98)
	iconFrame.Position = UDim2.new(0.08, 0, 0.08, 0)
	iconFrame.BackgroundColor3 = Color3.fromRGB(7, 19, 47)
	iconFrame.BorderSizePixel = 0
	iconFrame.ZIndex = 53
	iconFrame.ClipsDescendants = true
	iconFrame.Parent = card
	Instance.new("UICorner", iconFrame).CornerRadius = UDim.new(0, 16)
	createStroke(iconFrame, cfg.iconBorderColor or Color3.fromRGB(73, 208, 255), 2.2)

	local iconBgGradient = Instance.new("UIGradient")
	iconBgGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 62, 117)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(7, 19, 47)),
	})
	iconBgGradient.Rotation = 90
	iconBgGradient.Parent = iconFrame

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(1, -10, 1, -10)
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
	fallback.Text = cfg.fallbackIcon or "?"
	fallback.TextColor3 = cfg.fallbackColor or Color3.fromRGB(230, 245, 255)
	fallback.Font = BUBBLE_FONT
	fallback.TextSize = 42
	fallback.ZIndex = 54
	fallback.Parent = iconFrame

	fetchProductIconAsync(cfg.productId, icon, fallback)

	local nameL = Instance.new("TextLabel")
	nameL.Size = UDim2.new(1, -18, 0, 38)
	nameL.Position = UDim2.new(0, 9, 0, 114)
	nameL.BackgroundTransparency = 1
	nameL.Text = cfg.title
	nameL.TextColor3 = Color3.new(1, 1, 1)
	nameL.Font = BUBBLE_FONT
	nameL.TextWrapped = true
	nameL.TextSize = 32
	nameL.TextXAlignment = Enum.TextXAlignment.Left
	nameL.TextYAlignment = Enum.TextYAlignment.Top
	nameL.ZIndex = 53
	nameL.Parent = card
	createStroke(nameL, Color3.fromRGB(13, 22, 46), 3, Enum.ApplyStrokeMode.Contextual)

	local descL = Instance.new("TextLabel")
	descL.Size = UDim2.new(1, -18, 0, 17)
	descL.Position = UDim2.new(0, 9, 0, 166)
	descL.BackgroundTransparency = 1
	descL.Text = cfg.desc or ""
	descL.TextColor3 = cfg.descColor or Color3.fromRGB(188, 225, 255)
	descL.Font = FONT_SUB
	descL.TextSize = 13
	descL.TextXAlignment = Enum.TextXAlignment.Left
	descL.ZIndex = 53
	descL.Parent = card

	if cfg.badgeText and cfg.badgeText ~= "" then
		local badge = Instance.new("TextLabel")
		badge.Size = UDim2.new(1, -18, 0, 16)
		badge.Position = UDim2.new(0, 9, 0, 183)
		badge.BackgroundTransparency = 1
		badge.Text = cfg.badgeText
		badge.TextColor3 = cfg.badgeColor or Color3.fromRGB(255, 221, 110)
		badge.Font = BUBBLE_FONT
		badge.TextSize = 12
		badge.TextXAlignment = Enum.TextXAlignment.Left
		badge.ZIndex = 53
		badge.Parent = card
		createStroke(badge, Color3.fromRGB(13, 22, 46), 2, Enum.ApplyStrokeMode.Contextual)
	end

	local buyBtn = Instance.new("TextButton")
	buyBtn.Name = "BuyBtn"
	buyBtn.Size = UDim2.new(0.84, 0, 0, 50)
	buyBtn.Position = UDim2.new(0.5, 0, 1, -11)
	buyBtn.AnchorPoint = Vector2.new(0.5, 1)
	buyBtn.BackgroundColor3 = cfg.owned and Color3.fromRGB(45, 140, 64) or Color3.fromRGB(85, 219, 78)
	buyBtn.TextColor3 = Color3.new(1, 1, 1)
	buyBtn.Text = cfg.owned and "OWNED" or "BUY FOR\nR$ ..."
	buyBtn.Font = BUBBLE_FONT
	buyBtn.TextSize = cfg.owned and 18 or 20
	buyBtn.TextWrapped = true
	buyBtn.AutoButtonColor = false
	buyBtn.BorderSizePixel = 0
	buyBtn.ZIndex = 54
	buyBtn.Parent = card
	Instance.new("UICorner", buyBtn).CornerRadius = UDim.new(0, 12)
	createStroke(buyBtn, cfg.owned and Color3.fromRGB(33, 100, 47) or Color3.fromRGB(38, 146, 58), 2.5)
	createStroke(buyBtn, Color3.fromRGB(255, 255, 255), 1.2, Enum.ApplyStrokeMode.Contextual)

	if cfg.owned then
		buyBtn.TextColor3 = Color3.fromRGB(193, 255, 201)
	else
		if cfg.priceText then
			setBuyText(buyBtn, "BUY FOR", cfg.priceText)
		elseif cfg.productId and cfg.productId > 0 then
			fetchProductPriceAsync(cfg.productId, buyBtn, function(button, rawPrice)
				setBuyText(button, "BUY FOR", formatWithCommas(rawPrice))
			end)
		end

		local hoverTI = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		buyBtn.MouseEnter:Connect(function()
			TweenService:Create(buyBtn, hoverTI, {
				BackgroundColor3 = Color3.fromRGB(107, 240, 98),
				Size = UDim2.new(0.88, 0, 0, 53),
			}):Play()
		end)
		buyBtn.MouseLeave:Connect(function()
			TweenService:Create(buyBtn, hoverTI, {
				BackgroundColor3 = Color3.fromRGB(85, 219, 78),
				Size = UDim2.new(0.84, 0, 0, 50),
			}):Play()
		end)
		buyBtn.MouseButton1Click:Connect(function()
			if cfg.onPurchase then
				cfg.onPurchase()
				return
			end
			if cfg.productId and cfg.productId > 0 then
				MarketplaceService:PromptProductPurchase(player, cfg.productId)
			end
		end)
	end

	return card
end

local function buildPremiumCard(parent, cfg)
	local owned = cfg.checkOwned()
	return buildRobuxShopCard(parent, {
		key = cfg.key,
		title = cfg.title,
		desc = cfg.desc,
		badgeText = "PERMANENT",
		badgeColor = Color3.fromRGB(255, 229, 133),
		fallbackIcon = cfg.icon,
		fallbackColor = cfg.accent,
		borderColor = Color3.fromRGB(255, 227, 118),
		iconBorderColor = cfg.accent,
		gradTop = owned and Color3.fromRGB(54, 106, 73) or Color3.fromRGB(75, 60, 130),
		gradBottom = owned and Color3.fromRGB(27, 65, 41) or Color3.fromRGB(35, 31, 93),
		cardColor = owned and Color3.fromRGB(35, 79, 51) or Color3.fromRGB(40, 41, 112),
		productId = cfg.productId,
		owned = owned,
		order = cfg.order,
	})
end

-------------------------------------------------
-- GEM PACK CARD
-------------------------------------------------

local function buildGemCard(parent, cfg)
	return buildRobuxShopCard(parent, {
		key = "GemPack_" .. cfg.key,
		title = cfg.label,
		desc = "",
		fallbackIcon = "\u{1F48E}",
		fallbackColor = Color3.fromRGB(161, 229, 255),
		borderColor = CARD_BORDER,
		iconBorderColor = Color3.fromRGB(89, 216, 255),
		gradTop = Color3.fromRGB(31, 88, 154),
		gradBottom = Color3.fromRGB(18, 55, 105),
		cardColor = CARD_BG,
		productId = cfg.productId,
		owned = false,
		order = cfg.order,
	})
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
		ColorSequenceKeypoint.new(0, Color3.fromRGB(84, 116, 208)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(64, 88, 170)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(48, 68, 133)),
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
		child:Destroy()
	end
	scroll.CanvasPosition = Vector2.new(0, 0)
end

local function setupShowcaseRoot()
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.Parent = scroll

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 14)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = scroll
end

local function createRowFrame(order, height)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, height)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.ZIndex = 52
	row.Parent = scroll
	return row
end

local function makeGreenBuyButton(parent, widthScale, yOffset, productId, onClick, priceOverride)
	local btn = Instance.new("TextButton")
	btn.Name = "BuyBtn"
	btn.Size = UDim2.new(widthScale or 0.62, 0, 0, 52)
	btn.Position = UDim2.new(0.5, 0, 1, yOffset or -10)
	btn.AnchorPoint = Vector2.new(0.5, 1)
	btn.BackgroundColor3 = Color3.fromRGB(93, 215, 84)
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Font = BUBBLE_FONT
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextSize = 22
	btn.TextWrapped = true
	btn.Text = "BUY FOR\nR$ ..."
	btn.TextStrokeColor3 = Color3.fromRGB(28, 84, 30)
	btn.TextStrokeTransparency = 0.3
	btn.ZIndex = 55
	btn.Parent = parent
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 14)
	createStroke(btn, Color3.fromRGB(59, 149, 56), 2.6)
	createStroke(btn, Color3.fromRGB(255, 255, 255), 1.2, Enum.ApplyStrokeMode.Contextual)

	if priceOverride then
		setBuyText(btn, "BUY FOR", formatWithCommas(priceOverride))
	else
		fetchProductPriceAsync(productId, btn, function(button, rawPrice)
			setBuyText(button, "BUY FOR", formatWithCommas(rawPrice))
		end)
	end

	local hoverTI = TweenInfo.new(0.11, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, hoverTI, {
			Size = UDim2.new((widthScale or 0.62) + 0.03, 0, 0, 55),
			BackgroundColor3 = Color3.fromRGB(111, 236, 101),
		}):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, hoverTI, {
			Size = UDim2.new(widthScale or 0.62, 0, 0, 52),
			BackgroundColor3 = Color3.fromRGB(93, 215, 84),
		}):Play()
	end)
	btn.MouseButton1Click:Connect(function()
		if onClick then
			onClick()
		elseif productId and productId > 0 then
			MarketplaceService:PromptProductPurchase(player, productId)
		end
	end)

	return btn
end

local function buildCaseShowCard(parent, caseData, xScale, buttonColor, priceOverride)
	local productId = Economy.Products[caseData.key]
	local card = Instance.new("Frame")
	card.Size = UDim2.new(0.485, 0, 1, 0)
	card.Position = UDim2.new(xScale, 0, 0, 0)
	card.BackgroundColor3 = Color3.fromRGB(20, 38, 125)
	card.BorderSizePixel = 0
	card.ZIndex = 53
	card.Parent = parent
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 18)
	createStroke(card, Color3.fromRGB(233, 219, 124), 2.8)
	createStroke(card, Color3.fromRGB(70, 98, 201), 1.5, Enum.ApplyStrokeMode.Contextual)

	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(32, 64, 163)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 35, 106)),
	})
	grad.Rotation = 90
	grad.Parent = card

	local iconBubble = Instance.new("Frame")
	iconBubble.Size = UDim2.new(0, 76, 0, 76)
	iconBubble.Position = UDim2.new(0, 10, 0, 10)
	iconBubble.BackgroundColor3 = Color3.fromRGB(17, 23, 82)
	iconBubble.BorderSizePixel = 0
	iconBubble.ZIndex = 54
	iconBubble.Parent = card
	Instance.new("UICorner", iconBubble).CornerRadius = UDim.new(1, 0)
	createStroke(iconBubble, caseData.accent, 2.4)

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(1, -8, 1, -8)
	icon.Position = UDim2.new(0.5, 0, 0.5, 0)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Visible = false
	icon.ZIndex = 55
	icon.Parent = iconBubble
	fetchProductIconAsync(productId, icon, nil)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -96, 0, 34)
	title.Position = UDim2.new(0, 92, 0, 12)
	title.BackgroundTransparency = 1
	title.Text = caseData.name
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Font = BUBBLE_FONT
	title.TextSize = 21
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextWrapped = true
	title.ZIndex = 54
	title.Parent = card
	createStroke(title, Color3.fromRGB(0, 0, 0), 2.6, Enum.ApplyStrokeMode.Contextual)

	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, -96, 0, 16)
	subtitle.Position = UDim2.new(0, 92, 0, 46)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "Exclusive Robux Case • 1 Spin"
	subtitle.TextColor3 = Color3.fromRGB(210, 230, 255)
	subtitle.Font = FONT_SUB
	subtitle.TextSize = 12
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.ZIndex = 54
	subtitle.Parent = card

	local hero = Instance.new("ImageLabel")
	hero.Size = UDim2.new(0, 120, 0, 94)
	hero.Position = UDim2.new(0.5, 0, 0, 76)
	hero.AnchorPoint = Vector2.new(0.5, 0)
	hero.BackgroundTransparency = 1
	hero.ScaleType = Enum.ScaleType.Fit
	hero.Visible = false
	hero.ZIndex = 54
	hero.Parent = card
	fetchProductIconAsync(productId, hero, nil)

	for i, entry in ipairs(caseData.pool) do
		local streamerInfo = Streamers.ById[entry.streamerId]
		local rarityText = streamerInfo and streamerInfo.rarity or "?"

		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -14, 0, 24)
		row.Position = UDim2.new(0, 7, 0, 174 + ((i - 1) * 24))
		row.BackgroundTransparency = 1
		row.ZIndex = 54
		row.Parent = card

		local n = Instance.new("TextLabel")
		n.Size = UDim2.new(0.46, 0, 1, 0)
		n.BackgroundTransparency = 1
		n.Text = entry.streamerId
		n.TextColor3 = Color3.new(1, 1, 1)
		n.Font = BUBBLE_FONT
		n.TextSize = 19
		n.TextXAlignment = Enum.TextXAlignment.Left
		n.ZIndex = 55
		n.Parent = row
		createStroke(n, Color3.fromRGB(0, 0, 0), 2.4, Enum.ApplyStrokeMode.Contextual)

		local rarity = Instance.new("TextLabel")
		rarity.Size = UDim2.new(0.25, 0, 1, 0)
		rarity.Position = UDim2.new(0.49, 0, 0, 0)
		rarity.BackgroundTransparency = 1
		rarity.Text = rarityText
		rarity.TextColor3 = Color3.fromRGB(228, 178, 255)
		rarity.Font = BUBBLE_FONT
		rarity.TextSize = 16
		rarity.TextXAlignment = Enum.TextXAlignment.Center
		rarity.ZIndex = 55
		rarity.Parent = row
		createStroke(rarity, Color3.fromRGB(0, 0, 0), 1.8, Enum.ApplyStrokeMode.Contextual)

		local odds = Instance.new("TextLabel")
		odds.Size = UDim2.new(0.29, 0, 1, 0)
		odds.Position = UDim2.new(0.71, 0, 0, 0)
		odds.BackgroundTransparency = 1
		odds.Text = tostring(entry.weight) .. "%"
		odds.TextColor3 = (entry.weight <= 5) and Color3.fromRGB(255, 112, 120) or Color3.fromRGB(130, 255, 145)
		odds.Font = BUBBLE_FONT
		odds.TextSize = 21
		odds.TextXAlignment = Enum.TextXAlignment.Right
		odds.ZIndex = 55
		odds.Parent = row
		createStroke(odds, Color3.fromRGB(0, 0, 0), 2.4, Enum.ApplyStrokeMode.Contextual)
	end

	local btn = makeGreenBuyButton(card, 0.56, -10, productId, function()
		if isInventoryFull() then
			showStoreToast("Inventory & storage are full!")
			return
		end
		if productId and productId > 0 then
			MarketplaceService:PromptProductPurchase(player, productId)
		end
	end, priceOverride)
	btn.BackgroundColor3 = buttonColor

	return card
end

local function buildGemTile(parent, xScale, pack, order, priceOverride)
	local productId = Economy.Products[pack.key]
	local tile = Instance.new("Frame")
	tile.Size = UDim2.new(0.32, 0, 1, 0)
	tile.Position = UDim2.new(xScale, 0, 0, 0)
	tile.BackgroundColor3 = Color3.fromRGB(15, 82, 116)
	tile.BorderSizePixel = 0
	tile.ZIndex = 53
	tile.Parent = parent
	Instance.new("UICorner", tile).CornerRadius = UDim.new(0, 16)
	createStroke(tile, CARD_BORDER, 3)

	local iconBox = Instance.new("Frame")
	iconBox.Size = UDim2.new(0, 108, 0, 90)
	iconBox.Position = UDim2.new(0, 12, 0, 12)
	iconBox.BackgroundColor3 = Color3.fromRGB(7, 19, 47)
	iconBox.BorderSizePixel = 0
	iconBox.ZIndex = 54
	iconBox.Parent = tile
	Instance.new("UICorner", iconBox).CornerRadius = UDim.new(0, 14)
	createStroke(iconBox, Color3.fromRGB(77, 224, 255), 2.2)

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(1, -8, 1, -8)
	icon.Position = UDim2.new(0.5, 0, 0.5, 0)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Visible = false
	icon.ZIndex = 55
	icon.Parent = iconBox
	fetchProductIconAsync(productId, icon, nil)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -130, 0, 56)
	title.Position = UDim2.new(0, 126, 0, 16)
	title.BackgroundTransparency = 1
	title.Text = pack.label:gsub(" ", "\n", 1)
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Font = BUBBLE_FONT
	title.TextSize = 28
	title.TextWrapped = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Top
	title.ZIndex = 55
	title.Parent = tile
	createStroke(title, Color3.fromRGB(0, 0, 0), 2.8, Enum.ApplyStrokeMode.Contextual)

	makeGreenBuyButton(tile, 0.62, -10, productId, nil, priceOverride).LayoutOrder = order
	return tile
end

local function buildPremiumTile(parent, xScale, cfg, priceOverride)
	local productId = cfg.productId
	local owned = cfg.owned
	local tile = Instance.new("Frame")
	tile.Size = UDim2.new(0.485, 0, 1, 0)
	tile.Position = UDim2.new(xScale, 0, 0, 0)
	tile.BackgroundColor3 = Color3.fromRGB(47, 36, 77)
	tile.BorderSizePixel = 0
	tile.ZIndex = 53
	tile.Parent = parent
	Instance.new("UICorner", tile).CornerRadius = UDim.new(0, 18)
	createStroke(tile, Color3.fromRGB(227, 185, 95), 3)

	local iconBox = Instance.new("Frame")
	iconBox.Size = UDim2.new(0, 118, 0, 98)
	iconBox.Position = UDim2.new(0, 14, 0, 12)
	iconBox.BackgroundColor3 = Color3.fromRGB(9, 17, 45)
	iconBox.BorderSizePixel = 0
	iconBox.ZIndex = 54
	iconBox.Parent = tile
	Instance.new("UICorner", iconBox).CornerRadius = UDim.new(0, 14)
	createStroke(iconBox, Color3.fromRGB(250, 209, 103), 2.2)

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(1, -8, 1, -8)
	icon.Position = UDim2.new(0.5, 0, 0.5, 0)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Visible = false
	icon.ZIndex = 55
	icon.Parent = iconBox
	fetchProductIconAsync(productId, icon, nil)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -145, 0, 42)
	title.Position = UDim2.new(0, 138, 0, 18)
	title.BackgroundTransparency = 1
	title.Text = cfg.title
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Font = BUBBLE_FONT
	title.TextSize = 43
	title.TextWrapped = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 55
	title.Parent = tile
	createStroke(title, Color3.fromRGB(0, 0, 0), 2.8, Enum.ApplyStrokeMode.Contextual)

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, -145, 0, 44)
	sub.Position = UDim2.new(0, 138, 0, 60)
	sub.BackgroundTransparency = 1
	sub.Text = cfg.desc
	sub.TextColor3 = Color3.fromRGB(255, 232, 146)
	sub.Font = BUBBLE_FONT
	sub.TextSize = 19
	sub.TextWrapped = true
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextYAlignment = Enum.TextYAlignment.Top
	sub.ZIndex = 55
	sub.Parent = tile
	createStroke(sub, Color3.fromRGB(0, 0, 0), 2, Enum.ApplyStrokeMode.Contextual)

	if not owned then
		makeGreenBuyButton(tile, 0.52, -10, productId, nil, priceOverride)
	else
		local ownedL = Instance.new("TextLabel")
		ownedL.Size = UDim2.new(0.52, 0, 0, 52)
		ownedL.Position = UDim2.new(0.5, 0, 1, -10)
		ownedL.AnchorPoint = Vector2.new(0.5, 1)
		ownedL.BackgroundColor3 = Color3.fromRGB(45, 140, 64)
		ownedL.Text = "OWNED"
		ownedL.TextColor3 = Color3.fromRGB(205, 255, 206)
		ownedL.Font = BUBBLE_FONT
		ownedL.TextSize = 24
		ownedL.ZIndex = 55
		ownedL.Parent = tile
		Instance.new("UICorner", ownedL).CornerRadius = UDim.new(0, 14)
		createStroke(ownedL, Color3.fromRGB(33, 100, 47), 2.6)
	end

	return tile
end

local function buildShowcaseTab()
	setupShowcaseRoot()

	local prices = Economy.RobuxPrices

	local premiumRow = createRowFrame(1, 188)
	buildPremiumTile(premiumRow, 0, {
		title = "VIP Pass",
		desc = "1.5x Luck\nPermanent",
		productId = Economy.Products.VIP,
		owned = HUDController.Data.hasVIP == true,
	}, prices.VIP)
	buildPremiumTile(premiumRow, 0.515, {
		title = "2x Luck",
		desc = "2x Luck\nPermanent",
		productId = Economy.Products.X2Luck,
		owned = HUDController.Data.hasX2Luck == true,
	}, prices.X2Luck)

	local caseRow = createRowFrame(2, 336)
	buildCaseShowCard(caseRow, EnhancedCases.List[1], 0, Color3.fromRGB(78, 190, 245), prices.LunarEnhanced)
	buildCaseShowCard(caseRow, EnhancedCases.List[2], 0.515, Color3.fromRGB(100, 206, 85), prices.SolarEnhanced)

	local gemsRow = createRowFrame(3, 188)
	buildGemTile(gemsRow, 0, Economy.GemPacks[1], 1, prices.Gems1K)
	buildGemTile(gemsRow, 0.34, Economy.GemPacks[2], 2, prices.Gems10K)
	buildGemTile(gemsRow, 0.68, Economy.GemPacks[3], 3, prices.Gems100K)
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
	Instance.new("UICorner", modalFrame).CornerRadius = UDim.new(0, 24)
	UIHelper.SinkInput(modalFrame)

	createStroke(modalFrame, Color3.fromRGB(255, 255, 255), 3)
	UIHelper.CreateShadow(modalFrame)
	UIHelper.MakeResponsiveModal(modalFrame, MODAL_W, MODAL_H)

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(0.6, 0, 0, 40)
	title.Position = UDim2.new(0, 26, 0, 10)
	title.BackgroundTransparency = 1
	title.Text = "STORE!"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = BUBBLE_FONT
	title.TextSize = 52
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 53
	title.Parent = modalFrame
	createStroke(title, Color3.fromRGB(24, 40, 88), 3, Enum.ApplyStrokeMode.Contextual)

	-- Subtitle
	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(0.62, 0, 0, 16)
	sub.Position = UDim2.new(0, 28, 0, 56)
	sub.BackgroundTransparency = 1
	sub.Text = "Premium upgrades, gem packs & exclusive cases"
	sub.TextColor3 = Color3.fromRGB(236, 243, 255)
	sub.Font = FONT_SUB
	sub.TextSize = 12
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.ZIndex = 53
	sub.Parent = modalFrame

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 56, 0, 56)
	closeBtn.Position = UDim2.new(1, -16, 0, 12)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(248, 87, 87)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.TextStrokeColor3 = Color3.fromRGB(122, 41, 41)
	closeBtn.TextStrokeTransparency = 0
	closeBtn.Font = BUBBLE_FONT
	closeBtn.TextSize = 34
	closeBtn.BorderSizePixel = 0
	closeBtn.AutoButtonColor = false
	closeBtn.ZIndex = 55
	closeBtn.Parent = modalFrame
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1, 0)
	createStroke(closeBtn, Color3.fromRGB(255, 255, 255), 2.8)
	createStroke(closeBtn, Color3.fromRGB(122, 41, 41), 1.8, Enum.ApplyStrokeMode.Contextual)

	local closeBounce = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	closeBtn.MouseEnter:Connect(function()
		TweenService:Create(closeBtn, closeBounce, { Size = UDim2.new(0, 61, 0, 61), BackgroundColor3 = Color3.fromRGB(255, 107, 107) }):Play()
	end)
	closeBtn.MouseLeave:Connect(function()
		TweenService:Create(closeBtn, closeBounce, { Size = UDim2.new(0, 56, 0, 56), BackgroundColor3 = Color3.fromRGB(248, 87, 87) }):Play()
	end)
	closeBtn.MouseButton1Click:Connect(function()
		StoreController.Close()
	end)

	-------------------------------------------------
	-- SCROLL CONTENT AREA
	-------------------------------------------------
	scroll = Instance.new("ScrollingFrame")
	scroll.Name = "StoreScroll"
	scroll.Size = UDim2.new(1, -20, 1, -102)
	scroll.Position = UDim2.new(0.5, 0, 0, 94)
	scroll.AnchorPoint = Vector2.new(0.5, 0)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = Color3.fromRGB(87, 120, 213)
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ZIndex = 51
	scroll.Parent = modalFrame

	-- Build single store section
	buildShowcaseTab()
end

-------------------------------------------------
-- OPEN / CLOSE
-------------------------------------------------

function StoreController.Open(tabId)
	if isOpen then return end
	isOpen = true
	overlay.Visible = true
	modalFrame.Visible = true

	clearScroll()
	buildShowcaseTab()

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
