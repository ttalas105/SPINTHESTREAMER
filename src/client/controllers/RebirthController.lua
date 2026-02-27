--[[
	RebirthController.lua
	Rebirth UI – dark-themed panel matching the Case Shop / Potion Shop style.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
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
local levelBadgeRef, levelTextRef
local bonusValueRef, caseImageRef, caseNameRef, slotValueRef
local costRef, confirmBtnRef, confirmTextRef
local warnRef, maxedRef
local progressBarRef, progressFillRef, progressTextRef

local FONT = Enum.Font.FredokaOne
local FONT_SUB = Enum.Font.GothamBold
local MODAL_BG = Color3.fromRGB(30, 25, 45)
local ACCENT = Color3.fromRGB(255, 160, 50)
local ACCENT_DARK = Color3.fromRGB(200, 100, 20)
local GREEN = Color3.fromRGB(80, 220, 100)
local RED_BTN = Color3.fromRGB(220, 55, 55)
local MODAL_W, MODAL_H = 440, 500

local bounceTween = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

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
	if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
	if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
	return tostring(n)
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
		if titleRef then titleRef.Text = "Max Rebirth" end
		if levelTextRef then levelTextRef.Text = "MAX" end
		if bonusValueRef then
			bonusValueRef.Text = "+" .. Economy.GetRebirthBonusPercent(current) .. "% coins"
		end
		if caseImageRef then caseImageRef.Visible = false end
		if caseNameRef then caseNameRef.Text = "Base Slot Unlock" end
		if slotValueRef then slotValueRef.Text = "MAXED" end
		if costRef then costRef.Visible = false end
		if confirmBtnRef then confirmBtnRef.Visible = false end
		if warnRef then warnRef.Visible = false end
		if maxedRef then
			maxedRef.Text = "You've reached the highest rebirth!"
			maxedRef.Visible = true
		end
	-- Show next rebirth info
		return
	end

	local info = Economy.GetRebirthInfo(nextLevel)
	if not info then return end

	if maxedRef then maxedRef.Visible = false end
	if costRef then costRef.Visible = true end
	if confirmBtnRef then confirmBtnRef.Visible = true end
	if warnRef then warnRef.Visible = true end

	if titleRef then titleRef.Text = "Rebirth" end
	if levelTextRef then levelTextRef.Text = tostring(nextLevel) end

	if bonusValueRef then
		bonusValueRef.Text = "+" .. info.coinBonus .. "% coins"
	end

	if caseImageRef then caseImageRef.Visible = false end
	if caseNameRef then
		caseNameRef.Text = "Base Slot Unlock"
	end
	if slotValueRef then
		slotValueRef.Text = "Next slot"
	end

	if costRef then costRef.Text = "$" .. fmtNum(info.cost) end
	if confirmTextRef then confirmTextRef.Text = "REBIRTH" end
end

-------------------------------------------------
-- HELPER: small text stroke
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
-- BUILD UI
-------------------------------------------------
local function buildUI()
	screenGui = UIHelper.CreateScreenGui("RebirthGui", 22)
	screenGui.Parent = playerGui

	-- Dim overlay
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
	modalFrame.Name = "RebirthModal"
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

	titleRef = Instance.new("TextLabel")
	titleRef.Size = UDim2.new(0.6, 0, 0, 32)
	titleRef.Position = UDim2.new(0, 20, 0, 12)
	titleRef.BackgroundTransparency = 1
	titleRef.Text = "Rebirth"
	titleRef.TextColor3 = Color3.new(1, 1, 1)
	titleRef.Font = FONT
	titleRef.TextSize = 30
	titleRef.TextXAlignment = Enum.TextXAlignment.Left
	titleRef.ZIndex = 3
	titleRef.Parent = header
	addStroke(titleRef, Color3.new(0, 0, 0), 1.5)

	subtitleRef = Instance.new("TextLabel")
	subtitleRef.Size = UDim2.new(0.5, 0, 0, 16)
	subtitleRef.Position = UDim2.new(0, 22, 0, 42)
	subtitleRef.BackgroundTransparency = 1
	subtitleRef.Text = "Rebirth 0 / " .. Economy.MaxRebirths
	subtitleRef.TextColor3 = Color3.fromRGB(150, 145, 170)
	subtitleRef.Font = FONT_SUB
	subtitleRef.TextSize = 12
	subtitleRef.TextXAlignment = Enum.TextXAlignment.Left
	subtitleRef.ZIndex = 3
	subtitleRef.Parent = header

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 40, 0, 40)
	closeBtn.Position = UDim2.new(1, -14, 0, 10)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = RED_BTN
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
	cStroke.Color = Color3.fromRGB(160, 30, 30)
	cStroke.Thickness = 1.5
	cStroke.Parent = closeBtn
	addStroke(closeBtn, Color3.fromRGB(80, 0, 0), 1)

	closeBtn.MouseEnter:Connect(function()
		TweenService:Create(closeBtn, bounceTween, { Size = UDim2.new(0, 46, 0, 46), BackgroundColor3 = Color3.fromRGB(255, 75, 75) }):Play()
	end)
	closeBtn.MouseLeave:Connect(function()
		TweenService:Create(closeBtn, bounceTween, { Size = UDim2.new(0, 40, 0, 40), BackgroundColor3 = RED_BTN }):Play()
	end)
	closeBtn.MouseButton1Click:Connect(function() RebirthController.Close() end)

	-- Divider
	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(1, -30, 0, 1)
	divider.Position = UDim2.new(0.5, 0, 0, 62)
	divider.AnchorPoint = Vector2.new(0.5, 0)
	divider.BackgroundColor3 = Color3.fromRGB(60, 55, 80)
	divider.BorderSizePixel = 0
	divider.ZIndex = 3
	divider.Parent = modalFrame

	-- ===== CONTENT AREA =====
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -40, 1, -75)
	content.Position = UDim2.new(0.5, 0, 0, 72)
	content.AnchorPoint = Vector2.new(0.5, 0)
	content.BackgroundTransparency = 1
	content.ZIndex = 3
	content.Parent = modalFrame

	-- == Level badge (big centered number) ==
	local badgeSize = 90
	local badgeFrame = Instance.new("Frame")
	badgeFrame.Name = "LevelBadge"
	badgeFrame.Size = UDim2.new(0, badgeSize, 0, badgeSize)
	badgeFrame.Position = UDim2.new(0.5, 0, 0, 0)
	badgeFrame.AnchorPoint = Vector2.new(0.5, 0)
	badgeFrame.BackgroundColor3 = Color3.fromRGB(50, 40, 75)
	badgeFrame.BorderSizePixel = 0
	badgeFrame.ZIndex = 4
	badgeFrame.Parent = content
	Instance.new("UICorner", badgeFrame).CornerRadius = UDim.new(1, 0)
	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Color = ACCENT
	badgeStroke.Thickness = 2
	badgeStroke.Parent = badgeFrame

	levelBadgeRef = badgeFrame

	levelTextRef = Instance.new("TextLabel")
	levelTextRef.Size = UDim2.new(1, 0, 1, 0)
	levelTextRef.BackgroundTransparency = 1
	levelTextRef.Text = "1"
	levelTextRef.TextColor3 = ACCENT
	levelTextRef.Font = FONT
	levelTextRef.TextSize = 40
	levelTextRef.ZIndex = 5
	levelTextRef.Parent = badgeFrame
	addStroke(levelTextRef, ACCENT_DARK, 1.5)

	-- == Progress bar ==
	local barY = badgeSize + 12
	local barBg = Instance.new("Frame")
	barBg.Name = "ProgressBg"
	barBg.Size = UDim2.new(1, 0, 0, 18)
	barBg.Position = UDim2.new(0, 0, 0, barY)
	barBg.BackgroundColor3 = Color3.fromRGB(40, 35, 60)
	barBg.BorderSizePixel = 0
	barBg.ZIndex = 4
	barBg.Parent = content
	Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 9)

	progressFillRef = Instance.new("Frame")
	progressFillRef.Name = "Fill"
	progressFillRef.Size = UDim2.new(0, 0, 1, 0)
	progressFillRef.BackgroundColor3 = ACCENT
	progressFillRef.BorderSizePixel = 0
	progressFillRef.ZIndex = 5
	progressFillRef.Parent = barBg
	Instance.new("UICorner", progressFillRef).CornerRadius = UDim.new(0, 9)
	local fillGrad = Instance.new("UIGradient")
	fillGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 120, 30)),
	})
	fillGrad.Parent = progressFillRef

	progressTextRef = Instance.new("TextLabel")
	progressTextRef.Size = UDim2.new(1, 0, 1, 0)
	progressTextRef.BackgroundTransparency = 1
	progressTextRef.Text = "0 / " .. Economy.MaxRebirths
	progressTextRef.TextColor3 = Color3.new(1, 1, 1)
	progressTextRef.Font = FONT_SUB
	progressTextRef.TextSize = 11
	progressTextRef.ZIndex = 6
	progressTextRef.Parent = barBg
	addStroke(progressTextRef, Color3.new(0, 0, 0), 1)

	progressBarRef = barBg

	-- == Rewards card ==
	local cardY = barY + 30
	local rewardCard = Instance.new("Frame")
	rewardCard.Name = "RewardCard"
	rewardCard.Size = UDim2.new(1, 0, 0, 120)
	rewardCard.Position = UDim2.new(0, 0, 0, cardY)
	rewardCard.BackgroundColor3 = Color3.fromRGB(40, 35, 60)
	rewardCard.BorderSizePixel = 0
	rewardCard.ZIndex = 4
	rewardCard.Parent = content
	Instance.new("UICorner", rewardCard).CornerRadius = UDim.new(0, 14)

	-- "Rewards" header inside card
	local rwdTitle = Instance.new("TextLabel")
	rwdTitle.Size = UDim2.new(1, -16, 0, 22)
	rwdTitle.Position = UDim2.new(0, 12, 0, 8)
	rwdTitle.BackgroundTransparency = 1
	rwdTitle.Text = "REWARDS"
	rwdTitle.TextColor3 = Color3.fromRGB(180, 175, 200)
	rwdTitle.Font = FONT_SUB
	rwdTitle.TextSize = 12
	rwdTitle.TextXAlignment = Enum.TextXAlignment.Left
	rwdTitle.ZIndex = 5
	rwdTitle.Parent = rewardCard

	-- Coin bonus row
	local coinIcon = Instance.new("TextLabel")
	coinIcon.Size = UDim2.new(0, 30, 0, 30)
	coinIcon.Position = UDim2.new(0, 12, 0, 34)
	coinIcon.BackgroundTransparency = 1
	coinIcon.Text = "\u{1F4B0}"
	coinIcon.TextSize = 22
	coinIcon.Font = FONT
	coinIcon.ZIndex = 5
	coinIcon.Parent = rewardCard

	local coinLabel = Instance.new("TextLabel")
	coinLabel.Size = UDim2.new(0, 100, 0, 22)
	coinLabel.Position = UDim2.new(0, 46, 0, 38)
	coinLabel.BackgroundTransparency = 1
	coinLabel.Text = "Coin Bonus"
	coinLabel.TextColor3 = Color3.fromRGB(160, 160, 180)
	coinLabel.Font = FONT_SUB
	coinLabel.TextSize = 13
	coinLabel.TextXAlignment = Enum.TextXAlignment.Left
	coinLabel.ZIndex = 5
	coinLabel.Parent = rewardCard

	bonusValueRef = Instance.new("TextLabel")
	bonusValueRef.Size = UDim2.new(0, 120, 0, 22)
	bonusValueRef.Position = UDim2.new(1, -12, 0, 38)
	bonusValueRef.AnchorPoint = Vector2.new(1, 0)
	bonusValueRef.BackgroundTransparency = 1
	bonusValueRef.Text = "+5% coins"
	bonusValueRef.TextColor3 = GREEN
	bonusValueRef.Font = FONT
	bonusValueRef.TextSize = 18
	bonusValueRef.TextXAlignment = Enum.TextXAlignment.Right
	bonusValueRef.ZIndex = 5
	bonusValueRef.Parent = rewardCard
	addStroke(bonusValueRef, Color3.new(0, 0, 0), 1)

	-- Case unlock row
	caseImageRef = Instance.new("ImageLabel")
	caseImageRef.Size = UDim2.new(0, 40, 0, 40)
	caseImageRef.Position = UDim2.new(0, 7, 0, 68)
	caseImageRef.BackgroundTransparency = 1
	caseImageRef.Image = ""
	caseImageRef.ScaleType = Enum.ScaleType.Fit
	caseImageRef.ZIndex = 5
	caseImageRef.Parent = rewardCard

	caseNameRef = Instance.new("TextLabel")
	caseNameRef.Size = UDim2.new(0, 160, 0, 22)
	caseNameRef.Position = UDim2.new(0, 46, 0, 78)
	caseNameRef.BackgroundTransparency = 1
	caseNameRef.Text = "Base Slot Unlock"
	caseNameRef.TextColor3 = Color3.fromRGB(160, 160, 180)
	caseNameRef.Font = FONT_SUB
	caseNameRef.TextSize = 13
	caseNameRef.TextXAlignment = Enum.TextXAlignment.Left
	caseNameRef.ZIndex = 5
	caseNameRef.Parent = rewardCard
	addStroke(caseNameRef, Color3.new(0, 0, 0), 1)

	slotValueRef = Instance.new("TextLabel")
	slotValueRef.Size = UDim2.new(0, 120, 0, 22)
	slotValueRef.Position = UDim2.new(1, -12, 0, 78)
	slotValueRef.AnchorPoint = Vector2.new(1, 0)
	slotValueRef.BackgroundTransparency = 1
	slotValueRef.Text = "Next slot"
	slotValueRef.TextColor3 = GREEN
	slotValueRef.Font = FONT
	slotValueRef.TextSize = 18
	slotValueRef.TextXAlignment = Enum.TextXAlignment.Right
	slotValueRef.ZIndex = 5
	slotValueRef.Parent = rewardCard
	addStroke(slotValueRef, Color3.new(0, 0, 0), 1)

	-- == Cost display ==
	local costY = cardY + 132
	costRef = Instance.new("TextLabel")
	costRef.Name = "Cost"
	costRef.Size = UDim2.new(1, 0, 0, 28)
	costRef.Position = UDim2.new(0, 0, 0, costY)
	costRef.BackgroundTransparency = 1
	costRef.Text = "$100"
	costRef.TextColor3 = Color3.fromRGB(255, 220, 100)
	costRef.Font = FONT
	costRef.TextSize = 22
	costRef.ZIndex = 4
	costRef.Parent = content
	addStroke(costRef, Color3.new(0, 0, 0), 1)

	-- == Confirm button ==
	local btnY = costY + 34
	confirmBtnRef = Instance.new("TextButton")
	confirmBtnRef.Name = "ConfirmBtn"
	confirmBtnRef.Size = UDim2.new(1, 0, 0, 50)
	confirmBtnRef.Position = UDim2.new(0, 0, 0, btnY)
	confirmBtnRef.BackgroundColor3 = ACCENT
	confirmBtnRef.BorderSizePixel = 0
	confirmBtnRef.AutoButtonColor = false
	confirmBtnRef.Text = ""
	confirmBtnRef.ZIndex = 4
	confirmBtnRef.Parent = content
	Instance.new("UICorner", confirmBtnRef).CornerRadius = UDim.new(0, 14)
	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color = ACCENT_DARK
	btnStroke.Thickness = 1.5
	btnStroke.Parent = confirmBtnRef
	local btnGrad = Instance.new("UIGradient")
	btnGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 190, 70)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(240, 110, 30)),
	})
	btnGrad.Rotation = 90
	btnGrad.Parent = confirmBtnRef

	confirmTextRef = Instance.new("TextLabel")
	confirmTextRef.Size = UDim2.new(1, 0, 1, 0)
	confirmTextRef.BackgroundTransparency = 1
	confirmTextRef.Text = "REBIRTH"
	confirmTextRef.TextColor3 = Color3.new(1, 1, 1)
	confirmTextRef.Font = FONT
	confirmTextRef.TextSize = 24
	confirmTextRef.ZIndex = 5
	confirmTextRef.Parent = confirmBtnRef
	addStroke(confirmTextRef, Color3.new(0, 0, 0), 1.5)

	local idleSize = UDim2.new(1, 0, 0, 50)
	local hoverSize = UDim2.new(1, 6, 0, 54)
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
		confirmBtnRef.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
		RebirthRequest:FireServer()
	end)

	-- == Warning text (subtle, at bottom) ==
	local warnY = btnY + 58
	warnRef = Instance.new("TextLabel")
	warnRef.Name = "Warning"
	warnRef.Size = UDim2.new(1, 0, 0, 30)
	warnRef.Position = UDim2.new(0, 0, 0, warnY)
	warnRef.BackgroundTransparency = 1
	warnRef.Text = "Resets your money and active potions"
	warnRef.TextColor3 = Color3.fromRGB(200, 100, 100)
	warnRef.Font = FONT_SUB
	warnRef.TextSize = 12
	warnRef.ZIndex = 4
	warnRef.Parent = content

	-- == Maxed label (hidden by default) ==
	maxedRef = Instance.new("TextLabel")
	maxedRef.Name = "Maxed"
	maxedRef.Size = UDim2.new(1, 0, 0, 50)
	maxedRef.Position = UDim2.new(0, 0, 0, btnY)
	maxedRef.BackgroundTransparency = 1
	maxedRef.Text = ""
	maxedRef.TextColor3 = Color3.fromRGB(255, 220, 100)
	maxedRef.Font = FONT
	maxedRef.TextSize = 18
	maxedRef.TextWrapped = true
	maxedRef.Visible = false
	maxedRef.ZIndex = 4
	maxedRef.Parent = content
	addStroke(maxedRef, Color3.new(0, 0, 0), 1)
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
	-- Server tells us to open (proximity prompt)
-- INIT
-------------------------------------------------

	-- Rebirth result from server
function RebirthController.Init()
	buildUI()

	OpenRebirthGui.OnClientEvent:Connect(function()
		RebirthController.Open()
	end)

	RebirthResult.OnClientEvent:Connect(function(data)
		if data.success then
					-- Update current label
					local currentLabel = modalFrame:FindFirstChild("CurrentLabel")
					if currentLabel then
						currentLabel.Text = "Current Rebirth: " .. getRebirthCount() .. " / " .. Economy.MaxRebirths
					end
			if confirmTextRef then
				confirmTextRef.Text = "REBIRTHED!"
				confirmBtnRef.BackgroundColor3 = GREEN
				task.delay(1.2, function()
					confirmBtnRef.BackgroundColor3 = ACCENT
					updateDisplay()
				end)
			end
		else
			if confirmTextRef then
				confirmTextRef.Text = data.reason or "Failed!"
				confirmBtnRef.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
				task.delay(1.5, function()
					confirmBtnRef.BackgroundColor3 = ACCENT
					updateDisplay()
				end)
			end
		end
	end)
end

return RebirthController
