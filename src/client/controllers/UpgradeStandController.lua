--[[
	UpgradeStandController.lua
	Upgrade UI — dark-themed panel matching Case Shop / Potion Shop style.
	Two upgrades: Luck (+5 per purchase) and Coin Multiplier (+2% per purchase).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local UIHelper = require(script.Parent.UIHelper)
local HUDController = require(script.Parent.HUDController)

local UpgradeStandController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local OpenUpgradeStandGui = RemoteEvents:WaitForChild("OpenUpgradeStandGui")
local UpgradeLuckRequest = RemoteEvents:WaitForChild("UpgradeLuckRequest")
local UpgradeLuckResult = RemoteEvents:WaitForChild("UpgradeLuckResult")
local UpgradeCashRequest = RemoteEvents:WaitForChild("UpgradeCashRequest")
local UpgradeCashResult = RemoteEvents:WaitForChild("UpgradeCashResult")

local screenGui, overlay, modalFrame
local isOpen = false

local LUCK_PER_LEVEL = 5
local CASH_BONUS_PER_LEVEL = 2

local refs = {
	luck = {},
	cash = {},
}

local FONT = Enum.Font.FredokaOne
local FONT_SUB = Enum.Font.GothamBold
local MODAL_BG = Color3.fromRGB(30, 25, 45)
local RED = Color3.fromRGB(220, 55, 55)
local RED_DARK = Color3.fromRGB(160, 30, 30)
local CARD_BG = Color3.fromRGB(40, 35, 60)
local CARD_BG_DIM = Color3.fromRGB(34, 30, 50)
local MODAL_W, MODAL_H = 520, 500
local CASH_TOUCH_SOUND_ID = "rbxassetid://7112275565"
local CASH_SOUND_START_OFFSET = 0.28
local cachedUpgradeCashSound = nil

local bounceTween = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function getUpgradeCashSound()
	if cachedUpgradeCashSound and cachedUpgradeCashSound.Parent then
		return cachedUpgradeCashSound
	end
	for _, child in ipairs(SoundService:GetChildren()) do
		if child:IsA("Sound") and child.SoundId == CASH_TOUCH_SOUND_ID then
			cachedUpgradeCashSound = child
			return child
		end
	end
	return nil
end

local function playUpgradeCashSound()
	local sfx = getUpgradeCashSound()
	if not sfx then return end
	local clone = sfx:Clone()
	clone.Parent = SoundService
	clone.TimePosition = CASH_SOUND_START_OFFSET
	SoundService:PlayLocalSound(clone)
	clone.Ended:Connect(function()
		if clone and clone.Parent then clone:Destroy() end
	end)
	task.delay(2, function()
		if clone and clone.Parent then clone:Destroy() end
	end)
end

local function addStroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.new(0, 0, 0)
	s.Thickness = thickness or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = parent
	return s
end

local function fmtNum(n)
	local s = tostring(math.floor(n))
	local formatted = ""
	local len = #s
	for i = 1, len do
		formatted = formatted .. string.sub(s, i, i)
		if (len - i) % 3 == 0 and i < len then formatted = formatted .. "," end
	end
	return formatted
end

-------------------------------------------------
-- INFO TOOLTIP
-------------------------------------------------

local function createInfoTooltip(parent, text)
	local iconBtn = Instance.new("TextButton")
	iconBtn.Name = "InfoIcon"
	iconBtn.Size = UDim2.new(0, 20, 0, 20)
	iconBtn.Position = UDim2.new(1, -12, 0, 12)
	iconBtn.AnchorPoint = Vector2.new(1, 0)
	iconBtn.BackgroundColor3 = Color3.fromRGB(55, 50, 75)
	iconBtn.Text = "i"
	iconBtn.TextColor3 = Color3.fromRGB(220, 220, 240)
	iconBtn.Font = FONT
	iconBtn.TextSize = 14
	iconBtn.BorderSizePixel = 0
	iconBtn.AutoButtonColor = false
	iconBtn.ZIndex = 8
	iconBtn.Parent = parent
	Instance.new("UICorner", iconBtn).CornerRadius = UDim.new(1, 0)
	addStroke(iconBtn, Color3.fromRGB(0, 0, 0), 1)

	local tip = Instance.new("TextLabel")
	tip.Name = "Tooltip"
	tip.Size = UDim2.new(0, 230, 0, 54)
	tip.Position = UDim2.new(1, -38, 0, 36)
	tip.AnchorPoint = Vector2.new(1, 0)
	tip.BackgroundColor3 = Color3.fromRGB(25, 22, 38)
	tip.BackgroundTransparency = 0.1
	tip.Text = text
	tip.TextColor3 = Color3.fromRGB(215, 210, 230)
	tip.Font = FONT_SUB
	tip.TextSize = 11
	tip.TextWrapped = true
	tip.TextXAlignment = Enum.TextXAlignment.Left
	tip.TextYAlignment = Enum.TextYAlignment.Top
	tip.Visible = false
	tip.ZIndex = 9
	tip.Parent = parent
	Instance.new("UICorner", tip).CornerRadius = UDim.new(0, 8)
	addStroke(tip, Color3.fromRGB(70, 60, 100), 1)

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = tip

	local function showTip()
		tip.Visible = true
		task.delay(2.8, function()
			if tip and tip.Parent then tip.Visible = false end
		end)
	end
	iconBtn.MouseButton1Click:Connect(showTip)
	iconBtn.MouseEnter:Connect(showTip)
end

local function buildProgressDots(parent)
	local holder = Instance.new("Frame")
	holder.Name = "ProgressDots"
	holder.Size = UDim2.new(1, 0, 0, 12)
	holder.BackgroundTransparency = 1
	holder.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Parent = holder

	local dots = {}
	for i = 1, 10 do
		local d = Instance.new("Frame")
		d.Size = UDim2.new(0, 10, 0, 10)
		d.BackgroundColor3 = Color3.fromRGB(65, 60, 85)
		d.BorderSizePixel = 0
		d.Parent = holder
		Instance.new("UICorner", d).CornerRadius = UDim.new(1, 0)
		dots[i] = d
	end
	return holder, dots
end

-------------------------------------------------
-- CARD
-------------------------------------------------

local function buildUpgradeCard(parent, cfg)
	local card = Instance.new("Frame")
	card.Name = cfg.name .. "Card"
	card.Size = UDim2.new(1, 0, 0, 182)
	card.BackgroundColor3 = CARD_BG
	card.BorderSizePixel = 0
	card.Parent = parent
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)
	addStroke(card, Color3.fromRGB(65, 60, 85), 1.5)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0.7, 0, 0, 24)
	title.Position = UDim2.new(0, 16, 0, 10)
	title.BackgroundTransparency = 1
	title.Text = cfg.title
	title.TextColor3 = cfg.accent
	title.Font = FONT
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = card
	addStroke(title, Color3.new(0, 0, 0), 1.3)

	createInfoTooltip(card, cfg.tooltip)

	local level = Instance.new("TextLabel")
	level.Size = UDim2.new(0, 150, 0, 18)
	level.Position = UDim2.new(1, -40, 0, 13)
	level.AnchorPoint = Vector2.new(1, 0)
	level.BackgroundTransparency = 1
	level.Text = "Level 0"
	level.TextColor3 = Color3.fromRGB(190, 185, 210)
	level.Font = FONT_SUB
	level.TextSize = 12
	level.TextXAlignment = Enum.TextXAlignment.Right
	level.Parent = card

	local flow = Instance.new("TextLabel")
	flow.Size = UDim2.new(1, -32, 0, 20)
	flow.Position = UDim2.new(0, 16, 0, 38)
	flow.BackgroundTransparency = 1
	flow.Text = "Current: +0%  ->  Next: +0%"
	flow.TextColor3 = cfg.accent
	flow.Font = FONT
	flow.TextSize = 15
	flow.TextXAlignment = Enum.TextXAlignment.Left
	flow.Parent = card
	addStroke(flow, Color3.new(0, 0, 0), 1)

	local current = Instance.new("TextLabel")
	current.Size = UDim2.new(0.47, 0, 0, 18)
	current.Position = UDim2.new(0, 16, 0, 62)
	current.BackgroundTransparency = 1
	current.Text = "Current bonus: +0%"
	current.TextColor3 = Color3.fromRGB(145, 140, 170)
	current.Font = FONT_SUB
	current.TextSize = 12
	current.TextXAlignment = Enum.TextXAlignment.Left
	current.Parent = card

	local nextV = Instance.new("TextLabel")
	nextV.Size = UDim2.new(0.47, 0, 0, 18)
	nextV.Position = UDim2.new(1, -16, 0, 62)
	nextV.AnchorPoint = Vector2.new(1, 0)
	nextV.BackgroundTransparency = 1
	nextV.Text = "Next bonus: +0%"
	nextV.TextColor3 = cfg.valueColor
	nextV.Font = FONT_SUB
	nextV.TextSize = 12
	nextV.TextXAlignment = Enum.TextXAlignment.Right
	nextV.Parent = card

	local scaleTxt = Instance.new("TextLabel")
	scaleTxt.Size = UDim2.new(0.5, -8, 0, 16)
	scaleTxt.Position = UDim2.new(1, -16, 0, 82)
	scaleTxt.AnchorPoint = Vector2.new(1, 0)
	scaleTxt.BackgroundTransparency = 1
	scaleTxt.Text = ""
	scaleTxt.TextColor3 = Color3.fromRGB(150, 145, 175)
	scaleTxt.Font = FONT_SUB
	scaleTxt.TextSize = 11
	scaleTxt.TextXAlignment = Enum.TextXAlignment.Right
	scaleTxt.Parent = card

	local dotsHolder, dots = buildProgressDots(card)
	dotsHolder.Position = UDim2.new(0, 16, 0, 104)

	local btn = Instance.new("TextButton")
	btn.Name = "UpgradeBtn"
	btn.Size = UDim2.new(1, -32, 0, 38)
	btn.Position = UDim2.new(0.5, 0, 1, -12)
	btn.AnchorPoint = Vector2.new(0.5, 1)
	btn.BackgroundColor3 = cfg.btnColor
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.Parent = card
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)
	addStroke(btn, cfg.btnStroke, 1.5)

	local btnText = Instance.new("TextLabel")
	btnText.Size = UDim2.new(1, -8, 1, 0)
	btnText.Position = UDim2.new(0, 4, 0, 0)
	btnText.BackgroundTransparency = 1
	btnText.Text = "Upgrade"
	btnText.TextColor3 = Color3.new(1, 1, 1)
	btnText.Font = FONT
	btnText.TextSize = 15
	btnText.TextXAlignment = Enum.TextXAlignment.Center
	btnText.Parent = btn
	addStroke(btnText, Color3.new(0, 0, 0), 1)

	local affordHint = Instance.new("TextLabel")
	affordHint.Size = UDim2.new(1, -32, 0, 14)
	affordHint.Position = UDim2.new(0.5, 0, 1, -54)
	affordHint.AnchorPoint = Vector2.new(0.5, 1)
	affordHint.BackgroundTransparency = 1
	affordHint.Text = ""
	affordHint.TextColor3 = Color3.fromRGB(255, 120, 120)
	affordHint.Font = FONT_SUB
	affordHint.TextSize = 11
	affordHint.TextXAlignment = Enum.TextXAlignment.Center
	affordHint.Parent = card

	local idleSize = UDim2.new(1, -32, 0, 38)
	local hoverSize = UDim2.new(1, -28, 0, 42)
	btn.MouseEnter:Connect(function()
		if not btn.Active then return end
		TweenService:Create(btn, bounceTween, { Size = hoverSize }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, bounceTween, { Size = idleSize }):Play()
	end)

	return {
		card = card,
		level = level,
		flow = flow,
		current = current,
		next = nextV,
		scale = scaleTxt,
		dots = dots,
		btn = btn,
		btnText = btnText,
		affordHint = affordHint,
	}
