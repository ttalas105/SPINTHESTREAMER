--[[
	DailyRewardController.lua
	Shows a popup when the player receives their daily login reward.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UIHelper = require(script.Parent.UIHelper)

local DailyRewardController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

local FONT = Enum.Font.FredokaOne
local FONT_SUB = Enum.Font.GothamBold

local function fmtNum(n)
	if n >= 1e9 then return string.format("%.1fB", n / 1e9)
	elseif n >= 1e6 then return string.format("%.1fM", n / 1e6)
	elseif n >= 1e3 then return string.format("%.1fK", n / 1e3)
	end
	return tostring(n)
end

local function showRewardPopup(data)
	local day = data.day
	local reward = data.reward
	if not reward then return end

	local sg = Instance.new("ScreenGui")
	sg.Name = "DailyRewardPopup"
	sg.ResetOnSpawn = false
	sg.DisplayOrder = 100
	sg.Parent = playerGui

	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 1
	overlay.Parent = sg

	local modal = Instance.new("Frame")
	modal.Size = UDim2.new(0, 360, 0, 280)
	modal.Position = UDim2.new(0.5, 0, 0.5, 0)
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.BackgroundColor3 = Color3.fromRGB(30, 25, 45)
	modal.BorderSizePixel = 0
	modal.ZIndex = 2
	modal.Parent = sg
	Instance.new("UICorner", modal).CornerRadius = UDim.new(0, 18)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 200, 60)
	stroke.Thickness = 3
	stroke.Parent = modal

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 40)
	title.Position = UDim2.new(0, 0, 0, 12)
	title.BackgroundTransparency = 1
	title.Text = "Daily Login Reward!"
	title.TextColor3 = Color3.fromRGB(255, 220, 80)
	title.Font = FONT
	title.TextSize = 28
	title.ZIndex = 3
	title.Parent = modal

	local dayLabel = Instance.new("TextLabel")
	dayLabel.Size = UDim2.new(1, 0, 0, 30)
	dayLabel.Position = UDim2.new(0, 0, 0, 55)
	dayLabel.BackgroundTransparency = 1
	dayLabel.Text = reward.label or ("Day " .. day)
	dayLabel.TextColor3 = day == 7 and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(200, 200, 220)
	dayLabel.Font = FONT
	dayLabel.TextSize = 22
	dayLabel.ZIndex = 3
	dayLabel.Parent = modal

	local rewardLines = {}
	if reward.cash and reward.cash > 0 then
		table.insert(rewardLines, "$" .. fmtNum(reward.cash) .. " Cash")
	end
	if reward.gems and reward.gems > 0 then
		table.insert(rewardLines, fmtNum(reward.gems) .. " Gems")
	end
	if reward.spinCredits and reward.spinCredits > 0 then
		table.insert(rewardLines, reward.spinCredits .. " Spin Credits")
	end

	local rewardText = Instance.new("TextLabel")
	rewardText.Size = UDim2.new(1, -40, 0, 80)
	rewardText.Position = UDim2.new(0.5, 0, 0, 95)
	rewardText.AnchorPoint = Vector2.new(0.5, 0)
	rewardText.BackgroundTransparency = 1
	rewardText.Text = table.concat(rewardLines, "\n")
	rewardText.TextColor3 = Color3.fromRGB(120, 255, 150)
	rewardText.Font = FONT
	rewardText.TextSize = 20
	rewardText.ZIndex = 3
	rewardText.TextWrapped = true
	rewardText.Parent = modal

	local claimBtn = Instance.new("TextButton")
	claimBtn.Size = UDim2.new(0, 160, 0, 44)
	claimBtn.Position = UDim2.new(0.5, 0, 1, -20)
	claimBtn.AnchorPoint = Vector2.new(0.5, 1)
	claimBtn.BackgroundColor3 = Color3.fromRGB(60, 200, 90)
	claimBtn.Text = "Claim!"
	claimBtn.TextColor3 = Color3.new(1, 1, 1)
	claimBtn.Font = FONT
	claimBtn.TextSize = 20
	claimBtn.BorderSizePixel = 0
	claimBtn.AutoButtonColor = false
	claimBtn.ZIndex = 4
	claimBtn.Parent = modal
	Instance.new("UICorner", claimBtn).CornerRadius = UDim.new(0, 12)

	claimBtn.MouseButton1Click:Connect(function()
		TweenService:Create(modal, TweenInfo.new(0.2), { Size = UDim2.new(0, 0, 0, 0) }):Play()
		TweenService:Create(overlay, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
		task.delay(0.3, function()
			sg:Destroy()
		end)
	end)

	modal.Size = UDim2.new(0, 0, 0, 0)
	TweenService:Create(modal, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
		Size = UDim2.new(0, 360, 0, 280)
	}):Play()
end

function DailyRewardController.Init()
	local DailyRewardNotify = RemoteEvents:WaitForChild("DailyRewardNotify")
	DailyRewardNotify.OnClientEvent:Connect(function(data)
		showRewardPopup(data)
	end)
end

return DailyRewardController
