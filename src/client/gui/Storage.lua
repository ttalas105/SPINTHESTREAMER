--[[
	gui/Storage.lua
	Storage GUI. Modal for overflow streamers grid.
	Used by StorageController.
]]

local UIHelper = require(script.Parent.Parent.controllers.UIHelper)

local FONT = Enum.Font.FredokaOne
local BG = Color3.fromRGB(14, 12, 28)
local ACCENT = Color3.fromRGB(255, 165, 50)

local StorageGui = {}

function StorageGui.Build(parent)
	local modal = Instance.new("Frame")
	modal.Name = "StorageModal"
	modal.Size = UDim2.new(0, 560, 0, 480)
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

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, -32, 0, 48)
	header.Position = UDim2.new(0, 16, 0, 12)
	header.BackgroundTransparency = 1
	header.Parent = modal

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -140, 1, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "STORAGE"
	titleLabel.Font = FONT
	titleLabel.TextSize = 20
	titleLabel.TextColor3 = ACCENT
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = header

	local sortFrame = Instance.new("Frame")
	sortFrame.Name = "SortFrame"
	sortFrame.Size = UDim2.new(0, 120, 0, 32)
	sortFrame.Position = UDim2.new(1, -120, 0.5, -16)
	sortFrame.BackgroundTransparency = 1
	sortFrame.Parent = header

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "GridScroll"
	scroll.Size = UDim2.new(1, -32, 1, -72)
	scroll.Position = UDim2.new(0, 16, 0, 68)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = modal

	local gridFrame = Instance.new("Frame")
	gridFrame.Name = "Grid"
	gridFrame.Size = UDim2.new(1, 0, 0, 0)
	gridFrame.AutomaticSize = Enum.AutomaticSize.Y
	gridFrame.BackgroundTransparency = 1
	gridFrame.Parent = scroll

	local gridLayout = Instance.new("UIGridLayout", gridFrame)
	gridLayout.CellSize = UDim2.new(0, 80, 0, 100)
	gridLayout.CellPadding = UDim2.new(0, 6, 0, 6)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local refs = {
		modal = modal,
		header = header,
		titleLabel = titleLabel,
		sortFrame = sortFrame,
		scroll = scroll,
		gridFrame = gridFrame,
	}
	return modal, refs
end

return StorageGui
