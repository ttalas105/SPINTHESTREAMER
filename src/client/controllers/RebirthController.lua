--[[
	RebirthController.lua
	Rebirth UI – bright pastel-themed panel showing actual rebirth rewards:
	coin bonus, base slot unlock, luck bonus, case/potion unlocks.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local SlotsConfig = require(ReplicatedStorage.Shared.Config.SlotsConfig)
local UIHelper = require(script.Parent.UIHelper)

local RebirthController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local RebirthRequest = RemoteEvents:WaitForChild("RebirthRequest")
local RebirthResult = RemoteEvents:WaitForChild("RebirthResult")
local OpenRebirthGui = RemoteEvents:WaitForChild("OpenRebirthGui")

local screenGui, overlay, modalFrame
local isOpen = false

local titleRef, subtitleRef
local levelTextRef
local progressFillRef, progressTextRef
local coinBonusValueRef, slotValueRef, luckValueRef
local caseUnlockRow, caseUnlockImage, caseUnlockText
local potionUnlockRow, potionUnlockText
local noUnlocksRef
local costRef, confirmBtnRef, confirmTextRef
local warnRef, maxedRef

local FONT = Enum.Font.FredokaOne
local FONT_SUB = Enum.Font.GothamBold

local BG_TOP = Color3.fromRGB(180, 215, 255)
local BG_BOTTOM = Color3.fromRGB(210, 190, 255)
local CARD_BG = Color3.fromRGB(255, 255, 255)
local CARD_BORDER = Color3.fromRGB(180, 210, 255)
local GREEN = Color3.fromRGB(80, 200, 80)
local GREEN_DARK = Color3.fromRGB(40, 130, 40)
local GOLD = Color3.fromRGB(255, 200, 50)
local GOLD_DARK = Color3.fromRGB(180, 130, 10)
local RED_BTN = Color3.fromRGB(240, 60, 60)
local TEXT_DARK = Color3.fromRGB(40, 40, 60)
local TEXT_MED = Color3.fromRGB(100, 100, 130)
local PROGRESS_BG = Color3.fromRGB(50, 130, 170)
local MODAL_BORDER = Color3.fromRGB(100, 180, 255)

local MODAL_W, MODAL_H = 500, 650
local bounceTween = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local POTION_UNLOCKS = {
	[3]  = "Luck Potion 2 (2x Luck)",
	[5]  = "Money Potion 2 (2x Cash)",
	[8]  = "Luck Potion 3 (4x Luck)",
	[10] = "Money Potion 3 (4x Cash)",
}

-------------------------------------------------
-- GET CURRENT REBIRTH DATA
-------------------------------------------------

local function getRebirthCount()
	local HUDController = require(script.Parent.HUDController)
	return HUDController.Data.rebirthCount or 0
end

-------------------------------------------------
-- FORMAT NUMBER
-------------------------------------------------
local function fmtNum(n)
	if n >= 1e12 then return string.format("%.1fT", n / 1e12) end
	if n >= 1e9  then return string.format("%.1fB", n / 1e9) end
	if n >= 1e6  then return string.format("%.1fM", n / 1e6) end
	if n >= 1e3  then return string.format("%.1fK", n / 1e3) end
	return tostring(n)
end

-------------------------------------------------
-- HELPER: text stroke
-------------------------------------------------
local function addStroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.new(0, 0, 0)
	s.Thickness = thickness or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = parent
	return s
end

-------------------------------------------------
-- UPDATE DISPLAY
-------------------------------------------------

local function updateDisplay()
	local current = getRebirthCount()
	local nextLevel = current + 1

	if subtitleRef then
		subtitleRef.Text = "Rebirth " .. current .. " / " .. Economy.MaxRebirths
	end

	if progressFillRef then
		local pct = math.clamp(current / Economy.MaxRebirths, 0, 1)
		TweenService:Create(progressFillRef, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {
			Size = UDim2.new(pct, 0, 1, 0)
		}):Play()
	end
	if progressTextRef then
		progressTextRef.Text = current .. " / " .. Economy.MaxRebirths
	end

	if current >= Economy.MaxRebirths then
		if titleRef then titleRef.Text = "MAX REBIRTH" end
		if levelTextRef then levelTextRef.Text = "MAX" end
		if coinBonusValueRef then
			coinBonusValueRef.Text = "+" .. Economy.GetRebirthBonusPercent(current) .. "%"
		end
		if slotValueRef then slotValueRef.Text = "MAXED" end
		if luckValueRef then luckValueRef.Text = "+" .. (current * 2) .. "%" end
		if caseUnlockRow then caseUnlockRow.Visible = false end
		if potionUnlockRow then potionUnlockRow.Visible = false end
		if noUnlocksRef then noUnlocksRef.Visible = false end
		if costRef then costRef.Visible = false end
		if confirmBtnRef then confirmBtnRef.Visible = false end
		if warnRef then warnRef.Visible = false end
		if maxedRef then
			maxedRef.Text = "You've reached the highest rebirth!"
			maxedRef.Visible = true
		end
		return
	end

	local info = Economy.GetRebirthInfo(nextLevel)
	if not info then return end

	if maxedRef then maxedRef.Visible = false end
	if costRef then costRef.Visible = true end
	if confirmBtnRef then confirmBtnRef.Visible = true end
	if warnRef then warnRef.Visible = true end

	if titleRef then titleRef.Text = "REBIRTH" end
	if levelTextRef then levelTextRef.Text = tostring(nextLevel) end

	if coinBonusValueRef then
		coinBonusValueRef.Text = "+" .. info.coinBonus .. "%"
	end

	if slotValueRef then
		local currentSlots = SlotsConfig.GetSlotsForRebirth(current)
		local nextSlots = SlotsConfig.GetSlotsForRebirth(nextLevel)
		if nextSlots > currentSlots then
			slotValueRef.Text = currentSlots .. " \u{2192} " .. nextSlots
		else
			slotValueRef.Text = tostring(currentSlots) .. " (max)"
		end
	end

	if luckValueRef then
		luckValueRef.Text = "+" .. (nextLevel * 2) .. "%"
	end

	local hasBonusUnlock = false

	if caseUnlockRow then
		if info.unlocksCase then
			caseUnlockRow.Visible = true
			hasBonusUnlock = true
			if caseUnlockImage then
				caseUnlockImage.Image = Economy.CrateImageIds[info.unlocksCase] or ""
			end
			if caseUnlockText then
				caseUnlockText.Text = Economy.CrateNames[info.unlocksCase] or ("Case " .. info.unlocksCase)
			end
		else
			caseUnlockRow.Visible = false
		end
	end

	if potionUnlockRow then
		local potionName = POTION_UNLOCKS[nextLevel]
		if potionName then
			potionUnlockRow.Visible = true
			hasBonusUnlock = true
			if potionUnlockText then potionUnlockText.Text = potionName end
		else
			potionUnlockRow.Visible = false
		end
	end

	if noUnlocksRef then
		noUnlocksRef.Visible = not hasBonusUnlock
	end

	if costRef then costRef.Text = "Cost: $" .. fmtNum(info.cost) end
	if confirmTextRef then confirmTextRef.Text = "REBIRTH" end
end

-------------------------------------------------
-- BUILD UI
-------------------------------------------------
local function buildUI()
	screenGui = UIHelper.CreateScreenGui("RebirthGui", 22)
	screenGui.Parent = playerGui

	overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.4
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.ZIndex = 1
	overlay.Parent = screenGui

	modalFrame = Instance.new("Frame")
	modalFrame.Name = "RebirthModal"
	modalFrame.Size = UDim2.new(0, MODAL_W, 0, MODAL_H)
	modalFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	modalFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	modalFrame.BackgroundColor3 = Color3.fromRGB(220, 235, 255)
	modalFrame.BorderSizePixel = 0
	modalFrame.Visible = false
	modalFrame.ZIndex = 2
	modalFrame.ClipsDescendants = true
	modalFrame.Parent = screenGui

	Instance.new("UICorner", modalFrame).CornerRadius = UDim.new(0, 22)
	local mStroke = Instance.new("UIStroke")
	mStroke.Color = MODAL_BORDER
	mStroke.Thickness = 3
	mStroke.Parent = modalFrame

	local bgGrad = Instance.new("UIGradient")
	bgGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, BG_TOP),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(225, 235, 255)),
		ColorSequenceKeypoint.new(1, BG_BOTTOM),
	})
	bgGrad.Rotation = 180
	bgGrad.Parent = modalFrame

	UIHelper.MakeResponsiveModal(modalFrame, MODAL_W, MODAL_H)

	-- ===== HEADER =====
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 62)
	header.BackgroundTransparency = 1
	header.ZIndex = 3
	header.Parent = modalFrame

	titleRef = Instance.new("TextLabel")
	titleRef.Size = UDim2.new(0.6, 0, 0, 36)
	titleRef.Position = UDim2.new(0, 22, 0, 10)
	titleRef.BackgroundTransparency = 1
	titleRef.Text = "REBIRTH"
	titleRef.TextColor3 = TEXT_DARK
	titleRef.Font = FONT
	titleRef.TextSize = 34
	titleRef.TextXAlignment = Enum.TextXAlignment.Left
	titleRef.ZIndex = 3
	titleRef.Parent = header
	addStroke(titleRef, Color3.new(1, 1, 1), 2)

	subtitleRef = Instance.new("TextLabel")
	subtitleRef.Size = UDim2.new(0.5, 0, 0, 18)
	subtitleRef.Position = UDim2.new(0, 24, 0, 44)
	subtitleRef.BackgroundTransparency = 1
	subtitleRef.Text = "Rebirth 0 / " .. Economy.MaxRebirths
	subtitleRef.TextColor3 = TEXT_MED
	subtitleRef.Font = FONT_SUB
	subtitleRef.TextSize = 16
	subtitleRef.TextXAlignment = Enum.TextXAlignment.Left
	subtitleRef.ZIndex = 3
	subtitleRef.Parent = header

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 44, 0, 44)
	closeBtn.Position = UDim2.new(1, -14, 0, 10)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = RED_BTN
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = FONT
	closeBtn.TextSize = 24
	closeBtn.BorderSizePixel = 0
	closeBtn.AutoButtonColor = false
	closeBtn.ZIndex = 5
	closeBtn.Parent = modalFrame
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1, 0)
	local cStroke = Instance.new("UIStroke")
	cStroke.Color = Color3.fromRGB(180, 40, 40)
	cStroke.Thickness = 2
	cStroke.Parent = closeBtn

	closeBtn.MouseEnter:Connect(function()
		TweenService:Create(closeBtn, bounceTween, {
			Size = UDim2.new(0, 50, 0, 50),
			BackgroundColor3 = Color3.fromRGB(255, 80, 80),
		}):Play()
	end)
	closeBtn.MouseLeave:Connect(function()
		TweenService:Create(closeBtn, bounceTween, {
			Size = UDim2.new(0, 44, 0, 44),
			BackgroundColor3 = RED_BTN,
		}):Play()
	end)
	closeBtn.MouseButton1Click:Connect(function() RebirthController.Close() end)

	-- ===== CONTENT =====
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -36, 1, -70)
	content.Position = UDim2.new(0.5, 0, 0, 66)
	content.AnchorPoint = Vector2.new(0.5, 0)
	content.BackgroundTransparency = 1
	content.ZIndex = 3
	content.Parent = modalFrame

	-- == Level badge ==
	local badgeSize = 110
	local badgeOuter = Instance.new("Frame")
	badgeOuter.Name = "BadgeGlow"
	badgeOuter.Size = UDim2.new(0, badgeSize + 22, 0, badgeSize + 22)
	badgeOuter.Position = UDim2.new(0.5, 0, 0, -6)
	badgeOuter.AnchorPoint = Vector2.new(0.5, 0)
	badgeOuter.BackgroundColor3 = Color3.fromRGB(200, 190, 255)
	badgeOuter.BackgroundTransparency = 0.5
	badgeOuter.BorderSizePixel = 0
	badgeOuter.ZIndex = 3
	badgeOuter.Parent = content
	Instance.new("UICorner", badgeOuter).CornerRadius = UDim.new(1, 0)

	local badgeFrame = Instance.new("Frame")
	badgeFrame.Name = "LevelBadge"
	badgeFrame.Size = UDim2.new(0, badgeSize, 0, badgeSize)
	badgeFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	badgeFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	badgeFrame.BackgroundColor3 = Color3.fromRGB(220, 210, 255)
	badgeFrame.BorderSizePixel = 0
	badgeFrame.ZIndex = 4
	badgeFrame.Parent = badgeOuter
	Instance.new("UICorner", badgeFrame).CornerRadius = UDim.new(1, 0)

	local badgeGrad = Instance.new("UIGradient")
	badgeGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 170, 210)),
		ColorSequenceKeypoint.new(0.2, Color3.fromRGB(200, 160, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(160, 210, 255)),
		ColorSequenceKeypoint.new(0.8, Color3.fromRGB(160, 255, 210)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 170)),
	})
	badgeGrad.Rotation = 135
	badgeGrad.Parent = badgeFrame

	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Color = Color3.new(1, 1, 1)
	badgeStroke.Thickness = 3
	badgeStroke.Parent = badgeFrame

	levelTextRef = Instance.new("TextLabel")
	levelTextRef.Size = UDim2.new(1, 0, 1, 0)
	levelTextRef.BackgroundTransparency = 1
	levelTextRef.Text = "1"
	levelTextRef.TextColor3 = Color3.new(1, 1, 1)
	levelTextRef.Font = FONT
	levelTextRef.TextSize = 56
	levelTextRef.ZIndex = 5
	levelTextRef.Parent = badgeFrame
	addStroke(levelTextRef, Color3.fromRGB(100, 70, 160), 2.5)

	-- == Progress bar ==
	local barY = badgeSize + 22
	local barBg = Instance.new("Frame")
	barBg.Name = "ProgressBg"
	barBg.Size = UDim2.new(0.85, 0, 0, 28)
	barBg.Position = UDim2.new(0.5, 0, 0, barY)
	barBg.AnchorPoint = Vector2.new(0.5, 0)
	barBg.BackgroundColor3 = PROGRESS_BG
	barBg.BorderSizePixel = 0
	barBg.ZIndex = 4
	barBg.Parent = content
	Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 14)
	local barStroke = Instance.new("UIStroke")
	barStroke.Color = Color3.fromRGB(30, 90, 130)
	barStroke.Thickness = 2
	barStroke.Parent = barBg

	progressFillRef = Instance.new("Frame")
	progressFillRef.Name = "Fill"
	progressFillRef.Size = UDim2.new(0, 0, 1, 0)
	progressFillRef.BackgroundColor3 = Color3.fromRGB(100, 220, 80)
	progressFillRef.BorderSizePixel = 0
	progressFillRef.ZIndex = 5
	progressFillRef.Parent = barBg
	Instance.new("UICorner", progressFillRef).CornerRadius = UDim.new(0, 14)
	local fillGrad = Instance.new("UIGradient")
	fillGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 230, 80)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 190, 50)),
	})
	fillGrad.Parent = progressFillRef

	progressTextRef = Instance.new("TextLabel")
	progressTextRef.Size = UDim2.new(1, 0, 1, 0)
	progressTextRef.BackgroundTransparency = 1
	progressTextRef.Text = "0 / " .. Economy.MaxRebirths
	progressTextRef.TextColor3 = Color3.new(1, 1, 1)
	progressTextRef.Font = FONT_SUB
	progressTextRef.TextSize = 16
	progressTextRef.ZIndex = 6
	progressTextRef.Parent = barBg
	addStroke(progressTextRef, Color3.new(0, 0, 0), 1.5)

	-- ===== REWARDS HEADER =====
	local rwdY = barY + 40
	local rwdTitle = Instance.new("TextLabel")
	rwdTitle.Size = UDim2.new(1, 0, 0, 24)
	rwdTitle.Position = UDim2.new(0, 0, 0, rwdY)
	rwdTitle.BackgroundTransparency = 1
	rwdTitle.Text = "REWARDS"
	rwdTitle.TextColor3 = TEXT_DARK
	rwdTitle.Font = FONT
	rwdTitle.TextSize = 22
	rwdTitle.ZIndex = 4
	rwdTitle.Parent = content
	addStroke(rwdTitle, Color3.new(1, 1, 1), 1.5)

	-- ===== THREE REWARD CARDS =====
	local cardsY = rwdY + 30
	local gap = 10
	local cardW = math.floor((MODAL_W - 36 - gap * 2) / 3)
	local cardH = 100

	local function makeCard(name, xOffset, iconText, titleText, valueColor, valueDarkColor)
		local card = Instance.new("Frame")
		card.Name = name
		card.Size = UDim2.new(0, cardW, 0, cardH)
		card.Position = UDim2.new(0, xOffset, 0, cardsY)
		card.BackgroundColor3 = CARD_BG
		card.BorderSizePixel = 0
		card.ZIndex = 4
		card.Parent = content
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)
		local cs = Instance.new("UIStroke")
		cs.Color = CARD_BORDER
		cs.Thickness = 1.5
		cs.Parent = card

		local cTitle = Instance.new("TextLabel")
		cTitle.Size = UDim2.new(1, 0, 0, 18)
		cTitle.Position = UDim2.new(0.5, 0, 0, 8)
		cTitle.AnchorPoint = Vector2.new(0.5, 0)
		cTitle.BackgroundTransparency = 1
		cTitle.Text = titleText
		cTitle.TextColor3 = TEXT_MED
		cTitle.Font = FONT_SUB
		cTitle.TextSize = 14
		cTitle.ZIndex = 5
		cTitle.Parent = card

		local cIcon = Instance.new("TextLabel")
		cIcon.Size = UDim2.new(1, 0, 0, 28)
		cIcon.Position = UDim2.new(0.5, 0, 0, 28)
		cIcon.AnchorPoint = Vector2.new(0.5, 0)
		cIcon.BackgroundTransparency = 1
		cIcon.Text = iconText
		cIcon.TextSize = 26
		cIcon.Font = FONT
		cIcon.ZIndex = 5
		cIcon.Parent = card

		local cValue = Instance.new("TextLabel")
		cValue.Name = "Value"
		cValue.Size = UDim2.new(1, -6, 0, 28)
		cValue.Position = UDim2.new(0.5, 0, 1, -8)
		cValue.AnchorPoint = Vector2.new(0.5, 1)
		cValue.BackgroundTransparency = 1
		cValue.Text = ""
		cValue.TextColor3 = valueColor
		cValue.Font = FONT
		cValue.TextSize = 26
		cValue.ZIndex = 5
		cValue.Parent = card
		addStroke(cValue, valueDarkColor, 1.5)

		return card, cValue
	end

	local _, coinVal = makeCard(
		"CoinCard", 0,
		"\u{1F4B0}", "Coin Bonus",
		GREEN, GREEN_DARK
	)
	coinBonusValueRef = coinVal

	local _, slotVal = makeCard(
		"SlotCard", cardW + gap,
		"\u{1F511}", "Base Slot",
		Color3.fromRGB(80, 160, 255), Color3.fromRGB(30, 80, 160)
	)
	slotValueRef = slotVal

	local _, luckVal = makeCard(
		"LuckCard", (cardW + gap) * 2,
		"\u{2728}", "Luck Bonus",
		Color3.fromRGB(255, 180, 50), Color3.fromRGB(160, 100, 10)
	)
	luckValueRef = luckVal

	-- ===== ALSO UNLOCKS SECTION =====
	local bonusY = cardsY + cardH + 12
	local bonusFrame = Instance.new("Frame")
	bonusFrame.Name = "BonusUnlocks"
	bonusFrame.Size = UDim2.new(1, 0, 0, 90)
	bonusFrame.Position = UDim2.new(0, 0, 0, bonusY)
	bonusFrame.BackgroundColor3 = Color3.fromRGB(240, 245, 255)
	bonusFrame.BorderSizePixel = 0
	bonusFrame.ZIndex = 4
	bonusFrame.Parent = content
	Instance.new("UICorner", bonusFrame).CornerRadius = UDim.new(0, 14)
	local buStroke = Instance.new("UIStroke")
	buStroke.Color = Color3.fromRGB(200, 215, 240)
	buStroke.Thickness = 1.5
	buStroke.Parent = bonusFrame

	local alsoTitle = Instance.new("TextLabel")
	alsoTitle.Size = UDim2.new(1, 0, 0, 20)
	alsoTitle.Position = UDim2.new(0.5, 0, 0, 6)
	alsoTitle.AnchorPoint = Vector2.new(0.5, 0)
	alsoTitle.BackgroundTransparency = 1
	alsoTitle.Text = "ALSO UNLOCKS"
	alsoTitle.TextColor3 = TEXT_MED
	alsoTitle.Font = FONT_SUB
	alsoTitle.TextSize = 14
	alsoTitle.ZIndex = 5
	alsoTitle.Parent = bonusFrame

	local rowH = 30
	local rowStart = 28

	local function makeUnlockRow(name, yPos, icon, textColor)
		local row = Instance.new("Frame")
		row.Name = name
		row.Size = UDim2.new(1, -24, 0, rowH)
		row.Position = UDim2.new(0.5, 0, 0, yPos)
		row.AnchorPoint = Vector2.new(0.5, 0)
		row.BackgroundTransparency = 1
		row.ZIndex = 5
		row.Visible = false
		row.Parent = bonusFrame

		local ico = Instance.new("TextLabel")
		ico.Size = UDim2.new(0, 26, 0, 26)
		ico.Position = UDim2.new(0, 0, 0.5, 0)
		ico.AnchorPoint = Vector2.new(0, 0.5)
		ico.BackgroundTransparency = 1
		ico.Text = icon
		ico.TextSize = 22
		ico.Font = FONT
		ico.ZIndex = 5
		ico.Parent = row

		local txt = Instance.new("TextLabel")
		txt.Size = UDim2.new(1, -36, 0, rowH)
		txt.Position = UDim2.new(0, 32, 0, 0)
		txt.BackgroundTransparency = 1
		txt.Text = ""
		txt.TextColor3 = textColor
		txt.Font = FONT
		txt.TextSize = 18
		txt.TextXAlignment = Enum.TextXAlignment.Left
		txt.ZIndex = 5
		txt.Parent = row
		addStroke(txt, Color3.new(1, 1, 1), 1)

		return row, txt
	end

	caseUnlockRow, caseUnlockText = makeUnlockRow(
		"CaseUnlock", rowStart,
		"\u{1F4E6}", Color3.fromRGB(60, 140, 255)
	)

	caseUnlockImage = Instance.new("ImageLabel")
	caseUnlockImage.Size = UDim2.new(0, 26, 0, 26)
	caseUnlockImage.Position = UDim2.new(1, 0, 0.5, 0)
	caseUnlockImage.AnchorPoint = Vector2.new(1, 0.5)
	caseUnlockImage.BackgroundTransparency = 1
	caseUnlockImage.ScaleType = Enum.ScaleType.Fit
	caseUnlockImage.ZIndex = 5
	caseUnlockImage.Parent = caseUnlockRow

	potionUnlockRow, potionUnlockText = makeUnlockRow(
		"PotionUnlock", rowStart + rowH + 2,
		"\u{1F9EA}", Color3.fromRGB(170, 80, 220)
	)

	noUnlocksRef = Instance.new("TextLabel")
	noUnlocksRef.Size = UDim2.new(1, -24, 0, 50)
	noUnlocksRef.Position = UDim2.new(0.5, 0, 0, rowStart)
	noUnlocksRef.AnchorPoint = Vector2.new(0.5, 0)
	noUnlocksRef.BackgroundTransparency = 1
	noUnlocksRef.Text = "No additional unlocks at this level"
	noUnlocksRef.TextColor3 = Color3.fromRGB(160, 165, 185)
	noUnlocksRef.Font = FONT_SUB
	noUnlocksRef.TextSize = 15
	noUnlocksRef.ZIndex = 5
	noUnlocksRef.Visible = false
	noUnlocksRef.Parent = bonusFrame

	-- ===== COST =====
	local bottomY = bonusY + 102
	costRef = Instance.new("TextLabel")
	costRef.Name = "Cost"
	costRef.Size = UDim2.new(1, 0, 0, 28)
	costRef.Position = UDim2.new(0, 0, 0, bottomY)
	costRef.BackgroundTransparency = 1
	costRef.Text = "Cost: $100"
	costRef.TextColor3 = GOLD
	costRef.Font = FONT
	costRef.TextSize = 24
	costRef.ZIndex = 4
	costRef.Parent = content
	addStroke(costRef, GOLD_DARK, 1.5)

	-- ===== CONFIRM BUTTON =====
	local btnY = bottomY + 34
	confirmBtnRef = Instance.new("TextButton")
	confirmBtnRef.Name = "ConfirmBtn"
	confirmBtnRef.Size = UDim2.new(1, 0, 0, 56)
	confirmBtnRef.Position = UDim2.new(0, 0, 0, btnY)
	confirmBtnRef.BackgroundColor3 = GOLD
	confirmBtnRef.BorderSizePixel = 0
	confirmBtnRef.AutoButtonColor = false
	confirmBtnRef.Text = ""
	confirmBtnRef.ZIndex = 4
	confirmBtnRef.Parent = content
	Instance.new("UICorner", confirmBtnRef).CornerRadius = UDim.new(0, 14)
	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color = GOLD_DARK
	btnStroke.Thickness = 2
	btnStroke.Parent = confirmBtnRef
	local btnGrad = Instance.new("UIGradient")
	btnGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 225, 80)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 170, 30)),
	})
	btnGrad.Rotation = 90
	btnGrad.Parent = confirmBtnRef

	confirmTextRef = Instance.new("TextLabel")
	confirmTextRef.Size = UDim2.new(1, 0, 1, 0)
	confirmTextRef.BackgroundTransparency = 1
	confirmTextRef.Text = "REBIRTH"
	confirmTextRef.TextColor3 = Color3.new(1, 1, 1)
	confirmTextRef.Font = FONT
	confirmTextRef.TextSize = 30
	confirmTextRef.ZIndex = 5
	confirmTextRef.Parent = confirmBtnRef
	addStroke(confirmTextRef, Color3.fromRGB(120, 80, 0), 2)

	local idleSize = UDim2.new(1, 0, 0, 56)
	local hoverSize = UDim2.new(1, 6, 0, 60)
	confirmBtnRef.MouseEnter:Connect(function()
		TweenService:Create(confirmBtnRef, bounceTween, { Size = hoverSize }):Play()
	end)
	confirmBtnRef.MouseLeave:Connect(function()
		TweenService:Create(confirmBtnRef, bounceTween, { Size = idleSize }):Play()
	end)
	confirmBtnRef.MouseButton1Click:Connect(function()
		local current = getRebirthCount()
		if current >= Economy.MaxRebirths then return end
		confirmTextRef.Text = "REBIRTHING..."
		confirmBtnRef.BackgroundColor3 = Color3.fromRGB(180, 180, 180)
		RebirthRequest:FireServer()
	end)

	-- ===== WARNING =====
	local warnY = btnY + 62
	warnRef = Instance.new("TextLabel")
	warnRef.Name = "Warning"
	warnRef.Size = UDim2.new(1, 0, 0, 24)
	warnRef.Position = UDim2.new(0, 0, 0, warnY)
	warnRef.BackgroundTransparency = 1
	warnRef.Text = "Resets your money and active potions"
	warnRef.TextColor3 = Color3.fromRGB(220, 80, 80)
	warnRef.Font = FONT_SUB
	warnRef.TextSize = 14
	warnRef.ZIndex = 4
	warnRef.Parent = content

	-- ===== MAXED LABEL (hidden) =====
	maxedRef = Instance.new("TextLabel")
	maxedRef.Name = "Maxed"
	maxedRef.Size = UDim2.new(1, 0, 0, 56)
	maxedRef.Position = UDim2.new(0, 0, 0, btnY)
	maxedRef.BackgroundTransparency = 1
	maxedRef.Text = ""
	maxedRef.TextColor3 = GOLD
	maxedRef.Font = FONT
	maxedRef.TextSize = 22
	maxedRef.TextWrapped = true
	maxedRef.Visible = false
	maxedRef.ZIndex = 4
	maxedRef.Parent = content
	addStroke(maxedRef, GOLD_DARK, 1)
