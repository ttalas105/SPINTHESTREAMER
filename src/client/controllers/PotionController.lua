--[[
	PotionController.lua
	Client UI for buying potions (shop modal) and showing active potion indicators
	in the bottom-right corner with timer, potion icon, and tier number.
	Includes Divine Potion (premium Robux) section with rainbow design.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local Potions = require(ReplicatedStorage.Shared.Config.Potions)
local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local UIHelper = require(script.Parent.UIHelper)
local HUDController = require(script.Parent.HUDController)

local PotionController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local BuyPotionRequest = RemoteEvents:WaitForChild("BuyPotionRequest")
local BuyPotionResult = RemoteEvents:WaitForChild("BuyPotionResult")
local PotionUpdate = RemoteEvents:WaitForChild("PotionUpdate")
local OpenPotionStandGui = RemoteEvents:WaitForChild("OpenPotionStandGui")

local screenGui
local shopModal
local indicatorContainer
local luckIndicator
local cashIndicator
local divineIndicator
local isShopOpen = false
local divineCountLabel -- shows how many divine potions player owns

-- Exposed active potion data so other controllers (HUD) can read it
PotionController.ActivePotions = {} -- { Luck = {multiplier, tier, remaining}, Cash = ..., Divine = ... }

local BUBBLE_FONT = Enum.Font.FredokaOne

-- Rainbow color sequence for prismatic elements
local RAINBOW_SEQUENCE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
	ColorSequenceKeypoint.new(0.16, Color3.fromRGB(255, 200, 60)),
	ColorSequenceKeypoint.new(0.33, Color3.fromRGB(80, 255, 100)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 200, 255)),
	ColorSequenceKeypoint.new(0.66, Color3.fromRGB(160, 100, 255)),
	ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 100, 200)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 80)),
})

-------------------------------------------------
-- HELPERS
-------------------------------------------------

local function formatTime(seconds)
	local m = math.floor(seconds / 60)
	local s = seconds % 60
	return string.format("%d:%02d", m, s)
end

-------------------------------------------------
-- POTION ICON (kid-friendly bubbly potion bottle)
-------------------------------------------------

local function createPotionIcon(parent, liquidColor, size, isRainbow)
	size = size or 40

	local container = Instance.new("Frame")
	container.Name = "PotionIcon"
	container.Size = UDim2.new(0, size, 0, size)
	container.BackgroundTransparency = 1
	container.Parent = parent

	-- Bottle body
	local bottle = Instance.new("Frame")
	bottle.Name = "Bottle"
	bottle.Size = UDim2.new(0.65, 0, 0.7, 0)
	bottle.Position = UDim2.new(0.5, 0, 0.55, 0)
	bottle.AnchorPoint = Vector2.new(0.5, 0.5)
	bottle.BackgroundColor3 = Color3.fromRGB(220, 230, 240)
	bottle.BorderSizePixel = 0
	bottle.Parent = container
	local bottleCorner = Instance.new("UICorner")
	bottleCorner.CornerRadius = UDim.new(0.3, 0)
	bottleCorner.Parent = bottle
	local bottleStroke = Instance.new("UIStroke")
	bottleStroke.Color = Color3.fromRGB(160, 170, 180)
	bottleStroke.Thickness = 1.5
	bottleStroke.Parent = bottle

	-- Liquid inside
	local liquid = Instance.new("Frame")
	liquid.Name = "Liquid"
	liquid.Size = UDim2.new(0.85, 0, 0.55, 0)
	liquid.Position = UDim2.new(0.5, 0, 0.9, 0)
	liquid.AnchorPoint = Vector2.new(0.5, 1)
	liquid.BackgroundColor3 = liquidColor
	liquid.BorderSizePixel = 0
	liquid.Parent = bottle
	local liquidCorner = Instance.new("UICorner")
	liquidCorner.CornerRadius = UDim.new(0.3, 0)
	liquidCorner.Parent = liquid

	-- Rainbow gradient on liquid if prismatic
	if isRainbow then
		local lGrad = Instance.new("UIGradient")
		lGrad.Color = RAINBOW_SEQUENCE
		lGrad.Rotation = 0
		lGrad.Parent = liquid
		-- Animate the gradient rotation
		task.spawn(function()
			while liquid and liquid.Parent do
				for rot = 0, 360, 2 do
					if not liquid or not liquid.Parent then return end
					lGrad.Rotation = rot
					task.wait(0.03)
				end
			end
		end)
	end

	-- Neck
	local neck = Instance.new("Frame")
	neck.Name = "Neck"
	neck.Size = UDim2.new(0.3, 0, 0.2, 0)
	neck.Position = UDim2.new(0.5, 0, 0.15, 0)
	neck.AnchorPoint = Vector2.new(0.5, 0.5)
	neck.BackgroundColor3 = Color3.fromRGB(200, 210, 220)
	neck.BorderSizePixel = 0
	neck.Parent = container
	local neckCorner = Instance.new("UICorner")
	neckCorner.CornerRadius = UDim.new(0.2, 0)
	neckCorner.Parent = neck
	local neckStroke = Instance.new("UIStroke")
	neckStroke.Color = Color3.fromRGB(160, 170, 180)
	neckStroke.Thickness = 1
	neckStroke.Parent = neck

	-- Cork
	local cork = Instance.new("Frame")
	cork.Name = "Cork"
	cork.Size = UDim2.new(0.2, 0, 0.1, 0)
	cork.Position = UDim2.new(0.5, 0, 0.02, 0)
	cork.AnchorPoint = Vector2.new(0.5, 0)
	cork.BackgroundColor3 = isRainbow and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(160, 110, 60)
	cork.BorderSizePixel = 0
	cork.Parent = container
	local corkCorner = Instance.new("UICorner")
	corkCorner.CornerRadius = UDim.new(0.4, 0)
	corkCorner.Parent = cork

	-- Bubbles
	for i = 1, 3 do
		local bubble = Instance.new("Frame")
		bubble.Name = "Bubble" .. i
		bubble.Size = UDim2.new(0, math.random(3, 6), 0, math.random(3, 6))
		bubble.Position = UDim2.new(math.random(20, 70) / 100, 0, math.random(40, 80) / 100, 0)
		bubble.BackgroundColor3 = Color3.new(1, 1, 1)
		bubble.BackgroundTransparency = 0.4
		bubble.BorderSizePixel = 0
		bubble.Parent = bottle
		local bCorner = Instance.new("UICorner")
		bCorner.CornerRadius = UDim.new(1, 0)
		bCorner.Parent = bubble
	end

	return container
