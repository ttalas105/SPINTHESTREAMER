--[[
	UIHelper.lua
	Shared UI creation utilities for the client.
	Provides button creation, tween animations, screen scaling,
	shadows, gradients, and common widget patterns.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)

local UIHelper = {}

-------------------------------------------------
-- RESPONSIVE SCALING
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

	local uiScale = Instance.new("UIScale")
	uiScale.Name = "ResponsiveScale"
	uiScale.Scale = getViewportScale()
	uiScale.Parent = gui

	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			uiScale.Scale = getViewportScale()
		end)
	end

	return gui
end

function UIHelper.GetScale()
	return getViewportScale()
end

-------------------------------------------------
-- PUFFY GRADIENT (lighter top, darker bottom)
-------------------------------------------------

function UIHelper.AddPuffyGradient(guiObject)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 200, 210)),
	})
	grad.Rotation = 90
	grad.Parent = guiObject
	return grad
end

-------------------------------------------------
-- DROP SHADOW
-------------------------------------------------

function UIHelper.CreateShadow(parent)
	local shadow = Instance.new("Frame")
	shadow.Name = "_Shadow"
	shadow.Size = UDim2.new(1, 8, 1, 8)
	shadow.Position = UDim2.new(0.5, 3, 0.5, 3)
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.BackgroundColor3 = DesignConfig.Layout.ShadowColor
	shadow.BackgroundTransparency = DesignConfig.Layout.ShadowTransparency
	shadow.BorderSizePixel = 0
	shadow.ZIndex = -1

	local corner = Instance.new("UICorner")
	local parentCorner = parent:FindFirstChildOfClass("UICorner")
	corner.CornerRadius = parentCorner and parentCorner.CornerRadius or DesignConfig.Layout.ModalCorner
	corner.Parent = shadow

	shadow.Parent = parent
	return shadow
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
		stroke.Transparency = props.StrokeTransparency or 0.15
		stroke.Parent = frame
	end

	if props.Parent then
		frame.Parent = props.Parent
	end

	return frame
end

