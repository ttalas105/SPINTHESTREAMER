--[[
	UIHelper.lua
	Shared UI creation utilities for the client.
	Provides button creation, tween animations, screen scaling,
	and common widget patterns used across all controllers.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)

local UIHelper = {}

-------------------------------------------------
-- RESPONSIVE SCALING
-- Reference resolution: 1080p (1920×1080).
-- All UI is authored at 1080p pixel sizes; screens
-- larger or smaller than that get a proportional UIScale.
-- We use the *smaller* axis so nothing overflows.
-------------------------------------------------

local REF_WIDTH  = 1280
local REF_HEIGHT = 720

local function getViewportScale()
	local camera = workspace.CurrentCamera
	if not camera then return 1 end
	local vp = camera.ViewportSize
	local scaleX = vp.X / REF_WIDTH
	local scaleY = vp.Y / REF_HEIGHT
	return math.min(scaleX, scaleY)
end

-------------------------------------------------
-- SCREEN GUI
-------------------------------------------------

function UIHelper.CreateScreenGui(name: string, displayOrder: number?)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder or 1
	gui.IgnoreGuiInset = true

	-- Auto-scale all children relative to 1080p
	local uiScale = Instance.new("UIScale")
	uiScale.Name = "ResponsiveScale"
	uiScale.Scale = getViewportScale()
	uiScale.Parent = gui

	-- Update when the viewport changes (window resize, orientation flip on mobile)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			uiScale.Scale = getViewportScale()
		end)
	end

	return gui
end

--- Utility: get the current responsive scale factor (for controllers that
--- need to do math with pixel sizes outside of the ScreenGui tree).
function UIHelper.GetScale()
	return getViewportScale()
end

-------------------------------------------------
-- ROUNDED FRAME
-------------------------------------------------

function UIHelper.CreateRoundedFrame(props)
	local frame = Instance.new("Frame")
	frame.Name = props.Name or "Frame"
	frame.Size = props.Size or UDim2.new(0, 100, 0, 50)
	frame.Position = props.Position or UDim2.new(0, 0, 0, 0)
	frame.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
	frame.BackgroundColor3 = props.Color or DesignConfig.Colors.Background
	frame.BackgroundTransparency = props.Transparency or 0
	frame.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = props.CornerRadius or DesignConfig.Layout.ButtonCorner
	corner.Parent = frame

	if props.StrokeColor then
		local stroke = Instance.new("UIStroke")
		stroke.Color = props.StrokeColor
		stroke.Thickness = props.StrokeThickness or DesignConfig.Layout.StrokeThickness
		stroke.Parent = frame
	end

	if props.Parent then
		frame.Parent = props.Parent
	end

	return frame
end

-------------------------------------------------
-- BUTTON
-------------------------------------------------

function UIHelper.CreateButton(props)
	local button = Instance.new("TextButton")
	button.Name = props.Name or "Button"
	button.Size = props.Size or UDim2.new(0, 120, 0, 40)
	button.Position = props.Position or UDim2.new(0, 0, 0, 0)
	button.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
	button.BackgroundColor3 = props.Color or DesignConfig.Colors.ButtonIdle
	button.TextColor3 = props.TextColor or DesignConfig.Colors.TextPrimary
	button.Font = props.Font or DesignConfig.Fonts.Primary
	button.TextSize = props.TextSize or DesignConfig.FontSizes.Body
	button.Text = props.Text or "Button"
	button.BorderSizePixel = 0
	button.AutoButtonColor = false

	local corner = Instance.new("UICorner")
	corner.CornerRadius = props.CornerRadius or DesignConfig.Layout.ButtonCorner
	corner.Parent = button

	if props.StrokeColor then
		local stroke = Instance.new("UIStroke")
		stroke.Color = props.StrokeColor
		stroke.Thickness = props.StrokeThickness or DesignConfig.Layout.StrokeThickness
		stroke.Parent = button
	end

	local idleColor = props.Color or DesignConfig.Colors.ButtonIdle
	local hoverColor = props.HoverColor or DesignConfig.Colors.ButtonHover
	local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	button.MouseEnter:Connect(function()
		TweenService:Create(button, tweenInfo, {
			BackgroundColor3 = hoverColor,
			Size = props.Size and UDim2.new(
				props.Size.X.Scale * 1.05, props.Size.X.Offset * 1.05,
				props.Size.Y.Scale * 1.05, props.Size.Y.Offset * 1.05
			) or button.Size,
		}):Play()
	end)

	button.MouseLeave:Connect(function()
		TweenService:Create(button, tweenInfo, {
			BackgroundColor3 = idleColor,
			Size = props.Size or button.Size,
		}):Play()
	end)

	button.MouseButton1Down:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.08), {
			Size = props.Size and UDim2.new(
				props.Size.X.Scale * 0.95, props.Size.X.Offset * 0.95,
				props.Size.Y.Scale * 0.95, props.Size.Y.Offset * 0.95
			) or button.Size,
		}):Play()
	end)

	button.MouseButton1Up:Connect(function()
		TweenService:Create(button, tweenInfo, {
			Size = props.Size or button.Size,
			BackgroundColor3 = hoverColor,
		}):Play()
	end)

	if props.Parent then
		button.Parent = props.Parent
	end

	return button
