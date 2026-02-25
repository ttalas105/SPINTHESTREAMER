--[[
	LeaderboardService.lua
	Global leaderboard system using OrderedDataStores.
	Pushes player stats, fetches top 50, and updates the physical SurfaceGui boards.
	Falls back to showing online players when DataStore data is empty/unavailable.
	Also tracks timePlayed for all online players.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LeaderboardService = {}

local PlayerData

local PUSH_INTERVAL   = 30
local FETCH_INTERVAL  = 30
local TIME_TICK       = 10
local MAX_ENTRIES     = 50
local DISPLAY_ROWS    = 10

local CATEGORIES = {
	{ key = "Leaderboard_Spins",      stat = "totalSpins",      dsName = "LB_Spins",      prefix = "",   format = "number" },
	{ key = "Leaderboard_Cash",       stat = "totalCashEarned", dsName = "LB_Cash",        prefix = "$",  format = "cash" },
	{ key = "Leaderboard_TimePlayed", stat = "timePlayed",      dsName = "LB_TimePlayed",  prefix = "",   format = "time" },
	{ key = "Leaderboard_Robux",      stat = "robuxSpent",      dsName = "LB_Robux",       prefix = "R$", format = "number" },
}

local nameCache = {}
local isStudio = RunService:IsStudio()

-------------------------------------------------
-- FORMATTING
-------------------------------------------------

local function commaFormat(n)
	local s = tostring(math.floor(n))
	local formatted = ""
	local len = #s
	for i = 1, len do
		if i > 1 and (len - i + 1) % 3 == 0 then
			formatted = formatted .. ","
		end
		formatted = formatted .. s:sub(i, i)
	end
	return formatted
end

local function abbreviate(n)
	if n >= 1e12 then return string.format("%.1fT", n / 1e12) end
	if n >= 1e9  then return string.format("%.1fB", n / 1e9) end
	if n >= 1e6  then return string.format("%.1fM", n / 1e6) end
	if n >= 1e3  then return string.format("%.1fK", n / 1e3) end
	return tostring(math.floor(n))
end

local function formatTime(seconds)
	local totalMin = math.floor(seconds / 60)
	local h = math.floor(totalMin / 60)
	local m = totalMin % 60
	if h > 0 then
		return h .. "h " .. m .. "m"
	end
	if m > 0 then
		return m .. "m"
	end
	return math.floor(seconds) .. "s"
end

local function formatValue(value, fmt, prefix)
	if fmt == "cash" then
		return prefix .. abbreviate(value)
	elseif fmt == "time" then
		return formatTime(value)
	else
		return prefix .. commaFormat(value)
	end
end

-------------------------------------------------
-- NAME RESOLUTION
-------------------------------------------------

local function getPlayerName(userId)
	if nameCache[userId] then return nameCache[userId] end

	local player = Players:GetPlayerByUserId(userId)
	if player then
		nameCache[userId] = player.DisplayName or player.Name
		return nameCache[userId]
	end

	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and name then
		nameCache[userId] = name
		return name
	end
	return "Player_" .. userId
end

-------------------------------------------------
-- GUI UPDATE
-------------------------------------------------

local function updateBoard(cat, entries)
	local lbFolder = Workspace:FindFirstChild("Leaderboards")
	if not lbFolder then return end
	local boardPart = lbFolder:FindFirstChild(cat.key)
	if not boardPart then return end
	local gui = boardPart:FindFirstChild("LeaderboardGui")
	if not gui then return end
	local container = gui:FindFirstChild("Container")
	if not container then return end
	local scrollFrame = container:FindFirstChild("Entries")
	if not scrollFrame then return end

	for rank = 1, DISPLAY_ROWS do
		local row = scrollFrame:FindFirstChild("Row_" .. rank)
		if not row then continue end

		local nameLabel = row:FindFirstChild("PlayerName")
		local valueLabel = row:FindFirstChild("Value")

		if rank <= #entries then
			local entry = entries[rank]
			local userId = tonumber(entry.key)
			local displayName = userId and getPlayerName(userId) or "???"
			local displayValue = formatValue(entry.value, cat.format, cat.prefix)

			if nameLabel then nameLabel.Text = displayName end
			if valueLabel then valueLabel.Text = displayValue end
		else
			if nameLabel then nameLabel.Text = "---" end
			if valueLabel then valueLabel.Text = "" end
		end
	end
end

-------------------------------------------------
-- LOCAL FALLBACK (show online players' live stats)
-------------------------------------------------

local function buildLocalEntries(cat)
	local entries = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local data = PlayerData and PlayerData.Get(player)
		if data then
			local val = data[cat.stat] or 0
			table.insert(entries, {
				key = tostring(player.UserId),
				value = math.floor(val),
			})
		end
	end
	table.sort(entries, function(a, b) return a.value > b.value end)
	return entries
end

local function refreshLocal()
	for _, cat in ipairs(CATEGORIES) do
		local entries = buildLocalEntries(cat)
		updateBoard(cat, entries)
	end
end

-------------------------------------------------
-- DATA STORE OPERATIONS
-------------------------------------------------

local datastoreAvailable = false

local function pushAllPlayerStats()
	for _, player in ipairs(Players:GetPlayers()) do
		local data = PlayerData and PlayerData.Get(player)
		if data then
			for _, cat in ipairs(CATEGORIES) do
				local value = data[cat.stat] or 0
				if value > 0 then
					local ds = DataStoreService:GetOrderedDataStore(cat.dsName)
					local ok, err = pcall(function()
						ds:SetAsync(tostring(player.UserId), math.floor(value))
					end)
					if not ok then
						warn("[LeaderboardService] Push failed for " .. cat.dsName .. ": " .. tostring(err))
					else
						datastoreAvailable = true
					end
				end
			end
		end
	end
end

local function fetchAndDisplay()
	local anyData = false
	for _, cat in ipairs(CATEGORIES) do
		local ds = DataStoreService:GetOrderedDataStore(cat.dsName)
		local ok, pages = pcall(function()
			return ds:GetSortedAsync(false, MAX_ENTRIES)
		end)
		if ok and pages then
			datastoreAvailable = true
			local ok2, entries = pcall(function()
				return pages:GetCurrentPage()
			end)
			if ok2 and entries and #entries > 0 then
				anyData = true
				updateBoard(cat, entries)
			end
		else
			warn("[LeaderboardService] Fetch failed for " .. cat.dsName)
		end
	end

	if not anyData then
		refreshLocal()
	end
end

-------------------------------------------------
-- TIME PLAYED TRACKING
-------------------------------------------------

local function tickTimePlayed()
	for _, player in ipairs(Players:GetPlayers()) do
		if PlayerData then
			PlayerData.IncrementStat(player, "timePlayed", TIME_TICK)
		end
	end
end

-------------------------------------------------
-- INIT
-------------------------------------------------

function LeaderboardService.Init(playerDataModule)
	PlayerData = playerDataModule

	for _, player in ipairs(Players:GetPlayers()) do
		nameCache[player.UserId] = player.DisplayName or player.Name
	end

	Players.PlayerAdded:Connect(function(player)
		nameCache[player.UserId] = player.DisplayName or player.Name
		task.delay(2, refreshLocal)
	end)
	Players.PlayerRemoving:Connect(function(player)
		task.delay(1, refreshLocal)
	end)

	-- Immediate local display so boards are never empty
	task.delay(3, function()
		refreshLocal()
		print("[LeaderboardService] Initial local board refresh done")
	end)

	-- Push stats loop
	task.spawn(function()
		task.wait(10)
		pcall(pushAllPlayerStats)
		while true do
			task.wait(PUSH_INTERVAL)
			local ok, err = pcall(pushAllPlayerStats)
			if not ok then warn("[LeaderboardService] Push cycle error: " .. tostring(err)) end
		end
	end)

	-- Fetch + display loop
	task.spawn(function()
		task.wait(15)
		while true do
			local ok, err = pcall(fetchAndDisplay)
			if not ok then warn("[LeaderboardService] Fetch cycle error: " .. tostring(err)) end
			task.wait(FETCH_INTERVAL)
		end
	end)

	-- Time played tick (every 10 seconds)
	task.spawn(function()
		while true do
			task.wait(TIME_TICK)
			local ok, err = pcall(tickTimePlayed)
			if not ok then warn("[LeaderboardService] Time tick error: " .. tostring(err)) end
		end
	end)

	-- Periodic local refresh (every 5s) to keep boards up to date with live data
	task.spawn(function()
		while true do
			task.wait(5)
			if not datastoreAvailable then
				pcall(refreshLocal)
			end
		end
	end)

	print("[Server] LeaderboardService initialized (4 categories, top " .. MAX_ENTRIES .. ")")
end

return LeaderboardService