-------------------------------------------------
-- BUTTON (bouncy + puffy gradient)
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
		stroke.Transparency = 0.15
		stroke.Parent = button
	end

	-- Puffy gradient overlay
	if props.NoPuffy ~= true then
		UIHelper.AddPuffyGradient(button)
	end

	local idleSize = props.Size or button.Size
	local idleColor = props.Color or DesignConfig.Colors.ButtonIdle
	local hoverColor = props.HoverColor or DesignConfig.Colors.ButtonHover

	local hoverSize = UDim2.new(
		idleSize.X.Scale * 1.08, idleSize.X.Offset * 1.08,
		idleSize.Y.Scale * 1.08, idleSize.Y.Offset * 1.08
	)
	local clickSize = UDim2.new(
		idleSize.X.Scale * 0.93, idleSize.X.Offset * 0.93,
		idleSize.Y.Scale * 0.93, idleSize.Y.Offset * 0.93
	)

	local bounceTween = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local clickTween  = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	button.MouseEnter:Connect(function()
		TweenService:Create(button, bounceTween, {
			BackgroundColor3 = hoverColor,
			Size = hoverSize,
		}):Play()
	end)

	button.MouseLeave:Connect(function()
		TweenService:Create(button, bounceTween, {
			BackgroundColor3 = idleColor,
			Size = idleSize,
		}):Play()
	end)

	button.MouseButton1Down:Connect(function()
		TweenService:Create(button, clickTween, { Size = clickSize }):Play()
	end)

	button.MouseButton1Up:Connect(function()
		TweenService:Create(button, bounceTween, {
			Size = idleSize,
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
-- ICON BUTTON (bouncy + shadow + image-ready)
-------------------------------------------------

function UIHelper.CreateIconButton(props)
	local hasImage = props.ImageId and props.ImageId ~= ""
	local DEFAULT_BTN_BG = Color3.fromRGB(120, 200, 245)
	local btnBg = props.BgColor or (hasImage and DEFAULT_BTN_BG) or props.Color or DEFAULT_BTN_BG
	local btnBgHover = Color3.new(
		math.min(btnBg.R + 0.08, 1),
		math.min(btnBg.G + 0.08, 1),
		math.min(btnBg.B + 0.08, 1)
	)
	local btnStrokeColor = Color3.new(
		math.max(btnBg.R - 0.15, 0),
		math.max(btnBg.G - 0.15, 0),
		math.max(btnBg.B - 0.15, 0)
	)

	local container = Instance.new("Frame")
	container.Name = props.Name or "IconButton"
	container.Size = props.Size or DesignConfig.Sizes.SideButtonSize
	container.Position = props.Position or UDim2.new(0, 0, 0, 0)
	container.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
	container.BorderSizePixel = 0

	if hasImage then
		container.BackgroundColor3 = btnBg
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 18)
		corner.Parent = container

		local bgStroke = Instance.new("UIStroke")
		bgStroke.Color = btnStrokeColor
		bgStroke.Thickness = 1.5
		bgStroke.Transparency = 0.25
		bgStroke.Parent = container
	else
		container.BackgroundColor3 = props.BgColor or props.Color or DesignConfig.Colors.ButtonIdle
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 18)
		corner.Parent = container

		local bgStroke = Instance.new("UIStroke")
		bgStroke.Color = btnStrokeColor
		bgStroke.Thickness = 1.5
		bgStroke.Transparency = 0.25
		bgStroke.Parent = container
	end

	if hasImage then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.new(0, 90, 0, 90)
		icon.Position = UDim2.new(0.5, 0, 0.5, -12)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.BackgroundTransparency = 1
		icon.Image = props.ImageId
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = container
	else
		local icon = Instance.new("TextLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.new(0, 100, 0, 70)
		icon.Position = UDim2.new(0.5, 0, 0.5, -12)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.BackgroundTransparency = 1
		icon.TextColor3 = props.IconColor3 or DesignConfig.Colors.White
		icon.Font = props.IconFont or DesignConfig.Fonts.Accent
		icon.TextScaled = true
		icon.Text = props.Icon or "?"
		icon.Parent = container
	end

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Text = props.Label or ""
	label.Parent = container

	if hasImage then
		label.Size = UDim2.new(1, 0, 0, 30)
		label.Position = UDim2.new(0.5, 0, 1, -6)
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Font = Enum.Font.FredokaOne
		label.TextSize = 24
		label.TextScaled = false

		local labelStroke = Instance.new("UIStroke")
		labelStroke.Color = Color3.fromRGB(30, 30, 30)
		labelStroke.Thickness = 2.5
		labelStroke.Transparency = 0
		labelStroke.Parent = label
	else
		label.Size = UDim2.new(1, 0, 0, 30)
		label.Position = UDim2.new(0.5, 0, 1, -6)
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Font = props.LabelFont or Enum.Font.FredokaOne
		label.TextSize = 24
		label.TextScaled = false

		local labelStroke = Instance.new("UIStroke")
		labelStroke.Color = Color3.fromRGB(30, 30, 30)
		labelStroke.Thickness = 2.5
		labelStroke.Transparency = 0
		labelStroke.Parent = label
	end

	local clickButton = Instance.new("TextButton")
	clickButton.Name = "ClickZone"
	clickButton.Size = UDim2.new(1, 0, 1, 0)
	clickButton.BackgroundTransparency = 1
	clickButton.Text = ""
	clickButton.Parent = container

	local idleSize = props.Size or DesignConfig.Sizes.SideButtonSize

	local hoverSize = UDim2.new(
		idleSize.X.Scale * 1.08, idleSize.X.Offset * 1.08,
		idleSize.Y.Scale * 1.08, idleSize.Y.Offset * 1.08
	)
	local clickSize = UDim2.new(
		idleSize.X.Scale * 0.93, idleSize.X.Offset * 0.93,
		idleSize.Y.Scale * 0.93, idleSize.Y.Offset * 0.93
	)

	local bounceTween = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local clickTween  = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	if hasImage then
		clickButton.MouseEnter:Connect(function()
			TweenService:Create(container, bounceTween, {
				Size = hoverSize,
				BackgroundColor3 = btnBgHover,
			}):Play()
		end)
		clickButton.MouseLeave:Connect(function()
			TweenService:Create(container, bounceTween, {
				Size = idleSize,
				BackgroundColor3 = btnBg,
			}):Play()
		end)
	else
		local idleColor = props.Color or DesignConfig.Colors.ButtonIdle
		local hoverColor = props.HoverColor or DesignConfig.Colors.ButtonHover
		clickButton.MouseEnter:Connect(function()
			TweenService:Create(container, bounceTween, {
				BackgroundColor3 = hoverColor,
				Size = hoverSize,
			}):Play()
		end)
		clickButton.MouseLeave:Connect(function()
			TweenService:Create(container, bounceTween, {
				BackgroundColor3 = idleColor,
				Size = idleSize,
			}):Play()
		end)
		clickButton.MouseButton1Up:Connect(function()
			TweenService:Create(container, bounceTween, {
				Size = idleSize,
				BackgroundColor3 = hoverColor,
			}):Play()
		end)
	end

	clickButton.MouseButton1Down:Connect(function()
		TweenService:Create(container, clickTween, { Size = clickSize }):Play()
	end)

	local badge = UIHelper.CreateRoundedFrame({
		Name = "Badge",
		Size = UDim2.new(0, 24, 0, 24),
		Position = UDim2.new(1, -2, 0, -4),
		AnchorPoint = Vector2.new(1, 0),
		Color = Color3.fromRGB(255, 50, 50),
		CornerRadius = UDim.new(1, 0),
		Parent = container,
	})
	badge.Visible = false
	badge.ZIndex = 10

	local badgeText = Instance.new("TextLabel")
	badgeText.Name = "Count"
	badgeText.Size = UDim2.new(1, 0, 1, 0)
	badgeText.BackgroundTransparency = 1
	badgeText.TextColor3 = Color3.new(1, 1, 1)
	badgeText.Font = Enum.Font.FredokaOne
	badgeText.TextScaled = true
	badgeText.Text = "!"
	badgeText.ZIndex = 11
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

function UIHelper.ScaleOut(guiObject, duration)
	duration = duration or 0.25
	local targetSize = UDim2.new(
		guiObject.Size.X.Scale * 0.8, guiObject.Size.X.Offset * 0.8,
		guiObject.Size.Y.Scale * 0.8, guiObject.Size.Y.Offset * 0.8
	)
	local tween = TweenService:Create(guiObject, TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Size = targetSize,
	})
	tween:Play()
	tween.Completed:Connect(function()
		guiObject.Visible = false
		-- Restore original size so ScaleIn works next open
		guiObject.Size = UDim2.new(
			targetSize.X.Scale / 0.8, targetSize.X.Offset / 0.8,
			targetSize.Y.Scale / 0.8, targetSize.Y.Offset / 0.8
		)
	end)
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

--[[
	Makes a modal frame responsive to viewport size.
	designW/designH = the intended pixel size at the 1280x720 reference.
	The modal will scale down on smaller screens so it never overflows,
	covering phones (as small as ~360x640), tablets, laptops, and desktops.
	Returns a cleanup connection to disconnect when the UI is destroyed.
]]
function UIHelper.MakeResponsiveModal(modal, designW, designH)
	local camera = workspace.CurrentCamera

	local function fit()
		local vw = camera.ViewportSize.X
		local vh = camera.ViewportSize.Y
		local screenScale = math.min(vw / REF_WIDTH, vh / REF_HEIGHT)
		if screenScale <= 0 then screenScale = 1 end

		local renderedW = designW * screenScale
		local renderedH = designH * screenScale

		local maxW = vw * 0.94
		local maxH = vh * 0.88

		local fitScale = 1
		if renderedW > maxW then
			fitScale = math.min(fitScale, maxW / renderedW)
		end
		if renderedH > maxH then
			fitScale = math.min(fitScale, maxH / renderedH)
		end

		modal.Size = UDim2.new(0, math.floor(designW * fitScale), 0, math.floor(designH * fitScale))
	end

	fit()
	local conn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	return conn
end

--[[
	Returns true when the viewport is phone-sized (narrow or short).
	Useful for controllers that want to adjust layout on mobile.
]]
function UIHelper.IsMobile()
	local camera = workspace.CurrentCamera
	if not camera then return false end
	local vp = camera.ViewportSize
	return vp.X < 600 or vp.Y < 500
end

--[[
	Returns the current viewport size in pixels.
]]
function UIHelper.GetViewportSize()
	local camera = workspace.CurrentCamera
	if not camera then return Vector2.new(REF_WIDTH, REF_HEIGHT) end
	return camera.ViewportSize
end

return UIHelper