end

-------------------------------------------------
-- TEXT LABEL
-------------------------------------------------

function UIHelper.CreateLabel(props)
	local label = Instance.new("TextLabel")
	label.Name = props.Name or "Label"
	label.Size = props.Size or UDim2.new(0, 100, 0, 30)
	label.Position = props.Position or UDim2.new(0, 0, 0, 0)
	label.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
	label.BackgroundTransparency = props.BackgroundTransparency or 1
	label.BackgroundColor3 = props.Color or Color3.new(0, 0, 0)
	label.TextColor3 = props.TextColor or DesignConfig.Colors.TextPrimary
	label.Font = props.Font or DesignConfig.Fonts.Primary
	label.TextSize = props.TextSize or DesignConfig.FontSizes.Body
	label.Text = props.Text or ""
	label.TextScaled = props.TextScaled or false
	label.BorderSizePixel = 0

	if props.Parent then
		label.Parent = props.Parent
	end

	return label
end

-------------------------------------------------
-- ICON BUTTON (image icon + label underneath)
-- Uses ImageLabel for real asset icons
-------------------------------------------------

function UIHelper.CreateIconButton(props)
	local container = Instance.new("Frame")
	container.Name = props.Name or "IconButton"
	container.Size = props.Size or DesignConfig.Sizes.SideButtonSize
	container.Position = props.Position or UDim2.new(0, 0, 0, 0)
	container.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
	container.BackgroundColor3 = props.Color or DesignConfig.Colors.ButtonIdle
	container.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = props.CornerRadius or DesignConfig.Layout.ButtonCorner
	corner.Parent = container

	-- Image icon (if asset ID provided) or cartoon emoji text icon
	if props.ImageId and props.ImageId ~= "" then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.new(0.7, 0, 0.55, 0)
		icon.Position = UDim2.new(0.5, 0, 0.05, 0)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.BackgroundTransparency = 1
		icon.Image = props.ImageId
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = container
	else
		local icon = Instance.new("TextLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.new(1, 0, 0.62, 0)
		icon.Position = UDim2.new(0, 0, 0.02, 0)
		icon.BackgroundTransparency = 1
		icon.TextColor3 = props.IconColor3 or DesignConfig.Colors.White
		-- Cartoon-style font for emoji icons (FredokaOne is bouncy and kid-friendly)
		icon.Font = props.IconFont or DesignConfig.Fonts.Accent
		icon.TextScaled = true
		icon.Text = props.Icon or "?"
		icon.Parent = container
	end

	-- Label underneath (optional cartoon font for kid-friendly nav)
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 0.35, 0)
	label.Position = UDim2.new(0, 0, 0.65, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = DesignConfig.Colors.White
	label.Font = props.LabelFont or DesignConfig.Fonts.Primary
	label.TextScaled = true
	label.Text = props.Label or ""
	label.Parent = container

	-- Drop shadow / stroke on label for readability
	local labelStroke = Instance.new("UIStroke")
	labelStroke.Color = Color3.new(0, 0, 0)
	labelStroke.Thickness = 1.5
	labelStroke.Transparency = 0.3
	labelStroke.Parent = label

	-- Click detection (invisible button over the frame)
	local clickButton = Instance.new("TextButton")
	clickButton.Name = "ClickZone"
	clickButton.Size = UDim2.new(1, 0, 1, 0)
	clickButton.BackgroundTransparency = 1
	clickButton.Text = ""
	clickButton.Parent = container

	-- Hover animation
	local idleColor = props.Color or DesignConfig.Colors.ButtonIdle
	local hoverColor = props.HoverColor or DesignConfig.Colors.ButtonHover
	local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad)

	clickButton.MouseEnter:Connect(function()
		TweenService:Create(container, tweenInfo, { BackgroundColor3 = hoverColor }):Play()
	end)
	clickButton.MouseLeave:Connect(function()
		TweenService:Create(container, tweenInfo, { BackgroundColor3 = idleColor }):Play()
	end)

	-- Notification badge (hidden by default)
	local badge = UIHelper.CreateRoundedFrame({
		Name = "Badge",
		Size = UDim2.new(0, 20, 0, 20),
		Position = UDim2.new(1, -5, 0, -5),
		AnchorPoint = Vector2.new(1, 0),
		Color = DesignConfig.Colors.NotificationBadge,
		CornerRadius = UDim.new(1, 0),
		Parent = container,
	})
	badge.Visible = false

	local badgeText = Instance.new("TextLabel")
	badgeText.Name = "Count"
	badgeText.Size = UDim2.new(1, 0, 1, 0)
	badgeText.BackgroundTransparency = 1
	badgeText.TextColor3 = DesignConfig.Colors.White
	badgeText.Font = DesignConfig.Fonts.Primary
	badgeText.TextScaled = true
	badgeText.Text = "0"
	badgeText.Parent = badge

	if props.Parent then
		container.Parent = props.Parent
	end

	return container, clickButton
