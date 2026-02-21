--[[
	SpinStandController.lua
	Crate shop UI — vibrant, bubbly, kid-friendly.
	Cases 1–3 unlocked before Rebirth 1; Cases 4+ require Rebirth 1+.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local UIHelper = require(script.Parent.UIHelper)

local SpinStandController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local BuyCrateRequest = RemoteEvents:WaitForChild("BuyCrateRequest")
local OpenSpinStandGui = RemoteEvents:WaitForChild("OpenSpinStandGui")

local screenGui
local modalFrame
local overlay
local isOpen = false

-------------------------------------------------
-- STYLE CONSTANTS
-------------------------------------------------
local BUBBLE_CORNER = 28
local CARD_CORNER   = 22
local BTN_CORNER    = 16
local FONT          = Enum.Font.FredokaOne
local FONT_SUB      = Enum.Font.GothamBold

local BG_TOP    = Color3.fromRGB(45, 25, 80)
local BG_BOT    = Color3.fromRGB(20, 12, 50)
local STROKE_BG = Color3.fromRGB(140, 80, 255)

-------------------------------------------------
-- CRATE DEFINITIONS
-------------------------------------------------
local crates = {
	{ id = 1, name = "Crate 1", emoji = "📦", cost = Economy.Crate1Cost, luckPercent = 0,   desc = "+0% Luck",   color = Color3.fromRGB(80, 180, 255), colorBot = Color3.fromRGB(40, 110, 200),  strokeColor = Color3.fromRGB(130, 210, 255) },
	{ id = 2, name = "Crate 2", emoji = "🎁", cost = Economy.Crate2Cost, luckPercent = 5,   desc = "+5% Luck",   color = Color3.fromRGB(255, 120, 170), colorBot = Color3.fromRGB(200, 60, 120), strokeColor = Color3.fromRGB(255, 170, 210) },
	{ id = 3, name = "Crate 3", emoji = "📫", cost = Economy.Crate3Cost, luckPercent = 15,  desc = "+15% Luck",  color = Color3.fromRGB(100, 230, 130), colorBot = Color3.fromRGB(40, 160, 70),  strokeColor = Color3.fromRGB(160, 255, 180) },
	{ id = 4, name = "Crate 4", emoji = "🎀", cost = Economy.Crate4Cost, luckPercent = 100, desc = "+100% Luck", color = Color3.fromRGB(255, 190, 70),  colorBot = Color3.fromRGB(210, 130, 20), strokeColor = Color3.fromRGB(255, 220, 130) },
	{ id = 5, name = "Crate 5", emoji = "✨", cost = Economy.Crate5Cost, luckPercent = 200, desc = "+200% Luck", color = Color3.fromRGB(180, 130, 255), colorBot = Color3.fromRGB(110, 60, 200), strokeColor = Color3.fromRGB(210, 180, 255) },
	{ id = 6, name = "Crate 6", emoji = "🌟", cost = Economy.Crate6Cost, luckPercent = 150, desc = "+150% Luck", color = Color3.fromRGB(255, 200, 100), colorBot = Color3.fromRGB(210, 140, 30), strokeColor = Color3.fromRGB(255, 230, 160) },
	{ id = 7, name = "Crate 7", emoji = "💎", cost = Economy.Crate7Cost, luckPercent = 250, desc = "+250% Luck", color = Color3.fromRGB(120, 200, 255), colorBot = Color3.fromRGB(50, 120, 220), strokeColor = Color3.fromRGB(180, 230, 255) },
}

local cardRefs = {}

-------------------------------------------------
-- HELPERS
-------------------------------------------------
local function getRebirthCount()
	local HUDController = require(script.Parent.HUDController)
	return HUDController.Data.rebirthCount or 0
end

local function formatCash(n)
	local s = tostring(math.floor(n))
	local out, len = "", #s
	for i = 1, len do
		out = out .. s:sub(i, i)
		if (len - i) % 3 == 0 and i < len then out = out .. "," end
	end
	return "$" .. out
end

local function addOutlinedText(parent, props)
	local label = Instance.new("TextLabel")
	label.Name = props.Name or "Label"
	label.Size = props.Size or UDim2.new(1, 0, 0, 24)
	label.Position = props.Position or UDim2.new(0, 0, 0, 0)
	label.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
	label.BackgroundTransparency = 1
	label.Text = props.Text or ""
	label.TextColor3 = props.Color or Color3.new(1, 1, 1)
	label.Font = props.Font or FONT
	label.TextSize = props.TextSize or 20
	label.TextScaled = props.TextScaled or false
	label.TextWrapped = true
	label.RichText = props.RichText or false
	label.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = props.StrokeColor or Color3.fromRGB(0, 0, 0)
	stroke.Thickness = props.StrokeThickness or 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
	return label
end

-------------------------------------------------
-- BUILD CRATE CARD
-------------------------------------------------
local function buildCrateCard(crate, parent)
	local card = Instance.new("Frame")
	card.Name = "CrateCard_" .. crate.id
	card.Size = UDim2.new(0, 190, 0, 260)
	card.BackgroundColor3 = crate.color
	card.BorderSizePixel = 0
	card.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, CARD_CORNER)
	corner.Parent = card

	-- Card gradient (top lighter, bottom darker) for depth
	local cardGrad = Instance.new("UIGradient")
	cardGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.6, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 60, 80)),
	})
	cardGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 0),
	})
	cardGrad.Rotation = 90
	cardGrad.Parent = card

	-- Glow stroke
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Name = "CardStroke"
	cardStroke.Color = crate.strokeColor
	cardStroke.Thickness = 3
	cardStroke.Transparency = 0.2
	cardStroke.Parent = card

	-- Inner shadow frame at top for "puffy" feel
	local innerHighlight = Instance.new("Frame")
	innerHighlight.Name = "InnerHL"
	innerHighlight.Size = UDim2.new(1, -8, 0, 50)
	innerHighlight.Position = UDim2.new(0.5, 0, 0, 4)
	innerHighlight.AnchorPoint = Vector2.new(0.5, 0)
	innerHighlight.BackgroundColor3 = Color3.new(1, 1, 1)
	innerHighlight.BackgroundTransparency = 0.75
	innerHighlight.BorderSizePixel = 0
	innerHighlight.Parent = card
	local hlCorner = Instance.new("UICorner")
	hlCorner.CornerRadius = UDim.new(0, CARD_CORNER - 4)
	hlCorner.Parent = innerHighlight
	local hlGrad = Instance.new("UIGradient")
	hlGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	hlGrad.Rotation = 90
	hlGrad.Parent = innerHighlight

	-- Big emoji icon
	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(1, 0, 0, 70)
	icon.Position = UDim2.new(0.5, 0, 0, 10)
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.BackgroundTransparency = 1
	icon.Text = crate.emoji
	icon.TextSize = 52
	icon.Font = Enum.Font.SourceSans
	icon.TextScaled = false
	icon.Parent = card

	-- Crate name
	addOutlinedText(card, {
		Name = "Name",
		Size = UDim2.new(1, -12, 0, 32),
		Position = UDim2.new(0.5, 0, 0, 82),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = crate.name,
		Color = Color3.new(1, 1, 1),
		Font = FONT,
		TextSize = 24,
		StrokeThickness = 2.5,
	})

	-- Luck badge (colored pill)
	local luckBadge = Instance.new("Frame")
	luckBadge.Name = "LuckBadge"
	luckBadge.Size = UDim2.new(0.75, 0, 0, 28)
	luckBadge.Position = UDim2.new(0.5, 0, 0, 118)
	luckBadge.AnchorPoint = Vector2.new(0.5, 0)
	luckBadge.BackgroundColor3 = Color3.fromRGB(255, 255, 80)
	luckBadge.BackgroundTransparency = 0.15
	luckBadge.BorderSizePixel = 0
	luckBadge.Parent = card
	local lbCorner = Instance.new("UICorner")
	lbCorner.CornerRadius = UDim.new(0, 14)
	lbCorner.Parent = luckBadge
	local lbGrad = Instance.new("UIGradient")
	lbGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 120)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 200, 40)),
	})
	lbGrad.Rotation = 90
	lbGrad.Parent = luckBadge

	addOutlinedText(luckBadge, {
		Name = "LuckText",
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "🍀 " .. crate.desc,
		Color = Color3.fromRGB(30, 80, 10),
		Font = FONT,
		TextSize = 16,
		StrokeColor = Color3.fromRGB(200, 230, 100),
		StrokeThickness = 1,
	})

	-- Price label
	addOutlinedText(card, {
		Name = "Price",
		Size = UDim2.new(1, -12, 0, 30),
		Position = UDim2.new(0.5, 0, 0, 152),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = formatCash(crate.cost),
		Color = Color3.fromRGB(80, 255, 130),
		Font = FONT,
		TextSize = 24,
		StrokeThickness = 2.5,
	})

	-- BUY button (vibrant green pill)
	local buyBtn = Instance.new("TextButton")
	buyBtn.Name = "BuyBtn"
	buyBtn.Size = UDim2.new(0.82, 0, 0, 48)
	buyBtn.Position = UDim2.new(0.5, 0, 1, -14)
	buyBtn.AnchorPoint = Vector2.new(0.5, 1)
	buyBtn.BackgroundColor3 = Color3.fromRGB(60, 220, 100)
	buyBtn.Text = "BUY"
	buyBtn.TextColor3 = Color3.new(1, 1, 1)
	buyBtn.Font = FONT
	buyBtn.TextSize = 22
	buyBtn.BorderSizePixel = 0
	buyBtn.AutoButtonColor = false
	buyBtn.Parent = card
	local buyCorner = Instance.new("UICorner")
	buyCorner.CornerRadius = UDim.new(0, BTN_CORNER)
	buyCorner.Parent = buyBtn
	local buyStroke = Instance.new("UIStroke")
	buyStroke.Color = Color3.fromRGB(30, 160, 70)
	buyStroke.Thickness = 2.5
	buyStroke.Transparency = 0.1
	buyStroke.Parent = buyBtn
	local buyGrad = Instance.new("UIGradient")
	buyGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(100, 255, 150)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 190, 80)),
	})
	buyGrad.Rotation = 90
	buyGrad.Parent = buyBtn
	local buyTextStroke = Instance.new("UIStroke")
	buyTextStroke.Color = Color3.fromRGB(10, 60, 20)
	buyTextStroke.Thickness = 2
	buyTextStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	buyTextStroke.Parent = buyBtn

	-- Bounce on hover
	local idleSize = buyBtn.Size
	local hoverSize = UDim2.new(idleSize.X.Scale * 1.08, 0, 0, math.floor(idleSize.Y.Offset * 1.08))
	local clickSize = UDim2.new(idleSize.X.Scale * 0.93, 0, 0, math.floor(idleSize.Y.Offset * 0.93))
	local bounceTI = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local clickTI  = TweenInfo.new(0.08, Enum.EasingStyle.Quad)
	buyBtn.MouseEnter:Connect(function()
		TweenService:Create(buyBtn, bounceTI, { Size = hoverSize, BackgroundColor3 = Color3.fromRGB(90, 255, 140) }):Play()
	end)
	buyBtn.MouseLeave:Connect(function()
		TweenService:Create(buyBtn, bounceTI, { Size = idleSize, BackgroundColor3 = Color3.fromRGB(60, 220, 100) }):Play()
	end)
	buyBtn.MouseButton1Down:Connect(function()
		TweenService:Create(buyBtn, clickTI, { Size = clickSize }):Play()
	end)
	buyBtn.MouseButton1Up:Connect(function()
		TweenService:Create(buyBtn, bounceTI, { Size = idleSize }):Play()
	end)

	-- Lock overlay
	local lockOverlay = Instance.new("Frame")
	lockOverlay.Name = "LockOverlay"
	lockOverlay.Size = UDim2.new(1, 0, 1, 0)
	lockOverlay.BackgroundColor3 = Color3.fromRGB(15, 10, 30)
	lockOverlay.BackgroundTransparency = 0.35
	lockOverlay.BorderSizePixel = 0
	lockOverlay.ZIndex = 5
	lockOverlay.Visible = false
	lockOverlay.Parent = card
	local lockCorner = Instance.new("UICorner")
	lockCorner.CornerRadius = UDim.new(0, CARD_CORNER)
	lockCorner.Parent = lockOverlay

	local lockIcon = Instance.new("TextLabel")
	lockIcon.Size = UDim2.new(1, 0, 0, 60)
	lockIcon.Position = UDim2.new(0.5, 0, 0.3, 0)
	lockIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	lockIcon.BackgroundTransparency = 1
	lockIcon.Text = "🔒"
	lockIcon.TextSize = 48
	lockIcon.Font = Enum.Font.SourceSans
	lockIcon.ZIndex = 6
	lockIcon.Parent = lockOverlay

	addOutlinedText(lockOverlay, {
		Name = "LockText",
		Size = UDim2.new(1, -10, 0, 44),
		Position = UDim2.new(0.5, 0, 0.6, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "Rebirth " .. Economy.GetCrateRebirthRequirement(crate.id) .. "\nRequired",
		Color = Color3.fromRGB(255, 180, 80),
		Font = FONT,
		TextSize = 16,
		StrokeThickness = 2,
	}).ZIndex = 6

	buyBtn.MouseButton1Click:Connect(function()
		local rebirthReq = Economy.GetCrateRebirthRequirement(crate.id)
		local currentRebirth = getRebirthCount()
		if currentRebirth < rebirthReq then
			buyBtn.Text = "Rebirth " .. rebirthReq .. " needed!"
			task.delay(1.5, function()
				buyBtn.Text = "🔒 LOCKED"
			end)
			return
		end

		SpinStandController.Close()
		local SpinController = require(script.Parent.SpinController)
		SpinController.SetCurrentCost(crate.cost)
		SpinController.SetCurrentCrateId(crate.id)
		SpinController.Show()
		SpinController.RequestSpin()
	end)

	cardRefs[crate.id] = {
		card = card,
		buyBtn = buyBtn,
		lockOverlay = lockOverlay,
	}

	return card
end

-------------------------------------------------
-- UPDATE LOCK STATUS
-------------------------------------------------
local function updateLockStatus()
	local currentRebirth = getRebirthCount()
	for crateId, refs in pairs(cardRefs) do
		local rebirthReq = Economy.GetCrateRebirthRequirement(crateId)
		if currentRebirth >= rebirthReq then
			refs.lockOverlay.Visible = false
			refs.buyBtn.Text = "BUY"
			refs.buyBtn.BackgroundColor3 = Color3.fromRGB(60, 220, 100)
		else
			refs.lockOverlay.Visible = true
			refs.buyBtn.Text = "🔒 LOCKED"
			refs.buyBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 100)
		end
	end
