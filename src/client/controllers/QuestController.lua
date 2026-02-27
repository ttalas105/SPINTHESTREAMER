--[[
	QuestController.lua
	Client-side quest UI. Shows daily, weekly, and lifetime quests
	in a tabbed modal. Players can view progress and claim rewards.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Quests = require(ReplicatedStorage.Shared.Config.Quests)
local UIHelper = require(script.Parent.UIHelper)

local QuestController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local ClaimQuestReward = RemoteEvents:WaitForChild("ClaimQuestReward")
local QuestUpdate = RemoteEvents:WaitForChild("QuestUpdate")

local screenGui, overlay, modalFrame, scrollFrame
local isOpen = false
local currentTab = "Daily"
local questData = { progress = {}, claimed = {} }

local FONT = Enum.Font.FredokaOne
local FONT_SUB = Enum.Font.GothamBold
local MODAL_BG = Color3.fromRGB(30, 25, 45)
local MODAL_W, MODAL_H = 520, 520
local TAB_COLORS = {
	Daily = Color3.fromRGB(80, 200, 120),
	Weekly = Color3.fromRGB(100, 150, 255),
	Lifetime = Color3.fromRGB(255, 180, 60),
}

local bounceTween = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function fmtNum(n)
	if n >= 1e9 then return string.format("%.1fB", n / 1e9)
	elseif n >= 1e6 then return string.format("%.1fM", n / 1e6)
	elseif n >= 1e3 then return string.format("%.1fK", n / 1e3)
	end
	return tostring(n)
end

local function getQuestList()
	if currentTab == "Daily" then return Quests.Daily
	elseif currentTab == "Weekly" then return Quests.Weekly
	else return Quests.Lifetime end
end

local function buildQuestRow(quest, parent, order)
	local progress = questData.progress[quest.id] or 0
	local claimed = questData.claimed[quest.id] or false
	local complete = progress >= quest.goal

	local row = Instance.new("Frame")
	row.Name = "Quest_" .. quest.id
	row.Size = UDim2.new(1, -10, 0, 80)
	row.BackgroundColor3 = Color3.fromRGB(40, 35, 60)
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.ZIndex = 3
	row.Parent = parent
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 12)

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingTop = UDim.new(0, 8)
	pad.Parent = row

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(0.6, 0, 0, 20)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = quest.name
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.Font = FONT
	nameLabel.TextSize = 16
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.ZIndex = 4
	nameLabel.Parent = row

	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(0.6, 0, 0, 16)
	descLabel.Position = UDim2.new(0, 0, 0, 21)
	descLabel.BackgroundTransparency = 1
	descLabel.Text = quest.desc
	descLabel.TextColor3 = Color3.fromRGB(160, 155, 185)
	descLabel.Font = FONT_SUB
	descLabel.TextSize = 11
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.ZIndex = 4
	descLabel.Parent = row

	-- Progress bar
	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(0.55, 0, 0, 10)
	barBg.Position = UDim2.new(0, 0, 0, 42)
	barBg.BackgroundColor3 = Color3.fromRGB(25, 20, 35)
	barBg.BorderSizePixel = 0
	barBg.ZIndex = 4
	barBg.Parent = row
	Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 5)

	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.new(math.clamp(progress / quest.goal, 0, 1), 0, 1, 0)
	barFill.BackgroundColor3 = complete and Color3.fromRGB(80, 255, 120) or (TAB_COLORS[currentTab] or Color3.fromRGB(100, 150, 255))
	barFill.BorderSizePixel = 0
	barFill.ZIndex = 5
	barFill.Parent = barBg
	Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 5)

	local progressLabel = Instance.new("TextLabel")
	progressLabel.Size = UDim2.new(0.55, 0, 0, 14)
	progressLabel.Position = UDim2.new(0, 0, 0, 54)
	progressLabel.BackgroundTransparency = 1
	progressLabel.Text = fmtNum(math.min(progress, quest.goal)) .. " / " .. fmtNum(quest.goal)
	progressLabel.TextColor3 = Color3.fromRGB(180, 175, 200)
	progressLabel.Font = FONT_SUB
	progressLabel.TextSize = 10
	progressLabel.TextXAlignment = Enum.TextXAlignment.Left
	progressLabel.ZIndex = 4
	progressLabel.Parent = row

	-- Reward text
	local rewardParts = {}
	if quest.reward.cash then table.insert(rewardParts, "$" .. fmtNum(quest.reward.cash)) end
	if quest.reward.gems then table.insert(rewardParts, fmtNum(quest.reward.gems) .. " Gems") end
	if quest.reward.spinCredits then table.insert(rewardParts, quest.reward.spinCredits .. " Spins") end

	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Size = UDim2.new(0.35, -10, 0, 16)
	rewardLabel.Position = UDim2.new(0.65, 0, 0, 2)
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.Text = table.concat(rewardParts, " + ")
	rewardLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
	rewardLabel.Font = FONT_SUB
	rewardLabel.TextSize = 11
	rewardLabel.TextXAlignment = Enum.TextXAlignment.Right
	rewardLabel.ZIndex = 4
	rewardLabel.Parent = row

	-- Claim button
	local claimBtn = Instance.new("TextButton")
	claimBtn.Size = UDim2.new(0, 80, 0, 30)
	claimBtn.Position = UDim2.new(1, -6, 1, -6)
	claimBtn.AnchorPoint = Vector2.new(1, 1)
	claimBtn.BorderSizePixel = 0
	claimBtn.AutoButtonColor = false
	claimBtn.ZIndex = 5
	claimBtn.Parent = row
	Instance.new("UICorner", claimBtn).CornerRadius = UDim.new(0, 8)

	if claimed then
		claimBtn.BackgroundColor3 = Color3.fromRGB(50, 45, 65)
		claimBtn.Text = "CLAIMED"
		claimBtn.TextColor3 = Color3.fromRGB(120, 115, 130)
		claimBtn.Font = FONT_SUB
		claimBtn.TextSize = 11
	elseif complete then
		claimBtn.BackgroundColor3 = Color3.fromRGB(60, 200, 90)
		claimBtn.Text = "CLAIM"
		claimBtn.TextColor3 = Color3.new(1, 1, 1)
		claimBtn.Font = FONT
		claimBtn.TextSize = 14

		claimBtn.MouseEnter:Connect(function()
			TweenService:Create(claimBtn, bounceTween, { Size = UDim2.new(0, 88, 0, 34) }):Play()
		end)
		claimBtn.MouseLeave:Connect(function()
			TweenService:Create(claimBtn, bounceTween, { Size = UDim2.new(0, 80, 0, 30) }):Play()
		end)
		claimBtn.MouseButton1Click:Connect(function()
			ClaimQuestReward:FireServer(quest.id)
			claimBtn.Text = "..."
			claimBtn.BackgroundColor3 = Color3.fromRGB(50, 45, 65)
		end)
	else
		claimBtn.BackgroundColor3 = Color3.fromRGB(50, 45, 65)
		claimBtn.Text = "LOCKED"
		claimBtn.TextColor3 = Color3.fromRGB(100, 95, 115)
		claimBtn.Font = FONT_SUB
		claimBtn.TextSize = 11
	end

	return row
