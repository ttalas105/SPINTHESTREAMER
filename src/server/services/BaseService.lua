--[[
	BaseService.lua
	Manages per-player bases: 8 bases on each side of the central
	conveyor (16 total). Assigns positions, builds the physical base
	(dark gray floor, yellow border, pads), cleans up on leave.
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
-- POSITION CALCULATION
-- 2 columns (left + right of conveyor) x 8 rows = 16 base slots.
-- Fills alternating sides so players spread evenly.
-------------------------------------------------

local BASE_POSITIONS = {} -- pre-calculated list of Vector3 positions

do
	local cfg = DesignConfig.Base
	local cols = cfg.Columns   -- { LeftColumnX, RightColumnX }
	local rowStart = cfg.RowStartZ
	local rowSpace = cfg.RowSpacing
	local perSide = cfg.BasesPerSide or 8

	-- Fill positions: alternating left/right within each row
	local idx = 0
	for row = 0, perSide - 1 do
		for _, colX in ipairs(cols) do
			idx = idx + 1
			local z = rowStart + row * rowSpace
			BASE_POSITIONS[idx] = Vector3.new(colX, 0.5, z)
		end
	end
end

local function findAvailableSlot(): number
	for i = 1, #BASE_POSITIONS do
		if not BaseService._occupiedSlots[i] then
			return i
		end
	end
	-- Overflow: stack more rows
	return #BASE_POSITIONS + 1
end

local function getBasePosition(slotIndex: number): Vector3
	if BASE_POSITIONS[slotIndex] then
		return BASE_POSITIONS[slotIndex]
	end
	-- Overflow fallback: put extra bases further out
	local cfg = DesignConfig.Base
	local overflowRow = math.floor((slotIndex - 1) / #cfg.Columns)
	local overflowCol = ((slotIndex - 1) % #cfg.Columns) + 1
	local colX = cfg.Columns[overflowCol] or 0
	return Vector3.new(colX, 0.5, cfg.RowStartZ + overflowRow * cfg.RowSpacing)
end

-------------------------------------------------
-- BUILD BASE
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

local function buildBase(player, basePosition: Vector3)
	local cfg = DesignConfig.Base
	local model = Instance.new("Model")
	model.Name = "Base_" .. player.UserId

	-- BASE FLOOR
	createPart({
		Name = "BaseFloor",
		Size = cfg.FloorSize,
		Position = basePosition,
		Color = DesignConfig.Colors.BaseFloor,
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.05,
		Parent = model,
	})

	-- YELLOW BORDER (4 edges)
	local halfW = cfg.FloorWidth / 2
	local halfD = cfg.FloorDepth / 2
	local bh = cfg.BorderHeight
	local bt = cfg.BorderThickness

	createPart({
		Name = "BorderFront",
		Size = Vector3.new(cfg.FloorWidth + bt * 2, bh, bt),
		Position = basePosition + Vector3.new(0, bh / 2, -halfD - bt / 2),
		Color = DesignConfig.Colors.BaseBorder,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	createPart({
		Name = "BorderBack",
		Size = Vector3.new(cfg.FloorWidth + bt * 2, bh, bt),
		Position = basePosition + Vector3.new(0, bh / 2, halfD + bt / 2),
		Color = DesignConfig.Colors.BaseBorder,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	createPart({
		Name = "BorderLeft",
		Size = Vector3.new(bt, bh, cfg.FloorDepth),
		Position = basePosition + Vector3.new(-halfW - bt / 2, bh / 2, 0),
		Color = DesignConfig.Colors.BaseBorder,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	createPart({
		Name = "BorderRight",
		Size = Vector3.new(bt, bh, cfg.FloorDepth),
		Position = basePosition + Vector3.new(halfW + bt / 2, bh / 2, 0),
		Color = DesignConfig.Colors.BaseBorder,
		Material = Enum.Material.Neon,
		Parent = model,
	})

	-- PLAYER NAME SIGN
	local signPart = createPart({
		Name = "NameSign",
		Size = Vector3.new(20, 4, 0.5),
		Position = basePosition + Vector3.new(0, 5, -halfD - 1),
		Color = DesignConfig.Colors.BaseFloor,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(10, 0, 2, 0)
	billboard.AlwaysOnTop = false
	billboard.Parent = signPart

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = DesignConfig.Colors.White
	nameLabel.Font = DesignConfig.Fonts.Primary
	nameLabel.TextScaled = true
	nameLabel.Text = player.Name .. "'s Base"
	nameLabel.Parent = billboard

	-- PAD GRID
	local padsFolder = Instance.new("Folder")
	padsFolder.Name = "Pads"
	padsFolder.Parent = model

	local gridWidth = (cfg.PadCols - 1) * cfg.PadSpacing
	local gridDepth = (cfg.PadRows - 1) * cfg.PadSpacing
	local gridStartX = basePosition.X - gridWidth / 2
	local gridStartZ = basePosition.Z - gridDepth / 2

	local padIndex = 0
	for row = 0, cfg.PadRows - 1 do
		for col = 0, cfg.PadCols - 1 do
			padIndex = padIndex + 1

			local padX = gridStartX + col * cfg.PadSpacing
			local padZ = gridStartZ + row * cfg.PadSpacing
			local padPos = Vector3.new(padX, basePosition.Y + 0.1, padZ)

			local isPremium = padIndex == SlotsConfig.PremiumSlotIndex
			local isStarter = padIndex == 1

			local padColor = DesignConfig.Colors.PadLocked
			local padMaterial = Enum.Material.SmoothPlastic

			if isStarter then
				padColor = DesignConfig.Colors.PadStarter
				padMaterial = Enum.Material.Neon
			elseif isPremium then
				padColor = DesignConfig.Colors.PadPremium
			end

			local pad = createPart({
				Name = "Pad_" .. padIndex,
				Size = cfg.PadSize,
				Position = padPos,
				Color = padColor,
				Material = padMaterial,
				Parent = padsFolder,
			})

			-- Pad border frame
			createPart({
				Name = "PadBorder",
				Size = Vector3.new(cfg.PadSize.X + 0.5, cfg.PadSize.Y - 0.2, cfg.PadSize.Z + 0.5),
				Position = padPos - Vector3.new(0, 0.1, 0),
				Color = isStarter and DesignConfig.Colors.PadStarter or Color3.fromRGB(50, 50, 60),
				Material = Enum.Material.SmoothPlastic,
				Parent = pad,
			})

			-- Light
			local light = Instance.new("PointLight")
			light.Color = padColor
			light.Brightness = isStarter and 1 or 0.3
			light.Range = 8
			light.Parent = pad

			-- Green diamond markers between pads
			if col < cfg.PadCols - 1 and row < cfg.PadRows - 1 then
				local markerPos = Vector3.new(
					padX + cfg.PadSpacing / 2,
					basePosition.Y + 0.15,
					padZ + cfg.PadSpacing / 2
				)
				local marker = createPart({
					Name = "Marker",
					Size = Vector3.new(1.5, 0.15, 1.5),
					Position = markerPos,
					Color = DesignConfig.Colors.PadMarker,
					Material = Enum.Material.Neon,
					CanCollide = false,
					Parent = model,
				})
				marker.CFrame = CFrame.new(markerPos) * CFrame.Angles(0, math.rad(45), 0)
			end
		end
	end

	-- Parent to bases folder
	local basesFolder = Workspace:FindFirstChild("PlayerBases")
	if not basesFolder then
		basesFolder = Instance.new("Folder")
		basesFolder.Name = "PlayerBases"
		basesFolder.Parent = Workspace
	end
	model.Parent = basesFolder

	return model
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
		local isStarter = idx == 1
		local equippedStreamer = data.equippedPads[tostring(idx)]

		-- Color / Material
		if isUnlocked then
			if isStarter then
				pad.Color = DesignConfig.Colors.PadStarter
			elseif isPremium then
				pad.Color = DesignConfig.Colors.PadPremium
			else
				pad.Color = DesignConfig.Colors.PadUnlocked
			end
			pad.Material = Enum.Material.Neon
		else
			pad.Color = DesignConfig.Colors.PadLocked
			pad.Material = Enum.Material.SmoothPlastic
		end

		-- Light
		local light = pad:FindFirstChildOfClass("PointLight")
		if light then
			light.Brightness = isUnlocked and 0.8 or 0.2
			light.Color = pad.Color
		end

		-- Billboard
		local oldBB = pad:FindFirstChildOfClass("BillboardGui")
		if oldBB then oldBB:Destroy() end

		if isUnlocked and equippedStreamer then
			local streamerInfo = Streamers.ById[equippedStreamer]
			local rarityColor = DesignConfig.RarityColors[
				(streamerInfo or {}).rarity or "Common"
			] or Color3.fromRGB(100, 100, 100)

			local bb = Instance.new("BillboardGui")
			bb.Size = UDim2.new(6, 0, 3, 0)
			bb.StudsOffset = Vector3.new(0, 3, 0)
			bb.AlwaysOnTop = false
			bb.Parent = pad

			local frame = Instance.new("Frame")
			frame.Size = UDim2.new(1, 0, 1, 0)
			frame.BackgroundColor3 = rarityColor
			frame.BackgroundTransparency = 0.3
			frame.BorderSizePixel = 0
			frame.Parent = bb

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.15, 0)
			corner.Parent = frame

			local nameText = Instance.new("TextLabel")
			nameText.Size = UDim2.new(1, 0, 0.6, 0)
			nameText.BackgroundTransparency = 1
			nameText.TextColor3 = DesignConfig.Colors.White
			nameText.Font = DesignConfig.Fonts.Primary
			nameText.TextScaled = true
			nameText.Text = streamerInfo and streamerInfo.displayName or equippedStreamer
			nameText.Parent = frame

			local rarityText = Instance.new("TextLabel")
			rarityText.Size = UDim2.new(1, 0, 0.4, 0)
			rarityText.Position = UDim2.new(0, 0, 0.6, 0)
			rarityText.BackgroundTransparency = 1
			rarityText.TextColor3 = Color3.fromRGB(220, 220, 220)
			rarityText.Font = DesignConfig.Fonts.Secondary
			rarityText.TextScaled = true
			rarityText.Text = streamerInfo and streamerInfo.rarity or "?"
			rarityText.Parent = frame

		elseif isUnlocked then
			local bb = Instance.new("BillboardGui")
			bb.Size = UDim2.new(5, 0, 1.5, 0)
			bb.StudsOffset = Vector3.new(0, 2.5, 0)
			bb.AlwaysOnTop = false
			bb.Parent = pad

			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(1, 0, 1, 0)
			label.BackgroundTransparency = 1
			label.TextColor3 = Color3.fromRGB(150, 255, 180)
			label.Font = DesignConfig.Fonts.Secondary
			label.TextScaled = true
			label.Text = "EMPTY SLOT"
			label.Parent = bb

		elseif isPremium then
			local bb = Instance.new("BillboardGui")
			bb.Size = UDim2.new(6, 0, 2, 0)
			bb.StudsOffset = Vector3.new(0, 3, 0)
			bb.AlwaysOnTop = false
			bb.Parent = pad

			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(1, 0, 0.5, 0)
			label.BackgroundTransparency = 1
			label.TextColor3 = DesignConfig.Colors.PadPremium
			label.Font = DesignConfig.Fonts.Primary
			label.TextScaled = true
			label.Text = "PREMIUM SLOT"
			label.Parent = bb

			local idxLabel = Instance.new("TextLabel")
			idxLabel.Size = UDim2.new(1, 0, 0.5, 0)
			idxLabel.Position = UDim2.new(0, 0, 0.5, 0)
			idxLabel.BackgroundTransparency = 1
			idxLabel.TextColor3 = DesignConfig.Colors.TextSecondary
			idxLabel.Font = DesignConfig.Fonts.Secondary
			idxLabel.TextScaled = true
			idxLabel.Text = "© " .. tostring(idx)
			idxLabel.Parent = bb
		else
			local rebirthNeeded = SlotsConfig.GetRebirthForSlot(idx)
			local lockText = "LOCKED"
			if rebirthNeeded >= 0 then
				lockText = "LOCKED\n(Rebirth " .. rebirthNeeded .. ")"
			end

			local bb = Instance.new("BillboardGui")
			bb.Size = UDim2.new(5, 0, 2, 0)
			bb.StudsOffset = Vector3.new(0, 2.5, 0)
			bb.AlwaysOnTop = false
			bb.Parent = pad

			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(1, 0, 1, 0)
			label.BackgroundTransparency = 1
			label.TextColor3 = Color3.fromRGB(255, 100, 100)
			label.Font = DesignConfig.Fonts.Primary
			label.TextScaled = true
			label.Text = lockText
			label.Parent = bb
		end
	end
end

-------------------------------------------------
-- PUBLIC
-------------------------------------------------

function BaseService.Init(playerDataModule)
	PlayerData = playerDataModule

	-- Create bases folder
	local existing = Workspace:FindFirstChild("PlayerBases")
	if not existing then
		local folder = Instance.new("Folder")
		folder.Name = "PlayerBases"
		folder.Parent = Workspace
	end

	-- Player join
	Players.PlayerAdded:Connect(function(player)
		task.wait(1)

		local slot = findAvailableSlot()
		local position = getBasePosition(slot)

		BaseService._occupiedSlots[slot] = true
		local model = buildBase(player, position)

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

	-- Player leave
	Players.PlayerRemoving:Connect(function(player)
		local baseInfo = BaseService._bases[player.UserId]
		if baseInfo then
			BaseService._occupiedSlots[baseInfo.slotIndex] = nil
			if baseInfo.model then baseInfo.model:Destroy() end
			BaseService._bases[player.UserId] = nil
		end
	end)

	-- Equip request
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

	-- Unequip request
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
				local position = getBasePosition(slot)

				BaseService._occupiedSlots[slot] = true
				local baseModel = buildBase(player, position)

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
