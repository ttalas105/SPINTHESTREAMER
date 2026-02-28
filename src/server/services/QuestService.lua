--[[
	QuestService.lua
	Tracks quest progress server-side.
	Daily quests reset every 24h, weekly every 7 days.
	Lifetime quests are permanent.
	Other services call QuestService.Increment(player, type, amount)
	to advance quest progress. The service checks completion and
	fires QuestUpdate to the client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Quests = require(ReplicatedStorage.Shared.Config.Quests)

local QuestService = {}

local PlayerData
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

local function getCurrentDay()
	return math.floor(os.time() / 86400)
end

local function getCurrentWeek()
	return math.floor(os.time() / (86400 * 7))
end

local function ensureQuestData(data)
	if not data.questProgress then data.questProgress = {} end
	if not data.questClaimed then data.questClaimed = {} end
	if not data.questResetDay then data.questResetDay = 0 end
	if not data.questResetWeek then data.questResetWeek = 0 end
end

local function resetIfNeeded(data)
	ensureQuestData(data)
	local today = getCurrentDay()
	local thisWeek = getCurrentWeek()
	local changed = false

	if data.questResetDay ~= today then
		for _, q in ipairs(Quests.Daily) do
			data.questProgress[q.id] = 0
			data.questClaimed[q.id] = nil
		end
		data.questResetDay = today
		changed = true
	end

	if data.questResetWeek ~= thisWeek then
		for _, q in ipairs(Quests.Weekly) do
			data.questProgress[q.id] = 0
			data.questClaimed[q.id] = nil
		end
		data.questResetWeek = thisWeek
		changed = true
	end

	return changed
end

local function syncLifetimeProgress(data)
	ensureQuestData(data)

	local rebirthCount = data.rebirthCount or 0

	local indexCounts = {}
	if data.indexCollection then
		for key, val in pairs(data.indexCollection) do
			if val == "claimed" then
				local colon = string.find(key, ":")
				local effectKey = colon and string.sub(key, 1, colon - 1) or "Default"
				indexCounts[effectKey] = (indexCounts[effectKey] or 0) + 1
			end
		end
	end

	for _, q in ipairs(Quests.Lifetime) do
		if q.type == "rebirths" then
			local actual = math.min(rebirthCount, q.goal)
			local current = data.questProgress[q.id] or 0
			if actual > current then
				data.questProgress[q.id] = actual
			end
		end

		local PREFIX = "index"
		if string.sub(q.type, 1, #PREFIX) == PREFIX then
			local effectKey = string.sub(q.type, #PREFIX + 1)
			local count = indexCounts[effectKey] or 0
			local actual = math.min(count, q.goal)
			local current = data.questProgress[q.id] or 0
			if actual > current then
				data.questProgress[q.id] = actual
			end
		end
	end
end

local function sendQuestUpdate(player, data)
	ensureQuestData(data)
	local QuestUpdate = RemoteEvents:FindFirstChild("QuestUpdate")
	if QuestUpdate then
		QuestUpdate:FireClient(player, {
			progress = data.questProgress,
			claimed = data.questClaimed,
		})
	end
end

function QuestService.Increment(player, questType, amount)
	if not PlayerData then return end
	local data = PlayerData.Get(player)
	if not data then return end

	ensureQuestData(data)
	resetIfNeeded(data)

	amount = amount or 1
	local anyChanged = false

	local function checkList(list)
		for _, q in ipairs(list) do
			if q.type == questType then
				local prev = data.questProgress[q.id] or 0
				if prev < q.goal then
					data.questProgress[q.id] = math.min(prev + amount, q.goal)
					anyChanged = true
				end
			end
		end
	end

	checkList(Quests.Daily)
	checkList(Quests.Weekly)
	checkList(Quests.Lifetime)

	if anyChanged then
		sendQuestUpdate(player, data)
	end
end

local function handleClaimQuest(player, questId)
	if not PlayerData then return end
	if type(questId) ~= "string" then return end

	local data = PlayerData.Get(player)
	if not data then return end

	ensureQuestData(data)
	resetIfNeeded(data)

	local quest = Quests.ById[questId]
	if not quest then return end

	if data.questClaimed[questId] then return end

	local progress = data.questProgress[questId] or 0
	if progress < quest.goal then return end

	data.questClaimed[questId] = true

	local reward = quest.reward
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
	sendQuestUpdate(player, data)
end

function QuestService.Init(playerDataModule)
	PlayerData = playerDataModule

	local ClaimQuestReward = RemoteEvents:WaitForChild("ClaimQuestReward")
	ClaimQuestReward.OnServerEvent:Connect(function(player, questId)
		PlayerData.WithLock(player, function()
			handleClaimQuest(player, questId)
		end)
	end)

	local function onPlayerReady(player)
		PlayerData.WithLock(player, function()
			local data = PlayerData.Get(player)
			if data then
				resetIfNeeded(data)
				syncLifetimeProgress(data)
				sendQuestUpdate(player, data)
			end
		end)

		QuestService.Increment(player, "logins", 1)
	end

	Players.PlayerAdded:Connect(function(player)
		task.delay(4, function()
			onPlayerReady(player)
		end)
	end)

	for _, existingPlayer in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			task.delay(4, function()
				onPlayerReady(existingPlayer)
			end)
		end)
	end
end

return QuestService