end

-------------------------------------------------
-- ACTIVE POTION INDICATOR (bottom-right corner)
-------------------------------------------------

local function createIndicator(potionType, liquidColor, isRainbow)
	local frame = Instance.new("Frame")
	frame.Name = potionType .. "Indicator"
	frame.Size = UDim2.new(0, 70, 0, 90)
	frame.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel = 0
	frame.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = liquidColor
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = frame

	if isRainbow then
		-- Rainbow stroke effect
		task.spawn(function()
			local colors = {
				Color3.fromRGB(255, 80, 80),
				Color3.fromRGB(255, 200, 60),
				Color3.fromRGB(80, 255, 100),
				Color3.fromRGB(80, 200, 255),
				Color3.fromRGB(160, 100, 255),
				Color3.fromRGB(255, 100, 200),
			}
			local ci = 1
			while frame and frame.Parent do
				stroke.Color = colors[ci]
				ci = ci % #colors + 1
				task.wait(0.5)
			end
		end)
	end

	-- Timer label
	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "Timer"
	timerLabel.Size = UDim2.new(1, 0, 0, 18)
	timerLabel.Position = UDim2.new(0.5, 0, 0, 4)
	timerLabel.AnchorPoint = Vector2.new(0.5, 0)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Text = "0:00"
	timerLabel.TextColor3 = Color3.new(1, 1, 1)
	timerLabel.Font = BUBBLE_FONT
	timerLabel.TextSize = 14
	timerLabel.Parent = frame
	local timerStroke = Instance.new("UIStroke")
	timerStroke.Color = Color3.fromRGB(0, 0, 0)
	timerStroke.Thickness = 1.5
	timerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	timerStroke.Parent = timerLabel

	-- Potion icon
	local icon = createPotionIcon(frame, liquidColor, 40, isRainbow)
	icon.Position = UDim2.new(0.5, 0, 0.45, 0)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)

	-- Tier / type label
	local tierLabel = Instance.new("TextLabel")
	tierLabel.Name = "Tier"
	tierLabel.Size = UDim2.new(1, 0, 0, 18)
	tierLabel.Position = UDim2.new(0.5, 0, 1, -4)
	tierLabel.AnchorPoint = Vector2.new(0.5, 1)
	tierLabel.BackgroundTransparency = 1
	tierLabel.Text = isRainbow and "\u{1F308}" or "1"
	tierLabel.TextColor3 = liquidColor
	tierLabel.Font = BUBBLE_FONT
	tierLabel.TextSize = 16
	tierLabel.Parent = frame
	local tierStroke = Instance.new("UIStroke")
	tierStroke.Color = Color3.fromRGB(0, 0, 0)
	tierStroke.Thickness = 1.5
	tierStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	tierStroke.Parent = tierLabel

	-- Type label
	local typeLabel = Instance.new("TextLabel")
	typeLabel.Name = "TypeLabel"
	typeLabel.Size = UDim2.new(1, 0, 0, 12)
	typeLabel.Position = UDim2.new(0.5, 0, 0, 22)
	typeLabel.AnchorPoint = Vector2.new(0.5, 0)
	typeLabel.BackgroundTransparency = 1
	typeLabel.Text = potionType == "Divine" and "DIVINE" or potionType:upper()
	typeLabel.TextColor3 = liquidColor
	typeLabel.Font = BUBBLE_FONT
	typeLabel.TextSize = 10
	typeLabel.Parent = frame
	local tStroke = Instance.new("UIStroke")
	tStroke.Color = Color3.fromRGB(0, 0, 0)
	tStroke.Thickness = 1
	tStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	tStroke.Parent = typeLabel

	return frame
end

