--[[
	PotionController.lua
	Client UI for buying potions (shop modal) and showing active potion indicators
	in the bottom-right corner with timer, potion icon, and tier number.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

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
local isShopOpen = false

-- Exposed active potion data so other controllers (HUD) can read it
PotionController.ActivePotions = {} -- { Luck = {multiplier, tier, remaining}, Cash = ... }

local BUBBLE_FONT = Enum.Font.FredokaOne

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
-- Built from UI elements: rounded bottle shape with liquid inside
-------------------------------------------------

local function createPotionIcon(parent, liquidColor, size)
	size = size or 40

	local container = Instance.new("Frame")
	container.Name = "PotionIcon"
	container.Size = UDim2.new(0, size, 0, size)
	container.BackgroundTransparency = 1
	container.Parent = parent

	-- Bottle body (rounded rectangle)
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

	-- Liquid inside (colored fill, bottom half of bottle)
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

	-- Neck (thin rectangle on top)
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

	-- Cork (small brown circle on top)
	local cork = Instance.new("Frame")
	cork.Name = "Cork"
	cork.Size = UDim2.new(0.2, 0, 0.1, 0)
	cork.Position = UDim2.new(0.5, 0, 0.02, 0)
	cork.AnchorPoint = Vector2.new(0.5, 0)
	cork.BackgroundColor3 = Color3.fromRGB(160, 110, 60)
	cork.BorderSizePixel = 0
	cork.Parent = container
	local corkCorner = Instance.new("UICorner")
	corkCorner.CornerRadius = UDim.new(0.4, 0)
	corkCorner.Parent = cork

	-- Bubbles (small circles inside liquid)
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

local function createIndicator(potionType, liquidColor)
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

	-- Timer label (top)
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

	-- Potion icon (center)
	local icon = createPotionIcon(frame, liquidColor, 40)
	icon.Position = UDim2.new(0.5, 0, 0.45, 0)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)

	-- Tier number (bottom)
	local tierLabel = Instance.new("TextLabel")
	tierLabel.Name = "Tier"
	tierLabel.Size = UDim2.new(1, 0, 0, 18)
	tierLabel.Position = UDim2.new(0.5, 0, 1, -4)
	tierLabel.AnchorPoint = Vector2.new(0.5, 1)
	tierLabel.BackgroundTransparency = 1
	tierLabel.Text = "1"
	tierLabel.TextColor3 = liquidColor
	tierLabel.Font = BUBBLE_FONT
	tierLabel.TextSize = 16
	tierLabel.Parent = frame
	local tierStroke = Instance.new("UIStroke")
	tierStroke.Color = Color3.fromRGB(0, 0, 0)
	tierStroke.Thickness = 1.5
	tierStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	tierStroke.Parent = tierLabel

	-- Type label (very small, under tier)
	local typeLabel = Instance.new("TextLabel")
	typeLabel.Name = "TypeLabel"
	typeLabel.Size = UDim2.new(1, 0, 0, 12)
	typeLabel.Position = UDim2.new(0.5, 0, 0, 22)
	typeLabel.AnchorPoint = Vector2.new(0.5, 0)
	typeLabel.BackgroundTransparency = 1
	typeLabel.Text = potionType == "Luck" and "LUCK" or "CASH"
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

local function updateIndicator(indicator, data)
	if not data or not data.remaining or data.remaining <= 0 then
		indicator.Visible = false
		return
	end
	indicator.Visible = true
	local timerLabel = indicator:FindFirstChild("Timer")
	if timerLabel then timerLabel.Text = formatTime(data.remaining) end
	local tierLabel = indicator:FindFirstChild("Tier")
	if tierLabel then tierLabel.Text = tostring(data.tier or 1) end
end

-------------------------------------------------
-- SHOP MODAL
-------------------------------------------------

local function buildShopModal()
	-- Overlay
	local overlay = Instance.new("Frame")
	overlay.Name = "PotionOverlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 50
	overlay.Visible = false
	overlay.Parent = screenGui

	local modal = UIHelper.CreateRoundedFrame({
		Name = "PotionShop",
		Size = UDim2.new(0, 520, 0, 420),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Color3.fromRGB(25, 25, 40),
		CornerRadius = UDim.new(0, 16),
		StrokeColor = Color3.fromRGB(100, 200, 150),
		Parent = overlay,
	})
	modal.ZIndex = 51

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 40)
	title.Position = UDim2.new(0.5, 0, 0, 8)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.BackgroundTransparency = 1
	title.Text = "POTIONS"
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

	-- Subtitle: "5 min each. Stacks time (max 3h). Higher tier replaces multiplier."
	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, -20, 0, 18)
	subtitle.Position = UDim2.new(0.5, 0, 0, 48)
	subtitle.AnchorPoint = Vector2.new(0.5, 0)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "5 min each use  •  Stacks time (max 3h)  •  Higher tier replaces multiplier"
	subtitle.TextColor3 = Color3.fromRGB(180, 180, 200)
	subtitle.Font = Enum.Font.GothamBold
	subtitle.TextSize = 11
	subtitle.ZIndex = 52
	subtitle.Parent = modal

	-- Two rows: Luck potions and Cash potions
	local yStart = 80
	local categories = {
		{ type = "Luck", label = "LUCK POTIONS", color = Color3.fromRGB(80, 255, 100), desc = "Multiply your luck" },
		{ type = "Cash", label = "CASH POTIONS", color = Color3.fromRGB(255, 220, 60), desc = "Multiply streamer income" },
	}

	for ci, cat in ipairs(categories) do
		local y = yStart + (ci - 1) * 165

		-- Category label
		local catLabel = Instance.new("TextLabel")
		catLabel.Size = UDim2.new(1, -20, 0, 24)
		catLabel.Position = UDim2.new(0.5, 0, 0, y)
		catLabel.AnchorPoint = Vector2.new(0.5, 0)
		catLabel.BackgroundTransparency = 1
		catLabel.Text = cat.label .. "  —  " .. cat.desc
		catLabel.TextColor3 = cat.color
		catLabel.Font = BUBBLE_FONT
		catLabel.TextSize = 16
		catLabel.ZIndex = 52
		catLabel.Parent = modal
		local cStroke = Instance.new("UIStroke")
		cStroke.Color = Color3.fromRGB(0, 0, 0)
		cStroke.Thickness = 1.5
		cStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		cStroke.Parent = catLabel

		-- 3 potion cards side by side
		local potionList = Potions.Types[cat.type]
		for pi, potion in ipairs(potionList) do
			local cardX = 30 + (pi - 1) * 160
			local card = Instance.new("Frame")
			card.Name = cat.type .. "Card" .. pi
			card.Size = UDim2.new(0, 145, 0, 120)
			card.Position = UDim2.new(0, cardX, 0, y + 28)
			card.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
			card.BorderSizePixel = 0
			card.ZIndex = 52
			card.Parent = modal
			local cardCorner = Instance.new("UICorner")
			cardCorner.CornerRadius = UDim.new(0, 10)
			cardCorner.Parent = card
			local cardStroke = Instance.new("UIStroke")
			cardStroke.Color = potion.color
			cardStroke.Thickness = 2
			cardStroke.Parent = card

			-- Potion icon
			local icon = createPotionIcon(card, potion.color, 36)
			icon.Position = UDim2.new(0.15, 0, 0.05, 0)
			icon.ZIndex = 53

			-- Name
			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(0.55, 0, 0, 18)
			nameLabel.Position = UDim2.new(0.95, 0, 0, 6)
			nameLabel.AnchorPoint = Vector2.new(1, 0)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = potion.name
			nameLabel.TextColor3 = potion.color
			nameLabel.Font = BUBBLE_FONT
			nameLabel.TextSize = 12
			nameLabel.ZIndex = 53
			nameLabel.Parent = card

			-- Multiplier
			local multLabel = Instance.new("TextLabel")
			multLabel.Size = UDim2.new(0.55, 0, 0, 20)
			multLabel.Position = UDim2.new(0.95, 0, 0, 24)
			multLabel.AnchorPoint = Vector2.new(1, 0)
			multLabel.BackgroundTransparency = 1
			multLabel.Text = "x" .. potion.multiplier
			multLabel.TextColor3 = Color3.new(1, 1, 1)
			multLabel.Font = BUBBLE_FONT
			multLabel.TextSize = 18
			multLabel.ZIndex = 53
			multLabel.Parent = card

			-- Duration
			local durLabel = Instance.new("TextLabel")
			durLabel.Size = UDim2.new(1, -10, 0, 14)
			durLabel.Position = UDim2.new(0.5, 0, 0, 52)
			durLabel.AnchorPoint = Vector2.new(0.5, 0)
			durLabel.BackgroundTransparency = 1
			durLabel.Text = "5 min per use"
			durLabel.TextColor3 = Color3.fromRGB(160, 160, 180)
			durLabel.Font = Enum.Font.GothamBold
			durLabel.TextSize = 10
			durLabel.ZIndex = 53
			durLabel.Parent = card

			-- Buy button
			local buyBtn = Instance.new("TextButton")
			buyBtn.Name = "BuyBtn"
			buyBtn.Size = UDim2.new(0.8, 0, 0, 30)
			buyBtn.Position = UDim2.new(0.5, 0, 1, -8)
			buyBtn.AnchorPoint = Vector2.new(0.5, 1)
			buyBtn.BackgroundColor3 = potion.color
			buyBtn.Text = "$" .. potion.cost
			buyBtn.TextColor3 = Color3.fromRGB(20, 20, 30)
			buyBtn.Font = BUBBLE_FONT
			buyBtn.TextSize = 16
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

	return overlay
