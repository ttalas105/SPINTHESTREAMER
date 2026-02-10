--[[
	Server Entry Point — Spin the Streamer
	Initializes all server services in the correct order,
	builds the world, and sets up per-player bases.
]]

local services = script.Parent.services

-- Services
local PlayerData     = require(services.PlayerData)
local SpinService    = require(services.SpinService)
local EconomyService = require(services.EconomyService)
local RebirthService = require(services.RebirthService)
local StoreService   = require(services.StoreService)
local WorldBuilder   = require(services.WorldBuilder)
local BaseService    = require(services.BaseService)

-- Build the shared world (hub, stalls, decorations)
WorldBuilder.Build()

-- Initialize services (order matters: PlayerData first, then BaseService)
PlayerData.Init()
BaseService.Init(PlayerData)
SpinService.Init(PlayerData, BaseService)
EconomyService.Init(PlayerData)
RebirthService.Init(PlayerData, BaseService)
StoreService.Init(PlayerData, SpinService)

print("[Server] Spin the Streamer initialized! Map size: 400x1000 studs, 16 base slots")