local function updateIndicator(indicator, data, isRainbow)
	if not data or not data.remaining or data.remaining <= 0 then
		indicator.Visible = false
		return
	end
	indicator.Visible = true
	local timerLabel = indicator:FindFirstChild("Timer")
	if timerLabel then timerLabel.Text = formatTime(data.remaining) end
	local tierLabel = indicator:FindFirstChild("Tier")
	if tierLabel then
		tierLabel.Text = isRainbow and "\u{1F308}" or tostring(data.tier or 1)
	end
end

-------------------------------------------------
-- SHOP MODAL
-------------------------------------------------

local MODAL_BG     = Color3.fromRGB(28, 26, 34)
local CARD_BG      = Color3.fromRGB(42, 38, 50)
local CARD_HOVER   = Color3.fromRGB(55, 50, 65)
local FONT_SUB     = Enum.Font.GothamBold
local ROW_H        = 130
local IMG_SIZE     = 100
local MODAL_W      = 500
local MODAL_H      = 540

local RARITY_COLORS = {
	Common  = Color3.fromRGB(180, 180, 190),
	Rare    = Color3.fromRGB(80, 170, 255),
	Epic    = Color3.fromRGB(180, 80, 255),
}

local function buildPotionRow(potionType, potion, parent)
	local rarityColor = RARITY_COLORS[potion.rarity] or RARITY_COLORS.Common

	local row = Instance.new("Frame")
	row.Name = potionType .. "Row_" .. potion.tier
	row.Size = UDim2.new(1, 0, 0, ROW_H)
	row.BackgroundColor3 = CARD_BG
	row.BorderSizePixel = 0
	row.ZIndex = 52
	row.Parent = parent

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 14)
	rowCorner.Parent = row
	local rowStroke = Instance.new("UIStroke")
	rowStroke.Color = Color3.fromRGB(60, 55, 75)
	rowStroke.Thickness = 1.5
	rowStroke.Transparency = 0.3
	rowStroke.Parent = row

	-- Potion image (left side, bordered)
	local imgFrame = Instance.new("Frame")
	imgFrame.Name = "ImageFrame"
	imgFrame.Size = UDim2.new(0, IMG_SIZE, 0, IMG_SIZE)
	imgFrame.Position = UDim2.new(0, 14, 0.5, 0)
	imgFrame.AnchorPoint = Vector2.new(0, 0.5)
	imgFrame.BackgroundColor3 = Color3.fromRGB(35, 32, 45)
	imgFrame.BorderSizePixel = 0
	imgFrame.ZIndex = 53
	imgFrame.Parent = row
	local imgCorner = Instance.new("UICorner")
	imgCorner.CornerRadius = UDim.new(0, 10)
	imgCorner.Parent = imgFrame
	local imgStroke = Instance.new("UIStroke")
	imgStroke.Color = Color3.fromRGB(70, 65, 90)
	imgStroke.Thickness = 1.5
	imgStroke.Parent = imgFrame

	if potion.imageId and potion.imageId ~= "" then
		local img = Instance.new("ImageLabel")
		img.Size = UDim2.new(1, -8, 1, -8)
		img.Position = UDim2.new(0.5, 0, 0.5, 0)
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.BackgroundTransparency = 1
		img.Image = potion.imageId
		img.ScaleType = Enum.ScaleType.Fit
		img.ZIndex = 54
		img.Parent = imgFrame
	else
		local icon = createPotionIcon(imgFrame, potion.color, IMG_SIZE - 16)
		icon.Position = UDim2.new(0.5, 0, 0.5, 0)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.ZIndex = 54
	end

	-- Tier number overlay on image
	local tierBadge = Instance.new("TextLabel")
	tierBadge.Name = "TierBadge"
	tierBadge.Size = UDim2.new(0, 28, 0, 28)
	tierBadge.Position = UDim2.new(0, -2, 1, 2)
	tierBadge.AnchorPoint = Vector2.new(0, 1)
	tierBadge.BackgroundColor3 = Color3.fromRGB(50, 45, 65)
	tierBadge.Text = tostring(potion.tier)
	tierBadge.TextColor3 = Color3.new(1, 1, 1)
	tierBadge.Font = BUBBLE_FONT
	tierBadge.TextSize = 18
	tierBadge.ZIndex = 55
	tierBadge.Parent = imgFrame
	local tbCorner = Instance.new("UICorner")
	tbCorner.CornerRadius = UDim.new(0, 8)
	tbCorner.Parent = tierBadge
	local tbStroke = Instance.new("UIStroke")
	tbStroke.Color = Color3.fromRGB(0, 0, 0)
	tbStroke.Thickness = 1.5
	tbStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	tbStroke.Parent = tierBadge

	local textX = IMG_SIZE + 30

	-- Potion name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, -(textX + 14), 0, 28)
	nameLabel.Position = UDim2.new(0, textX, 0, 14)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = potion.name
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.Font = BUBBLE_FONT
	nameLabel.TextSize = 22
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.ZIndex = 53
	nameLabel.Parent = row
	local nameStroke = Instance.new("UIStroke")
	nameStroke.Color = Color3.fromRGB(0, 0, 0)
	nameStroke.Thickness = 2
	nameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	nameStroke.Parent = nameLabel

	-- Description
	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "DescLabel"
	descLabel.Size = UDim2.new(1, -(textX + 14), 0, 20)
	descLabel.Position = UDim2.new(0, textX, 0, 42)
	descLabel.BackgroundTransparency = 1
	descLabel.Text = potion.desc or ("x" .. potion.multiplier .. " multiplier for 5m")
	descLabel.TextColor3 = potion.color
	descLabel.Font = FONT_SUB
	descLabel.TextSize = 13
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.ZIndex = 53
	descLabel.Parent = row

	-- Rarity label
	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Name = "RarityLabel"
	rarityLabel.Size = UDim2.new(0, 100, 0, 20)
	rarityLabel.Position = UDim2.new(0, textX, 0, 64)
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Text = potion.rarity or "Common"
	rarityLabel.TextColor3 = rarityColor
	rarityLabel.Font = BUBBLE_FONT
	rarityLabel.TextSize = 14
	rarityLabel.TextXAlignment = Enum.TextXAlignment.Left
	rarityLabel.ZIndex = 53
	rarityLabel.Parent = row

	-- Rebirth requirement (if any)
	local rebirthRequired = potion.rebirthRequired or 0
	local currentRebirth = HUDController.Data.rebirthCount or 0
	local isLocked = rebirthRequired > 0 and currentRebirth < rebirthRequired

	if rebirthRequired > 0 then
		local reqLabel = Instance.new("TextLabel")
		reqLabel.Name = "RebirthReq"
		reqLabel.Size = UDim2.new(1, -(textX + 14), 0, 18)
		reqLabel.Position = UDim2.new(0, textX, 0, 82)
		reqLabel.BackgroundTransparency = 1
		reqLabel.Text = "Requires Rebirth " .. rebirthRequired
		reqLabel.TextColor3 = isLocked and Color3.fromRGB(255, 120, 80) or Color3.fromRGB(100, 200, 120)
		reqLabel.Font = FONT_SUB
		reqLabel.TextSize = 12
		reqLabel.TextXAlignment = Enum.TextXAlignment.Left
		reqLabel.ZIndex = 53
		reqLabel.Parent = row
	end

	-- Buy button (bottom right of row)
	local buyBtn = Instance.new("TextButton")
	buyBtn.Name = "BuyBtn"
	buyBtn.Size = UDim2.new(0, 80, 0, 34)
	buyBtn.Position = UDim2.new(1, -14, 1, -14)
	buyBtn.AnchorPoint = Vector2.new(1, 1)
	buyBtn.BackgroundColor3 = isLocked and Color3.fromRGB(70, 65, 80) or Color3.fromRGB(60, 200, 90)
	buyBtn.Text = isLocked and "LOCKED" or "BUY"
	buyBtn.TextColor3 = isLocked and Color3.fromRGB(120, 115, 130) or Color3.new(1, 1, 1)
	buyBtn.Font = BUBBLE_FONT
	buyBtn.TextSize = 16
	buyBtn.BorderSizePixel = 0
	buyBtn.AutoButtonColor = false
	buyBtn.ZIndex = 53
	buyBtn.Parent = row
	local buyCorner = Instance.new("UICorner")
	buyCorner.CornerRadius = UDim.new(0, 10)
	buyCorner.Parent = buyBtn
	local buyStroke = Instance.new("UIStroke")
	buyStroke.Color = isLocked and Color3.fromRGB(50, 48, 60) or Color3.fromRGB(30, 140, 50)
	buyStroke.Thickness = 2
	buyStroke.Parent = buyBtn
	local buyTextStroke = Instance.new("UIStroke")
	buyTextStroke.Color = Color3.fromRGB(10, 50, 20)
	buyTextStroke.Thickness = 1.5
	buyTextStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	buyTextStroke.Parent = buyBtn

	local bounceTI = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	if not isLocked then
		buyBtn.MouseEnter:Connect(function()
			TweenService:Create(row, bounceTI, { BackgroundColor3 = CARD_HOVER }):Play()
			TweenService:Create(buyBtn, bounceTI, { BackgroundColor3 = Color3.fromRGB(80, 235, 115) }):Play()
		end)
		buyBtn.MouseLeave:Connect(function()
			TweenService:Create(row, bounceTI, { BackgroundColor3 = CARD_BG }):Play()
			TweenService:Create(buyBtn, bounceTI, { BackgroundColor3 = Color3.fromRGB(60, 200, 90) }):Play()
		end)
		buyBtn.MouseButton1Click:Connect(function()
			BuyPotionRequest:FireServer(potionType, potion.tier)
		end)
	else
		buyBtn.MouseButton1Click:Connect(function()
			-- Optional: could show a toast "Reach Rebirth X to unlock"
		end)
	end

	return row
