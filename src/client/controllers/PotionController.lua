--[[
	PotionController.lua
	Client UI for buying potions (shop modal) and showing active potion indicators
	in the bottom-right corner with timer, potion icon, and tier number.
	Includes Prismatic Potion (premium Robux) section with rainbow design.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local Potions = require(ReplicatedStorage.Shared.Config.Potions)
local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local UIHelper = require(script.Parent.UIHelper)

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
local prismaticIndicator
local isShopOpen = false
local prismaticCountLabel -- shows how many prismatic potions player owns

-- Exposed active potion data so other controllers (HUD) can read it
PotionController.ActivePotions = {} -- { Luck = {multiplier, tier, remaining}, Cash = ..., Prismatic = ... }

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
	typeLabel.Text = potionType == "Prismatic" and "PRISM" or potionType:upper()
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

local function buildShopModal()
	local modal = Instance.new("Frame")
	modal.Name = "PotionShop"
	modal.Size = UDim2.new(0, 540, 0, 520)
	modal.Position = UDim2.new(0.5, 0, 0.5, 0)
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.BackgroundColor3 = Color3.fromRGB(20, 18, 35)
	modal.BorderSizePixel = 0
	modal.Visible = false
	modal.ZIndex = 50
	modal.ClipsDescendants = true
	modal.Parent = screenGui
	local mCorner = Instance.new("UICorner")
	mCorner.CornerRadius = UDim.new(0, 18)
	mCorner.Parent = modal
	local mStroke = Instance.new("UIStroke")
	mStroke.Color = Color3.fromRGB(100, 200, 150)
	mStroke.Thickness = 3
	mStroke.Parent = modal

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 40)
	title.Position = UDim2.new(0.5, 0, 0, 8)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.BackgroundTransparency = 1
	title.Text = "\u{1F9EA} POTIONS \u{1F9EA}"
	title.TextColor3 = Color3.fromRGB(150, 255, 180)
	title.Font = BUBBLE_FONT
	title.TextSize = 28
	title.ZIndex = 52
	title.Parent = modal
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.fromRGB(0, 0, 0)
	titleStroke.Thickness = 2
	titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	titleStroke.Parent = title

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 36, 0, 36)
	closeBtn.Position = UDim2.new(1, -8, 0, 8)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = BUBBLE_FONT
	closeBtn.TextSize = 20
	closeBtn.ZIndex = 53
	closeBtn.Parent = modal
	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0, 8)
	closeBtnCorner.Parent = closeBtn
	closeBtn.MouseButton1Click:Connect(function()
		PotionController.CloseShop()
	end)

	-- Subtitle (fixed at top)
	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, -20, 0, 18)
	subtitle.Position = UDim2.new(0.5, 0, 0, 48)
	subtitle.AnchorPoint = Vector2.new(0.5, 0)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "5 min each use  \u{2022}  Stacks time (max 3h)  \u{2022}  Cannot stack different tiers"
	subtitle.TextColor3 = Color3.fromRGB(180, 180, 200)
	subtitle.Font = Enum.Font.GothamBold
	subtitle.TextSize = 11
	subtitle.ZIndex = 52
	subtitle.Parent = modal

	-- Scrollable content area (below title/subtitle)
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ContentScroll"
	scrollFrame.Size = UDim2.new(1, 0, 1, -70)
	scrollFrame.Position = UDim2.new(0, 0, 0, 70)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 5
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 200, 150)
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 520)
	scrollFrame.ZIndex = 51
	scrollFrame.Parent = modal
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.None

	-- Luck and Cash rows (inside scroll area)
	local yStart = 4
	local categories = {
		{ type = "Luck", label = "\u{1F340} LUCK POTIONS", color = Color3.fromRGB(80, 255, 100), desc = "Multiply your luck" },
		{ type = "Cash", label = "\u{1F4B0} CASH POTIONS", color = Color3.fromRGB(255, 220, 60), desc = "Multiply streamer income" },
	}

	for ci, cat in ipairs(categories) do
		local y = yStart + (ci - 1) * 155

		local catLabel = Instance.new("TextLabel")
		catLabel.Size = UDim2.new(1, -20, 0, 22)
		catLabel.Position = UDim2.new(0.5, 0, 0, y)
		catLabel.AnchorPoint = Vector2.new(0.5, 0)
		catLabel.BackgroundTransparency = 1
		catLabel.Text = cat.label .. "  \u{2014}  " .. cat.desc
		catLabel.TextColor3 = cat.color
		catLabel.Font = BUBBLE_FONT
		catLabel.TextSize = 14
		catLabel.ZIndex = 52
		catLabel.Parent = scrollFrame
		local cStroke = Instance.new("UIStroke")
		cStroke.Color = Color3.fromRGB(0, 0, 0)
		cStroke.Thickness = 1.5
		cStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		cStroke.Parent = catLabel

		local potionList = Potions.Types[cat.type]
		for pi, potion in ipairs(potionList) do
			local cardX = 20 + (pi - 1) * 168
			local card = Instance.new("Frame")
			card.Name = cat.type .. "Card" .. pi
			card.Size = UDim2.new(0, 160, 0, 110)
			card.Position = UDim2.new(0, cardX, 0, y + 26)
			card.BackgroundColor3 = Color3.fromRGB(35, 35, 55)
			card.BorderSizePixel = 0
			card.ZIndex = 52
			card.Parent = scrollFrame
			local cardCorner = Instance.new("UICorner")
			cardCorner.CornerRadius = UDim.new(0, 10)
			cardCorner.Parent = card
			local cardStroke = Instance.new("UIStroke")
			cardStroke.Color = potion.color
			cardStroke.Thickness = 2
			cardStroke.Parent = card

			local icon = createPotionIcon(card, potion.color, 36)
			icon.Position = UDim2.new(0.15, 0, 0.05, 0)
			icon.ZIndex = 53

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(0.55, 0, 0, 16)
			nameLabel.Position = UDim2.new(0.95, 0, 0, 6)
			nameLabel.AnchorPoint = Vector2.new(1, 0)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = potion.name
			nameLabel.TextColor3 = potion.color
			nameLabel.Font = BUBBLE_FONT
			nameLabel.TextSize = 11
			nameLabel.ZIndex = 53
			nameLabel.Parent = card

			local multLabel = Instance.new("TextLabel")
			multLabel.Size = UDim2.new(0.55, 0, 0, 20)
			multLabel.Position = UDim2.new(0.95, 0, 0, 22)
			multLabel.AnchorPoint = Vector2.new(1, 0)
			multLabel.BackgroundTransparency = 1
			multLabel.Text = "x" .. potion.multiplier
			multLabel.TextColor3 = Color3.new(1, 1, 1)
			multLabel.Font = BUBBLE_FONT
			multLabel.TextSize = 18
			multLabel.ZIndex = 53
			multLabel.Parent = card

			local durLabel = Instance.new("TextLabel")
			durLabel.Size = UDim2.new(1, -10, 0, 14)
			durLabel.Position = UDim2.new(0.5, 0, 0, 46)
			durLabel.AnchorPoint = Vector2.new(0.5, 0)
			durLabel.BackgroundTransparency = 1
			durLabel.Text = "5 min per use"
			durLabel.TextColor3 = Color3.fromRGB(160, 160, 180)
			durLabel.Font = Enum.Font.GothamBold
			durLabel.TextSize = 10
			durLabel.ZIndex = 53
			durLabel.Parent = card

			local buyBtn = Instance.new("TextButton")
			buyBtn.Name = "BuyBtn"
			buyBtn.Size = UDim2.new(0.8, 0, 0, 28)
			buyBtn.Position = UDim2.new(0.5, 0, 1, -6)
			buyBtn.AnchorPoint = Vector2.new(0.5, 1)
			buyBtn.BackgroundColor3 = potion.color
			buyBtn.Text = "$" .. potion.cost
			buyBtn.TextColor3 = Color3.fromRGB(20, 20, 30)
			buyBtn.Font = BUBBLE_FONT
			buyBtn.TextSize = 15
			buyBtn.ZIndex = 53
			buyBtn.Parent = card
			local btnCorner = Instance.new("UICorner")
			btnCorner.CornerRadius = UDim.new(0, 8)
			btnCorner.Parent = buyBtn

			buyBtn.MouseButton1Click:Connect(function()
				BuyPotionRequest:FireServer(cat.type, potion.tier)
			end)
		end
	end

	-------------------------------------------------
	-- PRISMATIC SECTION (rainbow premium potion)
	-------------------------------------------------
	local prisY = yStart + 2 * 155 + 8

	-- Separator line (rainbow)
	local sepLine = Instance.new("Frame")
	sepLine.Size = UDim2.new(1, -40, 0, 3)
	sepLine.Position = UDim2.new(0.5, 0, 0, prisY - 6)
	sepLine.AnchorPoint = Vector2.new(0.5, 0)
	sepLine.BackgroundColor3 = Color3.new(1, 1, 1)
	sepLine.BorderSizePixel = 0
	sepLine.ZIndex = 52
	sepLine.Parent = scrollFrame
	local sepGrad = Instance.new("UIGradient")
	sepGrad.Color = RAINBOW_SEQUENCE
	sepGrad.Parent = sepLine

	-- Prismatic title
	local prisTitle = Instance.new("TextLabel")
	prisTitle.Size = UDim2.new(1, -20, 0, 28)
	prisTitle.Position = UDim2.new(0.5, 0, 0, prisY + 2)
	prisTitle.AnchorPoint = Vector2.new(0.5, 0)
	prisTitle.BackgroundTransparency = 1
	prisTitle.Text = "\u{1F308} PRISMATIC POTION \u{1F308}"
	prisTitle.TextColor3 = Color3.fromRGB(255, 200, 255)
	prisTitle.Font = BUBBLE_FONT
	prisTitle.TextSize = 20
	prisTitle.ZIndex = 52
	prisTitle.Parent = scrollFrame
	local pTStroke = Instance.new("UIStroke")
	pTStroke.Color = Color3.fromRGB(100, 0, 100)
	pTStroke.Thickness = 2
	pTStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	pTStroke.Parent = prisTitle

	-- Prismatic description
	local prisDesc = Instance.new("TextLabel")
	prisDesc.Size = UDim2.new(1, -20, 0, 16)
	prisDesc.Position = UDim2.new(0.5, 0, 0, prisY + 30)
	prisDesc.AnchorPoint = Vector2.new(0.5, 0)
	prisDesc.BackgroundTransparency = 1
	prisDesc.Text = "x7 Luck AND x7 Cash  \u{2022}  5 min each  \u{2022}  The ULTIMATE potion!"
	prisDesc.TextColor3 = Color3.fromRGB(200, 180, 220)
	prisDesc.Font = Enum.Font.GothamBold
	prisDesc.TextSize = 11
	prisDesc.ZIndex = 52
	prisDesc.Parent = scrollFrame

	-- Prismatic potion count + USE button
	local prisInfoRow = Instance.new("Frame")
	prisInfoRow.Size = UDim2.new(1, -40, 0, 36)
	prisInfoRow.Position = UDim2.new(0.5, 0, 0, prisY + 48)
	prisInfoRow.AnchorPoint = Vector2.new(0.5, 0)
	prisInfoRow.BackgroundColor3 = Color3.fromRGB(40, 30, 55)
	prisInfoRow.BorderSizePixel = 0
	prisInfoRow.ZIndex = 52
	prisInfoRow.Parent = scrollFrame
	local pirCorner = Instance.new("UICorner")
	pirCorner.CornerRadius = UDim.new(0, 10)
	pirCorner.Parent = prisInfoRow
	local pirStroke = Instance.new("UIStroke")
	pirStroke.Color = Color3.fromRGB(255, 120, 255)
	pirStroke.Thickness = 2
	pirStroke.Parent = prisInfoRow

	-- Potion icon in info row
	local prisIcon = createPotionIcon(prisInfoRow, Color3.fromRGB(255, 120, 255), 30, true)
	prisIcon.Position = UDim2.new(0, 6, 0.5, 0)
	prisIcon.AnchorPoint = Vector2.new(0, 0.5)
	prisIcon.ZIndex = 53

	prismaticCountLabel = Instance.new("TextLabel")
	prismaticCountLabel.Name = "PrisCount"
	prismaticCountLabel.Size = UDim2.new(0, 160, 1, 0)
	prismaticCountLabel.Position = UDim2.new(0, 42, 0, 0)
	prismaticCountLabel.BackgroundTransparency = 1
	prismaticCountLabel.Text = "You have: 0 potions"
	prismaticCountLabel.TextColor3 = Color3.fromRGB(255, 200, 255)
	prismaticCountLabel.Font = BUBBLE_FONT
	prismaticCountLabel.TextSize = 13
	prismaticCountLabel.TextXAlignment = Enum.TextXAlignment.Left
	prismaticCountLabel.ZIndex = 53
	prismaticCountLabel.Parent = prisInfoRow

	local useBtn = Instance.new("TextButton")
	useBtn.Name = "UseBtn"
	useBtn.Size = UDim2.new(0, 100, 0, 28)
	useBtn.Position = UDim2.new(1, -6, 0.5, 0)
	useBtn.AnchorPoint = Vector2.new(1, 0.5)
	useBtn.BackgroundColor3 = Color3.fromRGB(180, 80, 220)
	useBtn.Text = "\u{2728} USE"
	useBtn.TextColor3 = Color3.new(1, 1, 1)
	useBtn.Font = BUBBLE_FONT
	useBtn.TextSize = 15
	useBtn.ZIndex = 53
	useBtn.Parent = prisInfoRow
	local useBtnCorner = Instance.new("UICorner")
	useBtnCorner.CornerRadius = UDim.new(0, 8)
	useBtnCorner.Parent = useBtn
	local useBtnStroke = Instance.new("UIStroke")
	useBtnStroke.Color = Color3.fromRGB(120, 40, 160)
	useBtnStroke.Thickness = 2
	useBtnStroke.Parent = useBtn

	useBtn.MouseButton1Click:Connect(function()
		BuyPotionRequest:FireServer("UsePrismatic", 0)
	end)
	useBtn.MouseEnter:Connect(function()
		TweenService:Create(useBtn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(210, 110, 255) }):Play()
	end)
	useBtn.MouseLeave:Connect(function()
		TweenService:Create(useBtn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(180, 80, 220) }):Play()
	end)

	-- Pack purchase cards (Robux)
	local packY = prisY + 90
	local packs = Potions.Prismatic.packs

	for pi, pack in ipairs(packs) do
		local cardX = 20 + (pi - 1) * 168
		local card = Instance.new("Frame")
		card.Name = "PrismaticPack" .. pi
		card.Size = UDim2.new(0, 160, 0, 100)
		card.Position = UDim2.new(0, cardX, 0, packY)
		card.BackgroundColor3 = Color3.fromRGB(30, 20, 45)
		card.BorderSizePixel = 0
		card.ZIndex = 52
		card.Parent = scrollFrame
		local pcCorner = Instance.new("UICorner")
		pcCorner.CornerRadius = UDim.new(0, 12)
		pcCorner.Parent = card
		local pcStroke = Instance.new("UIStroke")
		pcStroke.Color = Color3.fromRGB(255, 120, 255)
		pcStroke.Thickness = 2
		pcStroke.Parent = card

		-- Rainbow gradient background
		local cardGrad = Instance.new("UIGradient")
		cardGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 30, 70)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 20, 50)),
		})
		cardGrad.Rotation = 90
		cardGrad.Parent = card

		-- Pack icon (potion with number)
		local packIcon = createPotionIcon(card, Color3.fromRGB(255, 120, 255), 34, true)
		packIcon.Position = UDim2.new(0.5, 0, 0, 4)
		packIcon.AnchorPoint = Vector2.new(0.5, 0)
		packIcon.ZIndex = 53

		-- Pack label
		local packLabel = Instance.new("TextLabel")
		packLabel.Size = UDim2.new(1, -8, 0, 16)
		packLabel.Position = UDim2.new(0.5, 0, 0, 40)
		packLabel.AnchorPoint = Vector2.new(0.5, 0)
		packLabel.BackgroundTransparency = 1
		packLabel.Text = pack.label
		packLabel.TextColor3 = Color3.fromRGB(255, 220, 255)
		packLabel.Font = BUBBLE_FONT
		packLabel.TextSize = 13
		packLabel.ZIndex = 53
		packLabel.Parent = card

		-- Sale tag (if present)
		if pack.tag then
			local tagLabel = Instance.new("TextLabel")
			tagLabel.Size = UDim2.new(1, -8, 0, 14)
			tagLabel.Position = UDim2.new(0.5, 0, 0, 55)
			tagLabel.AnchorPoint = Vector2.new(0.5, 0)
			tagLabel.BackgroundTransparency = 1
			tagLabel.Text = "\u{1F525} " .. pack.tag
			tagLabel.TextColor3 = Color3.fromRGB(255, 255, 100)
			tagLabel.Font = BUBBLE_FONT
			tagLabel.TextSize = 11
			tagLabel.ZIndex = 53
			tagLabel.Parent = card
		end

		-- Robux buy button
		local robuxBtn = Instance.new("TextButton")
		robuxBtn.Name = "RobuxBtn"
		robuxBtn.Size = UDim2.new(0.85, 0, 0, 26)
		robuxBtn.Position = UDim2.new(0.5, 0, 1, -5)
		robuxBtn.AnchorPoint = Vector2.new(0.5, 1)
		robuxBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 0)
		robuxBtn.Text = "\u{1F4B2} R$ " .. pack.robux
		robuxBtn.TextColor3 = Color3.new(1, 1, 1)
		robuxBtn.Font = BUBBLE_FONT
		robuxBtn.TextSize = 14
		robuxBtn.ZIndex = 53
		robuxBtn.Parent = card
		local rbCorner = Instance.new("UICorner")
		rbCorner.CornerRadius = UDim.new(0, 8)
		rbCorner.Parent = robuxBtn
		local rbStroke = Instance.new("UIStroke")
		rbStroke.Color = Color3.fromRGB(0, 120, 0)
		rbStroke.Thickness = 2
		rbStroke.Parent = robuxBtn

		robuxBtn.MouseEnter:Connect(function()
			TweenService:Create(robuxBtn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(0, 220, 0) }):Play()
		end)
		robuxBtn.MouseLeave:Connect(function()
			TweenService:Create(robuxBtn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(0, 180, 0) }):Play()
		end)

		-- Prompt Robux purchase
		local capturedAmount = pack.amount
		robuxBtn.MouseButton1Click:Connect(function()
			local productId = Potions.PrismaticProductIds[capturedAmount]
			if productId and productId > 0 then
				MarketplaceService:PromptProductPurchase(player, productId)
			else
				-- Product IDs not set yet — show a toast
				BuyPotionResult.OnClientEvent:Wait() -- won't fire, just show a manual toast
			end
		end)
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

	prismaticIndicator = createIndicator("Prismatic", Color3.fromRGB(255, 120, 255), true)
	prismaticIndicator.LayoutOrder = 3
	prismaticIndicator.Parent = indicatorContainer

	-- Listen for potion updates from server
	PotionUpdate.OnClientEvent:Connect(function(payload)
		PotionController.ActivePotions = payload or {}
		updateIndicator(luckIndicator, payload.Luck, false)
		updateIndicator(cashIndicator, payload.Cash, false)
		updateIndicator(prismaticIndicator, payload.Prismatic, true)

		-- Update prismatic count in shop
		if prismaticCountLabel then
			local count = payload._prismaticCount or 0
			prismaticCountLabel.Text = "You have: " .. count .. " potion" .. (count ~= 1 and "s" or "")
		end
	end)

	-- Listen for buy results (flash feedback + error toast)
	BuyPotionResult.OnClientEvent:Connect(function(result)
		if result.success then
			-- Brief green flash on the shop modal
			if shopModal and shopModal.Visible then
				local flash = Instance.new("Frame")
				flash.Size = UDim2.new(1, 0, 1, 0)
				flash.BackgroundColor3 = result.potionType == "Prismatic" and Color3.fromRGB(200, 100, 255) or Color3.fromRGB(80, 255, 100)
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