end

-------------------------------------------------
-- PUBLIC
-------------------------------------------------

function PotionController.OpenShop()
	if shopModal then
		shopModal.Visible = true
		isShopOpen = true
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
	indicatorContainer.Size = UDim2.new(0, 160, 0, 100)
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

	luckIndicator = createIndicator("Luck", Color3.fromRGB(80, 255, 100))
	luckIndicator.LayoutOrder = 1
	luckIndicator.Parent = indicatorContainer

	cashIndicator = createIndicator("Cash", Color3.fromRGB(255, 220, 60))
	cashIndicator.LayoutOrder = 2
	cashIndicator.Parent = indicatorContainer

	-- Listen for potion updates from server
	PotionUpdate.OnClientEvent:Connect(function(payload)
		PotionController.ActivePotions = payload or {}
		updateIndicator(luckIndicator, payload.Luck)
		updateIndicator(cashIndicator, payload.Cash)
	end)

	-- Listen for buy results (flash feedback + error toast)
	BuyPotionResult.OnClientEvent:Connect(function(result)
		local modalRef = shopModal and shopModal:FindFirstChild("PotionShop") or shopModal
		if result.success then
			-- Brief green flash on the shop modal
			if modalRef and shopModal.Visible then
				local flash = Instance.new("Frame")
				flash.Size = UDim2.new(1, 0, 1, 0)
				flash.BackgroundColor3 = Color3.fromRGB(80, 255, 100)
				flash.BackgroundTransparency = 0.6
				flash.ZIndex = 60
				flash.Parent = modalRef
				TweenService:Create(flash, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
				task.delay(0.4, function() flash:Destroy() end)
			end
		else
			-- Show error toast message
			local toastParent = modalRef or screenGui
			local toast = Instance.new("Frame")
			toast.Name = "ErrorToast"
			toast.Size = UDim2.new(0.85, 0, 0, 44)
			toast.Position = UDim2.new(0.5, 0, 0.88, 0)
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
			-- Fade out after 2.5 seconds
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
