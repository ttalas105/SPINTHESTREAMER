--[[
	Server Entry Point — Spin the Streamer
	Initializes all server services in the correct order,
	builds the world, and binds RemoteEvents.
]]

-- script = ServerScriptService.Main
-- script.Parent = ServerScriptService
local services = script.Parent.services

-- Services
local PlayerData     = require(services.PlayerData)
local SpinService    = require(services.SpinService)
local EconomyService = require(services.EconomyService)
local RebirthService = require(services.RebirthService)
local StoreService   = require(services.StoreService)
local WorldBuilder   = require(services.WorldBuilder)

-- Build the world (hub, stalls, lanes, decorations)
WorldBuilder.Build()

-- Initialize services (order matters: PlayerData first)
PlayerData.Init()
SpinService.Init(PlayerData)
EconomyService.Init(PlayerData)
RebirthService.Init(PlayerData)
StoreService.Init(PlayerData, SpinService)

print("[Server] Spin the Streamer initialized!")
