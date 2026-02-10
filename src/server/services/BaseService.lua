--[[
	BaseService.lua
	Manages per-player bases: 8 bases total (4 per side of the speed pads).
	Base structures are placed by WorldBuilder; this service adds
	player name signs, pad grids, and handles equip/unequip.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local SlotsConfig = require(ReplicatedStorage.Shared.Config.SlotsConfig)

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local BaseReady = RemoteEvents:WaitForChild("BaseReady")
local EquipRequest = RemoteEvents:WaitForChild("EquipRequest")
local EquipResult = RemoteEvents:WaitForChild("EquipResult")
local UnequipRequest = RemoteEvents:WaitForChild("UnequipRequest")
local UnequipResult = RemoteEvents:WaitForChild("UnequipResult")

local BaseService = {}

BaseService._bases = {}          -- userId -> { position, model, slotIndex }
BaseService._occupiedSlots = {}  -- set of occupied slot indices

local PlayerData

-------------------------------------------------
-- POSITION CALCULATION — 8 fixed positions
-------------------------------------------------

local BASE_POSITIONS = DesignConfig.BasePositions  -- array of {position, rotation}

local function findAvailableSlot(): number
	for i = 1, #BASE_POSITIONS do
		if not BaseService._occupiedSlots[i] then
			return i
		end
	end
	return nil  -- server full (8 max)
end

-------------------------------------------------
-- HELPERS
-------------------------------------------------

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
-- BUILD BASE (structure placed by WorldBuilder;
-- here we only add name sign + pad grid)
-------------------------------------------------

local function buildBase(player, slotIndex)
	local slotInfo = BASE_POSITIONS[slotIndex]
	local basePosition = slotInfo.position

	-- Base STRUCTURE is already placed by WorldBuilder.
	-- We add the player name to the asset's billboard + pad grid.

	local model = Instance.new("Model")
	model.Name = "Base_" .. player.UserId

	-- PLAYER NAME — floating above the base, visible from anywhere
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

	-- PAD GRID (placed on top of the base structure)
	-- Pads are numbered COLUMN-FIRST starting from the entrance side.
	-- The entrance faces the speed pad (toward X=0), so:
	--   Left bases (rotation 90): entrance is on the +X side → start from rightmost col
	--   Right bases (rotation -90): entrance is on the -X side → start from leftmost col
	local padsFolder = Instance.new("Folder")
	padsFolder.Name = "Pads"
	padsFolder.Parent = model

	local cfg = DesignConfig.Base
	local rotation = slotInfo.rotation or 0
	local gridWidth = (cfg.PadCols - 1) * cfg.PadSpacing
	local gridDepth = (cfg.PadRows - 1) * cfg.PadSpacing
	local gridStartX = basePosition.X - gridWidth / 2
	local gridStartZ = basePosition.Z - gridDepth / 2

	-- Build column order: entrance column first
	local colOrder = {}
	if rotation > 0 then
		-- Left base → entrance on +X side → start from highest column
		for c = cfg.PadCols - 1, 0, -1 do table.insert(colOrder, c) end
	else
		-- Right base → entrance on -X side → start from lowest column
		for c = 0, cfg.PadCols - 1 do table.insert(colOrder, c) end
	end

	local padIndex = 0
	for _, col in ipairs(colOrder) do
		for row = 0, cfg.PadRows - 1 do
			padIndex = padIndex + 1

			local padX = gridStartX + col * cfg.PadSpacing
			local padZ = gridStartZ + row * cfg.PadSpacing
			local padPos = Vector3.new(padX, basePosition.Y + 0.6, padZ)

			local isPremium = padIndex == SlotsConfig.PremiumSlotIndex
			local isStarter = padIndex <= SlotsConfig.StartingSlots

			local padColor = DesignConfig.Colors.PadLocked
			if isStarter then
				padColor = DesignConfig.Colors.PadStarter
			elseif isPremium then
				padColor = DesignConfig.Colors.PadPremium
			end

			local pad = createPart({
				Name = "Pad_" .. padIndex,
				Size = cfg.PadSize,
				Position = padPos,
				Color = padColor,
				Material = Enum.Material.SmoothPlastic,
				Parent = padsFolder,
			})

			createPart({
				Name = "PadBorder",
				Size = Vector3.new(cfg.PadSize.X + 0.5, cfg.PadSize.Y - 0.2, cfg.PadSize.Z + 0.5),
				Position = padPos - Vector3.new(0, 0.1, 0),
				Color = isStarter and DesignConfig.Colors.PadStarter or Color3.fromRGB(50, 50, 60),
				Material = Enum.Material.SmoothPlastic,
				Parent = pad,
			})
		end
	end

	-- Parent to a player-specific folder
	local basesFolder = Workspace:FindFirstChild("PlayerBaseData")
	if not basesFolder then
		basesFolder = Instance.new("Folder")
		basesFolder.Name = "PlayerBaseData"
		basesFolder.Parent = Workspace
	end
	model.Parent = basesFolder

	print("[BaseService] Assigned " .. player.Name .. " to base slot " .. slotIndex)
	return model, basePosition
end

-------------------------------------------------
-- UPDATE PAD VISUALS
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

	local totalSlots = SlotsConfig.GetTotalSlots(data.rebirthCount, data.premiumSlotUnlocked)
	local Streamers = require(ReplicatedStorage.Shared.Config.Streamers)

	for _, pad in ipairs(padsFolder:GetChildren()) do
		if not (pad:IsA("BasePart") and pad.Name:match("^Pad_")) then continue end

		local idx = tonumber(pad.Name:match("Pad_(%d+)"))
		if not idx then continue end

		local isUnlocked = idx <= totalSlots
		local isPremium = idx == SlotsConfig.PremiumSlotIndex
		local isStarter = idx <= SlotsConfig.StartingSlots
		local equippedStreamer = data.equippedPads[tostring(idx)]

		if isUnlocked then
			if isPremium then
				pad.Color = DesignConfig.Colors.PadPremium
			elseif isStarter then
				pad.Color = DesignConfig.Colors.PadStarter
			else
				pad.Color = DesignConfig.Colors.PadUnlocked
			end
		else
			pad.Color = DesignConfig.Colors.PadLocked
		end

		-- Remove any old billboard text
		local oldBB = pad:FindFirstChildOfClass("BillboardGui")
		if oldBB then oldBB:Destroy() end
	end
end

-------------------------------------------------
-- PUBLIC
-------------------------------------------------

function BaseService.Init(playerDataModule)
	PlayerData = playerDataModule

	-- PlayerBases folder (base structures) is created by WorldBuilder.
	-- PlayerBaseData folder (per-player pads/signs) is created on demand.

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
			-- Name sign is part of the player model, destroyed automatically

			BaseService._occupiedSlots[baseInfo.slotIndex] = nil
			if baseInfo.model then baseInfo.model:Destroy() end
			BaseService._bases[player.UserId] = nil
		end
	end)

	EquipRequest.OnServerEvent:Connect(function(player, streamerId, padSlot)
		if typeof(streamerId) ~= "string" or typeof(padSlot) ~= "number" then
			EquipResult:FireClient(player, { success = false, reason = "Invalid request." })
			return
		end
		local success = PlayerData.EquipToPad(player, streamerId, padSlot)
		if success then
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
end

function BaseService.GetBasePosition(player): Vector3?
	local baseInfo = BaseService._bases[player.UserId]
	return baseInfo and baseInfo.position or nil
end

return BaseService
