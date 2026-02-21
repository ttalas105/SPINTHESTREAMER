--[[
	gui/Settings.lua
	Settings GUI — modal for toggles (music, etc.).
	Used by SettingsController; build the modal frame and toggle container here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIHelper = require(script.Parent.Parent.controllers.UIHelper)

local FONT = Enum.Font.FredokaOne
local FONT2 = Enum.Font.GothamBold
local BG = Color3.fromRGB(22, 18, 42)
local PANEL_W = 420
local PANEL_H = 360

local SettingsGui = {}

function SettingsGui.Build(parent)
	local modal = Instance.new("Frame")
	modal.Name = "SettingsModal"
	modal.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
	modal.Position = UDim2.new(0.5, 0, 0.5, 0)
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.BackgroundColor3 = BG
	modal.BorderSizePixel = 0
	modal.Visible = false
	modal.Parent = parent

	Instance.new("UICorner", modal).CornerRadius = UDim.new(0, 20)
	local stroke = Instance.new("UIStroke", modal)
	stroke.Color = Color3.fromRGB(60, 50, 90)
	stroke.Thickness = 2

	-- Header
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, -32, 0, 48)
	header.Position = UDim2.new(0, 16, 0, 16)
	header.BackgroundTransparency = 1
	header.Parent = modal

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 1, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "SETTINGS"
	titleLabel.Font = FONT
	titleLabel.TextSize = 22
	titleLabel.TextColor3 = Color3.fromRGB(255, 240, 200)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = header

	-- Toggle list container
	local listFrame = Instance.new("Frame")
	listFrame.Name = "ToggleList"
	listFrame.Size = UDim2.new(1, -32, 1, -80)
	listFrame.Position = UDim2.new(0, 16, 0, 72)
	listFrame.BackgroundTransparency = 1
	listFrame.Parent = modal

	local listLayout = Instance.new("UIListLayout", listFrame)
	listLayout.Padding = UDim.new(0, 10)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local refs = {
		modal = modal,
		header = header,
		titleLabel = titleLabel,
		listFrame = listFrame,
	}
	return modal, refs
end

return SettingsGui
