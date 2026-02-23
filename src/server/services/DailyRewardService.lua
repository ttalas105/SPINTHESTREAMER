--[[
	DailyRewardService.lua
	Handles daily login rewards with a 7-day streak cycle.
	On player join, checks if a new calendar day has passed since last login.
	If so, increments streak (or resets if they missed a day) and grants rewards.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local DailyRewards = require(ReplicatedStorage.Shared.Config.DailyRewards)

local DailyRewardService = {}

local PlayerData
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

local function getCurrentDay()
	return math.floor(os.time() / 86400)
end

local function processLogin(player)
	if not PlayerData then return end
	local data = PlayerData.Get(player)
	if not data then return end

	local today = getCurrentDay()
	local lastDay = data.lastLoginDay or 0
	local streak = data.dailyLoginStreak or 0

	if today == lastDay then
		return
	end

	if today == lastDay + 1 then
		streak = streak + 1
		if streak > DailyRewards.MaxStreak then
			streak = 1
		end
	else
		streak = 1
	end

	data.dailyLoginStreak = streak
	data.lastLoginDay = today

	local reward = DailyRewards.Rewards[streak]
	if not reward then return end

	if reward.cash and reward.cash > 0 then
		PlayerData.AddCash(player, reward.cash)
	end
	if reward.gems and reward.gems > 0 then
		data.gems = (data.gems or 0) + reward.gems
	end
	if reward.spinCredits and reward.spinCredits > 0 then
		data.spinCredits = (data.spinCredits or 0) + reward.spinCredits
	end

	PlayerData.Replicate(player)

	local DailyRewardNotify = RemoteEvents:FindFirstChild("DailyRewardNotify")
	if DailyRewardNotify then
		DailyRewardNotify:FireClient(player, {
			day = streak,
			reward = reward,
		})
	end
end

function DailyRewardService.Init(playerDataModule)
	PlayerData = playerDataModule

	Players.PlayerAdded:Connect(function(player)
		task.delay(3, function()
			PlayerData.WithLock(player, function()
				processLogin(player)
			end)
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			task.delay(3, function()
				PlayerData.WithLock(player, function()
					processLogin(player)
				end)
			end)
		end)
	end
end

return DailyRewardService
