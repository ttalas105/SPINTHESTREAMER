--[[
	HoldService.lua
	Tracks which streamer each player is holding and broadcasts updates to all
	clients so every player can see what others are flexing.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Streamers = require(ReplicatedStorage.Shared.Config.Streamers)
local Effects = require(ReplicatedStorage.Shared.Config.Effects)

local HoldService = {}

local heldState = {}     -- [userId] = { id = string, effect = string? }
local lastUpdateTime = {} -- [userId] = os.clock() (rate limiting)

local RATE_LIMIT = 0.15

local HoldUpdate -- client -> server
local HoldSync   -- server -> client

function HoldService.Init()
	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	HoldUpdate = RemoteEvents:WaitForChild("HoldUpdate")
	HoldSync = RemoteEvents:WaitForChild("HoldSync")

	HoldUpdate.OnServerEvent:Connect(function(player, data)
		local userId = player.UserId

		if data == "init" then
			for uid, state in pairs(heldState) do
				if uid ~= userId then
					HoldSync:FireClient(player, uid, state)
				end
			end
			return
		end

		local now = os.clock()
		if lastUpdateTime[userId] and (now - lastUpdateTime[userId]) < RATE_LIMIT then
			return
		end
		lastUpdateTime[userId] = now

		if data == nil then
			heldState[userId] = nil
		elseif type(data) == "table" and type(data.id) == "string" then
			if not Streamers.ById[data.id] then return end
			if data.effect and not Effects.ByName[data.effect] then return end
			heldState[userId] = { id = data.id, effect = data.effect }
		else
			return
		end

		for _, otherPlayer in ipairs(Players:GetPlayers()) do
			if otherPlayer ~= player then
				HoldSync:FireClient(otherPlayer, userId, heldState[userId])
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(leavingPlayer)
		local userId = leavingPlayer.UserId
		heldState[userId] = nil
		lastUpdateTime[userId] = nil
		for _, otherPlayer in ipairs(Players:GetPlayers()) do
			if otherPlayer ~= leavingPlayer then
				HoldSync:FireClient(otherPlayer, userId, nil)
			end
		end
	end)
end

return HoldService