end

-------------------------------------------------
-- MODAL OVERLAY
-------------------------------------------------

function UIHelper.CreateModalOverlay(screenGui, onClick)
	local overlay = Instance.new("TextButton")
	overlay.Name = "ModalOverlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.BorderSizePixel = 0
	overlay.Text = ""
	overlay.ZIndex = 10
	overlay.Parent = screenGui

	if onClick then
		overlay.MouseButton1Click:Connect(onClick)
	end

	return overlay
end

-------------------------------------------------
-- TWEEN HELPERS
-------------------------------------------------

function UIHelper.FadeIn(guiObject, duration)
	duration = duration or 0.3
	guiObject.Visible = true
	if guiObject:IsA("Frame") or guiObject:IsA("TextLabel") or guiObject:IsA("TextButton") then
		guiObject.BackgroundTransparency = 1
		TweenService:Create(guiObject, TweenInfo.new(duration), {
			BackgroundTransparency = 0,
		}):Play()
	end
end

function UIHelper.SlideIn(guiObject, from, to, duration)
	duration = duration or 0.3
	guiObject.Position = from
	guiObject.Visible = true
	TweenService:Create(guiObject, TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = to,
	}):Play()
end

function UIHelper.ScaleIn(guiObject, duration)
	duration = duration or 0.3
	guiObject.Visible = true
	local targetSize = guiObject.Size
	guiObject.Size = UDim2.new(
		targetSize.X.Scale * 0.5, targetSize.X.Offset * 0.5,
		targetSize.Y.Scale * 0.5, targetSize.Y.Offset * 0.5
	)
	TweenService:Create(guiObject, TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = targetSize,
	}):Play()
end

-------------------------------------------------
-- CAMERA SHAKE
-------------------------------------------------

function UIHelper.CameraShake(intensity, duration)
	local camera = workspace.CurrentCamera
	if not camera then return end

	duration = duration or 0.3
	local elapsed = 0

	task.spawn(function()
		while elapsed < duration do
			local dt = task.wait()
			elapsed = elapsed + dt
			local progress = 1 - (elapsed / duration)
			local shakeX = (math.random() - 0.5) * 2 * intensity * progress
			local shakeY = (math.random() - 0.5) * 2 * intensity * progress
			camera.CFrame = camera.CFrame * CFrame.new(shakeX, shakeY, 0)
		end
	end)
end

return UIHelper
