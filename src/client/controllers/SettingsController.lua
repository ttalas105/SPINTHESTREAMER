--[[
	SettingsController.lua
	Bubbly, kid-friendly settings panel.
	Toggles: Main Music, Sacrifice Music.
	Matches the game's responsive UIScale system.
]]

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local UIHelper = require(script.Parent.UIHelper)
local MusicController = require(script.Parent.MusicController)

local SettingsController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = nil
local modalFrame = nil
local isOpen = false

local FONT = Enum.Font.FredokaOne
local FONT2 = Enum.Font.GothamBold
local BG = Color3.fromRGB(22, 18, 42)
local PANEL_W = 420
local PANEL_H = 360

local SETTINGS_GEAR_ASSET_ID = "rbxassetid://114090124339958"

-------------------------------------------------
-- TOGGLE SWITCH WIDGET (bubbly pill with smooth animation)
-------------------------------------------------

local function createToggle(parent, label, defaultOn, onChanged)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -40, 0, 56)
	row.BackgroundColor3 = Color3.fromRGB(34, 28, 60)
	row.BorderSizePixel = 0
	row.Parent = parent
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 16)

	local rowPad = Instance.new("UIPadding")
	rowPad.PaddingLeft = UDim.new(0, 20)
	rowPad.PaddingRight = UDim.new(0, 16)
	rowPad.Parent = row

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -80, 1, 0)
	lbl.Position = UDim2.new(0, 0, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = label
	lbl.TextColor3 = Color3.fromRGB(230, 225, 255)
	lbl.Font = FONT; lbl.TextSize = 18
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = row

	-- Track / pill
	local trackW, trackH = 56, 30
	local knobSize = 24
	local onColor = Color3.fromRGB(100, 220, 130)
	local offColor = Color3.fromRGB(80, 60, 100)
	local knobOnX = trackW - knobSize - 3
	local knobOffX = 3

	local track = Instance.new("Frame")
	track.Size = UDim2.new(0, trackW, 0, trackH)
	track.Position = UDim2.new(1, -trackW, 0.5, 0)
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.BackgroundColor3 = defaultOn and onColor or offColor
	track.BorderSizePixel = 0
	track.Parent = row
	Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

	local knob = Instance.new("Frame")
	knob.Size = UDim2.new(0, knobSize, 0, knobSize)
	knob.Position = UDim2.new(0, defaultOn and knobOnX or knobOffX, 0.5, 0)
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BorderSizePixel = 0
	knob.Parent = track
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

	-- Drop shadow on knob
	local knobStroke = Instance.new("UIStroke")
	knobStroke.Color = Color3.fromRGB(20, 15, 40)
	knobStroke.Thickness = 1.5
	knobStroke.Transparency = 0.5
	knobStroke.Parent = knob

	local state = defaultOn
	local tweenInfo = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	local clickZone = Instance.new("TextButton")
	clickZone.Size = UDim2.new(1, 0, 1, 0)
	clickZone.BackgroundTransparency = 1
	clickZone.Text = ""
	clickZone.Parent = row

	clickZone.MouseButton1Click:Connect(function()
		state = not state
		local targetKnobX = state and knobOnX or knobOffX
		local targetColor = state and onColor or offColor
		TweenService:Create(knob, tweenInfo, { Position = UDim2.new(0, targetKnobX, 0.5, 0) }):Play()
		TweenService:Create(track, TweenInfo.new(0.2), { BackgroundColor3 = targetColor }):Play()
		if onChanged then onChanged(state) end
	end)

	return row
end

-------------------------------------------------
-- BUILD UI
-------------------------------------------------

function SettingsController.Init()
	screenGui = UIHelper.CreateScreenGui("SettingsGui", 12)
	screenGui.Parent = playerGui

	-- Dimmed backdrop
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.BorderSizePixel = 0
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Parent = screenGui
	backdrop.MouseButton1Click:Connect(function() SettingsController.Close() end)

	-- Main panel
	modalFrame = Instance.new("Frame")
	modalFrame.Name = "SettingsPanel"
	modalFrame.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
	modalFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	modalFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	modalFrame.BackgroundColor3 = BG
	modalFrame.BorderSizePixel = 0
	modalFrame.ClipsDescendants = true
	modalFrame.Parent = screenGui
	Instance.new("UICorner", modalFrame).CornerRadius = UDim.new(0, 28)

	local outerStroke = Instance.new("UIStroke")
	outerStroke.Color = Color3.fromRGB(120, 80, 200)
	outerStroke.Thickness = 2.5
	outerStroke.Transparency = 0.2
	outerStroke.Parent = modalFrame
	UIHelper.CreateShadow(modalFrame)

	-- Header bar
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 60)
	header.BackgroundColor3 = Color3.fromRGB(50, 35, 90)
	header.BorderSizePixel = 0
	header.Parent = modalFrame
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, 28)

	-- Bottom-half mask so header looks flat at bottom
	local headerMask = Instance.new("Frame")
	headerMask.Size = UDim2.new(1, 0, 0.5, 0)
	headerMask.Position = UDim2.new(0, 0, 0.5, 0)
	headerMask.BackgroundColor3 = header.BackgroundColor3
	headerMask.BorderSizePixel = 0
	headerMask.Parent = header

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -70, 1, 0)
	titleLabel.Position = UDim2.new(0, 22, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "\u{2699}\u{FE0F}  Settings"
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.Font = FONT; titleLabel.TextSize = 26
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = header

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 40, 0, 40)
	closeBtn.Position = UDim2.new(1, -14, 0.5, 0)
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 80)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = FONT; closeBtn.TextSize = 20
	closeBtn.BorderSizePixel = 0
	closeBtn.AutoButtonColor = false
	closeBtn.Parent = header
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1, 0)
	closeBtn.MouseButton1Click:Connect(function() SettingsController.Close() end)

	-- Content area
	local content = Instance.new("Frame")
	content.Size = UDim2.new(1, 0, 1, -70)
	content.Position = UDim2.new(0, 0, 0, 68)
	content.BackgroundTransparency = 1
	content.Parent = modalFrame

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.Padding = UDim.new(0, 14)
	contentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Parent = content

	-- Section label: Music
	local musicSection = Instance.new("TextLabel")
	musicSection.Size = UDim2.new(1, -40, 0, 28)
	musicSection.BackgroundTransparency = 1
	musicSection.Text = "\u{1F3B5}  Music"
	musicSection.TextColor3 = Color3.fromRGB(180, 160, 255)
	musicSection.Font = FONT; musicSection.TextSize = 20
	musicSection.TextXAlignment = Enum.TextXAlignment.Left
	musicSection.LayoutOrder = 1
	musicSection.Parent = content

	local musicPad = Instance.new("UIPadding")
	musicPad.PaddingLeft = UDim.new(0, 20)
	musicPad.Parent = musicSection

	-- Toggle: Main Music
	local t1 = createToggle(content, "\u{1F3B6}  Main Music", not MusicController.IsLobbyMuted(), function(on)
		MusicController.SetLobbyMuted(not on)
	end)
	t1.LayoutOrder = 2

	-- Toggle: Sacrifice Music
	local t2 = createToggle(content, "\u{1F525}  Sacrifice Music", not MusicController.IsSacrificeMuted(), function(on)
		MusicController.SetSacrificeMuted(not on)
	end)
	t2.LayoutOrder = 3

	-- Spacer
	local spacer = Instance.new("Frame")
	spacer.Size = UDim2.new(0.75, 0, 0, 2)
	spacer.BackgroundColor3 = Color3.fromRGB(60, 50, 90)
	spacer.BorderSizePixel = 0
	spacer.LayoutOrder = 4
	spacer.Parent = content
	Instance.new("UICorner", spacer).CornerRadius = UDim.new(1, 0)

	-- Footer note
	local footer = Instance.new("TextLabel")
	footer.Size = UDim2.new(1, -40, 0, 30)
	footer.BackgroundTransparency = 1
	footer.Text = "More settings coming soon!"
	footer.TextColor3 = Color3.fromRGB(120, 110, 160)
	footer.Font = FONT2; footer.TextSize = 14
	footer.LayoutOrder = 5
	footer.Parent = content

	screenGui.Enabled = false
end

-------------------------------------------------
-- OPEN / CLOSE
-------------------------------------------------

function SettingsController.Open()
	if isOpen then SettingsController.Close(); return end
	isOpen = true
	screenGui.Enabled = true
	UIHelper.ScaleIn(modalFrame, 0.22)
end

function SettingsController.Close()
	if not isOpen then return end
	isOpen = false
	if modalFrame then
		UIHelper.ScaleOut(modalFrame, 0.2)
		task.delay(0.25, function()
			screenGui.Enabled = false
		end)
	else
		screenGui.Enabled = false
	end
end

function SettingsController.IsOpen()
	return isOpen
end

return SettingsController
