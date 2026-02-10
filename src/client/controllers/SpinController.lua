--[[
	SpinController.lua
	Full spin wheel UI with animation, rarity-based VFX,
	screen shake, glow, and result display.
	Spin results now go to INVENTORY — shown with "Added to inventory!" text.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Streamers = require(ReplicatedStorage.Shared.Config.Streamers)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local UIHelper = require(script.Parent.UIHelper)

local SpinController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local SpinRequest = RemoteEvents:WaitForChild("SpinRequest")
local SpinResult = RemoteEvents:WaitForChild("SpinResult")
local MythicAlert = RemoteEvents:WaitForChild("MythicAlert")

-- UI references
local screenGui
local spinContainer
local wheelFrame
local resultFrame
local spinButton
local isSpinning = false

-- Callback for when a spin result arrives
local onSpinResult = nil

-- Wheel segments
local SEGMENT_COUNT = 12
local segments = {}

-------------------------------------------------
-- BUILD WHEEL
-------------------------------------------------

local function buildWheel(parent)
	wheelFrame = UIHelper.CreateRoundedFrame({
		Name = "WheelFrame",
		Size = UDim2.new(0, 340, 0, 340),
		Position = UDim2.new(0.5, 0, 0.45, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = DesignConfig.Colors.Background,
		CornerRadius = UDim.new(1, 0),
		StrokeColor = Color3.fromRGB(150, 120, 255),
		Parent = parent,
	})

	local innerWheel = Instance.new("Frame")
	innerWheel.Name = "InnerWheel"
	innerWheel.Size = UDim2.new(0.9, 0, 0.9, 0)
	innerWheel.Position = UDim2.new(0.5, 0, 0.5, 0)
	innerWheel.AnchorPoint = Vector2.new(0.5, 0.5)
	innerWheel.BackgroundTransparency = 1
	innerWheel.Parent = wheelFrame

	local displayStreamers = {}
	for i = 1, math.min(SEGMENT_COUNT, #Streamers.List) do
		table.insert(displayStreamers, Streamers.List[i])
	end

	for i, streamer in ipairs(displayStreamers) do
		local angle = (i - 1) * (360 / #displayStreamers)
		local rad = math.rad(angle)
		local radius = 0.35

		local segFrame = UIHelper.CreateRoundedFrame({
			Name = "Seg_" .. streamer.id,
			Size = UDim2.new(0, 60, 0, 60),
			Position = UDim2.new(
				0.5 + math.sin(rad) * radius, 0,
				0.5 - math.cos(rad) * radius, 0
			),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Color = Rarities.ByName[streamer.rarity] and Rarities.ByName[streamer.rarity].color or Color3.fromRGB(100, 100, 100),
			CornerRadius = DesignConfig.Layout.ButtonCorner,
			Parent = innerWheel,
		})

		UIHelper.CreateLabel({
			Name = "Initial",
			Size = UDim2.new(1, 0, 0.65, 0),
			Text = string.sub(streamer.displayName, 1, 2),
			TextColor = DesignConfig.Colors.White,
			Font = DesignConfig.Fonts.Primary,
			TextScaled = true,
			Parent = segFrame,
		})

		UIHelper.CreateLabel({
			Name = "RarityTag",
			Size = UDim2.new(1, 0, 0.35, 0),
			Position = UDim2.new(0, 0, 0.65, 0),
			Text = streamer.rarity,
			TextColor = DesignConfig.Colors.TextSecondary,
			Font = DesignConfig.Fonts.Secondary,
			TextScaled = true,
			Parent = segFrame,
		})

		segments[i] = {
			frame = segFrame,
			streamer = streamer,
		}
	end

	-- Pointer
	UIHelper.CreateRoundedFrame({
		Name = "Pointer",
		Size = UDim2.new(0, 20, 0, 30),
		Position = UDim2.new(0.5, 0, 0, -5),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = DesignConfig.Colors.Danger,
		CornerRadius = UDim.new(0.3, 0),
		Parent = wheelFrame,
	})

	-- Center circle
	UIHelper.CreateRoundedFrame({
		Name = "CenterDot",
		Size = UDim2.new(0, 50, 0, 50),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Color3.fromRGB(60, 50, 90),
		CornerRadius = UDim.new(1, 0),
		StrokeColor = Color3.fromRGB(200, 180, 255),
		Parent = wheelFrame,
	})

	return wheelFrame
end

-------------------------------------------------
-- RESULT DISPLAY
-------------------------------------------------

local function buildResultDisplay(parent)
	resultFrame = UIHelper.CreateRoundedFrame({
		Name = "ResultFrame",
		Size = UDim2.new(0.7, 0, 0, 110),
		Position = UDim2.new(0.5, 0, 0.78, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = DesignConfig.Colors.BackgroundLight,
		CornerRadius = DesignConfig.Layout.PanelCorner,
		StrokeColor = Color3.fromRGB(100, 100, 140),
		Parent = parent,
	})
	resultFrame.Visible = false

	UIHelper.CreateLabel({
		Name = "ResultLabel",
		Size = UDim2.new(1, -20, 0, 22),
		Position = UDim2.new(0.5, 0, 0, 8),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "YOU GOT:",
		TextColor = DesignConfig.Colors.TextSecondary,
		Font = DesignConfig.Fonts.Secondary,
		TextSize = DesignConfig.FontSizes.Caption,
		Parent = resultFrame,
	})

	UIHelper.CreateLabel({
		Name = "StreamerName",
		Size = UDim2.new(1, -20, 0, 35),
		Position = UDim2.new(0.5, 0, 0, 30),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "",
		TextColor = DesignConfig.Colors.White,
		Font = DesignConfig.Fonts.Accent,
		TextSize = DesignConfig.FontSizes.Header,
		Parent = resultFrame,
	})

	UIHelper.CreateLabel({
		Name = "RarityLabel",
		Size = UDim2.new(1, -20, 0, 18),
		Position = UDim2.new(0.5, 0, 0, 65),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "",
		TextColor = Color3.fromRGB(170, 170, 170),
		Font = DesignConfig.Fonts.Primary,
		TextSize = DesignConfig.FontSizes.Caption,
		Parent = resultFrame,
	})

	-- "Added to inventory!" text
	UIHelper.CreateLabel({
		Name = "InventoryNotice",
		Size = UDim2.new(1, -20, 0, 16),
		Position = UDim2.new(0.5, 0, 0, 86),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "Added to inventory!",
		TextColor = DesignConfig.Colors.Accent,
		Font = DesignConfig.Fonts.Secondary,
		TextSize = DesignConfig.FontSizes.Small,
		Parent = resultFrame,
	})

	return resultFrame
end

-------------------------------------------------
-- SPIN ANIMATION
-------------------------------------------------

local function playSpinAnimation(callback)
	local innerWheel = wheelFrame:FindFirstChild("InnerWheel")
	if not innerWheel then return end

	local totalRotation = 360 * 5 + math.random(0, 360)
	local duration = 3.5

	local startTime = tick()
	local startRotation = innerWheel.Rotation

	task.spawn(function()
		while true do
			local elapsed = tick() - startTime
			if elapsed >= duration then break end

			local progress = elapsed / duration
			local eased = 1 - (1 - progress) ^ 3
			innerWheel.Rotation = startRotation + totalRotation * eased

			task.wait()
		end

		innerWheel.Rotation = startRotation + totalRotation

		if callback then
			callback()
		end
	end)
end

local function showResult(data)
	local rarityInfo = Rarities.ByName[data.rarity]
	local rarityColor = rarityInfo and rarityInfo.color or Color3.fromRGB(170, 170, 170)

	local nameLabel = resultFrame:FindFirstChild("StreamerName")
	local rarityLabel = resultFrame:FindFirstChild("RarityLabel")

	if nameLabel then
		nameLabel.Text = data.displayName
		nameLabel.TextColor3 = rarityColor
	end
	if rarityLabel then
		rarityLabel.Text = data.rarity
		rarityLabel.TextColor3 = rarityColor
	end

	resultFrame.Visible = true
	UIHelper.ScaleIn(resultFrame, 0.3)

	-- Glow wheel border
	local stroke = wheelFrame:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(0.3), {
			Color = rarityColor,
			Thickness = 4,
		}):Play()
		task.delay(2, function()
			TweenService:Create(stroke, TweenInfo.new(0.5), {
				Color = Color3.fromRGB(150, 120, 255),
				Thickness = 2,
			}):Play()
		end)
	end

	-- Camera shake for high rarities
	local shakeIntensity = rarityInfo and rarityInfo.shakeIntensity or 0
	if shakeIntensity > 0 then
		UIHelper.CameraShake(shakeIntensity * 0.1, 0.4)
	end

	-- Flash for legendary/mythic
	if data.rarity == "Legendary" or data.rarity == "Mythic" then
		local flash = Instance.new("Frame")
		flash.Name = "Flash"
		flash.Size = UDim2.new(1, 0, 1, 0)
		flash.BackgroundColor3 = rarityColor
		flash.BackgroundTransparency = 0.5
		flash.ZIndex = 100
		flash.Parent = screenGui

		TweenService:Create(flash, TweenInfo.new(0.5), {
			BackgroundTransparency = 1,
		}):Play()
		task.delay(0.5, function()
			flash:Destroy()
		end)
	end

	-- Notify callback (for inventory flash)
	if onSpinResult then
		task.spawn(onSpinResult, data)
	end
end

-------------------------------------------------
-- MYTHIC ALERT
-------------------------------------------------

local function showMythicAlert(data)
	local alert = UIHelper.CreateRoundedFrame({
		Name = "MythicAlert",
		Size = UDim2.new(0.5, 0, 0, 60),
		Position = UDim2.new(0.5, 0, 0.15, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Color3.fromRGB(40, 10, 10),
		CornerRadius = DesignConfig.Layout.PanelCorner,
		StrokeColor = Rarities.ByName["Mythic"].color,
		Parent = screenGui,
	})

	UIHelper.CreateLabel({
		Name = "AlertText",
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = data.playerName .. " pulled MYTHIC " .. data.displayName .. "!",
		TextColor = Rarities.ByName["Mythic"].color,
		Font = DesignConfig.Fonts.Accent,
		TextSize = DesignConfig.FontSizes.Body,
		Parent = alert,
	})

	UIHelper.ScaleIn(alert, 0.4)

	task.delay(4, function()
		local tween = TweenService:Create(alert, TweenInfo.new(0.5), {
			Position = UDim2.new(0.5, 0, -0.1, 0),
		})
		tween:Play()
		tween.Completed:Connect(function()
			alert:Destroy()
		end)
	end)
end

-------------------------------------------------
-- BUILD UI
-------------------------------------------------

function SpinController.Init()
	screenGui = UIHelper.CreateScreenGui("SpinGui", 10)
	screenGui.Parent = playerGui

	spinContainer = UIHelper.CreateRoundedFrame({
		Name = "SpinContainer",
		Size = UDim2.new(0.45, 0, 0.85, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = DesignConfig.Colors.Background,
		CornerRadius = DesignConfig.Layout.ModalCorner,
		StrokeColor = Color3.fromRGB(80, 80, 120),
		Parent = screenGui,
	})
	spinContainer.Visible = false

	UIHelper.CreateLabel({
		Name = "SpinTitle",
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.new(0.5, 0, 0, 8),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "SPIN THE STREAMER",
		TextColor = Color3.fromRGB(200, 120, 255),
		Font = DesignConfig.Fonts.Accent,
		TextSize = DesignConfig.FontSizes.Title,
		Parent = spinContainer,
	})

	buildWheel(spinContainer)
	buildResultDisplay(spinContainer)

	spinButton = UIHelper.CreateButton({
		Name = "SpinButton",
		Size = UDim2.new(0.4, 0, 0, 50),
		Position = UDim2.new(0.5, 0, 0.95, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = DesignConfig.Colors.Accent,
		HoverColor = Color3.fromRGB(0, 230, 120),
		Text = "SPIN  ($" .. Economy.SpinCost .. ")",
		TextColor = DesignConfig.Colors.White,
		Font = DesignConfig.Fonts.Primary,
		TextSize = DesignConfig.FontSizes.Header,
		CornerRadius = DesignConfig.Layout.ButtonCorner,
		StrokeColor = Color3.fromRGB(0, 255, 130),
		Parent = spinContainer,
	})

	spinButton.MouseButton1Click:Connect(function()
		SpinController.RequestSpin()
	end)

	-- Listen for spin results
	SpinResult.OnClientEvent:Connect(function(data)
		if data.success then
			playSpinAnimation(function()
				showResult(data)
				isSpinning = false
				spinButton.Text = "SPIN  ($" .. Economy.SpinCost .. ")"
			end)
		else
			isSpinning = false
			spinButton.Text = data.reason or "ERROR"
			task.delay(1.5, function()
				spinButton.Text = "SPIN  ($" .. Economy.SpinCost .. ")"
			end)
		end
	end)

	-- Listen for mythic alerts
	MythicAlert.OnClientEvent:Connect(function(data)
		showMythicAlert(data)
	end)
end

-------------------------------------------------
-- PUBLIC
-------------------------------------------------

function SpinController.RequestSpin()
	if isSpinning then return end
	isSpinning = true
	resultFrame.Visible = false
	spinButton.Text = "SPINNING..."
	SpinRequest:FireServer()
end

function SpinController.Show()
	spinContainer.Visible = true
	UIHelper.ScaleIn(spinContainer, 0.3)
end

function SpinController.Hide()
	spinContainer.Visible = false
end

function SpinController.IsVisible(): boolean
	return spinContainer.Visible
end

--- Set callback for spin result (used by Main to flash inventory)
function SpinController.OnSpinResult(callback)
	onSpinResult = callback
end

return SpinController
