--[[
	RebirthController.lua
	Kid-friendly rebirth UI that opens when the player interacts with the Rebirth stand.
	Shows only the NEXT rebirth available with:
	  - Coin bonus (+5% per rebirth)
	  - Case unlock icon
	  - Big warning: "Rebirth will reset your money and potions!"
	  - Confirm button
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

local screenGui
local modalFrame
local isOpen = false

-- Cached label refs for dynamic update
local titleLabelRef
local coinBonusLabelRef
local caseUnlockLabelRef
local costLabelRef
local confirmBtnRef
local warningLabelRef
local maxedLabelRef

local Economy2 = require(ReplicatedStorage.Shared.Config.Economy)

-------------------------------------------------
-- GET CURRENT REBIRTH DATA
-------------------------------------------------

local function getRebirthCount()
	local HUDController = require(script.Parent.HUDController)
	return HUDController.Data.rebirthCount or 0
end

-------------------------------------------------
-- UPDATE UI TO SHOW NEXT REBIRTH
-------------------------------------------------

local function updateDisplay()
	local current = getRebirthCount()
	local nextLevel = current + 1

	if current >= Economy.MaxRebirths then
		-- Maxed out!
		if titleLabelRef then titleLabelRef.Text = "🏆 MAX REBIRTH! 🏆" end
		if coinBonusLabelRef then coinBonusLabelRef.Text = "Coin Bonus: +" .. (current * Economy.RebirthCoinBonusPercent) .. "%" end
		if caseUnlockLabelRef then caseUnlockLabelRef.Text = "All cases unlocked!" end
		if costLabelRef then costLabelRef.Visible = false end
		if confirmBtnRef then confirmBtnRef.Visible = false end
		if warningLabelRef then warningLabelRef.Visible = false end
		if maxedLabelRef then
			maxedLabelRef.Text = "You've reached the highest rebirth!\nCongratulations! 🎉"
			maxedLabelRef.Visible = true
		end
		return
	end

	-- Show next rebirth info
	local info = Economy.GetRebirthInfo(nextLevel)
	if not info then return end

	if maxedLabelRef then maxedLabelRef.Visible = false end
	if costLabelRef then costLabelRef.Visible = true end
	if confirmBtnRef then confirmBtnRef.Visible = true end
	if warningLabelRef then warningLabelRef.Visible = true end

	if titleLabelRef then
		titleLabelRef.Text = "⭐ Rebirth " .. nextLevel .. " ⭐"
	end

	if coinBonusLabelRef then
		local totalBonus = nextLevel * Economy.RebirthCoinBonusPercent
		coinBonusLabelRef.Text = "💰  +" .. totalBonus .. "% Coin Bonus"
	end

	if caseUnlockLabelRef then
		if info.unlocksCase then
			local caseName = Economy2.CrateNames[info.unlocksCase] or ("Case " .. info.unlocksCase)
			caseUnlockLabelRef.Text = "📦  Unlock: " .. caseName .. "  ➕"
			caseUnlockLabelRef.Visible = true
		else
			caseUnlockLabelRef.Text = "🏆  Final Rebirth Bonus!"
			caseUnlockLabelRef.Visible = true
		end
	end

	if costLabelRef then
		costLabelRef.Text = "Cost: $" .. info.cost
	end

	if confirmBtnRef then
		confirmBtnRef.Text = "REBIRTH  ($" .. info.cost .. ")"
	end
end

-------------------------------------------------
-- BUILD UI
-------------------------------------------------

local function buildUI()
	screenGui = UIHelper.CreateScreenGui("RebirthGui", 22)
	screenGui.Parent = playerGui

	modalFrame = Instance.new("Frame")
	modalFrame.Name = "RebirthModal"
	modalFrame.Size = UDim2.new(0, 420, 0, 480)
	modalFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	modalFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	modalFrame.BackgroundColor3 = Color3.fromRGB(25, 20, 40)
	modalFrame.BorderSizePixel = 0
	modalFrame.Visible = false
	modalFrame.Parent = screenGui
	local modalCorner = Instance.new("UICorner")
	modalCorner.CornerRadius = UDim.new(0, 24)
	modalCorner.Parent = modalFrame
	local modalStroke = Instance.new("UIStroke")
	modalStroke.Color = Color3.fromRGB(255, 140, 60)
	modalStroke.Thickness = 3
	modalStroke.Transparency = 0.15
	modalStroke.Parent = modalFrame
	UIHelper.CreateShadow(modalFrame)

	-- Orange gradient accent at top
	local topAccent = Instance.new("Frame")
	topAccent.Name = "TopAccent"
	topAccent.Size = UDim2.new(1, 0, 0, 5)
	topAccent.Position = UDim2.new(0, 0, 0, 0)
	topAccent.BackgroundColor3 = Color3.fromRGB(255, 140, 50)
	topAccent.BorderSizePixel = 0
	topAccent.ZIndex = 5
	topAccent.Parent = modalFrame
	local accentGrad = Instance.new("UIGradient")
	accentGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 50)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 120, 40)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 200, 50)),
	})
	accentGrad.Parent = topAccent

	-- Title
	titleLabelRef = Instance.new("TextLabel")
	titleLabelRef.Name = "Title"
	titleLabelRef.Size = UDim2.new(1, -20, 0, 50)
	titleLabelRef.Position = UDim2.new(0.5, 0, 0, 18)
	titleLabelRef.AnchorPoint = Vector2.new(0.5, 0)
	titleLabelRef.BackgroundTransparency = 1
	titleLabelRef.Text = "⭐ Rebirth 1 ⭐"
	titleLabelRef.TextColor3 = Color3.fromRGB(255, 200, 80)
	titleLabelRef.Font = Enum.Font.FredokaOne
	titleLabelRef.TextSize = 32
	titleLabelRef.Parent = modalFrame
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.fromRGB(180, 80, 30)
	titleStroke.Thickness = 2
	titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	titleStroke.Parent = titleLabelRef

	-- Coin bonus section (green panel)
	local coinPanel = Instance.new("Frame")
	coinPanel.Name = "CoinPanel"
	coinPanel.Size = UDim2.new(0.85, 0, 0, 60)
	coinPanel.Position = UDim2.new(0.5, 0, 0, 80)
	coinPanel.AnchorPoint = Vector2.new(0.5, 0)
	coinPanel.BackgroundColor3 = Color3.fromRGB(30, 60, 30)
	coinPanel.BorderSizePixel = 0
	coinPanel.Parent = modalFrame
	local cpCorner = Instance.new("UICorner")
	cpCorner.CornerRadius = UDim.new(0, 14)
	cpCorner.Parent = coinPanel
	local cpStroke = Instance.new("UIStroke")
	cpStroke.Color = Color3.fromRGB(80, 200, 80)
	cpStroke.Thickness = 2
	cpStroke.Parent = coinPanel

	coinBonusLabelRef = Instance.new("TextLabel")
	coinBonusLabelRef.Name = "CoinBonusLabel"
	coinBonusLabelRef.Size = UDim2.new(1, -20, 1, 0)
	coinBonusLabelRef.Position = UDim2.new(0.5, 0, 0.5, 0)
	coinBonusLabelRef.AnchorPoint = Vector2.new(0.5, 0.5)
	coinBonusLabelRef.BackgroundTransparency = 1
	coinBonusLabelRef.Text = "💰  +5% Coin Bonus"
	coinBonusLabelRef.TextColor3 = Color3.fromRGB(100, 255, 120)
	coinBonusLabelRef.Font = Enum.Font.FredokaOne
	coinBonusLabelRef.TextSize = 24
	coinBonusLabelRef.Parent = coinPanel
	local cbStroke = Instance.new("UIStroke")
	cbStroke.Color = Color3.fromRGB(0, 0, 0)
	cbStroke.Thickness = 1.5
	cbStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	cbStroke.Parent = coinBonusLabelRef

	-- Case unlock section (blue panel)
	local casePanel = Instance.new("Frame")
	casePanel.Name = "CasePanel"
	casePanel.Size = UDim2.new(0.85, 0, 0, 60)
	casePanel.Position = UDim2.new(0.5, 0, 0, 152)
	casePanel.AnchorPoint = Vector2.new(0.5, 0)
	casePanel.BackgroundColor3 = Color3.fromRGB(25, 35, 65)
	casePanel.BorderSizePixel = 0
	casePanel.Parent = modalFrame
	local csCorner = Instance.new("UICorner")
	csCorner.CornerRadius = UDim.new(0, 14)
	csCorner.Parent = casePanel
	local csStroke = Instance.new("UIStroke")
	csStroke.Color = Color3.fromRGB(80, 140, 255)
	csStroke.Thickness = 2
	csStroke.Parent = casePanel

	caseUnlockLabelRef = Instance.new("TextLabel")
	caseUnlockLabelRef.Name = "CaseUnlockLabel"
	caseUnlockLabelRef.Size = UDim2.new(1, -20, 1, 0)
	caseUnlockLabelRef.Position = UDim2.new(0.5, 0, 0.5, 0)
	caseUnlockLabelRef.AnchorPoint = Vector2.new(0.5, 0.5)
	caseUnlockLabelRef.BackgroundTransparency = 1
	caseUnlockLabelRef.Text = "📦  Unlock Case 2  ➕"
	caseUnlockLabelRef.TextColor3 = Color3.fromRGB(120, 180, 255)
	caseUnlockLabelRef.Font = Enum.Font.FredokaOne
	caseUnlockLabelRef.TextSize = 22
	caseUnlockLabelRef.Parent = casePanel
	local cuStroke = Instance.new("UIStroke")
	cuStroke.Color = Color3.fromRGB(0, 0, 0)
	cuStroke.Thickness = 1.5
	cuStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	cuStroke.Parent = caseUnlockLabelRef

	-- WARNING section (red panel, very visible)
	local warnPanel = Instance.new("Frame")
	warnPanel.Name = "WarnPanel"
	warnPanel.Size = UDim2.new(0.85, 0, 0, 70)
	warnPanel.Position = UDim2.new(0.5, 0, 0, 228)
	warnPanel.AnchorPoint = Vector2.new(0.5, 0)
	warnPanel.BackgroundColor3 = Color3.fromRGB(80, 20, 20)
	warnPanel.BorderSizePixel = 0
	warnPanel.Parent = modalFrame
	local wpCorner = Instance.new("UICorner")
	wpCorner.CornerRadius = UDim.new(0, 14)
	wpCorner.Parent = warnPanel
	local wpStroke = Instance.new("UIStroke")
	wpStroke.Color = Color3.fromRGB(255, 80, 80)
	wpStroke.Thickness = 2
	wpStroke.Parent = warnPanel

	warningLabelRef = Instance.new("TextLabel")
	warningLabelRef.Name = "WarningLabel"
	warningLabelRef.Size = UDim2.new(1, -16, 1, 0)
	warningLabelRef.Position = UDim2.new(0.5, 0, 0.5, 0)
	warningLabelRef.AnchorPoint = Vector2.new(0.5, 0.5)
	warningLabelRef.BackgroundTransparency = 1
	warningLabelRef.Text = "⚠️ WARNING ⚠️\nRebirth will RESET your money\nand active potions!"
	warningLabelRef.TextColor3 = Color3.fromRGB(255, 100, 100)
	warningLabelRef.Font = Enum.Font.FredokaOne
	warningLabelRef.TextSize = 17
	warningLabelRef.TextWrapped = true
	warningLabelRef.Parent = warnPanel
	local wlStroke = Instance.new("UIStroke")
	wlStroke.Color = Color3.fromRGB(0, 0, 0)
	wlStroke.Thickness = 1.5
	wlStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	wlStroke.Parent = warningLabelRef

	-- Cost label
	costLabelRef = Instance.new("TextLabel")
	costLabelRef.Name = "CostLabel"
	costLabelRef.Size = UDim2.new(0.85, 0, 0, 30)
	costLabelRef.Position = UDim2.new(0.5, 0, 0, 310)
	costLabelRef.AnchorPoint = Vector2.new(0.5, 0)
	costLabelRef.BackgroundTransparency = 1
	costLabelRef.Text = "Cost: $1"
	costLabelRef.TextColor3 = Color3.fromRGB(255, 220, 100)
	costLabelRef.Font = Enum.Font.FredokaOne
	costLabelRef.TextSize = 22
	costLabelRef.Parent = modalFrame
	local clStroke = Instance.new("UIStroke")
	clStroke.Color = Color3.fromRGB(0, 0, 0)
	clStroke.Thickness = 1.5
	clStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	clStroke.Parent = costLabelRef

	-- Maxed label (hidden by default)
	maxedLabelRef = Instance.new("TextLabel")
	maxedLabelRef.Name = "MaxedLabel"
	maxedLabelRef.Size = UDim2.new(0.85, 0, 0, 60)
	maxedLabelRef.Position = UDim2.new(0.5, 0, 0, 310)
	maxedLabelRef.AnchorPoint = Vector2.new(0.5, 0)
	maxedLabelRef.BackgroundTransparency = 1
	maxedLabelRef.Text = ""
	maxedLabelRef.TextColor3 = Color3.fromRGB(255, 220, 100)
	maxedLabelRef.Font = Enum.Font.FredokaOne
	maxedLabelRef.TextSize = 20
	maxedLabelRef.TextWrapped = true
	maxedLabelRef.Visible = false
	maxedLabelRef.Parent = modalFrame

	-- Confirm button (big orange gradient)
	confirmBtnRef = Instance.new("TextButton")
	confirmBtnRef.Name = "ConfirmBtn"
	confirmBtnRef.Size = UDim2.new(0.7, 0, 0, 56)
	confirmBtnRef.Position = UDim2.new(0.5, 0, 0, 355)
	confirmBtnRef.AnchorPoint = Vector2.new(0.5, 0)
	confirmBtnRef.BackgroundColor3 = Color3.fromRGB(255, 140, 50)
	confirmBtnRef.Text = "REBIRTH  ($1)"
	confirmBtnRef.TextColor3 = Color3.fromRGB(255, 255, 255)
	confirmBtnRef.Font = Enum.Font.FredokaOne
	confirmBtnRef.TextSize = 24
	confirmBtnRef.BorderSizePixel = 0
	confirmBtnRef.Parent = modalFrame
	local cbCorner = Instance.new("UICorner")
	cbCorner.CornerRadius = UDim.new(0, 16)
	cbCorner.Parent = confirmBtnRef
	local cbBtnStroke = Instance.new("UIStroke")
	cbBtnStroke.Color = Color3.fromRGB(200, 80, 20)
	cbBtnStroke.Thickness = 3
	cbBtnStroke.Parent = confirmBtnRef
	local btnGrad = Instance.new("UIGradient")
	btnGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 180, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(230, 100, 30)),
	})
	btnGrad.Rotation = 90
	btnGrad.Parent = confirmBtnRef

	confirmBtnRef.MouseButton1Click:Connect(function()
		local current = getRebirthCount()
		if current >= Economy.MaxRebirths then return end
		-- Disable button temporarily
		confirmBtnRef.Text = "REBIRTHING..."
		confirmBtnRef.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
		RebirthRequest:FireServer()
	end)

	-- Close button (bubbly X)
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 44, 0, 44)
	closeBtn.Position = UDim2.new(1, -14, 0, -8)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
	closeBtn.Text = "✕"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Font = Enum.Font.FredokaOne
	closeBtn.TextSize = 26
	closeBtn.BorderSizePixel = 0
	closeBtn.ZIndex = 3
	closeBtn.Parent = modalFrame
	local ccCorner = Instance.new("UICorner")
	ccCorner.CornerRadius = UDim.new(1, 0)
	ccCorner.Parent = closeBtn
	local ccStroke = Instance.new("UIStroke")
	ccStroke.Color = Color3.fromRGB(120, 30, 30)
	ccStroke.Thickness = 2
	ccStroke.Parent = closeBtn
	closeBtn.MouseButton1Click:Connect(function()
		RebirthController.Close()
	end)

	-- Your current rebirth text at the bottom
	local currentLabel = Instance.new("TextLabel")
	currentLabel.Name = "CurrentLabel"
	currentLabel.Size = UDim2.new(1, -20, 0, 28)
	currentLabel.Position = UDim2.new(0.5, 0, 1, -38)
	currentLabel.AnchorPoint = Vector2.new(0.5, 0)
	currentLabel.BackgroundTransparency = 1
	currentLabel.Text = "Current Rebirth: 0"
	currentLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
	currentLabel.Font = Enum.Font.FredokaOne
	currentLabel.TextSize = 16
	currentLabel.Parent = modalFrame
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
	-- Update current rebirth text
	local currentLabel = modalFrame:FindFirstChild("CurrentLabel")
	if currentLabel then
		currentLabel.Text = "Current Rebirth: " .. getRebirthCount() .. " / " .. Economy.MaxRebirths
	end
	modalFrame.Visible = true
	UIHelper.ScaleIn(modalFrame, 0.3)
