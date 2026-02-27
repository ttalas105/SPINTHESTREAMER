-- gui/Index.lua - Index GUI for Streamer Index. Used by IndexController.
local UIHelper = require(script.Parent.Parent.controllers.UIHelper)
local FONT = Enum.Font.FredokaOne
local BG = Color3.fromRGB(45, 35, 75)
local IndexGui = {}

function IndexGui.Build(parent)
	local modal = Instance.new("Frame")
	modal.Name = "IndexModal"
	modal.Size = UDim2.new(0, 940, 0, 670)
	modal.Position = UDim2.new(0.5, 0, 0.5, 0)
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.BackgroundColor3 = BG
	modal.BorderSizePixel = 0
	modal.Visible = false
	modal.Parent = parent
	Instance.new("UICorner", modal).CornerRadius = UDim.new(0, 28)
	local stroke = Instance.new("UIStroke", modal)
	stroke.Color = Color3.fromRGB(180, 130, 255)
	stroke.Thickness = 2.5
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, -32, 0, 70)
	header.Position = UDim2.new(0, 16, 0, 12)
	header.BackgroundTransparency = 1
	header.Parent = modal
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -80, 1, 0)
	titleLabel.Position = UDim2.new(0.5, 0, 0, 0)
	titleLabel.AnchorPoint = Vector2.new(0.5, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "STREAMER INDEX"
	titleLabel.Font = FONT
	titleLabel.TextSize = 38
	titleLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	titleLabel.Parent = header
	local counterLabel = Instance.new("TextLabel")
	counterLabel.Name = "Counter"
	counterLabel.Size = UDim2.new(0, 160, 0, 26)
	counterLabel.Position = UDim2.new(0.5, 0, 1, 4)
	counterLabel.AnchorPoint = Vector2.new(0.5, 0)
	counterLabel.BackgroundTransparency = 1
	counterLabel.Text = "0 / 0"
	counterLabel.Font = FONT
	counterLabel.TextSize = 20
	counterLabel.TextColor3 = Color3.fromRGB(200, 180, 255)
	counterLabel.Parent = header
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -32, 1, -105)
	content.Position = UDim2.new(0, 16, 0, 95)
	content.BackgroundTransparency = 1
	content.Parent = modal
	local sidebar = Instance.new("Frame")
	sidebar.Name = "Sidebar"
	sidebar.Size = UDim2.new(0, 165, 1, 0)
	sidebar.BackgroundTransparency = 1
	sidebar.Parent = content
	local listLayout = Instance.new("UIListLayout", sidebar)
	listLayout.Padding = UDim.new(0, 5)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	local gridFrame = Instance.new("Frame")
	gridFrame.Name = "Grid"
	gridFrame.Size = UDim2.new(1, -175, 1, 0)
	gridFrame.Position = UDim2.new(0, 175, 0, 0)
	gridFrame.BackgroundTransparency = 1
	gridFrame.Parent = content
	local gl = Instance.new("UIGridLayout", gridFrame)
	gl.CellSize = UDim2.new(0, 180, 0, 240)
	gl.CellPadding = UDim2.new(0, 10, 0, 10)
	gl.SortOrder = Enum.SortOrder.LayoutOrder

	UIHelper.MakeResponsiveModal(modal, 940, 670)

	return modal, { modal = modal, header = header, titleLabel = titleLabel, counterLabel = counterLabel, content = content, sidebar = sidebar, gridFrame = gridFrame }
end
return IndexGui