end

-------------------------------------------------
-- REFRESH
-------------------------------------------------

local function setAffordableState(r, canAfford, cfg)
	r.btn.Active = canAfford
	if canAfford then
		r.btn.BackgroundColor3 = cfg.btnColor
		r.card.BackgroundColor3 = CARD_BG
		r.affordHint.Text = ""
		r.btnText.TextColor3 = Color3.new(1, 1, 1)
	else
		r.btn.BackgroundColor3 = Color3.fromRGB(70, 65, 85)
		r.card.BackgroundColor3 = CARD_BG_DIM
		r.affordHint.Text = "Not enough cash"
		r.btnText.TextColor3 = Color3.fromRGB(185, 180, 200)
	end
end

local function refreshProgress(dots, level, color)
	local lit = math.min(10, level)
	for i, d in ipairs(dots) do
		d.BackgroundColor3 = i <= lit and color or Color3.fromRGB(65, 60, 85)
	end
end

local function refreshModal()
	local cash = HUDController.Data.cash or 0
	local luck = HUDController.Data.luck or 0
	local luckLevel = math.floor(luck / LUCK_PER_LEVEL)
	local currentLuckBonus = luckLevel * LUCK_PER_LEVEL
	local nextLuckBonus = currentLuckBonus + LUCK_PER_LEVEL
	local luckCost = Economy.GetLuckUpgradeCost(luck)
	local nextLuckCost = Economy.GetLuckUpgradeCost(luck + LUCK_PER_LEVEL)

	local rL = refs.luck
	rL.level.Text = "Level " .. luckLevel
	rL.flow.Text = ("Current +%d%%  ->  Next +%d%%"):format(currentLuckBonus, nextLuckBonus)
	rL.current.Visible = false
	rL.next.Text = ("Next bonus: +%d%%"):format(nextLuckBonus)
	rL.btnText.Text = "Upgrade: $" .. fmtNum(luckCost)
	refreshProgress(rL.dots, luckLevel, Color3.fromRGB(90, 230, 130))
	rL.scale.Text = ""
	setAffordableState(rL, cash >= luckCost, {
		btnColor = Color3.fromRGB(50, 200, 90),
	})
	if cash >= luckCost then
		rL.affordHint.Text = "After upgrade: $" .. fmtNum(math.max(0, cash - luckCost)) .. "  •  Next: $" .. fmtNum(nextLuckCost)
		rL.affordHint.TextColor3 = Color3.fromRGB(150, 235, 170)
	end

	local cashLevel = HUDController.Data.cashUpgrade or 0
	local currentCashBonus = cashLevel * CASH_BONUS_PER_LEVEL
	local nextCashBonus = currentCashBonus + CASH_BONUS_PER_LEVEL
	local cashCost = Economy.GetCashUpgradeCost(cashLevel)
	local nextCashCost = Economy.GetCashUpgradeCost(cashLevel + 1)

	local rC = refs.cash
	rC.level.Text = "Level " .. cashLevel
	rC.flow.Text = ("Current +%d%%  ->  Next +%d%%"):format(currentCashBonus, nextCashBonus)
	rC.current.Visible = false
	rC.next.Text = ("Next bonus: +%d%%"):format(nextCashBonus)
	rC.btnText.Text = "Upgrade: $" .. fmtNum(cashCost)
	refreshProgress(rC.dots, cashLevel, Color3.fromRGB(245, 200, 90))
	rC.scale.Text = ""
	setAffordableState(rC, cash >= cashCost, {
		btnColor = Color3.fromRGB(235, 180, 60),
	})
	if cash >= cashCost then
		rC.affordHint.Text = "After upgrade: $" .. fmtNum(math.max(0, cash - cashCost)) .. "  •  Next: $" .. fmtNum(nextCashCost)
		rC.affordHint.TextColor3 = Color3.fromRGB(245, 220, 140)
	end