end

-------------------------------------------------
-- OPEN / CLOSE
-------------------------------------------------

function SpinStandController.Open()
	if isOpen then return end
	isOpen = true
	updateLockStatus()
	overlay.Visible = true
	modalFrame.Visible = true
	UIHelper.ScaleIn(modalFrame, 0.35)
end

function SpinStandController.Close()
	if not isOpen then return end
	isOpen = false
	overlay.Visible = false
	modalFrame.Visible = false
end

function SpinStandController.IsOpen(): boolean
	return isOpen
end

-------------------------------------------------
-- INIT
-------------------------------------------------

function SpinStandController.Init()
	screenGui = UIHelper.CreateScreenGui("SpinStandGui", 18)
	screenGui.Parent = playerGui

	-- Dark overlay
	overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.45
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.ZIndex = 1
	overlay.Parent = screenGui

	-- Modal panel
	modalFrame = Instance.new("Frame")
	modalFrame.Name = "CrateShopModal"
	modalFrame.Size = UDim2.new(0, 560, 0, 420)
	modalFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	modalFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	modalFrame.BackgroundColor3 = BG_TOP
	modalFrame.BorderSizePixel = 0
	modalFrame.ZIndex = 2
	modalFrame.Visible = false
	modalFrame.Parent = screenGui

	local modalCorner = Instance.new("UICorner")
	modalCorner.CornerRadius = UDim.new(0, BUBBLE_CORNER)
	modalCorner.Parent = modalFrame

	-- Background gradient
	local bgGrad = Instance.new("UIGradient")
	bgGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, BG_TOP),
		ColorSequenceKeypoint.new(1, BG_BOT),
	})
	bgGrad.Rotation = 90
	bgGrad.Parent = modalFrame

	-- Outer glow stroke
	local modalStroke = Instance.new("UIStroke")
	modalStroke.Color = STROKE_BG
	modalStroke.Thickness = 3
	modalStroke.Transparency = 0.15
	modalStroke.Parent = modalFrame

	UIHelper.CreateShadow(modalFrame)

	-- Top rainbow accent line
	local topAccent = Instance.new("Frame")
	topAccent.Name = "TopAccent"
	topAccent.Size = UDim2.new(1, -20, 0, 5)
	topAccent.Position = UDim2.new(0.5, 0, 0, 10)
	topAccent.AnchorPoint = Vector2.new(0.5, 0)
	topAccent.BackgroundColor3 = Color3.new(1, 1, 1)
	topAccent.BorderSizePixel = 0
	topAccent.ZIndex = 3
	topAccent.Parent = modalFrame
	local topAccentCorner = Instance.new("UICorner")
	topAccentCorner.CornerRadius = UDim.new(0, 3)
	topAccentCorner.Parent = topAccent
	local accentGrad = Instance.new("UIGradient")
	accentGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 120)),
		ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 200, 50)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(80, 255, 150)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(80, 180, 255)),
		ColorSequenceKeypoint.new(0.8, Color3.fromRGB(200, 80, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 120)),
	})
	accentGrad.Parent = topAccent

	-- Title
	local title = addOutlinedText(modalFrame, {
		Name = "Title",
		Size = UDim2.new(1, -90, 0, 46),
		Position = UDim2.new(0.5, 0, 0, 22),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "🎰  PICK A CRATE!  🎰",
		Color = Color3.fromRGB(255, 240, 100),
		Font = FONT,
		TextSize = 32,
		StrokeColor = Color3.fromRGB(180, 80, 0),
		StrokeThickness = 3,
	})
	title.ZIndex = 3

	-- Subtitle
	addOutlinedText(modalFrame, {
		Name = "Subtitle",
		Size = UDim2.new(1, -60, 0, 22),
		Position = UDim2.new(0.5, 0, 0, 68),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "Higher luck = rarer drops!",
		Color = Color3.fromRGB(200, 190, 255),
		Font = FONT_SUB,
		TextSize = 16,
		StrokeColor = Color3.fromRGB(40, 20, 80),
		StrokeThickness = 1.5,
	})

	-- Scrollable cards container
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "CardsScroll"
	scroll.Size = UDim2.new(1, -36, 0, 296)
	scroll.Position = UDim2.new(0.5, 0, 0, 96)
	scroll.AnchorPoint = Vector2.new(0.5, 0)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = Color3.fromRGB(140, 100, 220)
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.X
	scroll.ZIndex = 2
	scroll.Parent = modalFrame

	local cardsFrame = Instance.new("Frame")
	cardsFrame.Name = "CardsFrame"
	cardsFrame.Size = UDim2.new(0, 0, 1, 0)
	cardsFrame.AutomaticSize = Enum.AutomaticSize.X
	cardsFrame.BackgroundTransparency = 1
	cardsFrame.Parent = scroll

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Horizontal
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	listLayout.Padding = UDim.new(0, 16)
	listLayout.Parent = cardsFrame

	-- Left padding so first card isn't flush
	local leftPad = Instance.new("UIPadding")
	leftPad.PaddingLeft = UDim.new(0, 6)
	leftPad.PaddingRight = UDim.new(0, 6)
	leftPad.Parent = cardsFrame

	for _, crate in ipairs(crates) do
		buildCrateCard(crate, cardsFrame)
	end

	-- Close button (bubbly red circle)
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 42, 0, 42)
	closeBtn.Position = UDim2.new(1, -12, 0, 12)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(240, 60, 70)
	closeBtn.Text = "✕"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = FONT
	closeBtn.TextSize = 24
	closeBtn.BorderSizePixel = 0
	closeBtn.AutoButtonColor = false
	closeBtn.ZIndex = 5
	closeBtn.Parent = modalFrame

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(1, 0)
	closeCorner.Parent = closeBtn

	local closeStroke = Instance.new("UIStroke")
	closeStroke.Color = Color3.fromRGB(180, 30, 30)
	closeStroke.Thickness = 2.5
	closeStroke.Parent = closeBtn

	local closeGrad = Instance.new("UIGradient")
	closeGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 100, 100)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 40, 50)),
	})
	closeGrad.Rotation = 90
	closeGrad.Parent = closeBtn

	local closeTextStroke = Instance.new("UIStroke")
	closeTextStroke.Color = Color3.fromRGB(80, 0, 0)
	closeTextStroke.Thickness = 1.5
	closeTextStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	closeTextStroke.Parent = closeBtn

	-- Bounce on hover
	local closeBounce = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	closeBtn.MouseEnter:Connect(function()
		TweenService:Create(closeBtn, closeBounce, { Size = UDim2.new(0, 48, 0, 48) }):Play()
	end)
	closeBtn.MouseLeave:Connect(function()
		TweenService:Create(closeBtn, closeBounce, { Size = UDim2.new(0, 42, 0, 42) }):Play()
	end)
	closeBtn.MouseButton1Click:Connect(function()
		SpinStandController.Close()
	end)

	-- Server event
	OpenSpinStandGui.OnClientEvent:Connect(function()
		SpinStandController.Open()
	end)
end

return SpinStandController