end

local function buildShopModal()
	local modal = Instance.new("Frame")
	modal.Name = "PotionShop"
	modal.Size = UDim2.new(0, MODAL_W, 0, MODAL_H)
	modal.Position = UDim2.new(0.5, 0, 0.5, 0)
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.BackgroundColor3 = MODAL_BG
	modal.BorderSizePixel = 0
	modal.Visible = false
	modal.ZIndex = 50
	modal.ClipsDescendants = true
	modal.Parent = screenGui

	local mCorner = Instance.new("UICorner")
	mCorner.CornerRadius = UDim.new(0, 20)
	mCorner.Parent = modal
	local mStroke = Instance.new("UIStroke")
	mStroke.Color = Color3.fromRGB(70, 60, 100)
	mStroke.Thickness = 2.5
	mStroke.Transparency = 0.2
	mStroke.Parent = modal
	UIHelper.CreateShadow(modal)
	UIHelper.MakeResponsiveModal(modal, MODAL_W, MODAL_H)

	-- Header area
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 60)
	header.BackgroundTransparency = 1
	header.ZIndex = 52
	header.Parent = modal

	-- Title: "Potion Shop"
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(0.6, 0, 0, 36)
	title.Position = UDim2.new(0, 20, 0, 10)
	title.BackgroundTransparency = 1
	title.Text = "Potion Shop"
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Font = BUBBLE_FONT
	title.TextSize = 30
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 52
	title.Parent = header
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.fromRGB(0, 0, 0)
	titleStroke.Thickness = 2.5
	titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	titleStroke.Parent = title

	-- Subtitle
	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(0.5, 0, 0, 16)
	subtitle.Position = UDim2.new(0, 22, 0, 44)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "5 min per use • stacks time (max 3h)"
	subtitle.TextColor3 = Color3.fromRGB(140, 135, 160)
	subtitle.Font = FONT_SUB
	subtitle.TextSize = 11
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.ZIndex = 52
	subtitle.Parent = header

	-- Close button (red X)
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
	closeBtn.Parent = modal
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(1, 0)
	closeCorner.Parent = closeBtn
	local closeStroke = Instance.new("UIStroke")
	closeStroke.Color = Color3.fromRGB(160, 30, 30)
	closeStroke.Thickness = 2
	closeStroke.Parent = closeBtn
	local closeTextStroke = Instance.new("UIStroke")
	closeTextStroke.Color = Color3.fromRGB(80, 0, 0)
	closeTextStroke.Thickness = 1.5
	closeTextStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	closeTextStroke.Parent = closeBtn

	local closeBounce = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	closeBtn.MouseEnter:Connect(function()
		TweenService:Create(closeBtn, closeBounce, { Size = UDim2.new(0, 48, 0, 48), BackgroundColor3 = Color3.fromRGB(255, 75, 75) }):Play()
	end)
	closeBtn.MouseLeave:Connect(function()
		TweenService:Create(closeBtn, closeBounce, { Size = UDim2.new(0, 42, 0, 42), BackgroundColor3 = Color3.fromRGB(220, 55, 55) }):Play()
	end)
	closeBtn.MouseButton1Click:Connect(function()
		PotionController.CloseShop()
	end)

	-- Divider line
	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(1, -30, 0, 1)
	divider.Position = UDim2.new(0.5, 0, 0, 62)
	divider.AnchorPoint = Vector2.new(0.5, 0)
	divider.BackgroundColor3 = Color3.fromRGB(65, 60, 80)
	divider.BorderSizePixel = 0
	divider.ZIndex = 52
	divider.Parent = modal

	-- Scrollable potion list
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "PotionScroll"
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
	scroll.Parent = modal

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.Padding = UDim.new(0, 10)
	listLayout.Parent = scroll

	local scrollPad = Instance.new("UIPadding")
	scrollPad.PaddingTop = UDim.new(0, 8)
	scrollPad.PaddingBottom = UDim.new(0, 12)
	scrollPad.PaddingLeft = UDim.new(0, 6)
	scrollPad.PaddingRight = UDim.new(0, 6)
	scrollPad.Parent = scroll

	-------------------------------------------------
	-- DIVINE POTION (featured at top, special card)
	-------------------------------------------------
	local prisData = Potions.Divine
	local prisRow = Instance.new("Frame")
	prisRow.Name = "DivineRow"
	prisRow.Size = UDim2.new(1, -24, 0, 180)
	prisRow.BackgroundColor3 = Color3.fromRGB(40, 30, 55)
	prisRow.BorderSizePixel = 0
	prisRow.LayoutOrder = 0
	prisRow.ZIndex = 52
	prisRow.Parent = scroll
	local prCorner = Instance.new("UICorner")
	prCorner.CornerRadius = UDim.new(0, 14)
	prCorner.Parent = prisRow
	local prStroke = Instance.new("UIStroke")
	prStroke.Color = Color3.fromRGB(200, 100, 255)
	prStroke.Thickness = 2
	prStroke.Parent = prisRow

	-- Rainbow gradient bg
	local prisGrad = Instance.new("UIGradient")
	prisGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 30, 70)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(35, 25, 50)),
	})
	prisGrad.Rotation = 90
	prisGrad.Parent = prisRow

	-- Divine image
	local prisImgFrame = Instance.new("Frame")
	prisImgFrame.Size = UDim2.new(0, IMG_SIZE, 0, IMG_SIZE)
	prisImgFrame.Position = UDim2.new(0, 14, 0, 14)
	prisImgFrame.BackgroundColor3 = Color3.fromRGB(30, 22, 45)
	prisImgFrame.BorderSizePixel = 0
	prisImgFrame.ZIndex = 53
	prisImgFrame.Parent = prisRow
	local piCorner = Instance.new("UICorner")
	piCorner.CornerRadius = UDim.new(0, 10)
	piCorner.Parent = prisImgFrame
	local piStroke = Instance.new("UIStroke")
	piStroke.Color = Color3.fromRGB(150, 80, 200)
	piStroke.Thickness = 1.5
	piStroke.Parent = prisImgFrame

	if prisData.imageId and prisData.imageId ~= "" then
		local pImg = Instance.new("ImageLabel")
		pImg.Size = UDim2.new(1, -8, 1, -8)
		pImg.Position = UDim2.new(0.5, 0, 0.5, 0)
		pImg.AnchorPoint = Vector2.new(0.5, 0.5)
		pImg.BackgroundTransparency = 1
		pImg.Image = prisData.imageId
		pImg.ScaleType = Enum.ScaleType.Fit
		pImg.ZIndex = 54
		pImg.Parent = prisImgFrame
	else
		local pIcon = createPotionIcon(prisImgFrame, prisData.color, IMG_SIZE - 16, true)
		pIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
		pIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		pIcon.ZIndex = 54
	end

	local prisTextX = IMG_SIZE + 30

	-- Divine name
	local prisName = Instance.new("TextLabel")
	prisName.Size = UDim2.new(1, -(prisTextX + 14), 0, 28)
	prisName.Position = UDim2.new(0, prisTextX, 0, 10)
	prisName.BackgroundTransparency = 1
	prisName.Text = prisData.name
	prisName.TextColor3 = Color3.new(1, 1, 1)
	prisName.Font = BUBBLE_FONT
	prisName.TextSize = 24
	prisName.TextXAlignment = Enum.TextXAlignment.Left
	prisName.ZIndex = 53
	prisName.Parent = prisRow
	local pnStroke = Instance.new("UIStroke")
	pnStroke.Color = Color3.fromRGB(0, 0, 0)
	pnStroke.Thickness = 2
	pnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	pnStroke.Parent = prisName

	-- Divine description
	local prisDesc = Instance.new("TextLabel")
	prisDesc.Size = UDim2.new(1, -(prisTextX + 14), 0, 20)
	prisDesc.Position = UDim2.new(0, prisTextX, 0, 38)
	prisDesc.BackgroundTransparency = 1
	prisDesc.Text = prisData.desc
	prisDesc.TextColor3 = Color3.fromRGB(100, 255, 140)
	prisDesc.Font = FONT_SUB
	prisDesc.TextSize = 12
	prisDesc.TextXAlignment = Enum.TextXAlignment.Left
	prisDesc.TextWrapped = true
	prisDesc.ZIndex = 53
	prisDesc.Parent = prisRow

	-- "Divine" rarity label
	local prisRarity = Instance.new("TextLabel")
	prisRarity.Size = UDim2.new(0, 100, 0, 20)
	prisRarity.Position = UDim2.new(0, prisTextX, 0, 60)
	prisRarity.BackgroundTransparency = 1
	prisRarity.Text = "Divine"
	prisRarity.TextColor3 = Color3.fromRGB(220, 140, 255)
	prisRarity.Font = BUBBLE_FONT
	prisRarity.TextSize = 14
	prisRarity.TextXAlignment = Enum.TextXAlignment.Left
	prisRarity.ZIndex = 53
	prisRarity.Parent = prisRow

	-- Divine count + USE
	divineCountLabel = Instance.new("TextLabel")
	divineCountLabel.Name = "DivineCount"
	divineCountLabel.Size = UDim2.new(0, 120, 0, 18)
	divineCountLabel.Position = UDim2.new(0, prisTextX, 0, 82)
	divineCountLabel.BackgroundTransparency = 1
	divineCountLabel.Text = "Owned: 0"
	divineCountLabel.TextColor3 = Color3.fromRGB(200, 180, 230)
	divineCountLabel.Font = FONT_SUB
	divineCountLabel.TextSize = 12
	divineCountLabel.TextXAlignment = Enum.TextXAlignment.Left
	divineCountLabel.ZIndex = 53
	divineCountLabel.Parent = prisRow

	local useBtn = Instance.new("TextButton")
	useBtn.Name = "UseBtn"
	useBtn.Size = UDim2.new(0, 70, 0, 28)
	useBtn.Position = UDim2.new(0, prisTextX + 90, 0, 78)
	useBtn.BackgroundColor3 = Color3.fromRGB(180, 80, 220)
	useBtn.Text = "USE"
	useBtn.TextColor3 = Color3.new(1, 1, 1)
	useBtn.Font = BUBBLE_FONT
	useBtn.TextSize = 14
	useBtn.BorderSizePixel = 0
	useBtn.AutoButtonColor = false
	useBtn.ZIndex = 53
	useBtn.Parent = prisRow
	local ubCorner = Instance.new("UICorner")
	ubCorner.CornerRadius = UDim.new(0, 8)
	ubCorner.Parent = useBtn
	local ubStroke = Instance.new("UIStroke")
	ubStroke.Color = Color3.fromRGB(120, 40, 160)
	ubStroke.Thickness = 2
	ubStroke.Parent = useBtn

	useBtn.MouseButton1Click:Connect(function()
		BuyPotionRequest:FireServer("UseDivine", 0)
	end)
	useBtn.MouseEnter:Connect(function()
		TweenService:Create(useBtn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(210, 110, 255) }):Play()
	end)
	useBtn.MouseLeave:Connect(function()
		TweenService:Create(useBtn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(180, 80, 220) }):Play()
	end)

	-- Purchase pack buttons (bottom of prismatic card, horizontal)
	local packRow = Instance.new("Frame")
	packRow.Name = "PackRow"
	packRow.Size = UDim2.new(1, -28, 0, 44)
	packRow.Position = UDim2.new(0.5, 0, 1, -10)
	packRow.AnchorPoint = Vector2.new(0.5, 1)
	packRow.BackgroundTransparency = 1
	packRow.ZIndex = 53
	packRow.Parent = prisRow

	local packLayout = Instance.new("UIListLayout")
	packLayout.FillDirection = Enum.FillDirection.Horizontal
	packLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	packLayout.Padding = UDim.new(0, 12)
	packLayout.Parent = packRow

	for _, pack in ipairs(prisData.packs) do
		local packBtn = Instance.new("TextButton")
		packBtn.Name = "Pack_" .. pack.amount
		packBtn.Size = UDim2.new(0, 120, 0, 40)
		packBtn.BackgroundColor3 = Color3.fromRGB(60, 45, 85)
		packBtn.Text = ""
		packBtn.BorderSizePixel = 0
		packBtn.AutoButtonColor = false
		packBtn.ZIndex = 54
		packBtn.Parent = packRow

		local pbCorner = Instance.new("UICorner")
		pbCorner.CornerRadius = UDim.new(0, 10)
		pbCorner.Parent = packBtn
		local pbStroke = Instance.new("UIStroke")
		pbStroke.Color = Color3.fromRGB(200, 100, 255)
		pbStroke.Thickness = 1.5
		pbStroke.Parent = packBtn

		-- Gem icon + price
		local priceLabel = Instance.new("TextLabel")
		priceLabel.Size = UDim2.new(0.55, 0, 1, 0)
		priceLabel.Position = UDim2.new(0, 8, 0, 0)
		priceLabel.BackgroundTransparency = 1
		priceLabel.Text = "💎 " .. pack.robux
		priceLabel.TextColor3 = Color3.fromRGB(100, 220, 255)
		priceLabel.Font = BUBBLE_FONT
		priceLabel.TextSize = 15
		priceLabel.TextXAlignment = Enum.TextXAlignment.Left
		priceLabel.ZIndex = 55
		priceLabel.Parent = packBtn

		-- Amount label
		local amtLabel = Instance.new("TextLabel")
		amtLabel.Size = UDim2.new(0.4, 0, 1, 0)
		amtLabel.Position = UDim2.new(1, -8, 0, 0)
		amtLabel.AnchorPoint = Vector2.new(1, 0)
		amtLabel.BackgroundTransparency = 1
		amtLabel.Text = pack.label
		amtLabel.TextColor3 = Color3.fromRGB(220, 200, 255)
		amtLabel.Font = BUBBLE_FONT
		amtLabel.TextSize = 14
		amtLabel.TextXAlignment = Enum.TextXAlignment.Right
		amtLabel.ZIndex = 55
		amtLabel.Parent = packBtn

		local capturedAmount = pack.amount
		packBtn.MouseEnter:Connect(function()
			TweenService:Create(packBtn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(80, 60, 110) }):Play()
		end)
		packBtn.MouseLeave:Connect(function()
			TweenService:Create(packBtn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(60, 45, 85) }):Play()
		end)
		packBtn.MouseButton1Click:Connect(function()
			local productId = Potions.DivineProductIds[capturedAmount]
			if productId and productId > 0 then
				MarketplaceService:PromptProductPurchase(player, productId)
			end
		end)
	end

	-------------------------------------------------
	-- LUCK POTIONS
	-------------------------------------------------
	for _, potion in ipairs(Potions.Types.Luck) do
		local r = buildPotionRow("Luck", potion, scroll)
		r.LayoutOrder = potion.tier
	end

	-- Divider between Luck and Money potions
	local potionDivider = Instance.new("Frame")
	potionDivider.Name = "PotionDivider"
	potionDivider.Size = UDim2.new(0.9, 0, 0, 3)
	potionDivider.BackgroundColor3 = Color3.fromRGB(120, 100, 170)
	potionDivider.BorderSizePixel = 0
	potionDivider.LayoutOrder = 9
	potionDivider.Parent = scroll
	Instance.new("UICorner", potionDivider).CornerRadius = UDim.new(1, 0)

	-------------------------------------------------
	-- MONEY POTIONS
	-------------------------------------------------
	for _, potion in ipairs(Potions.Types.Cash) do
		local r = buildPotionRow("Cash", potion, scroll)
		r.LayoutOrder = 10 + potion.tier
	end

	return modal
