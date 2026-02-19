--[[
	BaseService.lua
	Manages per-player bases: 8 bases total (4 per side of the speed pads).
	Base structures are placed by WorldBuilder; this service adds
	player name signs, pad grids, ProximityPrompts, display models,
	key accumulation, collection pads, and handles equip/unequip.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local SlotsConfig = require(ReplicatedStorage.Shared.Config.SlotsConfig)
local Streamers = require(ReplicatedStorage.Shared.Config.Streamers)
local Effects = require(ReplicatedStorage.Shared.Config.Effects)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local BaseReady = RemoteEvents:WaitForChild("BaseReady")
local EquipRequest = RemoteEvents:WaitForChild("EquipRequest")
local EquipResult = RemoteEvents:WaitForChild("EquipResult")
local UnequipRequest = RemoteEvents:WaitForChild("UnequipRequest")
local UnequipResult = RemoteEvents:WaitForChild("UnequipResult")
local DisplayInteract = RemoteEvents:WaitForChild("DisplayInteract")
local CollectKeysResult = RemoteEvents:WaitForChild("CollectKeysResult")

local BaseService = {}

BaseService._bases = {}          -- userId -> { position, model, slotIndex }
BaseService._occupiedSlots = {}  -- set of occupied slot indices
BaseService._pendingKeys = {}    -- userId -> { ["padSlot"] = accumulatedAmount }
BaseService._displayModels = {}  -- userId -> { ["padSlot"] = Model }
BaseService._collectDebounce = {}

local PlayerData
local PotionService

-------------------------------------------------
-- POSITION CALCULATION — 8 fixed positions
-------------------------------------------------

local BASE_POSITIONS = DesignConfig.BasePositions

local function findAvailableSlot(): number
	for i = 1, #BASE_POSITIONS do
		if not BaseService._occupiedSlots[i] then
			return i
		end
	end
	return nil
end

-------------------------------------------------
-- HELPERS
-------------------------------------------------

local function formatNumber(n)
	local s = tostring(math.floor(n))
	local formatted = ""
	local len = #s
	for i = 1, len do
		formatted = formatted .. string.sub(s, i, i)
		if (len - i) % 3 == 0 and i < len then
			formatted = formatted .. ","
		end
	end
	return formatted
end

local function createPart(props)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = props.CanCollide ~= false
	part.Size = props.Size or Vector3.new(4, 1, 4)
	part.Position = props.Position or Vector3.new(0, 0, 0)
	part.Color = props.Color or Color3.fromRGB(200, 200, 200)
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Name = props.Name or "Part"
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if props.Transparency then part.Transparency = props.Transparency end
	if props.Reflectance then part.Reflectance = props.Reflectance end
	part.Parent = props.Parent or Workspace
	return part
end

-------------------------------------------------
-- DISPLAY MODEL MANAGEMENT
-------------------------------------------------

local function cleanDisplayModel(model)
	local toDestroy = {}
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("Script") or desc:IsA("LocalScript") or desc:IsA("ModuleScript")
			or desc:IsA("BillboardGui") or desc:IsA("SurfaceGui")
			or desc:IsA("ClickDetector") or desc:IsA("ProximityPrompt")
			or desc:IsA("Sound") then
			table.insert(toDestroy, desc)
		end
	end
	for _, obj in ipairs(toDestroy) do
		pcall(function() obj:Destroy() end)
	end

	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.PlatformStand = true
		hum.BreakJointsOnDeath = false
		local animator = hum:FindFirstChildOfClass("Animator")
		if animator then animator:Destroy() end
	end

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Massless = true
		end
	end
end

local function placeDisplayModel(player, padSlot, streamerItem)
	local baseInfo = BaseService._bases[player.UserId]
	if not baseInfo then return end

	local model = baseInfo.model
	local padsFolder = model:FindFirstChild("Pads")
	if not padsFolder then return end

	local pad = padsFolder:FindFirstChild("Pad_" .. padSlot)
	if not pad then return end

	local streamerId = type(streamerItem) == "table" and streamerItem.id or streamerItem
	local modelsFolder = ReplicatedStorage:FindFirstChild("StreamerModels")
	if not modelsFolder then return end

	local modelTemplate = modelsFolder:FindFirstChild(streamerId)
	if not modelTemplate then return end

	local clone = modelTemplate:Clone()
	clone.Name = "DisplayModel_" .. padSlot
	cleanDisplayModel(clone)

	local primaryPart = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
	if not primaryPart then
		clone:Destroy()
		return
	end
	clone.PrimaryPart = primaryPart

	local TARGET_HEIGHT = 5.5
	local ok, _, size = pcall(function() return clone:GetBoundingBox() end)
	if ok and size and size.Y > 0 then
		clone:ScaleTo(TARGET_HEIGHT / size.Y)
	end

	local displayY = pad.Position.Y + pad.Size.Y / 2 + TARGET_HEIGHT / 2 + 0.3
	clone:PivotTo(CFrame.new(pad.Position.X, displayY, pad.Position.Z))
	clone.Parent = pad

	if not BaseService._displayModels[player.UserId] then
		BaseService._displayModels[player.UserId] = {}
	end
	BaseService._displayModels[player.UserId][tostring(padSlot)] = clone
end

local function removeDisplayModel(player, padSlot)
	local models = BaseService._displayModels[player.UserId]
	if not models then return end
	local key = tostring(padSlot)
	if models[key] then
		pcall(function() models[key]:Destroy() end)
		models[key] = nil
	end
end

local function clearAllDisplayModels(player)
	local models = BaseService._displayModels[player.UserId]
	if not models then return end
	for _, m in pairs(models) do
		pcall(function() m:Destroy() end)
	end
	BaseService._displayModels[player.UserId] = nil
end

-------------------------------------------------
-- BUILD BASE
-------------------------------------------------

local function buildBase(player, slotIndex)
	local slotInfo = BASE_POSITIONS[slotIndex]
	local basePosition = slotInfo.position
	local rotation = slotInfo.rotation or 0

	local model = Instance.new("Model")
	model.Name = "Base_" .. player.UserId

	-- PLAYER NAME
	local signAnchor = createPart({
		Name = "NameSign",
		Size = Vector3.new(1, 1, 1),
		Position = basePosition + Vector3.new(0, 40, 0),
		Transparency = 1,
		CanCollide = false,
		Parent = model,
	})

	local bb = Instance.new("BillboardGui")
	bb.Name = "NameGui"
	bb.Size = UDim2.new(0, 400, 0, 80)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 200
	bb.Parent = signAnchor

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.Text = player.Name .. "'s Base"
	nameLabel.Parent = bb

	-- PAD GRID
	local padsFolder = Instance.new("Folder")
	padsFolder.Name = "Pads"
	padsFolder.Parent = model

	local cfg = DesignConfig.Base
	local gridWidth = (cfg.PadCols - 1) * cfg.PadSpacing
	local gridDepth = (cfg.PadRows - 1) * cfg.PadSpacing
	local gridStartX = basePosition.X - gridWidth / 2
	local gridStartZ = basePosition.Z - gridDepth / 2

	local colOrder = {}
	if rotation > 0 then
		for c = cfg.PadCols - 1, 0, -1 do table.insert(colOrder, c) end
	else
		for c = 0, cfg.PadCols - 1 do table.insert(colOrder, c) end
	end

	local data = PlayerData.Get(player)
	local totalSlots = data and SlotsConfig.GetTotalSlots(data.rebirthCount, data.premiumSlotUnlocked) or SlotsConfig.StartingSlots

	-- Direction toward entrance (for orienting display sections)
	local entranceDir = rotation > 0 and Vector3.new(1, 0, 0) or Vector3.new(-1, 0, 0)

	local padIndex = 0
	for _, col in ipairs(colOrder) do
		for row = 0, cfg.PadRows - 1 do
			padIndex = padIndex + 1

			local padX = gridStartX + col * cfg.PadSpacing
			local padZ = gridStartZ + row * cfg.PadSpacing
			local sectionCenter = Vector3.new(padX, basePosition.Y + 0.5, padZ)

			local isUnlocked = padIndex <= totalSlots
			local isPremium = padIndex == SlotsConfig.PremiumSlotIndex
			local isStarter = padIndex <= SlotsConfig.StartingSlots

			local padColor
			if isUnlocked then
				if isPremium then
					padColor = DesignConfig.Colors.PadPremium
				elseif isStarter then
					padColor = DesignConfig.Colors.PadStarter
				else
					padColor = DesignConfig.Colors.PadUnlocked
				end
			else
				padColor = Color3.fromRGB(180, 50, 50)
			end

			-- Section frame (dark base plate that unifies the display area)
			createPart({
				Name = "SectionBase_" .. padIndex,
				Size = Vector3.new(8.5, 0.15, 7),
				Position = sectionCenter,
				Color = Color3.fromRGB(30, 30, 40),
				Material = Enum.Material.SmoothPlastic,
				Parent = padsFolder,
			})

			-- Display pad (raised pedestal in the back half of the section)
			local displayPos = sectionCenter + (-entranceDir * 2.0) + Vector3.new(0, 0.45, 0)
			local pad = createPart({
				Name = "Pad_" .. padIndex,
				Size = Vector3.new(5, 0.9, 6),
				Position = displayPos,
				Color = padColor,
				Material = Enum.Material.SmoothPlastic,
				Parent = padsFolder,
			})

			-- Display border (subtle raised edge)
			createPart({
				Name = "PadBorder",
				Size = Vector3.new(5.5, 0.7, 6.5),
				Position = displayPos - Vector3.new(0, 0.15, 0),
				Color = isUnlocked and Color3.fromRGB(50, 50, 60) or Color3.fromRGB(100, 30, 30),
				Material = Enum.Material.SmoothPlastic,
				Parent = pad,
			})

			if isUnlocked then
				-- ProximityPrompt
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "DisplayPrompt"
				prompt.KeyboardKeyCode = Enum.KeyCode.E
				prompt.MaxActivationDistance = 8
				prompt.HoldDuration = 0
				prompt.RequiresLineOfSight = false
				prompt.ActionText = "Place Streamer"
				prompt.ObjectText = "Display " .. padIndex
				prompt.Parent = pad

				-- Floating billboard above the display
				local displayBB = Instance.new("BillboardGui")
				displayBB.Name = "DisplayInfo"
				displayBB.Size = UDim2.new(0, 220, 0, 70)
				displayBB.StudsOffset = Vector3.new(0, 7, 0)
				displayBB.AlwaysOnTop = false
				displayBB.MaxDistance = 50
				displayBB.Parent = pad

				local statusLabel = Instance.new("TextLabel")
				statusLabel.Name = "StatusLabel"
				statusLabel.Size = UDim2.new(1, 0, 1, 0)
				statusLabel.BackgroundTransparency = 1
				statusLabel.Font = Enum.Font.FredokaOne
				statusLabel.TextScaled = true
				statusLabel.TextWrapped = true
				statusLabel.Text = "Empty Display"
				statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
				statusLabel.Parent = displayBB

				local stroke = Instance.new("UIStroke")
				stroke.Color = Color3.fromRGB(0, 0, 0)
				stroke.Thickness = 2
				stroke.Parent = statusLabel

				-- Green collection pad (front of section, toward entrance)
				local collectPos = sectionCenter + (entranceDir * 3.0) + Vector3.new(0, 0.15, 0)
				local collectionPad = createPart({
					Name = "CollectPad_" .. padIndex,
					Size = Vector3.new(2.5, 0.3, 6),
					Position = collectPos,
					Color = Color3.fromRGB(50, 200, 80),
					Material = Enum.Material.Neon,
					CanCollide = true,
					Parent = padsFolder,
				})

				collectionPad.Touched:Connect(function(hit)
					local char = hit.Parent
					if not char then return end
					local hum = char:FindFirstChildOfClass("Humanoid")
					if not hum then return end
					local touchPlayer = Players:GetPlayerFromCharacter(char)
					if not touchPlayer or touchPlayer.UserId ~= player.UserId then return end
					BaseService._collectKeysForPad(touchPlayer, padIndex)
				end)
			else
				-- Locked: flat lock icon on the pad surface
				local lockGui = Instance.new("SurfaceGui")
				lockGui.Name = "LockGui"
				lockGui.Face = Enum.NormalId.Top
				lockGui.Parent = pad

				local lockLabel = Instance.new("TextLabel")
				lockLabel.Name = "LockLabel"
				lockLabel.Size = UDim2.new(1, 0, 1, 0)
				lockLabel.BackgroundTransparency = 1
				lockLabel.Font = Enum.Font.FredokaOne
				lockLabel.TextScaled = true
				lockLabel.Text = "🔒"
				lockLabel.TextColor3 = Color3.fromRGB(200, 60, 60)
				lockLabel.Rotation = rotation > 0 and -90 or 90
				lockLabel.Parent = lockGui
			end
		end
	end

	-- Parent to player-specific folder
	local basesFolder = Workspace:FindFirstChild("PlayerBaseData")
	if not basesFolder then
		basesFolder = Instance.new("Folder")
		basesFolder.Name = "PlayerBaseData"
		basesFolder.Parent = Workspace
	end
	model.Parent = basesFolder

	-- Initialize pending keys
	BaseService._pendingKeys[player.UserId] = {}

	-- Place display models for any already-equipped streamers
	if data and data.equippedPads then
		for padKey, item in pairs(data.equippedPads) do
			local slot = tonumber(padKey)
			if slot then
				placeDisplayModel(player, slot, item)
			end
		end
	end

	print("[BaseService] Assigned " .. player.Name .. " to base slot " .. slotIndex)
	return model, basePosition
end

-------------------------------------------------
-- KEY COLLECTION
-------------------------------------------------

function BaseService._collectKeysForPad(player, padSlot)
	local userId = player.UserId
	local debounceKey = userId .. "_" .. padSlot
	if BaseService._collectDebounce[debounceKey] then return end
	BaseService._collectDebounce[debounceKey] = true

	local pending = BaseService._pendingKeys[userId]
	if not pending then
		BaseService._collectDebounce[debounceKey] = nil
		return
	end

	local padKey = tostring(padSlot)
	local amount = pending[padKey] or 0

	if amount > 0 then
		local collected = math.floor(amount)
		pending[padKey] = 0
		PlayerData.AddCash(player, collected)
		CollectKeysResult:FireClient(player, { success = true, amount = collected, padSlot = padSlot })
	end

	task.delay(0.3, function()
		BaseService._collectDebounce[debounceKey] = nil
	end)
end

-------------------------------------------------
-- UPDATE PAD VISUALS + BILLBOARDS
-------------------------------------------------

function BaseService.UpdateBasePads(player)
	if not PlayerData then return end
	local baseInfo = BaseService._bases[player.UserId]
	if not baseInfo then return end

	local data = PlayerData.Get(player)
	if not data then return end

	local model = baseInfo.model
	local padsFolder = model:FindFirstChild("Pads")
	if not padsFolder then return end

	local slotInfo = BASE_POSITIONS[baseInfo.slotIndex]
	local rotation = slotInfo and slotInfo.rotation or 0
	local cfg = DesignConfig.Base
	local totalSlots = SlotsConfig.GetTotalSlots(data.rebirthCount, data.premiumSlotUnlocked)
	local pending = BaseService._pendingKeys[player.UserId] or {}

	for _, pad in ipairs(padsFolder:GetChildren()) do
		if not (pad:IsA("BasePart") and pad.Name:match("^Pad_")) then continue end

		local idx = tonumber(pad.Name:match("Pad_(%d+)"))
		if not idx then continue end

		local isUnlocked = idx <= totalSlots
		local isPremium = idx == SlotsConfig.PremiumSlotIndex
		local isStarter = idx <= SlotsConfig.StartingSlots
		local equippedItem = data.equippedPads[tostring(idx)]

		-- Update pad color
		if isUnlocked then
			if isPremium then
				pad.Color = DesignConfig.Colors.PadPremium
			elseif isStarter then
				pad.Color = DesignConfig.Colors.PadStarter
			else
				pad.Color = DesignConfig.Colors.PadUnlocked
			end
		else
			pad.Color = Color3.fromRGB(180, 50, 50)
		end

		-- Update ProximityPrompt
		local prompt = pad:FindFirstChild("DisplayPrompt")
		if prompt and isUnlocked then
			if equippedItem then
				prompt.ActionText = "Remove"
				prompt.ObjectText = "Display " .. idx
			else
				prompt.ActionText = "Place Streamer"
				prompt.ObjectText = "Display " .. idx
			end
		end

		-- Update billboard (only exists on unlocked pads)
		local displayBB = pad:FindFirstChild("DisplayInfo")
		if displayBB then
			local statusLabel = displayBB:FindFirstChild("StatusLabel")
			if statusLabel then
				if equippedItem then
					local streamerId = type(equippedItem) == "table" and equippedItem.id or equippedItem
					local info = Streamers.ById[streamerId]
					local name = info and info.displayName or streamerId
					local keys = pending[tostring(idx)] or 0
					statusLabel.Text = name .. "\nTotal Money: $" .. formatNumber(keys)
					statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
				else
					statusLabel.Text = "Empty Display"
					statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
				end
			end
		end

		-- Newly unlocked pad (was locked, now unlocked after rebirth)
		if isUnlocked and not prompt then
			local entranceDir = rotation > 0 and Vector3.new(1, 0, 0) or Vector3.new(-1, 0, 0)

			-- Remove SurfaceGui lock icon
			local lockGui = pad:FindFirstChild("LockGui")
			if lockGui then lockGui:Destroy() end

			-- Update pad and border colors
			pad.Color = isStarter and DesignConfig.Colors.PadStarter or DesignConfig.Colors.PadUnlocked
			local border = pad:FindFirstChild("PadBorder")
			if border then border.Color = Color3.fromRGB(50, 50, 60) end

			-- Create ProximityPrompt
			local newPrompt = Instance.new("ProximityPrompt")
			newPrompt.Name = "DisplayPrompt"
			newPrompt.KeyboardKeyCode = Enum.KeyCode.E
			newPrompt.MaxActivationDistance = 8
			newPrompt.HoldDuration = 0
			newPrompt.RequiresLineOfSight = false
			newPrompt.ActionText = "Place Streamer"
			newPrompt.ObjectText = "Display " .. idx
			newPrompt.Parent = pad

			-- Create floating billboard
			local newBB = Instance.new("BillboardGui")
			newBB.Name = "DisplayInfo"
			newBB.Size = UDim2.new(0, 220, 0, 70)
			newBB.StudsOffset = Vector3.new(0, 7, 0)
			newBB.AlwaysOnTop = false
			newBB.MaxDistance = 50
			newBB.Parent = pad

			local newStatus = Instance.new("TextLabel")
			newStatus.Name = "StatusLabel"
			newStatus.Size = UDim2.new(1, 0, 1, 0)
			newStatus.BackgroundTransparency = 1
			newStatus.Font = Enum.Font.FredokaOne
			newStatus.TextScaled = true
			newStatus.TextWrapped = true
			newStatus.Text = "Empty Display"
			newStatus.TextColor3 = Color3.fromRGB(150, 150, 150)
			newStatus.Parent = newBB

			local newStroke = Instance.new("UIStroke")
			newStroke.Color = Color3.fromRGB(0, 0, 0)
			newStroke.Thickness = 2
			newStroke.Parent = newStatus

			-- Create green collection pad (toward entrance from pad)
			local existingCollect = padsFolder:FindFirstChild("CollectPad_" .. idx)
			if not existingCollect then
				local collectPos = pad.Position + (entranceDir * 5.0) + Vector3.new(0, -0.3, 0)
				local newCollect = createPart({
					Name = "CollectPad_" .. idx,
					Size = Vector3.new(2.5, 0.3, 6),
					Position = collectPos,
					Color = Color3.fromRGB(50, 200, 80),
					Material = Enum.Material.Neon,
					CanCollide = true,
					Parent = padsFolder,
				})

				newCollect.Touched:Connect(function(hit)
					local char = hit.Parent
					if not char then return end
					local hum = char:FindFirstChildOfClass("Humanoid")
					if not hum then return end
					local touchPlayer = Players:GetPlayerFromCharacter(char)
					if not touchPlayer or touchPlayer.UserId ~= player.UserId then return end
					BaseService._collectKeysForPad(touchPlayer, idx)
				end)
			end (feat: add billboard displays above base pads showing streamer name, rarity color, and effect prefix)
		end
	end
end

-------------------------------------------------
-- KEY ACCUMULATION LOOP
-------------------------------------------------

local function startKeyAccumulation()
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in ipairs(Players:GetPlayers()) do
				local data = PlayerData.Get(player)
				if not data then continue end
				local userId = player.UserId

				if not BaseService._pendingKeys[userId] then
					BaseService._pendingKeys[userId] = {}
				end

				local hasEquipped = false
				for padKey, item in pairs(data.equippedPads) do
					local streamerId = type(item) == "table" and item.id or item
					local effect = type(item) == "table" and item.effect or nil
					local info = Streamers.ById[streamerId]
					if info and info.cashPerSecond then
						local income = info.cashPerSecond

						if effect then
							local effectInfo = Effects.ByName[effect]
							if effectInfo and effectInfo.cashMultiplier then
								income = income * effectInfo.cashMultiplier
							end
						end

						local rebirthMult = Economy.GetRebirthCoinMultiplier(data.rebirthCount or 0)
						income = income * rebirthMult

						local cashUpgradeMult = PlayerData.GetCashUpgradeMultiplier(player)
						income = income * cashUpgradeMult

						if PlayerData.HasDoubleCash(player) then
							income = income * Economy.DoubleCashMultiplier
						end

						local potionCashMult = PotionService and PotionService.GetCashMultiplier(player) or 1
						income = income * potionCashMult

						local pending = BaseService._pendingKeys[userId]
						pending[padKey] = (pending[padKey] or 0) + math.floor(income)
						hasEquipped = true
					end
				end

				if hasEquipped then
					BaseService.UpdateBasePads(player)
				end
			end
		end
	end)
end

-------------------------------------------------
-- PUBLIC
-------------------------------------------------

function BaseService.Init(playerDataModule, potionServiceModule)
	PlayerData = playerDataModule
	PotionService = potionServiceModule

	Players.PlayerAdded:Connect(function(player)
		task.wait(1)

		local slot = findAvailableSlot()
		if not slot then
			warn("[BaseService] Server full (8 max), no slot for " .. player.Name)
			return
		end

		BaseService._occupiedSlots[slot] = true
		local model, position = buildBase(player, slot)

		BaseService._bases[player.UserId] = {
			position = position,
			model = model,
			slotIndex = slot,
		}

		BaseService.UpdateBasePads(player)

		BaseReady:FireClient(player, {
			position = position,
			floorSize = DesignConfig.Base.FloorSize,
		})
	end)

	Players.PlayerRemoving:Connect(function(player)
		local baseInfo = BaseService._bases[player.UserId]
		if baseInfo then
			BaseService._occupiedSlots[baseInfo.slotIndex] = nil
			clearAllDisplayModels(player)
			if baseInfo.model then baseInfo.model:Destroy() end
			BaseService._bases[player.UserId] = nil
		end
		BaseService._pendingKeys[player.UserId] = nil
		BaseService._displayModels[player.UserId] = nil
		BaseService._collectDebounce = {} -- clean up any stale debounce entries
	end)

	-- DisplayInteract: client presses E on a display pad
	DisplayInteract.OnServerEvent:Connect(function(player, padSlot, heldStreamerId, heldEffect)
		if typeof(padSlot) ~= "number" then return end

		local data = PlayerData.Get(player)
		if not data then return end

		local totalSlots = SlotsConfig.GetTotalSlots(data.rebirthCount, data.premiumSlotUnlocked)
		if padSlot < 1 or padSlot > totalSlots then return end
		if padSlot == SlotsConfig.PremiumSlotIndex and not data.premiumSlotUnlocked then return end

		local padKey = tostring(padSlot)
		local equipped = data.equippedPads[padKey]

		if equipped then
			-- Remove streamer from display → back to inventory
			local success = PlayerData.UnequipFromPad(player, padSlot)
			if success then
				removeDisplayModel(player, padSlot)
				if BaseService._pendingKeys[player.UserId] then
					BaseService._pendingKeys[player.UserId][padKey] = 0
				end
				BaseService.UpdateBasePads(player)
				UnequipResult:FireClient(player, { success = true, padSlot = padSlot })
			end
		elseif heldStreamerId and typeof(heldStreamerId) == "string" then
			-- Place streamer from inventory onto display
			local success = PlayerData.EquipToPad(player, heldStreamerId, padSlot)
			if success then
				local newEquipped = data.equippedPads[padKey]
				placeDisplayModel(player, padSlot, newEquipped)
				BaseService.UpdateBasePads(player)
				EquipResult:FireClient(player, { success = true, padSlot = padSlot, streamerId = heldStreamerId })
			else
				EquipResult:FireClient(player, { success = false, reason = "Cannot place here." })
			end
		end
	end)

	-- Legacy equip/unequip handlers (from inventory click)
	EquipRequest.OnServerEvent:Connect(function(player, streamerId, padSlot)
		if typeof(streamerId) ~= "string" or typeof(padSlot) ~= "number" then
			EquipResult:FireClient(player, { success = false, reason = "Invalid request." })
			return
		end
		local success = PlayerData.EquipToPad(player, streamerId, padSlot)
		if success then
			local data = PlayerData.Get(player)
			local newEquipped = data and data.equippedPads[tostring(padSlot)]
			placeDisplayModel(player, padSlot, newEquipped)
			BaseService.UpdateBasePads(player)
			EquipResult:FireClient(player, { success = true, padSlot = padSlot, streamerId = streamerId })
		else
			EquipResult:FireClient(player, { success = false, reason = "Cannot equip here." })
		end
	end)

	UnequipRequest.OnServerEvent:Connect(function(player, padSlot)
		if typeof(padSlot) ~= "number" then
			UnequipResult:FireClient(player, { success = false, reason = "Invalid request." })
			return
		end
		local success = PlayerData.UnequipFromPad(player, padSlot)
		if success then
			removeDisplayModel(player, padSlot)
			if BaseService._pendingKeys[player.UserId] then
				BaseService._pendingKeys[player.UserId][tostring(padSlot)] = 0
			end
			BaseService.UpdateBasePads(player)
			UnequipResult:FireClient(player, { success = true, padSlot = padSlot })
		else
			UnequipResult:FireClient(player, { success = false, reason = "Nothing to unequip." })
		end
	end)

	-- Handle already-connected players
	for _, player in ipairs(Players:GetPlayers()) do
		if not BaseService._bases[player.UserId] then
			task.spawn(function()
				local slot = findAvailableSlot()
				if not slot then return end

				BaseService._occupiedSlots[slot] = true
				local baseModel, position = buildBase(player, slot)

				BaseService._bases[player.UserId] = {
					position = position,
					model = baseModel,
					slotIndex = slot,
				}

				BaseService.UpdateBasePads(player)
				BaseReady:FireClient(player, {
					position = position,
					floorSize = DesignConfig.Base.FloorSize,
				})
			end)
		end
	end

	startKeyAccumulation()
end

function BaseService.GetBasePosition(player): Vector3?
	local baseInfo = BaseService._bases[player.UserId]
	return baseInfo and baseInfo.position or nil
end

-- Called by RebirthService to clean up displays on rebirth
function BaseService.ClearDisplaysForRebirth(player)
	clearAllDisplayModels(player)
	BaseService._pendingKeys[player.UserId] = {}
end

return BaseService