end

function RebirthController.Close()
	if not isOpen then return end
	isOpen = false
	if modalFrame then UIHelper.ScaleOut(modalFrame, 0.2) end
end

-------------------------------------------------
-- INIT
-------------------------------------------------

function RebirthController.Init()
	buildUI()

	-- Server tells us to open (proximity prompt)
	OpenRebirthGui.OnClientEvent:Connect(function()
		RebirthController.Open()
	end)

	-- Rebirth result from server
	RebirthResult.OnClientEvent:Connect(function(data)
		if data.success then
			-- Show success flash
			if confirmBtnRef then
				confirmBtnRef.Text = "REBIRTHED! ✨"
				confirmBtnRef.BackgroundColor3 = Color3.fromRGB(80, 255, 120)
				task.delay(1.5, function()
					confirmBtnRef.BackgroundColor3 = Color3.fromRGB(255, 140, 50)
					updateDisplay()
					-- Update current label
					local currentLabel = modalFrame:FindFirstChild("CurrentLabel")
					if currentLabel then
						currentLabel.Text = "Current Rebirth: " .. getRebirthCount() .. " / " .. Economy.MaxRebirths
					end
				end)
			end
		else
			-- Show error
			if confirmBtnRef then
				confirmBtnRef.Text = data.reason or "Failed!"
				confirmBtnRef.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
				task.delay(2, function()
					confirmBtnRef.BackgroundColor3 = Color3.fromRGB(255, 140, 50)
					updateDisplay()
				end)
			end
		end
	end)
end

return RebirthController