end

-------------------------------------------------
-- PUBLIC
-------------------------------------------------

function PotionController.OpenShop()
	if shopModal then
		shopModal.Visible = true
		isShopOpen = true
		UIHelper.ScaleIn(shopModal, 0.25)
	end
end

function PotionController.CloseShop()
	if shopModal then
		shopModal.Visible = false
		isShopOpen = false
	end
end

function PotionController.IsShopOpen()
	return isShopOpen
end

function PotionController.Init()
	screenGui = UIHelper.CreateScreenGui("PotionGui", 15)
	screenGui.Parent = playerGui

	-- Build shop
	shopModal = buildShopModal()

	-- Build indicators (bottom-right)
	indicatorContainer = Instance.new("Frame")
	indicatorContainer.Name = "PotionIndicators"
	indicatorContainer.Size = UDim2.new(0, 240, 0, 100)
	indicatorContainer.Position = UDim2.new(1, -10, 1, -10)
	indicatorContainer.AnchorPoint = Vector2.new(1, 1)
	indicatorContainer.BackgroundTransparency = 1
	indicatorContainer.Parent = screenGui

	local indLayout = Instance.new("UIListLayout")
	indLayout.FillDirection = Enum.FillDirection.Horizontal
	indLayout.SortOrder = Enum.SortOrder.LayoutOrder
	indLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	indLayout.Padding = UDim.new(0, 8)
	indLayout.Parent = indicatorContainer

	luckIndicator = createIndicator("Luck", Color3.fromRGB(80, 255, 100), false)
	luckIndicator.LayoutOrder = 1
	luckIndicator.Parent = indicatorContainer

	cashIndicator = createIndicator("Cash", Color3.fromRGB(255, 220, 60), false)
	cashIndicator.LayoutOrder = 2
	cashIndicator.Parent = indicatorContainer

	divineIndicator = createIndicator("Divine", Color3.fromRGB(255, 120, 255), true)
	divineIndicator.LayoutOrder = 3
	divineIndicator.Parent = indicatorContainer

	-- Listen for potion updates from server
	PotionUpdate.OnClientEvent:Connect(function(payload)
		PotionController.ActivePotions = payload or {}
		updateIndicator(luckIndicator, payload.Luck, false)
		updateIndicator(cashIndicator, payload.Cash, false)
		updateIndicator(divineIndicator, payload.Divine, true)

		-- Update divine count in shop
		if divineCountLabel then
			local count = payload._divineCount or 0
			divineCountLabel.Text = "You have: " .. count .. " potion" .. (count ~= 1 and "s" or "")
		end
	end)

	-- Listen for buy results (flash feedback + error toast)
	BuyPotionResult.OnClientEvent:Connect(function(result)
		if result.success then
			-- Brief green flash on the shop modal
			if shopModal and shopModal.Visible then
				local flash = Instance.new("Frame")
				flash.Size = UDim2.new(1, 0, 1, 0)
				flash.BackgroundColor3 = result.potionType == "Divine" and Color3.fromRGB(200, 100, 255) or Color3.fromRGB(80, 255, 100)
				flash.BackgroundTransparency = 0.6
				flash.ZIndex = 60
				flash.Parent = shopModal
				local flashCorner = Instance.new("UICorner")
				flashCorner.CornerRadius = UDim.new(0, 18)
				flashCorner.Parent = flash
				TweenService:Create(flash, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
				task.delay(0.4, function() flash:Destroy() end)
			end
		else
			-- Show error toast message
			local toastParent = shopModal or screenGui
			local toast = Instance.new("Frame")
			toast.Name = "ErrorToast"
			toast.Size = UDim2.new(0.85, 0, 0, 44)
			toast.Position = UDim2.new(0.5, 0, 0.92, 0)
			toast.AnchorPoint = Vector2.new(0.5, 0.5)
			toast.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
			toast.BorderSizePixel = 0
			toast.ZIndex = 65
			toast.Parent = toastParent
			local toastCorner = Instance.new("UICorner")
			toastCorner.CornerRadius = UDim.new(0, 10)
			toastCorner.Parent = toast
			local toastLabel = Instance.new("TextLabel")
			toastLabel.Size = UDim2.new(1, -16, 1, 0)
			toastLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
			toastLabel.AnchorPoint = Vector2.new(0.5, 0.5)
			toastLabel.BackgroundTransparency = 1
			toastLabel.Text = result.reason or "Something went wrong!"
			toastLabel.TextColor3 = Color3.new(1, 1, 1)
			toastLabel.Font = BUBBLE_FONT
			toastLabel.TextSize = 13
			toastLabel.TextWrapped = true
			toastLabel.ZIndex = 66
			toastLabel.Parent = toast
			task.delay(2, function()
				TweenService:Create(toast, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
				TweenService:Create(toastLabel, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
				task.delay(0.5, function() toast:Destroy() end)
			end)
		end
	end)

	-- Open shop from proximity prompt
	OpenPotionStandGui.OnClientEvent:Connect(function()
		if isShopOpen then
			PotionController.CloseShop()
		else
			PotionController.OpenShop()
		end
	end)
end

return PotionController
