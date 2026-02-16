--[[
	MusicController.lua
	Manages two audio tracks:
	  • "Chill Zone Here" — permanent lobby loop, pauses/resumes when sacrifice opens/closes
	  • "SJ_1"            — sacrifice-menu music, restarts each open, loops while menu is open

	Sounds can live in SoundService OR Workspace (searches both).
	Settings toggles can mute each channel independently.
]]

local SoundService = game:GetService("SoundService")

local MusicController = {}

local lobbySound: Sound? = nil
local sacrificeSound: Sound? = nil

local lobbyMuted = false
local sacrificeMuted = false

local function findSound(name: string): Sound?
	local s = SoundService:FindFirstChild(name)
	if s then return s end
	s = workspace:FindFirstChild(name)
	if s then return s end
	return nil
end

-------------------------------------------------
-- INIT — find Sound objects from SoundService or Workspace
-------------------------------------------------

function MusicController.Init()
	lobbySound = findSound("Chill Zone Here")
	sacrificeSound = findSound("SJ_1")

	if lobbySound then
		lobbySound.Looped = true
		lobbySound.Volume = lobbyMuted and 0 or 0.45
		lobbySound:Play()
	else
		warn("[MusicController] Could not find 'Chill Zone Here' in SoundService or Workspace")
	end

	if sacrificeSound then
		sacrificeSound.Looped = true
		sacrificeSound.Volume = sacrificeMuted and 0 or 0.45
		sacrificeSound:Stop()
	else
		warn("[MusicController] Could not find 'SJ_1' in SoundService or Workspace")
	end
end

-------------------------------------------------
-- SACRIFICE OPEN — pause lobby, start sacrifice music from beginning
-------------------------------------------------

function MusicController.OnSacrificeOpen()
	if lobbySound and lobbySound.IsPlaying then
		lobbySound:Pause()
	end
	if sacrificeSound then
		sacrificeSound.TimePosition = 0
		sacrificeSound.Volume = sacrificeMuted and 0 or 0.45
		sacrificeSound:Play()
	end
end

-------------------------------------------------
-- SACRIFICE CLOSE — stop sacrifice music, resume lobby
-------------------------------------------------

function MusicController.OnSacrificeClose()
	if sacrificeSound then
		sacrificeSound:Stop()
	end
	if lobbySound then
		lobbySound.Volume = lobbyMuted and 0 or 0.45
		lobbySound:Resume()
	end
end

-------------------------------------------------
-- SETTINGS TOGGLES
-------------------------------------------------

function MusicController.SetLobbyMuted(muted: boolean)
	lobbyMuted = muted
	if lobbySound then
		lobbySound.Volume = muted and 0 or 0.45
	end
end

function MusicController.SetSacrificeMuted(muted: boolean)
	sacrificeMuted = muted
	if sacrificeSound then
		sacrificeSound.Volume = muted and 0 or 0.45
	end
end

function MusicController.IsLobbyMuted(): boolean
	return lobbyMuted
end

function MusicController.IsSacrificeMuted(): boolean
	return sacrificeMuted
end

return MusicController