end

local function refreshQuests()
	if not scrollFrame then return end
	for _, c in ipairs(scrollFrame:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end

	local list = getQuestList()
	for i, q in ipairs(list) do
		buildQuestRow(q, scrollFrame, i)
	end

	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, #list * 90 + 10)
end

local tabButtons = {}

local function setTab(tab)
	currentTab = tab
	for t, btn in pairs(tabButtons) do
		if t == tab then
			btn.BackgroundColor3 = TAB_COLORS[t] or Color3.fromRGB(100, 150, 255)
			btn.TextColor3 = Color3.new(1, 1, 1)
		else
			btn.BackgroundColor3 = Color3.fromRGB(50, 45, 70)
			btn.TextColor3 = Color3.fromRGB(150, 145, 170)
		end
	end
	refreshQuests()
end

function QuestController.Open()
	if isOpen then QuestController.Close(); return end
	isOpen = true
	if modalFrame then
		overlay.Visible = true
		modalFrame.Visible = true
		refreshQuests()
		UIHelper.ScaleIn(modalFrame, 0.25)
	end
end

function QuestController.Close()
	if not isOpen then return end
	isOpen = false
	if overlay then overlay.Visible = false end
	if modalFrame then UIHelper.ScaleOut(modalFrame, 0.2) end
end

function QuestController.IsOpen()
	return isOpen
end

function QuestController.Init()
	screenGui = UIHelper.CreateScreenGui("QuestGui", 12)
	screenGui.Parent = playerGui

	overlay = Instance.new("Frame")
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 1
	overlay.Visible = false
	overlay.Parent = screenGui

	overlay.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			QuestController.Close()
		end
	end)

	modalFrame = Instance.new("Frame")
	modalFrame.Name = "QuestModal"
	modalFrame.Size = UDim2.new(0, MODAL_W, 0, MODAL_H)
	modalFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	modalFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	modalFrame.BackgroundColor3 = MODAL_BG
	modalFrame.BorderSizePixel = 0
	modalFrame.ZIndex = 2
	modalFrame.Visible = false
	modalFrame.Parent = screenGui
	Instance.new("UICorner", modalFrame).CornerRadius = UDim.new(0, 18)
	UIHelper.SinkInput(modalFrame)

	UIHelper.MakeResponsiveModal(modalFrame, MODAL_W, MODAL_H)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(80, 200, 120)
	stroke.Thickness = 2.5
	stroke.Parent = modalFrame

	-- Title
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 40)
	title.Position = UDim2.new(0, 0, 0, 8)
	title.BackgroundTransparency = 1
	title.Text = "QUESTS"
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Font = FONT
	title.TextSize = 26
	title.ZIndex = 3
	title.Parent = modalFrame

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 32, 0, 32)
	closeBtn.Position = UDim2.new(1, -8, 0, 8)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(220, 55, 55)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = FONT
	closeBtn.TextSize = 16
	closeBtn.BorderSizePixel = 0
	closeBtn.AutoButtonColor = false
	closeBtn.ZIndex = 4
	closeBtn.Parent = modalFrame
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1, 0)
	closeBtn.MouseButton1Click:Connect(function() QuestController.Close() end)

	-- Tabs
	local tabY = 50
	for i, tabName in ipairs({ "Daily", "Weekly", "Lifetime" }) do
		local tab = Instance.new("TextButton")
		tab.Size = UDim2.new(0, 140, 0, 32)
		tab.Position = UDim2.new(0, 16 + (i - 1) * 158, 0, tabY)
		tab.BackgroundColor3 = i == 1 and (TAB_COLORS[tabName] or Color3.fromRGB(100, 150, 255)) or Color3.fromRGB(50, 45, 70)
		tab.Text = tabName
		tab.TextColor3 = i == 1 and Color3.new(1, 1, 1) or Color3.fromRGB(150, 145, 170)
		tab.Font = FONT
		tab.TextSize = 15
		tab.BorderSizePixel = 0
		tab.AutoButtonColor = false
		tab.ZIndex = 3
		tab.Parent = modalFrame
		Instance.new("UICorner", tab).CornerRadius = UDim.new(0, 10)

		tabButtons[tabName] = tab
		tab.MouseButton1Click:Connect(function()
			setTab(tabName)
		end)
	end

	-- Scroll frame
	scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Size = UDim2.new(1, -20, 1, -(tabY + 48))
	scrollFrame.Position = UDim2.new(0, 10, 0, tabY + 42)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 6
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(80, 75, 100)
	scrollFrame.ZIndex = 2
	scrollFrame.Parent = modalFrame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scrollFrame

	-- Listen for quest updates
	QuestUpdate.OnClientEvent:Connect(function(data)
		if data.progress then questData.progress = data.progress end
		if data.claimed then questData.claimed = data.claimed end
		if isOpen then refreshQuests() end
	end)

	-- Wire quest button from left nav
	local OpenQuestGui = RemoteEvents:FindFirstChild("OpenQuestGui")
	if OpenQuestGui then
		OpenQuestGui.OnClientEvent:Connect(function()
			QuestController.Open()
		end)
	end
end

return QuestController
