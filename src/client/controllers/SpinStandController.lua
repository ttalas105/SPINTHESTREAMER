--[[
	SpinStandController.lua
	Case Shop UI — dark themed, vertical list like Spin the Baddies Dice Shop.
	18 cases, unlocked by rebirths.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local UIHelper = require(script.Parent.UIHelper)
local HUDController = require(script.Parent.HUDController)

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
-- STYLE
-------------------------------------------------
local FONT        = Enum.Font.FredokaOne
local FONT_SUB    = Enum.Font.GothamBold
local MODAL_BG    = Color3.fromRGB(28, 26, 34)
local CARD_BG     = Color3.fromRGB(42, 38, 50)
local CARD_HOVER  = Color3.fromRGB(55, 50, 65)
local CARD_LOCKED = Color3.fromRGB(30, 28, 36)
local ACCENT      = Color3.fromRGB(100, 220, 120)
local LOCKED_TEXT = Color3.fromRGB(180, 160, 200)

local ROW_H       = 130
local IMAGE_SIZE  = 105
local MODAL_W     = 580
local MODAL_H     = 620

local RARITY_COLORS = {
	Common    = Color3.fromRGB(180, 180, 190),
	Uncommon  = Color3.fromRGB(100, 220, 120),
	Rare      = Color3.fromRGB(80, 170, 255),
	Epic      = Color3.fromRGB(180, 80, 255),
	Legendary = Color3.fromRGB(255, 180, 40),
	Mythic    = Color3.fromRGB(255, 80, 120),
	Godly     = Color3.fromRGB(255, 60, 60),
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
	if n >= 1e9 then
		return "$" .. string.format("%.1fB", n / 1e9)
	elseif n >= 1e6 then
		return "$" .. string.format("%.1fM", n / 1e6)
	end
	local s = tostring(math.floor(n))
	local out, len = "", #s
	for i = 1, len do
		out = out .. s:sub(i, i)
		if (len - i) % 3 == 0 and i < len then out = out .. "," end
	end
	return "$" .. out
end

local function luckString(bonus)
	return "+" .. math.floor(bonus * 100) .. "% Luck"
end

-------------------------------------------------
-- BUILD SINGLE CASE ROW
-------------------------------------------------
local function buildCaseRow(crateId, parent)
	local cost = Economy.CrateCosts[crateId]
	local luck = Economy.CrateLuckBonuses[crateId]
	local imageId = Economy.CrateImageIds[crateId]
	local name = Economy.CrateNames[crateId]
	local rarity = Economy.CrateRarities[crateId]
	local rarityColor = RARITY_COLORS[rarity] or RARITY_COLORS.Common

	local row = Instance.new("Frame")
	row.Name = "CaseRow_" .. crateId
	row.Size = UDim2.new(1, 0, 0, ROW_H)
	row.BackgroundColor3 = CARD_BG
	row.BorderSizePixel = 0
	row.LayoutOrder = crateId
	row.Parent = parent

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 14)
	rowCorner.Parent = row

	local rowStroke = Instance.new("UIStroke")
	rowStroke.Name = "RowStroke"
	rowStroke.Color = Color3.fromRGB(60, 55, 75)
	rowStroke.Thickness = 1.5
	rowStroke.Transparency = 0.3
	rowStroke.Parent = row

	-- Case image (left) — cases 13-18 use larger display to compensate for smaller source images
	local imgScale = crateId >= 13 and 1.3 or 1.0
	local displaySize = math.floor(IMAGE_SIZE * imgScale)

	local caseImage = Instance.new("ImageLabel")
	caseImage.Name = "CaseImage"
	caseImage.Size = UDim2.new(0, displaySize, 0, displaySize)
	caseImage.Position = UDim2.new(0, 10 - math.floor((displaySize - IMAGE_SIZE) / 2), 0.5, 0)
	caseImage.AnchorPoint = Vector2.new(0, 0.5)
	caseImage.BackgroundTransparency = 1
	caseImage.Image = imageId or ""
	caseImage.ScaleType = Enum.ScaleType.Fit
	caseImage.ClipsDescendants = false
	caseImage.Parent = row

	local textX = IMAGE_SIZE + 24

	-- Name (right of image)
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, -(textX + 130), 0, 34)
	nameLabel.Position = UDim2.new(0, textX, 0, 12)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = name
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.Font = FONT
	nameLabel.TextSize = 26
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = row
	local nameStroke = Instance.new("UIStroke")
	nameStroke.Color = Color3.fromRGB(0, 0, 0)
	nameStroke.Thickness = 1.5
	nameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	nameStroke.Parent = nameLabel

	-- Rarity + Luck line
	local infoLabel = Instance.new("TextLabel")
	infoLabel.Name = "InfoLabel"
	infoLabel.Size = UDim2.new(1, -(textX + 130), 0, 24)
	infoLabel.Position = UDim2.new(0, textX, 0, 48)
	infoLabel.BackgroundTransparency = 1
	infoLabel.Text = rarity .. " - " .. luckString(luck)
	infoLabel.TextColor3 = rarityColor
	infoLabel.Font = FONT_SUB
	infoLabel.TextSize = 17
	infoLabel.TextXAlignment = Enum.TextXAlignment.Left
	infoLabel.Parent = row
	local infoStroke = Instance.new("UIStroke")
	infoStroke.Color = Color3.fromRGB(0, 0, 0)
	infoStroke.Thickness = 1.2
	infoStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	infoStroke.Parent = infoLabel

	-- Cost label
	local costLabel = Instance.new("TextLabel")
	costLabel.Name = "CostLabel"
	costLabel.Size = UDim2.new(1, -(textX + 130), 0, 24)
	costLabel.Position = UDim2.new(0, textX, 0, 76)
	costLabel.BackgroundTransparency = 1
	costLabel.Text = formatCash(cost)
	costLabel.TextColor3 = Color3.fromRGB(100, 255, 130)
	costLabel.Font = FONT
	costLabel.TextSize = 20
	costLabel.TextXAlignment = Enum.TextXAlignment.Left
	costLabel.Parent = row
	local costStroke = Instance.new("UIStroke")
	costStroke.Color = Color3.fromRGB(0, 0, 0)
	costStroke.Thickness = 1.5
	costStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	costStroke.Parent = costLabel

	-- BUY button (right side)
	local buyBtn = Instance.new("TextButton")
	buyBtn.Name = "BuyBtn"
	buyBtn.Size = UDim2.new(0, 105, 0, 48)
	buyBtn.Position = UDim2.new(1, -14, 0.5, 0)
	buyBtn.AnchorPoint = Vector2.new(1, 0.5)
	buyBtn.BackgroundColor3 = Color3.fromRGB(60, 200, 90)
	buyBtn.Text = "SPIN"
	buyBtn.TextColor3 = Color3.new(1, 1, 1)
	buyBtn.Font = FONT
	buyBtn.TextSize = 22
	buyBtn.BorderSizePixel = 0
	buyBtn.AutoButtonColor = false
	buyBtn.Parent = row

	local buyCorner = Instance.new("UICorner")
	buyCorner.CornerRadius = UDim.new(0, 12)
	buyCorner.Parent = buyBtn
	local buyStroke = Instance.new("UIStroke")
	buyStroke.Color = Color3.fromRGB(30, 140, 50)
	buyStroke.Thickness = 2
	buyStroke.Parent = buyBtn
	local buyTextStroke = Instance.new("UIStroke")
	buyTextStroke.Color = Color3.fromRGB(10, 50, 20)
	buyTextStroke.Thickness = 1.5
	buyTextStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	buyTextStroke.Parent = buyBtn

	-- Hover effects (row + button)
	local bounceTI = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local idleSize = buyBtn.Size
	local hoverSize = UDim2.new(0, 115, 0, 52)

	buyBtn.MouseEnter:Connect(function()
		TweenService:Create(row, bounceTI, { BackgroundColor3 = CARD_HOVER }):Play()
		TweenService:Create(buyBtn, bounceTI, { Size = hoverSize, BackgroundColor3 = Color3.fromRGB(80, 235, 115) }):Play()
	end)
	buyBtn.MouseLeave:Connect(function()
		TweenService:Create(row, bounceTI, { BackgroundColor3 = CARD_BG }):Play()
		TweenService:Create(buyBtn, bounceTI, { Size = idleSize, BackgroundColor3 = Color3.fromRGB(60, 200, 90) }):Play()
	end)

	-- Lock overlay (for rebirth-gated cases)
	local lockOverlay = Instance.new("Frame")
	lockOverlay.Name = "LockOverlay"
	lockOverlay.Size = UDim2.new(1, 0, 1, 0)
	lockOverlay.BackgroundColor3 = Color3.fromRGB(15, 12, 25)
	lockOverlay.BackgroundTransparency = 0.3
	lockOverlay.BorderSizePixel = 0
	lockOverlay.ZIndex = 5
	lockOverlay.Visible = false
	lockOverlay.Parent = row
	local lockCorner = Instance.new("UICorner")
	lockCorner.CornerRadius = UDim.new(0, 14)
	lockCorner.Parent = lockOverlay

	local lockIcon = Instance.new("TextLabel")
	lockIcon.Size = UDim2.new(0, 50, 0, 50)
	lockIcon.Position = UDim2.new(0.5, -30, 0.5, 0)
	lockIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	lockIcon.BackgroundTransparency = 1
	lockIcon.Text = "🔒"
	lockIcon.TextSize = 40
	lockIcon.Font = Enum.Font.SourceSans
	lockIcon.ZIndex = 6
	lockIcon.Parent = lockOverlay

	local lockText = Instance.new("TextLabel")
	lockText.Name = "LockText"
	lockText.Size = UDim2.new(0, 220, 0, 30)
	lockText.Position = UDim2.new(0.5, 30, 0.5, 0)
	lockText.AnchorPoint = Vector2.new(0.5, 0.5)
	lockText.BackgroundTransparency = 1
	lockText.Text = "Rebirth " .. Economy.GetCrateRebirthRequirement(crateId) .. " Required"
	lockText.TextColor3 = Color3.fromRGB(255, 180, 80)
	lockText.Font = FONT
	lockText.TextSize = 20
	lockText.ZIndex = 6
	lockText.Parent = lockOverlay
	local ltStroke = Instance.new("UIStroke")
	ltStroke.Color = Color3.fromRGB(0, 0, 0)
	ltStroke.Thickness = 1.5
	ltStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	ltStroke.Parent = lockText

	-- Buy click handler
	buyBtn.MouseButton1Click:Connect(function()
		local rebirthReq = Economy.GetCrateRebirthRequirement(crateId)
		local currentRebirth = getRebirthCount()
		if currentRebirth < rebirthReq then
			buyBtn.Text = "LOCKED"
			task.delay(1.2, function()
				buyBtn.Text = "🔒"
			end)
			return
		end

		local playerCash = HUDController.Data and HUDController.Data.cash or 0
		if playerCash < cost then
			local origText = buyBtn.Text
			local origColor = buyBtn.BackgroundColor3
			local origScaled = buyBtn.TextScaled
			buyBtn.Text = "NO CASH!"
			buyBtn.TextScaled = true
			buyBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
			task.delay(1.5, function()
				buyBtn.Text = origText
				buyBtn.TextScaled = origScaled
				buyBtn.BackgroundColor3 = origColor
			end)
			return
		end

		SpinStandController.Close()
		local SpinController = require(script.Parent.SpinController)
		SpinController.SetCurrentCost(cost)
		SpinController.SetCurrentCrateId(crateId)
		SpinController.Show()
		SpinController.RequestSpin()
	end)

	cardRefs[crateId] = {
		card = row,
		buyBtn = buyBtn,
		lockOverlay = lockOverlay,
	}

	return row
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
			refs.buyBtn.Text = "SPIN"
			refs.buyBtn.BackgroundColor3 = Color3.fromRGB(60, 200, 90)
			refs.card.BackgroundColor3 = CARD_BG
		else
			refs.lockOverlay.Visible = true
			refs.buyBtn.Text = "🔒"
			refs.buyBtn.BackgroundColor3 = Color3.fromRGB(70, 65, 85)
			refs.card.BackgroundColor3 = CARD_LOCKED
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
	overlay.BackgroundTransparency = 0.4
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.ZIndex = 1
	overlay.Parent = screenGui

	-- Modal panel (dark themed like Spin the Baddies)
	modalFrame = Instance.new("Frame")
	modalFrame.Name = "CaseShopModal"
	modalFrame.Size = UDim2.new(0, MODAL_W, 0, MODAL_H)
	modalFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	modalFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	modalFrame.BackgroundColor3 = MODAL_BG
	modalFrame.BorderSizePixel = 0
	modalFrame.ZIndex = 2
	modalFrame.Visible = false
	modalFrame.Parent = screenGui

	local modalCorner = Instance.new("UICorner")
	modalCorner.CornerRadius = UDim.new(0, 20)
	modalCorner.Parent = modalFrame

	local modalStroke = Instance.new("UIStroke")
	modalStroke.Color = Color3.fromRGB(70, 60, 100)
	modalStroke.Thickness = 1.5
	modalStroke.Transparency = 0.3
	modalStroke.Parent = modalFrame

	UIHelper.CreateShadow(modalFrame)
	UIHelper.MakeResponsiveModal(modalFrame, MODAL_W, MODAL_H)

	-- Header area
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 60)
	header.BackgroundTransparency = 1
	header.ZIndex = 3
	header.Parent = modalFrame

	-- Title: "Case Shop"
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(0.6, 0, 0, 36)
	title.Position = UDim2.new(0, 20, 0, 14)
	title.BackgroundTransparency = 1
	title.Text = "Case Shop"
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Font = FONT
	title.TextSize = 36
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 3
	title.Parent = header
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.fromRGB(0, 0, 0)
	titleStroke.Thickness = 1.5
	titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	titleStroke.Parent = title

	-- Close button (red X, top right)
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 42, 0, 42)
	closeBtn.Position = UDim2.new(1, -14, 0, 10)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(220, 55, 55)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = FONT
	closeBtn.TextSize = 22
	closeBtn.BorderSizePixel = 0
	closeBtn.AutoButtonColor = false
	closeBtn.ZIndex = 5
	closeBtn.Parent = modalFrame

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
		SpinStandController.Close()
	end)

	-- Divider line under header
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.Size = UDim2.new(1, -30, 0, 1)
	divider.Position = UDim2.new(0.5, 0, 0, 64)
	divider.AnchorPoint = Vector2.new(0.5, 0)
	divider.BackgroundColor3 = Color3.fromRGB(65, 60, 80)
	divider.BorderSizePixel = 0
	divider.ZIndex = 3
	divider.Parent = modalFrame

	-- Scrollable case list
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "CaseScroll"
	scroll.Size = UDim2.new(1, -24, 1, -80)
	scroll.Position = UDim2.new(0.5, 0, 0, 72)
	scroll.AnchorPoint = Vector2.new(0.5, 0)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Color3.fromRGB(100, 90, 140)
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ZIndex = 2
	scroll.Parent = modalFrame

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 10)
	listLayout.Parent = scroll

	local topPad = Instance.new("UIPadding")
	topPad.PaddingTop = UDim.new(0, 4)
	topPad.PaddingBottom = UDim.new(0, 10)
	topPad.Parent = scroll

	-- Build all 18 case rows
	for i = 1, Economy.TotalCases do
		buildCaseRow(i, scroll)
	end

	-- Server event
	OpenSpinStandGui.OnClientEvent:Connect(function()
		SpinStandController.Open()
	end)
end

return SpinStandController