end

-------------------------------------------------
-- OPEN / CLOSE
-------------------------------------------------

function RebirthController.Open()
	if isOpen then
		RebirthController.Close()
		return
	end
	isOpen = true
	updateDisplay()
	overlay.Visible = true
	modalFrame.Visible = true
	UIHelper.ScaleIn(modalFrame, 0.3)
end

function RebirthController.IsOpen()
	return isOpen
end

function RebirthController.Close()
	if not isOpen then return end
	isOpen = false
	if overlay then overlay.Visible = false end
	if modalFrame then UIHelper.ScaleOut(modalFrame, 0.2) end
end

-------------------------------------------------
-- INIT
-------------------------------------------------

function RebirthController.Init()
	buildUI()

	OpenRebirthGui.OnClientEvent:Connect(function()
		RebirthController.Open()
	end)

	RebirthResult.OnClientEvent:Connect(function(data)
		if data.success then
			if confirmTextRef then
				confirmTextRef.Text = "REBIRTHED!"
				confirmBtnRef.BackgroundColor3 = GREEN
				task.delay(1.2, function()
					confirmBtnRef.BackgroundColor3 = GOLD
					updateDisplay()
				end)
			end
		else
			if confirmTextRef then
				confirmTextRef.Text = data.reason or "Failed!"
				confirmBtnRef.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
				task.delay(1.5, function()
					confirmBtnRef.BackgroundColor3 = GOLD
					updateDisplay()
				end)
			end
		end
	end)
end

return RebirthController