end

local function flashButton(btn, color)
	btn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	TweenService:Create(btn, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {
		BackgroundColor3 = color,
	}):Play()
end

-------------------------------------------------
-- OPEN / CLOSE
-------------------------------------------------

function UpgradeStandController.Open()
	if isOpen then return end
	isOpen = true
	if modalFrame then
		overlay.Visible = true
		modalFrame.Visible = true
		refreshModal()
		UIHelper.ScaleIn(modalFrame, 0.25)
	end
end

function UpgradeStandController.IsOpen()
	return isOpen
end

function UpgradeStandController.Close()
	if not isOpen then return end
	isOpen = false
	if overlay then overlay.Visible = false end
	if modalFrame then UIHelper.ScaleOut(modalFrame, 0.2) end
end

-------------------------------------------------
-- INIT
-------------------------------------------------

function UpgradeStandController.Init()
	screenGui = UIHelper.CreateScreenGui("UpgradeStandGui", 5)
	screenGui.Parent = playerGui

	-- Overlay
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
	modalFrame.Name = "UpgradeModal"
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
	title.Text = "Upgrades"
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Font = FONT
	title.TextSize = 28
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 3
	title.Parent = header
	addStroke(title, Color3.new(0, 0, 0), 1.5)

	-- Close button
	local closeBtn = Instance.new("TextButton")
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
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1, 0)
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
	closeBtn.MouseButton1Click:Connect(function() UpgradeStandController.Close() end)

	-- Divider
	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(1, -30, 0, 1)
	divider.Position = UDim2.new(0.5, 0, 0, 62)
	divider.AnchorPoint = Vector2.new(0.5, 0)
	divider.BackgroundColor3 = Color3.fromRGB(60, 55, 80)
	divider.BorderSizePixel = 0
	divider.ZIndex = 3
	divider.Parent = modalFrame

	-- ===== CARDS AREA =====
	local cardsContainer = Instance.new("Frame")
	cardsContainer.Name = "Cards"
	cardsContainer.Size = UDim2.new(1, -30, 1, -90)
	cardsContainer.Position = UDim2.new(0.5, 0, 0, 72)
	cardsContainer.AnchorPoint = Vector2.new(0.5, 0)
	cardsContainer.BackgroundTransparency = 1
	cardsContainer.ZIndex = 3
	cardsContainer.Parent = modalFrame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 12)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = cardsContainer

	-- LUCK CARD
	refs.luck = buildUpgradeCard(cardsContainer, {
		name = "Luck",
		title = "Luck Upgrade",
		accent = Color3.fromRGB(80, 220, 120),
		valueColor = Color3.fromRGB(120, 255, 160),
		btnColor = Color3.fromRGB(50, 200, 90),
		btnStroke = Color3.fromRGB(30, 140, 50),
		scalingText = "x3.0 per level",
		tooltip = "Increases drop odds. Each level adds +5% luck. Stacks with rebirth, VIP, and potion luck.",
	})
	refs.luck.btn.MouseButton1Click:Connect(function()
		UpgradeLuckRequest:FireServer()
	end)

	-- CASH CARD
	refs.cash = buildUpgradeCard(cardsContainer, {
		name = "Cash",
		title = "Coin Upgrade",
		accent = Color3.fromRGB(240, 200, 50),
		valueColor = Color3.fromRGB(255, 230, 120),
		btnColor = Color3.fromRGB(240, 180, 40),
		btnStroke = Color3.fromRGB(180, 120, 20),
		scalingText = "x3.0 per level",
		tooltip = "Increases streamer income. Each level adds +2% coins. Stacks with VIP and potions.",
	})
	refs.cash.btn.MouseButton1Click:Connect(function()
		UpgradeCashRequest:FireServer()
	end)

	-------------------------------------------------
	-- EVENTS
	-------------------------------------------------

	HUDController.OnDataUpdated(function()
		if isOpen then refreshModal() end
	end)

	UpgradeLuckResult.OnClientEvent:Connect(function(result)
		if result.success then
			playUpgradeCashSound()
			flashButton(refs.luck.btn, Color3.fromRGB(50, 200, 90))
			if isOpen then refreshModal() end
		end
	end)

	UpgradeCashResult.OnClientEvent:Connect(function(result)
		if result.success then
			playUpgradeCashSound()
			flashButton(refs.cash.btn, Color3.fromRGB(240, 180, 40))
			if isOpen then refreshModal() end
		end
	end)

	OpenUpgradeStandGui.OnClientEvent:Connect(function()
		local TutorialController = require(script.Parent.TutorialController)
		if TutorialController.IsActive() then return end
		if isOpen then
			UpgradeStandController.Close()
		else
			UpgradeStandController.Open()
		end
	end)

	modalFrame.Visible = false
end

return UpgradeStandController
